module TAdd where

import Dwt hiding (fromRight)
import Data.Graph.Inductive
import Test.HUnit hiding (Node)
import Text.Megaparsec (parse)
import Control.Monad.Trans.State (runStateT, execStateT)

tAdd = TestList [ TestLabel "tAddLabeled" tAddLabeled
                , TestLabel "tAddUnlabeled" tAddUnlabeled
                ]

tAddLabeled = TestCase $ do
  let Right g = execStateT f empty
      f = mapM (addExpr . fr . parse expr "" ) exprs
      exprs = ["a #x", "#x a", "a #x b", "##x b #x"]
      qa = QLeaf $ Word "a"
      qb = QLeaf $ Word "b"
      qab = QRel (QLeaf $ mkTplt "_ x _") [qa,qb]
  assertBool "1" $ either (const False) (const True) $ qGet1 g qa
  assertBool "2" $ do either (const False) (const True) $ qGet1 g qb
  assertBool "3" $ do either (const False) (const True) $ qGet1 g qab

tAddUnlabeled = TestCase $ do
  let Right g = execStateT f empty
      f = mapM (addExpr . fr . parse expr "" ) exprs
      exprs = ["a #", "# a", "a # b", "## b #"]
        -- TODO: unlabeled rels (a #) and (# a) are visually indistinguishable
      qa = QLeaf $ Word "a"
      qb = QLeaf $ Word "b"
      qab = QRel (QLeaf $ mkTplt "_ _") [qa,qb]
  assertBool "1" $ either (const False) (const True) $ qGet1 g qa
  assertBool "2" $ do either (const False) (const True) $ qGet1 g qb
  assertBool "3" $ do either (const False) (const True) $ qGet1 g qab
