{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ViewPatterns #-}

module Dwt.Search.QNode (
  qGet -- RSLT -> QNode -> Either DwtErr [Node]
  , qGetLab -- RSLT -> QNode -> Either DwtErr [LNode Expr]
  , qGet1 -- RSLT -> QNode -> Either DwtErr Node
  , qPutSt -- QNode -> StateT RSLT (Either DwtErr) Node

  , qRegexWord -- RSLT -> String -> [Node]

  -- for internal export, not for interface
  , NodeOrVarConcrete(..) -- Uses Node, not QNode. Still uses Mbrship.
  , RelSpecConcrete -- Uses NodeOrVarConcrete
  , _matchRelSpecNodes -- RSLT -> RelSpecConcrete -> Either DwtErr [Node]
    -- critical: the intersection-finding function
  , _matchRelSpecNodesLab -- same, except LNodes
  , _usersInRole -- RSLT -> Node -> RelRole -> Either DwtErr [Node]
  , _mkRelSpec -- Node -> [Node] -> RelSpecConcrete
) where

import Text.Regex

import Data.Graph.Inductive
import Dwt.Types
import Dwt.Edit
import Dwt.Util (fr, maxNode, dropEdges, fromRight, prependCaller, listIntersect, gelemM)
import Dwt.Measure (extractTplt, isAbsent)
import Data.Maybe (fromJust)

import Control.Monad (liftM)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.State
import Control.Lens
import qualified Data.Map as M
import qualified Data.Maybe as Mb
import Control.Monad (foldM)

-- | "Concrete" in the sense that it uses Nodes, not QNodes
data NodeOrVarConcrete = NodeSpecC Node
  | VarSpecC Mbrship deriving (Show,Read,Eq)
type RelSpecConcrete = M.Map RelRole NodeOrVarConcrete

_matchRelSpecNodes :: RSLT -> RelSpecConcrete -> Either DwtErr [Node]
_matchRelSpecNodes g spec = prependCaller "_matchRelSpecNodes: " $ do
  let nodeSpecs = M.toList
        $ M.filter (\ns -> case ns of NodeSpecC _ -> True; _ -> False)
        $ spec :: [(RelRole,NodeOrVarConcrete)]
  nodeListList <- mapM (\(r,NodeSpecC n) -> _usersInRole g n r) nodeSpecs
  return $ listIntersect nodeListList

-- ifdo speed: this searches for nodes, then searches again for labels
_matchRelSpecNodesLab :: RSLT -> RelSpecConcrete -> Either DwtErr [LNode Expr]
_matchRelSpecNodesLab g spec = prependCaller "_matchRelSpecNodesLab: " $ do
  ns <- _matchRelSpecNodes g spec
  return $ zip ns $ map (fromJust . lab g) ns
    -- TODO: slow: this looks up each node a second time to find its label
    -- fromJust is safe because _matchRelSpecNodes only returns Nodes in g

-- | Rels using Node n in RelRole r
_usersInRole :: RSLT -> Node -> RelRole -> Either DwtErr [Node]
_usersInRole g n r = prependCaller "usersInRole: " $
  do gelemM g n -- makes f safe
     return $ f g n r
  where f :: (Graph gr) => gr a RSLTEdge -> Node -> RelRole -> [Node]
        f g n r = [m | (m,r') <- lpre g n, r' == RelEdge r]

-- | Use when all the nodes the Rel involves are known.
_mkRelSpec :: Node -> [Node] -> RelSpecConcrete
_mkRelSpec t ns = M.fromList $ [(TpltRole, NodeSpecC t)] ++ mbrSpecs
  where mbrSpecs = zip (fmap Mbr [1..]) (fmap NodeSpecC ns)


-- TODO: simplify some stuff (maybe outside of this file?) by using 
-- Graph.whereis :: RSLT -> Expr -> [Node] -- hopefully length = 1

_qGet :: -- x herein is either Node or LNode Expr
     (RSLT -> Node -> x) -- | gets what's there; used for QAt.
  -- Can safely be unsafe, because the QAt's contents are surely present.
  -> (RSLT -> [x])       -- | nodes or labNodes; used for QLeaf
  -> (RSLT -> RelSpecConcrete -> Either DwtErr [x])
    -- | _matchRelSpecNodes or _matchRelSpecNodesLab; used for QRel
  -> RSLT -> QNode -> Either DwtErr [x]
_qGet f _ _ g (At n) = return $ if gelem n g then [f g n] else []
_qGet _ f _ g (QLeaf l) = return $ f $ labfilter (==l) $ dropEdges g
_qGet _ _ f g q@(QRel _ qms) = prependCaller "_qGet: " $ do
  t <- extractTplt q
  tnode <- qGet1 g (QLeaf t) -- todo ? multiple qt, qms matches
  ms <- mapM (qGet1 g) qms
  let relspec = _mkRelSpec tnode ms
  f g relspec

qGet :: RSLT -> QNode -> Either DwtErr [Node]
qGet = _qGet (\_ n -> n) nodes _matchRelSpecNodes

qGetLab :: RSLT -> QNode -> Either DwtErr [LNode Expr]
qGetLab = _qGet f labNodes _matchRelSpecNodesLab where
  f g n = (n, Mb.fromJust $ lab g n)

qGet1 :: RSLT -> QNode -> Either DwtErr Node
qGet1 g q = prependCaller "qGet1: " $ case qGet g q of
    Right [] -> Left (FoundNo, queryError, ".")
    Right [a] -> Right a
    Right as -> Left (FoundMany, queryError, ".")
    Left e -> Left e
  where queryError = [ErrQNode q]

qPutSt :: QNode -> StateT RSLT (Either DwtErr) Node
qPutSt i@(QRel _ qms) = do
  -- TODO ? would be more efficient to return even the half-completed state
  -- let tag = prependCaller "qPutSt: " -- TODO: use
  t <- lift $ extractTplt i
  tnode <- qPutSt $ QLeaf t
  ms <- mapM qPutSt $ filter (not . isAbsent) qms
  g <- get
  insRelSt tnode ms
qPutSt (At n) = lift $ Right n
qPutSt q@(QLeaf x) = get >>= \g -> case qGet1 g q of
  Right n -> lift $ Right n
  Left (FoundNo,_,_) -> let g' = insLeaf x g
    in put g' >> lift (Right $ maxNode g')
  Left e -> lift $ prependCaller "qPutSt: " $ Left e

-- == Regex
qRegexWord :: RSLT -> String -> [Node]
qRegexWord g s = nodes $ labfilter f $ dropEdges g
  where r = mkRegex s
        f (Word t) = Mb.isJust $ matchRegex r t
        f _ = False
