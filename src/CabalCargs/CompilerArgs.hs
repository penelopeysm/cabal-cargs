{-# Language PatternGuards, TemplateHaskell, Rank2Types #-}

module CabalCargs.CompilerArgs
   ( CompilerArgs(..)
   , fromSourceFile
   , fromCabalFile
   , fromCmdArgs
   , fromSpec
   ) where

import CabalCargs.Spec (Spec)
import qualified CabalCargs.Spec as Spec
import qualified CabalCargs.Args as A
import qualified CabalCargs.Sections as S
import qualified CabalCargs.Field as F
import qualified CabalCargs.Fields as Fs
import qualified CabalCargs.Lenses as L
import Data.List (nub, foldl')
import Data.Maybe (maybeToList)
import Control.Applicative ((<|>), (<$>))
import Control.Lens
import Control.Monad.Trans.Either (runEitherT)
import qualified Filesystem.Path.CurrentOS as FP
import Filesystem.Path ((</>))
import qualified Distribution.PackageDescription as PD
import qualified Language.Haskell.Extension as Lang


-- | The collected compiler args from the cabal file.
data CompilerArgs = CompilerArgs 
   { hsSourceDirs        :: [FilePath]
   , ghcOptions          :: [String]
   , defaultExtensions   :: [String]
   , defaultLanguage     :: Maybe String
   , cppOptions          :: [String]
   , cSources            :: [FilePath]
   , ccOptions           :: [String]
   , extraLibDirs        :: [FilePath]
   , extraLibraries      :: [String]
   , ldOptions           :: [String]
   , includeDirs         :: [FilePath]
   , includes            :: [String]
   , packageDB           :: Maybe FilePath -- ^ the path to the package database of the cabal sandbox
   , autogenHsSourceDirs :: [FilePath]     -- ^ dirs of automatically generated haskell source files by cabal (e.g. Paths_*)
   , autogenIncludeDirs  :: [FilePath]     -- ^ dirs of automatically generated include files by cabal
   , autogenIncludes     :: [String]       -- ^ automatically generated include files by cabal (e.g. cabal_macros.h)
   , cabalFile           :: FilePath       -- ^ path to the used cabal file
   }
   deriving (Show, Eq)

makeLensesFor [ ("hsSourceDirs"       , "hsSourceDirsL")
              , ("ghcOptions"         , "ghcOptionsL")
              , ("defaultExtensions"  , "defaultExtensionsL")
              , ("defaultLanguage"    , "defaultLanguageL")
              , ("cppOptions"         , "cppOptionsL")
              , ("cSources"           , "cSourcesL")
              , ("ccOptions"          , "ccOptionsL")
              , ("extraLibDirs"       , "extraLibDirsL")
              , ("extraLibraries"     , "extraLibrariesL")
              , ("ldOptions"          , "ldOptionsL")
              , ("includeDirs"        , "includeDirsL")
              , ("includes"           , "includesL")
              , ("autogenHsSourceDirs", "autogenHsSourceDirsL")
              , ("autogenIncludeDirs" , "autogenIncludeDirsL")
              , ("autogenIncludes"    , "autogenIncludesL")
              ] ''CompilerArgs

type Error = String

-- | Create a 'CompilerArgs' from the given cabal file, sections and fields.
--
--   If a cabal sandbox is present in the directory of the cabal file, then
--   the path to its package database is also returned.
fromCabalFile :: FilePath -> S.Sections -> Fs.Fields -> IO (Either Error CompilerArgs)
fromCabalFile file sections fields = runEitherT $ do
   fromSpec <$> Spec.fromCabalFile file sections fields


-- | Create a 'CompilerArgs' from the given source file and fields.
--
--   Starting at the directory of the source file a cabal file is searched
--   upwards the directory tree.
--
--   The found cabal file is searched for a fitting section for the source file.
--   If no fitting section could be found, then all sections are used.
--
--   If a cabal sandbox is present in the directory of the cabal file, then
--   the path to its package database is also returned.
fromSourceFile :: FilePath -> Fs.Fields -> IO (Either Error CompilerArgs)
fromSourceFile file fields = runEitherT $ do
   fromSpec <$> Spec.fromSourceFile file fields


-- | Create a 'CompilerArgs' by the command line arguments given to 'cabal-cargs'.
--
--   Depending on the command line arguments 'fromCmdArgs' might behave like
--   'fromCabalFile', if only a cabal file was given, like 'fromSourceFile',
--   if only a source file was given or like a mix of both, if a cabal file
--   and a source file have been given.
fromCmdArgs :: A.Args -> IO (Either Error CompilerArgs)
fromCmdArgs args = runEitherT $ do
   fromSpec <$> Spec.fromCmdArgs args


-- | Collect the compiler args specified by 'Spec'.
fromSpec :: Spec -> CompilerArgs
fromSpec spec =
   case Spec.sections spec of
        S.Sections sections ->
           setCabalFile $ absolutePaths $ foldl' collectFromSection defaultCompilerArgs sections

        S.AllSections ->
           setCabalFile $ absolutePaths $ collectFields L.allBuildInfos defaultCompilerArgs

   where
      setCabalFile cargs = cargs { cabalFile = Spec.cabalFile spec }

      absolutePaths cargs =
         cargs & hsSourceDirsL        %~ map prependCabalDir
               & cSourcesL            %~ map prependCabalDir
               & extraLibDirsL        %~ map prependCabalDir
               & includeDirsL         %~ map prependCabalDir
               & includesL            %~ map prependCabalDir
               & autogenHsSourceDirsL %~ map prependCabalDir
               & autogenIncludeDirsL  %~ map prependCabalDir
               & autogenIncludesL     %~ map prependCabalDir
         where
            prependCabalDir path = FP.encodeString $ cabalDir </> FP.decodeString path
            cabalDir             = FP.directory . FP.decodeString $ Spec.cabalFile spec

      collectFromSection cargs section =
         collectFields (L.buildInfoOf section) cargs

      collectFields buildInfo cargs =
        foldl' addField cargs fields
        where
           addField cargs field = addArg field buildInfo cargs

           addArg F.Default_Language buildInfo cargs = cargs
--              cargs & defaultLanguageL %~ (<|> (toString <$> (cabalPkg ^. buildInfo . L.defaultLang)))
--              where
--                 toString (Lang.UnknownLanguage lang) = lang
--                 toString lang                        = show lang

           addArg F.Package_Db _ cargs =
              cargs & packageDBL %~ (<|> (maybeToList $ Spec.packageDB spec))

           addArg F.Autogen_Hs_Source_Dirs _ cargs =
              cargs & autogenHsSourceDirsL .~ ["dist/build/autogen"]

           addArg F.Autogen_Include_Dirs _ cargs =
              cargs & autogenIncludeDirsL .~ ["dist/build/autogen"]

           addArg F.Autogen_Includes _ cargs =
              cargs & autogenIncludesL .~ ["cabal_macros.h"]

           addArg field buildInfo cargs =
              cargs & (fieldL field) %~ nub . (++ cabalPkg ^. buildInfo . (L.field field))

           cabalPkg = Spec.cabalPackage spec
           fields   = case Spec.fields spec of
                           Fs.Fields fs -> fs
                           _            -> F.allFields



packageDBL :: Lens' CompilerArgs [String]
packageDBL = lens getter setter
   where
      getter = maybeToList . packageDB

      setter cargs [db@(_:_)] = cargs { packageDB = Just db }
      setter cargs          _ = cargs


fieldL :: F.Field -> Lens' CompilerArgs [String]
fieldL F.Hs_Source_Dirs         = hsSourceDirsL
fieldL F.Ghc_Options            = ghcOptionsL
fieldL F.Default_Extensions     = defaultExtensionsL
fieldL F.Default_Language       = error $ "Unexpected argument 'Default_Language' for 'CabalCargs.CompilerArgs.fieldL'!"
fieldL F.Cpp_Options            = cppOptionsL
fieldL F.C_Sources              = cSourcesL
fieldL F.Cc_Options             = ccOptionsL
fieldL F.Extra_Lib_Dirs         = extraLibDirsL
fieldL F.Extra_Libraries        = extraLibrariesL
fieldL F.Ld_Options             = ldOptionsL
fieldL F.Include_Dirs           = includeDirsL
fieldL F.Includes               = includesL
fieldL F.Package_Db             = packageDBL
fieldL F.Autogen_Hs_Source_Dirs = error $ "Unexpected argument 'Autogen_Hs_Source_Dirs' for 'CabalCargs.CompilerArgs.fieldL'!"
fieldL F.Autogen_Include_Dirs   = error $ "Unexpected argument 'Autogen_Include_Dirs' for 'CabalCargs.CompilerArgs.fieldL'!"
fieldL F.Autogen_Includes       = error $ "Unexpected argument 'Autogen_Includes' for 'CabalCargs.CompilerArgs.fieldL'!"


defaultCompilerArgs :: CompilerArgs
defaultCompilerArgs = CompilerArgs
   { hsSourceDirs        = []
   , ghcOptions          = []
   , defaultExtensions   = []
   , defaultLanguage     = Nothing
   , cppOptions          = []
   , cSources            = []
   , ccOptions           = []
   , extraLibDirs        = []
   , extraLibraries      = []
   , ldOptions           = []
   , includeDirs         = []
   , includes            = []
   , cabalFile           = ""
   , packageDB           = Nothing
   , autogenHsSourceDirs = []
   , autogenIncludeDirs  = []
   , autogenIncludes     = []
   }
