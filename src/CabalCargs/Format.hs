{-# Language PatternGuards #-}

module CabalCargs.Format
   ( format
   ) where

import CabalCargs.CompilerArgs (CompilerArgs(..))
import CabalCargs.Formatting (Formatting(..))
import Data.Maybe (maybeToList)
import Data.List (foldl')
import qualified Filesystem.Path.CurrentOS as FP
import Filesystem.Path ((</>))


format :: Formatting -> CompilerArgs -> [String]
format Ghc cargs = concat [ formatHsSourceDirs $ hsSourceDirs cargs
                          , ghcOptions cargs
                          , map ("-X" ++) (defaultExtensions cargs)
                          , map ("-X" ++) (defaultLanguage cargs)
                          , map ("-optP" ++) (cppOptions cargs)
                          , map ("-optc" ++) (ccOptions cargs)
                          , map ("-L" ++) (extraLibDirs cargs)
                          , map ("-l" ++) (extraLibraries cargs)
                          , formatIncludeDirs $ includeDirs cargs
                          , formatIncludes $ includes cargs
                          , maybe [""] (\db -> ["-package-conf=" ++ db]) (packageDB cargs)
                          , formatHsSourceDirs $ autogenHsSourceDirs cargs
                          , formatIncludeDirs $ autogenIncludeDirs cargs
                          , formatIncludes $ autogenIncludes cargs
                          ]
   where
      formatHsSourceDirs = map ("-i" ++)
      formatIncludeDirs  = map ("-I" ++)

      formatIncludes incs = reverse $ foldl' addInclude [] incs
         where
            addInclude incs inc = ("-optP" ++ inc) : ("-optP-include") : incs


format Hdevtools cargs = (map ("-g" ++) (format Ghc cargs)) ++ socket
   where
      socket = ["--socket=" ++ prependCabalDir cargs ".hdevtools.sock"]


format Pure cargs = concat [ hsSourceDirs cargs
                           , ghcOptions cargs
                           , defaultExtensions cargs
                           , defaultLanguage cargs
                           , cppOptions cargs
                           , cSources cargs
                           , ccOptions cargs
                           , extraLibDirs cargs
                           , extraLibraries cargs
                           , ldOptions cargs
                           , includeDirs cargs
                           , includes cargs
                           , maybeToList $ packageDB cargs
                           , autogenHsSourceDirs cargs
                           , autogenIncludeDirs cargs
                           , autogenIncludes cargs
                           ]


prependCabalDir :: CompilerArgs -> String -> String
prependCabalDir cargs path = FP.encodeString $ cabalDir </> (FP.decodeString path)
   where
      cabalDir = FP.directory $ FP.decodeString (cabalFile cargs)
