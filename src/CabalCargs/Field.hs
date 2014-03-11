{-# LANGUAGE DeriveDataTypeable #-}

module CabalCargs.Field
   ( Field(..)
   , allFields
   ) where

import Data.Data (Data, Typeable)

-- | A compiler relevant field from the cabal file.
data Field = Hs_Source_Dirs
           | Ghc_Options
           | Default_Extensions

           | Cpp_Options
           | C_Sources
           | Cc_Options

           | Extra_Lib_Dirs
           | Extra_Libraries
           | Ld_Options

           | Include_Dirs
           | Includes

           -- | This isn't a field of the cabal file, but represents
           --   the package database of a cabal sandbox.
           | Package_Db
           deriving (Data, Typeable, Show, Eq)


allFields :: [Field]
allFields = [ Hs_Source_Dirs
            , Ghc_Options
            , Default_Extensions
            , Cpp_Options
            , C_Sources
            , Cc_Options
            , Extra_Lib_Dirs
            , Extra_Libraries
            , Ld_Options
            , Include_Dirs
            , Includes
            , Package_Db
            ]
