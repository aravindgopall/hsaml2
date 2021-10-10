{-# LANGUAGE CPP #-}
{-# LANGUAGE NoRebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
module Paths_hsaml2 (
    version,
    getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir,
    getDataFileName, getSysconfDir
  ) where

import qualified Control.Exception as Exception
import Data.Version (Version(..))
import System.Environment (getEnv)
import Prelude

#if defined(VERSION_base)

#if MIN_VERSION_base(4,0,0)
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#else
catchIO :: IO a -> (Exception.Exception -> IO a) -> IO a
#endif

#else
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#endif
catchIO = Exception.catch

version :: Version
version = Version [0,1,1] []
bindir, libdir, dynlibdir, datadir, libexecdir, sysconfdir :: FilePath

bindir     = "/Users/aravindmallapureddy/acreed/hsaml2/.stack-work/install/x86_64-osx/4fdb821a7b45486aed2c8226096acf82d772954b5858bf4e1bd206d22bc79bd3/8.10.4/bin"
libdir     = "/Users/aravindmallapureddy/acreed/hsaml2/.stack-work/install/x86_64-osx/4fdb821a7b45486aed2c8226096acf82d772954b5858bf4e1bd206d22bc79bd3/8.10.4/lib/x86_64-osx-ghc-8.10.4/hsaml2-0.1.1-3hwt0tsJdAh6FkF5C5xfFp"
dynlibdir  = "/Users/aravindmallapureddy/acreed/hsaml2/.stack-work/install/x86_64-osx/4fdb821a7b45486aed2c8226096acf82d772954b5858bf4e1bd206d22bc79bd3/8.10.4/lib/x86_64-osx-ghc-8.10.4"
datadir    = "/Users/aravindmallapureddy/acreed/hsaml2/.stack-work/install/x86_64-osx/4fdb821a7b45486aed2c8226096acf82d772954b5858bf4e1bd206d22bc79bd3/8.10.4/share/x86_64-osx-ghc-8.10.4/hsaml2-0.1.1"
libexecdir = "/Users/aravindmallapureddy/acreed/hsaml2/.stack-work/install/x86_64-osx/4fdb821a7b45486aed2c8226096acf82d772954b5858bf4e1bd206d22bc79bd3/8.10.4/libexec/x86_64-osx-ghc-8.10.4/hsaml2-0.1.1"
sysconfdir = "/Users/aravindmallapureddy/acreed/hsaml2/.stack-work/install/x86_64-osx/4fdb821a7b45486aed2c8226096acf82d772954b5858bf4e1bd206d22bc79bd3/8.10.4/etc"

getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir, getSysconfDir :: IO FilePath
getBinDir = catchIO (getEnv "hsaml2_bindir") (\_ -> return bindir)
getLibDir = catchIO (getEnv "hsaml2_libdir") (\_ -> return libdir)
getDynLibDir = catchIO (getEnv "hsaml2_dynlibdir") (\_ -> return dynlibdir)
getDataDir = catchIO (getEnv "hsaml2_datadir") (\_ -> return datadir)
getLibexecDir = catchIO (getEnv "hsaml2_libexecdir") (\_ -> return libexecdir)
getSysconfDir = catchIO (getEnv "hsaml2_sysconfdir") (\_ -> return sysconfdir)

getDataFileName :: FilePath -> IO FilePath
getDataFileName name = do
  dir <- getDataDir
  return (dir ++ "/" ++ name)
