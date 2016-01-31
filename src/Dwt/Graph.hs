    {-# LANGUAGE FlexibleContexts #-}

    module Dwt.Graph
      ( module Data.Graph.Inductive
      , module Dwt.Graph
      ) where

    import Dwt.Util
    import Data.Graph.Inductive
    import Data.Either (partitionEithers)
    import Data.List (intersect)
    import qualified Data.Map as Map
    import Data.Maybe (catMaybes, fromJust)
    import Control.Monad (mapM_)
    import Control.Monad.Except (MonadError, throwError, catchError)
    import Data.Text (splitOn, pack, unpack)

-- types
    type RelPos = Int -- the k members of a k-ary Rel take RelPos values [1..k]
    type Arity = Int

    type Mindmap = Gr Expr DwtEdge
    data Expr = Str String | Fl Float -- Str, Fl, Tplt: leaves(graph, not tree)
              | Tplt [String] | Rel | Coll
              | RelSpecExpr RelVarSpec deriving(Show,Read,Eq,Ord)

    data DwtEdge = RelEdge RelRole | CollEdge CollRole deriving(Show,Read,Eq,Ord)
    data RelRole = RelTplt | Mbr RelPos deriving(Show,Read,Eq,Ord)
    data CollRole = CollMbr | CollPrinciple deriving(Show,Read,Eq,Ord)

  -- for (partially) specifying Rels
    data MbrVar = It | Any | Ana | Kata -- todo ? use omission instead of Any
      deriving (Show,Read,Eq,Ord)
    data MbrSpec = VarSpec MbrVar | NodeSpec Node deriving(Show,Read,Eq,Ord)

    type RelVarSpec = Map.Map RelRole MbrVar -- subset of RelSpec info, but
      -- a RelVarSpec in a Mindmap is transformable into a RelSpec.
      -- The rest of the info can be inferred from the edges connected to it.
    type RelNodeSpec = Map.Map RelRole Node
    type RelSpec =    Map.Map RelRole MbrSpec
      -- if well-formed, has a Tplt, and RelPoss from 1 to the Tplt's Arity

-- build
  -- Tplt <-> String
    splitStringForTplt :: String -> [String]
    splitStringForTplt t = map unpack $ splitOn (pack "_") (pack t)

    stringToTplt :: String -> Expr
    stringToTplt = Tplt . splitStringForTplt -- even length=0 works

    subInTplt :: Expr -> [String] -> String -- todo ? test length, use Either
    subInTplt (Tplt ts) ss = let pairList = zip ts $ ss ++ [""] 
      -- append "" because there are n+1 segments in an n-ary Tplt; 
        -- zipper ends early otherwise
      in foldl (\s (a,b) -> s++a++b) "" pairList
    subInTplt _ _ = error "subInTplt: not a Tplt"

  -- insert
    -- todo ? use a single ins function for Str, Tplt, Fl
      -- I think yes: will otherwise need similar duplicates: delete, replace ...
    insLeaf :: Expr -> Mindmap -> Mindmap
    insLeaf e g = case isLeaf e of
      True -> insNode (newNode, e) g
        where [newNode] = newNodes 1 g
      False -> error $ "insLeaf: " ++ show e ++ "is not a leaf."

    insRel :: (MonadError String m) => Node -> [Node] -> Mindmap -> m Mindmap
    insRel tn ns g =
      do mapM_ (gelemM g) $ tn:ns
         t <- tpltAt g tn
         let a = tpltArity t
         nodesMatchTplt ns t
         return $ f (zip ns [1..a]) g'
      where newNode = head $ newNodes 1 g
            f []     g = g
            f (p:ps) g = f ps $ insEdge (newNode, fst p, RelEdge $ Mbr $ snd p) g
            g' =                insEdge (newNode, tn, RelEdge RelTplt)
                              $ insNode (newNode, Rel) g

    insRelUsf :: Node -> [Node] -> Mindmap -> Mindmap
    insRelUsf t ns g = if ta /= length ns -- t is tplt, otherwise like ns
        then error "insRelUsf: Tplt Arity /= number of members Nodes."
        else if any (==False) $ map (flip gelem g) $ (t:ns)
          then error "insRelUsf: One of those Nodes is not in the Mindmap." 
        else f (zip ns [1..ta]) g'
      where te@(Tplt ts) = fromJust $ lab g t -- can also error:
              -- by finding Str or Rel where expected Tplt
            ta = tpltArity te
            newNode = head $ newNodes 1 g
            f []     g = g
            f (p:ps) g = f ps $ insEdge (newNode, fst p, RelEdge $ Mbr $ snd p) g
            g' =                insEdge (newNode, t, RelEdge RelTplt)
                              $ insNode (newNode, Rel) g

    insColl :: (MonadError String m) => 
      (Maybe Node) -> -- title
      [Node] -> Mindmap -> m Mindmap
    insColl mt ns g = do
      mapM_ (gelemM g) ns
      let newNode = head $ newNodes 1 g
          nameEdges = case mt of Nothing -> []
                                 Just tn -> [(newNode, tn,CollEdge CollPrinciple)]
          newEdges = nameEdges ++
            map (\n -> (newNode, n, CollEdge CollMbr)) ns
      return $ insEdges newEdges $ insNode (newNode,Coll) g

    partitionRelSpec :: RelSpec -> (RelVarSpec, RelNodeSpec)
    partitionRelSpec rSpec =
      let (vs,ns) = Map.partition (\mSpec -> case mSpec of VarSpec _ -> True
                                                           NodeSpec _ -> False
                                  ) rSpec
      in ( Map.map  (\(VarSpec  v) -> v)  vs
         , Map.map  (\(NodeSpec n) -> n)  ns )

    insRelSpec :: (MonadError String m) => RelSpec -> Mindmap -> m Mindmap
    insRelSpec rSpec g = do
      let (varMap, nodeMap) = partitionRelSpec rSpec
          newNode = head $ newNodes 1 g
          newLNode = (newNode, RelSpecExpr varMap)
      mapM_ (gelemM g) $ Map.elems nodeMap
      let newLEdges = map (\(r,n) -> (newNode, n, RelEdge r))
                    $ Map.toList nodeMap
      return $ insEdges newLEdges
             $ insNode newLNode g

  -- edit
    chNonUserAt :: (MonadError String m) => Mindmap -> Node -> Expr -> m Mindmap
      -- Strs and Tplts are used, but are not users. (Rels and Colls use them.)
    chNonUserAt g n e' = do
      let me = lab g n
      let mismatch = throwError $ "chNonUserAt: constructor mismatch"
      case me of
        Just e@(Str _)  -> if isLikeExpr e e' then return () else mismatch
        Just e@(Tplt _) -> if isLikeExpr e e' then return () else mismatch
        Nothing -> throwError $ "chNonUserAt: Node " ++ show n ++ " absent."
        _       -> throwError $ "chNonUserAt: Node " ++ show n ++ " is a user."
      return $ chNonUserAtUsf g n e'

    chNonUserAtUsf :: Mindmap -> Node -> Expr -> Mindmap
    chNonUserAtUsf g n e = let (Just (a,b,c,d),g') = match n g
      in (a,b,e,d) & g'

    chRelMbr :: (MonadError String m) => 
      Mindmap -> Node -> Node -> RelRole -> m Mindmap
    chRelMbr g user newMbr role = do
      isRelM g user `catchError` (\_ -> throwError "chRelMbr: Node " ++ show user
        ++ " not a Rel.")
      gelemM g newMbr
      let candidates = [n | (n,lab) <- lsuc g user, lab == RelEdge role]
      if length candidates /= 1
        then throwError "chRelMbr: invalid graph state, or RelPos out of range"
        else return ()
      let oldMbr = head candidates
      return $ delLEdge (user,oldMbr,RelEdge role)
             $ insEdge (user,newMbr,RelEdge role) g

-- query
  -- tests and lookups for smaller-than-graph types
    gelemM :: (MonadError String m, Graph gr) => gr a b -> Node -> m ()
    gelemM g n = if gelem n g then return () 
      else throwError $ "gelemM: Node " ++ show n ++ " absent."

    hasLEdgeM :: (MonadError String m, Graph gr, Eq b, Show b) => 
      gr a b -> LEdge b -> m ()
    hasLEdgeM g le = if hasLEdge g le then return ()
      else throwError $ "hasLEdgeM: LEdge " ++ show le ++ " absent."

    _isExprConstructor :: (MonadError String m, Graph gr) => (a -> Bool) ->
      gr a b -> Node -> m Bool
    _isExprConstructor pred g n = case mExpr of 
        Nothing -> throwError $ "Node " ++ show n ++ " absent."
          -- todo ? report the using function (isStr, isTplt, isRel) in the error
        Just expr ->  return $ pred expr
      where mExpr = lab g n

    _isExprConstructorM :: (MonadError String m, Graph gr) => (a -> Bool) ->
      gr a b -> Node -> m ()
    _isExprConstructorM pred g n = case mExpr of 
        Nothing -> throwError $ "Node " ++ show n ++ " absent."
          -- todo ? report the using function (isStr, isTplt, isRel) in the error
        Just expr ->  case pred expr of True -> return ()
                                        False -> throwError $ "nope"
                                          -- TODO: catch, give more useful message
      where mExpr = lab g n

    -- TODO: These should return m (), so I can avoid all those case statements
    isStr :: (MonadError String m) => Mindmap -> Node -> m Bool
    isStr = _isExprConstructor (\x -> case x of Str _ -> True; _ -> False)

    isTplt :: Expr -> Bool
    isTplt x = case x of Tplt _ -> True; _ -> False

    isTpltM :: (MonadError String m) => Mindmap -> Node -> m ()
    isTpltM = _isExprConstructorM isTplt

    isFl :: Expr -> Bool
    isFl x = case x of Fl _ -> True; _ -> False

    isFlM :: (MonadError String m) => Mindmap -> Node -> m Bool
    isFlM = _isExprConstructor isFl

    isRel :: Expr -> Bool
    isRel x = case x of Rel -> True; _ -> False

    isRelM :: (MonadError String m) => Mindmap -> Node -> m ()
    isRelM = _isExprConstructorM isRel

    isColl :: (MonadError String m) => Mindmap -> Node -> m Bool
    isColl = _isExprConstructor (\x -> case x of Coll -> True; _ -> False)

    isLeaf :: Expr -> Bool -- TODO ? make Leaf an Expr constructor
    isLeaf (Str _) = True
    isLeaf (Fl _) = True
    isLeaf (Tplt _) = True
    isLeaf _ = False

    isLikeExpr :: Expr -> Expr -> Bool
    isLikeExpr e f = case e of
      Str _  ->  case f of Str  _ -> True;  _ -> False
      Tplt _ ->  case f of Tplt _ -> True;  _ -> False
      Rel    ->  case f of Rel    -> True;  _ -> False
      Coll   ->  case f of Coll   -> True;  _ -> False

    tpltAt :: (MonadError String m) => Mindmap -> Node -> m Expr
    tpltAt g tn = case lab g tn of
      Just t@(Tplt _) -> return t
      Nothing -> throwError $ "tpltAt: Node " ++ show tn ++ " absent."
      _       -> throwError $ "tpltAt: LNode " ++ show tn ++ " not a Tplt."

    relTplt :: (MonadError String m) => Mindmap -> Node -> m Expr
    relTplt g relNode = do
      isRelM g relNode `catchError` (\_ -> throwError 
        $ "relTplt: LNode " ++ show relNode ++ " not a Rel.")
      return $ fromJust $ lab g -- fromJust: safe, because found in next line
          $ head [n | (n, RelEdge RelTplt) <- lsuc g relNode]
      -- head: safe, because each Rel should have exactly one Tplt

    collPrinciple :: (MonadError String m) => Mindmap -> Node -> m Expr
    collPrinciple g collNode = do
      ic <- isColl g collNode
      if not ic then throwError $ "collName: LNode "++show collNode++" not a Coll"
                else return $ fromJust $ lab g $ head
                       [n | (n, CollEdge CollPrinciple) <- lsuc g collNode]
      -- head kind of safe, because each Rel should have exactly one Tplt

    tpltArity :: Expr -> Arity
    tpltArity e = case e of Tplt ss -> length ss - 1
                            _       -> error "tpltArity: Expr not a Tplt."

    nodesMatchTplt :: (MonadError String m) => [Node] -> Expr -> m ()
    nodesMatchTplt ns e = case e of
      Tplt _ -> if (tpltArity e) == length ns
        then return ()
        else throwError "nodesMatchTplt: Tplt Arity /= number of member Nodes." 
      _ -> throwError "nodesMatchTplt: Expr not a Tplt."

  -- .. -> [Node]
    users :: (MonadError String m, Graph gr) => gr a b -> Node -> m [Node]
    users g n = do gelemM g n
                   return [m | (m,label@_) <- lpre g n]

    -- Rels using Node n in RelRole r
    specUsers :: (MonadError String m) => Mindmap -> Node -> RelRole -> m [Node]
    specUsers g n r = do -- TODO ! bad name, spec(ific) conflicts with (Rel)spec
      gelemM g n
      return $ specUsersUsf g n r

    specUsersUsf :: (Graph gr) => gr a DwtEdge -> Node -> RelRole -> [Node]
    specUsersUsf g n r = [m | (m,r') <- lpre g n, r'==RelEdge r]

    redundancySubs :: RelSpec -> Map.Map Node String
    redundancySubs = Map.fromList 
      . map (\(NodeSpec n) -> (n,show n))
      . Map.elems
      . Map.filter (\ns -> case ns of NodeSpec _ -> True; _ -> False) 

    matchRel :: (MonadError String m) => Mindmap -> RelSpec -> m [Node]
    matchRel g spec = do
      let specList = Map.toList
            $ Map.filter (\ns -> case ns of NodeSpec _ -> True; _ -> False) 
            $ spec :: [(RelRole,MbrSpec)]
      nodeListList <- mapM (\(r,NodeSpec n) -> specUsers g n r) specList
      return $ listIntersect nodeListList

    has1Ana :: RelSpec -> Bool
    has1Ana rc = length as == 1
      where as = Map.toList 
               $ Map.filter (\x -> case x of VarSpec Ana -> True; _ -> False) 
               rc

    fork1Ana :: (MonadError String m) => Mindmap -> Node -> RelSpec -> m [Node]
    fork1Ana g n r = -- one generation, maybe many Katas, but only one Ana
      matchRel g r'
      -- TODO: Use katas to filter result
      where r' = Map.map (\x -> case x of VarSpec Ana -> NodeSpec n;
                                          _ -> x) r
            katas = Map.keys $ Map.filter (\x -> case x of VarSpec Kata -> True;
                                                           _ -> False) r

    validRole :: (MonadError String m) => Mindmap -> Node -> RelRole -> m ()
    validRole g relNode role = do
      isRelM g relNode `catchError` (\_ -> throwError 
        $ "validRole: Node " ++ show relNode ++ "not a Rel.")
      case role of
        RelTplt -> return ()
        Mbr p -> do
          if p < 1 then throwError $ "validRole: RelPos < 1" else return ()
          t <- relTplt g relNode
          let a = tpltArity t
          if p <= a then return ()
            else throwError $ "validRole: Arity " ++ show a ++ 
              " < RelPos " ++ show p

--    -- todo ? This generalizes relTplt; could rewrite relTplt to use it
--    relElts :: (MonadError String m) => Mindmap -> Node -> [RelRole] -> m [Node]
--    relElts g relNode roles = do
--      ir <- isRel g relNode
--      if not ir
--        then throwError $ "relTplt: LNode " ++ show relNode ++ " not a Rel."
--        else do
--          let a = tpltArity $ lab g relNode
--        --else return $ fromJust $ lab g -- fromJust: safe b/c found in next line
--          -- $ head [n | (n, RelEdge RelTplt) <- lsuc g relNode]
--      -- head kind of safe, because each Rel should have exactly one Tplt

--    fork :: Mindmap -> Node -> RelSpec -> [Node]
--    fork g n rc =
--      Use only RelSpecs in which there is exactly 1 Ana and 1 Kata.
--        Othewrise would have to make a sep RelSpec for each Ana (hard, no?),
--        use matchRel for each, and take their union.

--    chase :: (MonadError String m) => Mindmap -> Node -> RelSpec -> m [Node]
--    chase g n dir = do
--      gelemM g n
--      ... more ...

-- deprecated
    insStr :: String -> Mindmap -> Mindmap -- generalized to insLeaf
    insStr str g = insNode (newNode, Str str) g
      where newNode = head $ newNodes 1 g

    insTplt :: String -> Mindmap -> Mindmap -- generalized to insLeaf
    insTplt s g = insNode (newNode, stringToTplt s) g
      where newNode = head $ newNodes 1 g

    insFl :: Float -> Mindmap -> Mindmap -- generalized to insLeaf
    insFl f g = insNode (newNode, Fl f) g
      where newNode = head $ newNodes 1 g
