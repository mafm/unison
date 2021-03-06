module Unison.Test.Common where

import qualified Unison.Builtin as B
import qualified Unison.FileParsers as FP
import           Unison.Parser (Ann(..))
import           Unison.Result (Result,Note)
import qualified Unison.Result as Result
import           Unison.Symbol (Symbol)
import           Unison.Term (AnnotatedTerm)
import           Unison.Type (AnnotatedType)
import qualified Unison.Typechecker as Typechecker

type Term v = AnnotatedTerm v Ann
type Type v = AnnotatedType v Ann

tm :: String -> Term Symbol
tm = B.tm

file :: String -> Result (Note Symbol Ann) (Term Symbol, Type Symbol)
file = FP.parseAndSynthesizeAsFile ""

fileTerm :: String -> Result (Note Symbol Ann) (Term Symbol)
fileTerm = fmap fst . FP.parseAndSynthesizeAsFile "<test>"

fileTermType :: String -> Maybe (Term Symbol, Type Symbol)
fileTermType = Result.toMaybe . FP.parseAndSynthesizeAsFile "<test>"

t :: String -> Type Symbol
t = B.t

typechecks :: String -> Bool
typechecks = Result.isSuccess . file

env :: Monad m => Typechecker.Env m Symbol Ann
env = Typechecker.Env Intrinsic [] typeOf dd ed where
  typeOf r = error $ "no type for: " ++ show r
  dd r = error $ "no data declaration for: " ++ show r
  ed r = error $ "no effect declaration for: " ++ show r

typechecks' :: Term Symbol -> Bool
typechecks' term = Result.isSuccess $ Typechecker.synthesize env term

check' :: Term Symbol -> Type Symbol -> Bool
check' term typ = Result.isSuccess $ Typechecker.check env term typ

check :: String -> String -> Bool
check terms typs = check' (tm terms) (t typs)
