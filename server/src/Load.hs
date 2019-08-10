-- | Use the Unison compiler as a library to get info about a codebase.
module Load
  ( load
  , FunctionCallGraph(..)
  , Names(..)
  , Hash(..)
  ) where

import Control.Monad
import Data.Aeson
import Data.Map (Map)
import Data.Maybe
import Data.Set (Set)
import Data.Text (Text)
import Data.Traversable
import GHC.Generics
import Prelude hiding (head, id)
import System.Exit (die)
import Unison.Codebase (Codebase)
import Unison.Codebase.Serialization.V1 (formatSymbol)
import Unison.Name (Name)
import Unison.Parser (Ann(External))
import Unison.Reference (Reference)
import Unison.Referent (Referent)
import Unison.Symbol (Symbol)
import Unison.Util.Star3 (Star3)

import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified System.IO
import qualified Unison.ABT as ABT
import qualified Unison.Codebase as Codebase
import qualified Unison.Codebase.Branch as Branch
import qualified Unison.Codebase.FileCodebase as FileCodebase
import qualified Unison.Codebase.Serialization as S
import qualified Unison.Name as Name
import qualified Unison.Reference as Reference
import qualified Unison.Referent as Referent
import qualified Unison.Term as Term
import qualified Unison.Util.Relation as Relation
import qualified Unison.Util.Star3 as Star3

data FunctionCallGraph
  = FunctionCallGraph (Map Hash (Set Hash))
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

data Names
  = Names (Map Hash Text)
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

newtype Hash
  = Hash Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON, ToJSONKey)

load :: IO (Names, FunctionCallGraph)
load = do
  let
    codebasePath :: FilePath
    codebasePath =
      ".unison/v1"

    codebase :: Codebase IO Symbol Ann
    codebase =
      FileCodebase.codebase1 formatSymbol formatAnn codebasePath

  exists <- FileCodebase.exists codebasePath
  when (not exists) (die "No codebase found")

  branch <- Codebase.getRootBranch codebase

  let
    head :: Branch.Branch0 IO
    head =
      Branch.head branch

    terms
      :: Star3
           Referent
           Name
           Reference -- Type
           (Reference, Reference) -- Type, Value
    terms =
      Branch.deepTerms head

    refToName :: Map Referent (Set Name)
    refToName =
      Relation.domain (Star3.d1 terms)

    refMap :: Map Referent Reference.Id
    refMap =
      Map.fromList $
        mapMaybe
          (\referent ->
            fmap
              (\id -> (referent, id))
              (r2r referent))
          (Map.keys refToName)

  res <- fcg codebase (Set.fromList (Map.elems refMap))
  pure (mkNames refMap refToName, res)

-- * Helpers

fcg :: Codebase IO Symbol Ann -> Set Reference.Id -> IO FunctionCallGraph
fcg codebase refs = do
  FunctionCallGraph . Map.fromList <$> for (Set.toList refs) f
  where
    f :: Reference.Id -> IO (Hash, Set Hash)
    f ref = do
      mTerm <- Codebase.getTerm codebase ref
      case mTerm of
        Nothing -> do
          TIO.hPutStrLn System.IO.stderr ("Skipping reference (can't find term): " <> refToHashText ref)
          pure (refToHash ref, mempty)

        Just (t :: Codebase.Term Symbol Ann) ->
          pure (refToHash ref, calls t)

refToHash :: Reference.Id -> Hash
refToHash =
  Hash . refToHashText

-- | A separate function from 'refToHash' for use in making logs.
refToHashText :: Reference.Id -> Text
refToHashText (Reference.Id hash _ _) =
  T.pack (show hash)

mkNames :: Map Referent Reference.Id -> Map Referent (Set Name) -> Names
mkNames xs nameMap =
  Names (Map.fromList (fmap f (Map.toList xs)))
  where
    f :: (Referent, Reference.Id) -> (Hash, Text)
    f (referent, id) =
      case Map.lookup referent nameMap of
        Nothing ->
          error "Name not found"

        Just names ->
          ( refToHash id
          , textFromName names
          )

textFromName :: Set Name -> Text
textFromName xs =
  case Set.toList xs of
    [] ->
      "<none>"

    [x] ->
      Name.toText x

    x:_ ->
      Name.toText x <> " (conflicted)"

-- | @Codebase.Term Symbol Ann@ desugars to
-- @ABT.Term (Term.F Symbol Ann Ann) Symbol Ann@.
calls :: ABT.Term (Term.F Symbol Ann Ann) Symbol Ann -> Set Hash
calls =
  Set.fromList . mapMaybe f . Set.toList . Term.dependencies
  where
    f :: Reference -> Maybe Hash
    f = \case
      Reference.Builtin _ ->
        Nothing

      Reference.DerivedId id ->
        Just (refToHash id)

r2r :: Referent -> Maybe Reference.Id
r2r r =
  case reference of
    Reference.Builtin _ ->
      Nothing

    Reference.DerivedId id ->
      Just id
  where
    reference :: Reference
    reference =
      case r of
        Referent.Ref a ->
          a

        Referent.Con a _ _ ->
          a

formatAnn :: S.Format Ann
formatAnn =
  S.Format (pure External) (\_ -> pure ())
