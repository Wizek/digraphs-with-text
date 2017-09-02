{-# LANGUAGE FlexibleContexts #-}

module Dwt.Leaf (
  _splitStringForTplt, mkTplt
  , subInTplt, padTpltStrings, subInTpltWithHashes
  , tpltArity, mbrListMatchesTpltArity
  , insLeaf
    , insWord, insTplt, insFl -- deprec ? insLeaf generalizes these
  , hasLEdgeM, isWord, isWordM, isTplt, isTpltM, isFl, isFlM
  , isRel, isRelM, isColl, isCollM, isLeaf, areLikeExprs
  ) where

import Dwt.Types
import Dwt.Util (hasLEdgeM)
import Data.Graph.Inductive (Node, Graph, lab, newNodes, insNode)
import Control.Monad.Except (MonadError, throwError, catchError)
import Data.Text (pack, unpack, strip, splitOn)


-- == Tplt
_splitStringForTplt :: String -> [String]
_splitStringForTplt t = map unpack $ splitOn (pack "_") (pack t)

mkTplt :: String -> Expr
mkTplt = Tplt
  . map (unpack . strip . pack)
  . _splitStringForTplt

subInTpltWithHashes :: Expr      -- must be a Tplt
                     -> [String] -- members for the Tplt
                     -> Int      -- relationship level = number of #s
                     -> String
  -- todo ? test length (should match arity), use Either
  -- todo ? test each tplt-string; if has space, wrap in parens
subInTpltWithHashes (Tplt ts) ss prefixCount =
  let ts' = padTpltStrings (Tplt ts)
          $ replicate (2^prefixCount) '#'
      pairList = zip ts' $ ss ++ [""]
       -- append "" because there are n+1 segments in an n-ary Tplt; 
         -- zipper ends early otherwise
  in foldl (\s (a,b) -> s++a++b) "" pairList
subInTpltWithHashes _ _ _ = error "subInTplt: not a Tplt" -- todo ? omit

subInTplt :: Expr -> [String] -> String
subInTplt (Tplt ts) ss = subInTpltWithHashes (Tplt ts) ss 0

padTpltStrings :: Expr -> String -> [String]
padTpltStrings (Tplt ss) prefix =
  let a = head ss
      z = last ss
      middle = reverse $ tail $ reverse $ tail ss
      f s = if elem ' ' s then '(' : (s ++ ")") else s
      doToMiddle s = " " ++ prefix ++ f s ++ " "
      doToFirst s = case s of "" -> ""
                              _ -> prefix ++ f s ++ " "
      doToLast  s = case s of "" -> ""
                              _ -> " " ++ prefix ++ f s
  in [doToFirst a] ++ map doToMiddle middle ++ [doToLast z]

tpltArity :: Expr -> Arity
tpltArity e = case e of Tplt ss -> length ss - 1
                        _       -> error "tpltArity: Expr not a Tplt."

mbrListMatchesTpltArity :: (MonadError String m) => [Node] -> Expr -> m ()
mbrListMatchesTpltArity ns e = case e of
  Tplt _ -> if (tpltArity e) == length ns
    then return ()
    else throwError "mbrListMatchesTpltArity: Tplt Arity /= number of member Nodes." 
  _ -> throwError "mbrListMatchesTpltArity: Expr not a Tplt."


-- == Insert
insLeaf :: Expr -> RSLT -> RSLT
  -- TODO : use this to avoid duplicate ways to delete, replace, ...
insLeaf e g = case isLeaf e of
  True -> insNode (newAddr, e) g where [newAddr] = newNodes 1 g
  False -> error $ "insLeaf: " ++ show e ++ "is not a leaf."

insWord :: String -> RSLT -> RSLT
insWord str = insLeaf (Word str)

insTplt :: String -> RSLT -> RSLT
insTplt s = insLeaf $ mkTplt s

insFl :: Float -> RSLT -> RSLT
insFl f = insLeaf $ Fl f


-- == Expr tests
_isExprMConstructor :: (MonadError String m, Graph gr) => (a -> Bool) ->
  gr a b -> Node -> m () -- constructs an isExprM function (Expr a variable)
  -- todo ? catch these erorrs, append strings
    -- otherwise the distinction bewteen absence and inequality is lost
_isExprMConstructor pred g n = case mExpr of 
    Nothing -> throwError $ "Node " ++ show n ++ " absent."
    Just expr ->  case pred expr of True -> return ()
                                    False -> throwError $ "is not"
  where mExpr = lab g n

isWord :: Expr -> Bool
isWord x = case x of Word _ -> True; _ -> False

isWordM :: (MonadError String m) => RSLT -> Node -> m ()
isWordM = _isExprMConstructor isWord

isTplt :: Expr -> Bool
isTplt x = case x of Tplt _ -> True; _ -> False

isTpltM :: (MonadError String m) => RSLT -> Node -> m ()
isTpltM = _isExprMConstructor isTplt

isFl :: Expr -> Bool
isFl x = case x of Fl _ -> True; _ -> False

isFlM :: (MonadError String m) => RSLT -> Node -> m ()
isFlM = _isExprMConstructor isFl

isRel :: Expr -> Bool
isRel x = case x of Rel -> True; _ -> False

isRelM :: (MonadError String m) => RSLT -> Node -> m ()
isRelM = _isExprMConstructor isRel

isColl :: Expr -> Bool
isColl x = case x of Coll -> True; _ -> False

isCollM :: (MonadError String m) => RSLT -> Node -> m ()
isCollM = _isExprMConstructor isColl

isLeaf :: Expr -> Bool -- todo ? make Leaf an Expr constructor
isLeaf (Word _) = True
isLeaf (Fl _) = True
isLeaf (Tplt _) = True
isLeaf _ = False

areLikeExprs :: Expr -> Expr -> Bool
areLikeExprs e f = case e of
  Word _  ->  case f of Word  _ -> True;  _ -> False
  Tplt _ ->  case f of Tplt _ -> True;  _ -> False
  Rel    ->  case f of Rel    -> True;  _ -> False
  Coll   ->  case f of Coll   -> True;  _ -> False
  RelSpecExpr _ ->  case f of RelSpecExpr _ -> True;  _ -> False