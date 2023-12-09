{-# LANGUAGE CPP #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE OverloadedStrings#-}
-- |
-- XML Signature Syntax and Processing
--
-- <http://www.w3.org/TR/2008/REC-xmldsig-core-20080610/> (selected portions)
module SAML2.XML.Signature
  ( module SAML2.XML.Signature.Types
  , generateReference
  , SigningKey(..)
  , PublicKeys(..)
  , signingKeySignatureAlgorithm
  , signBase64
  , verifyBase64
  , generateSignature
  , juspaySignature
  , verifySignature
  , signingKeyValue
  ) where

import Control.Applicative ((<|>))
import Control.DeepSeq
import Control.Monad (guard, (<=<))
import Crypto.Number.Basic (numBytes)
import Crypto.Number.Serialize (i2ospOf_, os2ip)
import Crypto.Hash (hashlazy, SHA1(..), SHA256(..), SHA512(..), RIPEMD160(..))
import qualified Crypto.PubKey.DSA as DSA
import qualified Crypto.PubKey.RSA.Types as RSA
import qualified Crypto.PubKey.RSA.PKCS15 as RSA
import qualified Data.ByteArray as BA
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as BSL
import qualified Data.List.NonEmpty as NonEmpty
import Data.Maybe (isJust)
import Data.Monoid ((<>))
import qualified Data.X509 as X509
import Network.URI (URI(..))
import qualified Text.XML.HXT.Core as HXT
import qualified Text.XML.HXT.DOM.ShowXml as DOM
import qualified Text.XML.HXT.DOM.XmlNode as DOM
import qualified Text.XML.HXT.DOM.QualifiedName as DOM

import SAML2.XML
import SAML2.XML.Canonical
import qualified Text.XML.HXT.Arrow.Pickle.Xml.Invertible as XP
import SAML2.XML.Signature.Types

isDSElem :: HXT.ArrowXml a => String -> a HXT.XmlTree HXT.XmlTree
isDSElem n = HXT.isElem HXT.>>> HXT.hasQName (mkNName ns n)

getID :: HXT.ArrowXml a => String -> a HXT.XmlTree HXT.XmlTree
getID = HXT.deep . HXT.hasAttrValue "ID" . (==)

applyCanonicalization :: CanonicalizationMethod -> Maybe String -> HXT.XmlTree -> IO BS.ByteString
applyCanonicalization (CanonicalizationMethod (Identified a) ins []) x y = canonicalize a ins x y
applyCanonicalization m _ _ = fail $ "applyCanonicalization: unsupported " ++ show m

applyTransformsBytes :: [Transform] -> BSL.ByteString -> IO BSL.ByteString
applyTransformsBytes [] v = return v
applyTransformsBytes (t : _) _ = fail ("applyTransforms: unsupported Signature " ++ show t)

applyTransformsXML :: [Transform] -> HXT.XmlTree -> IO BSL.ByteString
applyTransformsXML (Transform (Identified (TransformCanonicalization a)) ins x : tl) =
  applyTransformsBytes tl . BSL.fromStrict
  <=< applyCanonicalization (CanonicalizationMethod (Identified a) ins (map (XP.pickleDoc XP.xpickle) x)) Nothing
applyTransformsXML (Transform (Identified TransformEnvelopedSignature) Nothing [] : tl) =
  -- XXX assumes "this" signature in top-level
  applyTransformsXML tl
  . head . HXT.runLA (HXT.processChildren $ HXT.processChildren
    $ HXT.neg (isDSElem "Signature"))
applyTransformsXML tl = applyTransformsBytes tl . DOM.xshowBlob . return

applyTransforms :: Maybe Transforms -> HXT.XmlTree -> IO BSL.ByteString
applyTransforms = applyTransformsXML . maybe [] (NonEmpty.toList . transforms)

asType :: a -> proxy a -> proxy a
asType _ = id

applyDigest :: DigestMethod -> BSL.ByteString -> BS.ByteString
applyDigest (DigestMethod (Identified DigestSHA1) []) = BA.convert . asType SHA1 . hashlazy
applyDigest (DigestMethod (Identified DigestSHA256) []) = BA.convert . asType SHA256 . hashlazy
applyDigest (DigestMethod (Identified DigestSHA512) []) = BA.convert . asType SHA512 . hashlazy
applyDigest (DigestMethod (Identified DigestRIPEMD160) []) = BA.convert . asType RIPEMD160 . hashlazy
applyDigest d = error $ "unsupported " ++ show d

generateReference :: Reference -> HXT.XmlTree -> IO Reference
generateReference r x = do
  t <- applyTransforms (referenceTransforms r) x
  let d = applyDigest (referenceDigestMethod r) t
  return r
    { referenceDigestValue = d }

verifyReference :: Reference -> HXT.XmlTree -> IO Bool
verifyReference r doc = case referenceURI r of
  Just URI{ uriScheme = "", uriAuthority = Nothing, uriPath = "", uriQuery = "", uriFragment = '#':xid }
    | x@[_] <- HXT.runLA (getID xid) doc -> do
    t <- applyTransforms (referenceTransforms r) $ DOM.mkRoot [] x
    return (applyDigest (referenceDigestMethod r) t == referenceDigestValue r)
  _ -> do
    t <- applyTransforms (referenceTransforms r) doc
    print $ "log-reference: "         <> show r
    print $ "log-transformed-xml: "   <> t
    print $ "log-calculated-digest: " <> show (applyDigest (referenceDigestMethod r) t)
    print $ "log-xml-digest: "        <> show (referenceDigestValue r)
    return (applyDigest (referenceDigestMethod r) t == referenceDigestValue r)

data SigningKey
  = SigningKeyDSA DSA.KeyPair
  | SigningKeyRSA RSA.KeyPair
  deriving (Eq, Show)

data PublicKeys = PublicKeys
  { publicKeyDSA :: Maybe DSA.PublicKey
  , publicKeyRSA :: Maybe RSA.PublicKey
  } deriving (Eq, Show)

#if MIN_VERSION_base(4,11,0)
instance Semigroup PublicKeys where
  PublicKeys dsa1 rsa1 <> PublicKeys dsa2 rsa2 =
    PublicKeys (dsa1 <|> dsa2) (rsa1 <|> rsa2)
#endif
instance Monoid PublicKeys where
  mempty = PublicKeys Nothing Nothing
  PublicKeys dsa1 rsa1 `mappend` PublicKeys dsa2 rsa2 =
    PublicKeys (dsa1 <|> dsa2) (rsa1 <|> rsa2)

signingKeySignatureAlgorithm :: SigningKey -> SignatureAlgorithm
signingKeySignatureAlgorithm (SigningKeyDSA _) = SignatureDSA_SHA1
signingKeySignatureAlgorithm (SigningKeyRSA _) = SignatureRSA_SHA1

signingKeyValue :: SigningKey -> KeyValue
signingKeyValue (SigningKeyDSA (DSA.toPublicKey -> DSA.PublicKey p y)) = DSAKeyValue
  { dsaKeyValuePQ = Just (DSA.params_p p, DSA.params_q p)
  , dsaKeyValueG = Just (DSA.params_g p)
  , dsaKeyValueY = y
  , dsaKeyValueJ = Nothing
  , dsaKeyValueSeedPgenCounter = Nothing
  }
signingKeyValue (SigningKeyRSA (RSA.toPublicKey -> RSA.PublicKey _ n e)) = RSAKeyValue
  { rsaKeyValueModulus = n
  , rsaKeyValueExponent = e
  }

publicKeyValues :: KeyValue -> PublicKeys
publicKeyValues DSAKeyValue{ dsaKeyValuePQ = Just (p, q), dsaKeyValueG = Just g, dsaKeyValueY = y } = mempty
  { publicKeyDSA = Just $ DSA.PublicKey
    { DSA.public_params = DSA.Params
      { DSA.params_p = p
      , DSA.params_q = q
      , DSA.params_g = g
      }
    , DSA.public_y = y
    }
  }
publicKeyValues RSAKeyValue{ rsaKeyValueModulus = n, rsaKeyValueExponent = e } = mempty
  { publicKeyRSA = Just $ RSA.PublicKey (numBytes n) n e
  }
publicKeyValues _ = mempty

signBytes :: SigningKey -> BS.ByteString -> IO BS.ByteString
signBytes (SigningKeyDSA k) b = do
  s <- DSA.sign (DSA.toPrivateKey k) SHA1 b
  return $ i2ospOf_ 20 (DSA.sign_r s) <> i2ospOf_ 20 (DSA.sign_s s)
signBytes (SigningKeyRSA k) b =
  either (fail . show) return =<< RSA.signSafer (Just SHA1) (RSA.toPrivateKey k) b

-- | indicate verification result; return 'Nothing' if no matching key/alg pair is found
verifyBytes :: PublicKeys -> IdentifiedURI SignatureAlgorithm -> BS.ByteString -> BS.ByteString -> Maybe Bool
verifyBytes PublicKeys{ publicKeyDSA = Just k } (Identified SignatureDSA_SHA1) sig m = Just $
  BS.length sig == 40 &&
  DSA.verify SHA1 k DSA.Signature{ DSA.sign_r = os2ip r, DSA.sign_s = os2ip s } m
  where (r, s) = BS.splitAt 20 sig
verifyBytes PublicKeys{ publicKeyRSA = Just k } (Identified SignatureRSA_SHA1) sig m = Just $
  RSA.verify (Just SHA1) k m sig
verifyBytes PublicKeys{ publicKeyRSA = Just k } (Identified SignatureRSA_SHA256) sig m = Just $
  RSA.verify (Just SHA256) k m sig
verifyBytes _ _ _ _ = Nothing

signBase64 :: SigningKey -> BS.ByteString -> IO BS.ByteString
signBase64 sk = fmap Base64.encode . signBytes sk

verifyBase64 :: PublicKeys -> IdentifiedURI SignatureAlgorithm -> BS.ByteString -> BS.ByteString -> Maybe Bool
verifyBase64 pk alg m = either (const $ Just False) (verifyBytes pk alg m) . Base64.decode where

juspaySignature :: SigningKey -> SignedInfo -> BS.ByteString -> IO Signature
juspaySignature sk si ns = do
  let six = "<SignedInfo xmlns=\"http://www.w3.org/2000/09/xmldsig#\"><CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"></CanonicalizationMethod><SignatureMethod Algorithm=\"http://www.w3.org/2000/09/xmldsig#rsa-sha1\"></SignatureMethod><Reference URI=\"\"><Transforms><Transform Algorithm=\"http://www.w3.org/2000/09/xmldsig#enveloped-signature\"></Transform><Transform Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"></Transform></Transforms><DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"></DigestMethod><DigestValue>" <> ns <> "</DigestValue></Reference></SignedInfo>"
  sv <- signBytes sk six
  return Signature
    { signatureId = Nothing
    , signatureSignedInfo = si
    , signatureSignatureValue = SignatureValue Nothing sv
    , signatureKeyInfo = Just $ KeyInfo Nothing $ KeyInfoKeyValue (signingKeyValue sk) NonEmpty.:| []
    , signatureObject = []
    }

generateSignature :: SigningKey -> SignedInfo -> IO Signature
generateSignature sk si = do
  -- XXX: samlToDoc may not match later
  six <- applyCanonicalization (signedInfoCanonicalizationMethod si) Nothing $ samlToDoc si
  sv <- signBytes sk six
  return Signature
    { signatureId = Nothing
    , signatureSignedInfo = si
    , signatureSignatureValue = SignatureValue Nothing sv
    , signatureKeyInfo = Just $ KeyInfo Nothing $ KeyInfoKeyValue (signingKeyValue sk) NonEmpty.:| []
    , signatureObject = []
    }

-- Exception in IO:  something is syntactically wrong with the input
-- Nothing:          no matching key/alg pairs found
-- Just False:       signature verification failed || dangling refs || explicit ref is not among the signed ones
-- Just True:        everything is ok!
verifySignature :: PublicKeys -> HXT.XmlTree -> IO (Maybe Bool)
verifySignature pks xmlTree' = do
  let xmlTree = force xmlTree' -- force evaluation is needed
      (DOM.NTree rootNode _) = xmlTree
      childrenNodesList = HXT.runLA (HXT.getChildren HXT.>>> HXT.cleanupNamespaces HXT.collectPrefixUriPairs) xmlTree
      signatureNode = addNs $ last childrenNodesList
      xmlTreeWOSignature = DOM.NTree rootNode (init childrenNodesList)
  signature@Signature{ signatureSignedInfo = signedInfo } <- either fail return $ docToSAML signatureNode
  signedInfoXml <- applyCanonicalization (signedInfoCanonicalizationMethod signedInfo) (Just xpath) $ DOM.mkRoot [] [xmlTree]
  (isDigestValid NonEmpty.:| _) <- mapM (`verifyReference` xmlTreeWOSignature) (signedInfoReference signedInfo)
  let keys = pks <> foldMap (foldMap keyinfo . keyInfoElements) (signatureKeyInfo signature)
      isDigestVerified = verifyBytes keys (signatureMethodAlgorithm $ signedInfoSignatureMethod signedInfo) (signatureValue $ signatureSignatureValue signature) signedInfoXml
  -----
  print $ "log-xmlTree: " <> show xmlTree
  print $ "log-rootNode: " <> show rootNode
  print $ "log-childrenNodesList: " <> show childrenNodesList
  print $ "log-signatureNode: " <> show signatureNode -- this has namespace "ds:"
  print $ "log-xmlTreeWOSignature: " <> show xmlTreeWOSignature
  print $ "log-signature: " <> show signature
  print $ "log-signedInfo: " <> show signedInfo
  print $ "log-xpath: " <> show xpath
  print $ "log-signedInfoXml: " <> signedInfoXml
  print $ "log-isDigestValid: " <> show isDigestValid
  print $ "log-isDigestVerified: " <> show isDigestVerified
  -----
  return $ (isDigestValid &&) <$> isDigestVerified
  where
    addNs (DOM.NTree (HXT.XTag qn attrs) six) = DOM.NTree (HXT.XTag (DOM.mkNsName ("ds:" <> DOM.qualifiedName qn) "http://www.w3.org/2000/09/xmldsig#") (addNs <$> attrs)) (addNs <$> six)
    addNs x = x
    child n = HXT.runLA $ HXT.getChildren HXT.>>> isDSElem n HXT.>>> HXT.cleanupNamespaces HXT.collectPrefixUriPairs
    keyinfo (KeyInfoKeyValue kv) = publicKeyValues kv
    keyinfo (X509Data l) = foldMap keyx509d l
    keyinfo _ = mempty
    keyx509d (X509Certificate sc) = keyx509p $ X509.certPubKey $ X509.getCertificate sc
    keyx509d _ = mempty
    keyx509p (X509.PubKeyRSA r) = mempty{ publicKeyRSA = Just r }
    keyx509p (X509.PubKeyDSA d) = mempty{ publicKeyDSA = Just d }
    keyx509p _ = mempty
    xpathsel t = "/*[local-name()='" ++ t ++ "' and namespace-uri()='" ++ namespaceURIString ns ++ "']"
    xpathbase = "/*" ++ xpathsel "Signature" ++ xpathsel "SignedInfo" ++ "//"
    xpath = xpathbase ++ ". | " ++ xpathbase ++ "@* | " ++ xpathbase ++ "namespace::*"
