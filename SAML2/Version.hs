module SAML2.Version
  ( SAMLVersion(..)
  ) where

import Data.Version (Version, makeVersion)

data SAMLVersion
  = SAML10
  | SAML11
  | SAML20
  deriving (Eq, Ord, Enum, Bounded)

samlVersion :: SAMLVersion -> Version
samlVersion SAML10 = makeVersion [1,0]
samlVersion SAML11 = makeVersion [1,1]
samlVersion SAML20 = makeVersion [2,0]

instance Show SAMLVersion where
  show = show . samlVersion
  showsPrec p = showsPrec p . samlVersion

instance Read SAMLVersion where
  readsPrec _ ('1':'.':'0':s) = [(SAML10, s)]
  readsPrec _ ('1':'.':'1':s) = [(SAML11, s)]
  readsPrec _ ('2':'.':'0':s) = [(SAML20, s)]
  readsPrec _ _ = []
