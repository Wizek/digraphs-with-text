module Dwt.Search.Recursive where

import Data.Graph.Inductive
import Dwt.Types
import Dwt.Graph
import Dwt.Search.Local

import Dwt.Util (listIntersect, prependCaller, gelemM, otherDir)
import qualified Data.Map as Map
import Data.Maybe (fromJust)
import Data.List (nub)

import Control.Monad
import Control.Monad.Reader
import Control.Monad.Trans.Class

partitionRelSpecQ :: RSLT -> RelSpecQ
  -> Either DwtErr (RelVarSpec, RelNodeSpec)
partitionRelSpecQ g rSpec = let f (VarSpecQ _) = True
                                f (NodeSpecQ _) = False
                                (vs,qs) = Map.partition f rSpec
  in do ns <- mapM (\(NodeSpecQ q) -> qGet1 g q)  qs
        return (Map.map  (\(VarSpecQ  v) -> v)  vs, ns)

insRelSpecQ :: RelSpecQ -> RSLT -> Either DwtErr RSLT
insRelSpecQ rSpec g = do
  (varMap, nodeMap) <- partitionRelSpecQ g rSpec
  let newAddr = head $ newNodes 1 g
      newLNode = (newAddr, RelSpecExpr varMap)
        -- this node specifies the variable nodes
  mapM_ (gelemM g) $ Map.elems nodeMap
  let newLEdges = map (\(role,n) -> (newAddr, n, RelEdge role))
                $ Map.toList nodeMap
        -- these edges specify the addressed nodes
  return $ insEdges newLEdges $ insNode newLNode g

relNodeSpecQ :: RSLT -> QNode -> Either DwtErr RelNodeSpec
relNodeSpecQ g q = prependCaller "relNodeSpec: " $ do
  n <- qGet1 g q
  case lab g n of
    Just (RelSpecExpr _) -> return $ Map.fromList $ map f $ lsuc g n
      where f (node,RelEdge r) = (r,node)
    Just _ -> Left
      (NotRelSpecExpr, [ErrNode n], "")
    Nothing -> Left (FoundNo, [ErrNode n], "")

relSpecQ :: RSLT -> QNode -> Either DwtErr RelSpec
  -- name ? getRelSpecDe
  -- is nearly inverse to partitionRelSpec
relSpecQ g q = prependCaller "relSpec: " $ do
  n <- qGet1 g q
  case (fromJust $ lab g n) of
    RelSpecExpr rvs -> do
      rnsl <- Map.toList <$> relNodeSpec g n
      let rvsl = Map.toList rvs
          rvsl' = map (\(role,var) ->(role,VarSpec  var )) rvsl
          rnsl' = map (\(role,node)->(role,NodeSpec node)) rnsl
      return $ Map.fromList $ rvsl' ++ rnsl'
    x -> Left (ConstructorMistmatch, [ErrExpr x, ErrQNode $ QAt n]
              , "relSpecQ.")

usersInRoleQ :: RSLT -> QNode -> RelRole -> Either DwtErr [Node]
usersInRoleQ g (QAt n) r = prependCaller "usersInRole: " $ usersInRole g n r
usersInRoleQ g q r = qGet1 g q >>= \n -> usersInRole g n r

matchRelSpecNodesQ :: RSLT -> RelSpecQ -> Either DwtErr [Node]
matchRelSpecNodesQ g spec = prependCaller "matchRelSpecNodes: " $ do
  let qNodeSpecs = Map.toList
        $ Map.filter (\ns -> case ns of NodeSpecQ _ -> True; _ -> False)
        $ spec :: [(RelRole,NodeOrVarQ)]
  nodeListList <- mapM (\(r,NodeSpecQ n) -> usersInRoleQ g n r) qNodeSpecs
  return $ listIntersect nodeListList

-- ifdo speed: this searches for nodes, then searches again for labels
matchRelSpecNodesLabQ :: RSLT -> RelSpecQ -> Either DwtErr [LNode Expr]
matchRelSpecNodesLabQ g spec = prependCaller "matchRelSpecNodesLab: " $ do
  ns <- matchRelSpecNodesQ g spec
  return $ zip ns $ map (fromJust . lab g) ns
    -- fromJust is safe because matchRelSpecNodesQ only returns Nodes in g

has1DirQ :: Mbrship -> RelSpecQ -> Bool
has1DirQ mv rc = 1 == length (Map.toList $ Map.filter f rc)
  where f (VarSpecQ y) = y == mv
        f _ = False

fork1DirQ :: RSLT -> QNode -> (Mbrship,RelSpecQ) -> Either DwtErr [Node]
fork1DirQ g qFrom (dir,axis) = do -- returns one generation, neighbors
  fromDir <- otherDir dir
  if has1DirQ fromDir axis then return ()
     else Left (Invalid, [ErrRelSpecQ axis]
               , "fork1DirQ: should have only one " ++ show fromDir)
  let dirRoles = Map.keys $ Map.filter (== VarSpecQ dir) axis
  axis' <- runReaderT (subNodeForVarsQ qFrom fromDir axis) g
  rels <- matchRelSpecNodesQ g axis'
  concat <$> mapM (\rel -> relElts g rel dirRoles) rels
    -- TODO: this line is unnecessary. just return the rels, not their elts.
      -- EXCEPT: that might hurt the dfs, bfs functions below

--TODO: fork1DirsQ
--fork1DirsQ :: RSLT -> QNode -> [(Mbrship,RelSpecQ)] -> Either DwtErr [Node]
--fork1DirsQ g q rs = concat <$> mapM (fork1Dir g n) rs

subNodeForVarsQ :: QNode -> Mbrship -> RelSpecQ
  -> ReaderT RSLT (Either DwtErr) RelSpecQ
subNodeForVarsQ q v r = do -- TODO: use prependCaller
  g <- ask
  n <- lift $ qGet1 g q
  let f (VarSpecQ v') = if v == v' then NodeSpecQ (QAt n) else VarSpecQ v'
      f x = x -- the v,v' distinction is needed; otherwise v gets masked
  lift $ Right $ Map.map f r -- ^ change each VarSpecQ v to NodeSpecQ n

_bfsOrDfsQ :: ([Node] -> [Node] -> [Node]) -- | determines dfs|bfs
  -> RSLT -> (Mbrship, RelSpecQ) -> [Node] -> [Node] -> Either DwtErr [Node]
_bfsOrDfsQ _ _ _ [] acc = return acc
_bfsOrDfsQ collector g qdir pending@(n:ns) acc = do
  newNodes <- fork1DirQ g (QAt n) qdir
    --ifdo speed: calls has1Dir redundantly
  _bfsOrDfsQ collector g qdir (nub $ collector newNodes ns) (n:acc)
    -- ifdo speed: discard visited nodes from graph

_dwtBfsQ = _bfsOrDfsQ (\new old -> old ++ new)
_dwtDfsQ = _bfsOrDfsQ (\new old -> new ++ old)

dwtDfsQ :: RSLT -> (Mbrship,RelSpecQ) -> [Node] -> Either DwtErr [Node]
dwtDfsQ g dir starts = do mapM_ (gelemM g) $ starts
                          (nub . reverse) <$> _dwtDfsQ g dir starts []

dwtBfsQ :: RSLT -> (Mbrship, RelSpecQ) -> [Node] -> Either DwtErr [Node]
dwtBfsQ g dir starts = do mapM_ (gelemM g) $ starts
                          (nub . reverse) <$> _dwtBfsQ g dir starts []