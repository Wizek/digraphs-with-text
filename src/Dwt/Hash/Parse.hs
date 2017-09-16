-- From an expression like "I #like turtles ##when the sun #is big", creates a set of instructions for adding expressions to a RSLT.
-- discussion: https://www.reddit.com/r/haskell/comments/6v9b13/can_this_problem_be_approached_from_the_bottomup/
{-# LANGUAGE ViewPatterns #-}

module Dwt.Hash.Parse where

import Text.Megaparsec
import Dwt.ParseUtils (Parser, anyWord, lexeme, parens, phrase, word, sc)
import Text.Megaparsec.Expr (makeExprParser, Operator(..))
import Text.Megaparsec.Char (satisfy, string, char)

import Data.Graph.Inductive (Node)
import Dwt.Types
import Dwt.Leaf (mkTplt)

import Control.Applicative (empty)
import Data.Void (Void)
import Data.List (intersperse)


hasBlanks :: Parser Bool
hasBlanks = (>0) . length . concat <$> (sc *> (many $ blank <|> other))
  where blank, other :: Parser String  -- order across the <|> matters
        blank = try $ word "_"
        other = const "" <$> anyWord


-- == Things used when parsing Word and Rel values
-- QNode expresses how to add (nested) data to the RSLT
isInsRel :: QNode -> Bool
isInsRel (QRel _ _ _) = True
isInsRel _ = False

startRel :: Level -> Joint -> QNode -> QNode -> QNode
startRel l j a b = QRel (EO True l) [j] [a,b]

-- | PITFALL: In "a # b # c # d", you might imagine evaluating the middle #
-- after the others. In that case both sides would be a QRel, and you would
-- want to modify both, rather than make one a member of the other. These
-- concat functions skip that possibility; one of the two QNode arguments is
-- always incorporated into the other. I believe that is safe, because 
-- expressions in serial on the same level will always be parsed left to
-- right, not outside to inside.
rightConcat :: Joint -> QNode -> QNode -> QNode
  -- TODO: if|when need speed, use a two-sided list of pairs
rightConcat j m (QRel eo joints mbrs)
  = QRel eo (joints ++ [j]) (mbrs ++ [m])
rightConcat _ _ _ = error "can only rightConcat into a QRel"

leftConcat :: Joint -> QNode -> QNode -> QNode
leftConcat j m (QRel eo joints mbrs)
  = QRel eo (j : joints) (m : mbrs)
leftConcat _ _ _ = error "can only leftConcat into a QRel"

close :: QNode -> QNode
close (QQLeaf x) = QQLeaf x
close (QRel (EO _     a) b c)
     = QRel (EO False a) b c

hash :: Level -> Joint -> QNode -> QNode -> QNode
hash l j a@(isInsRel -> False) b@(isInsRel -> False)       = startRel l j a b
hash l j a@(isInsRel -> False) b@(QRel (EO False _) _ _) = startRel l j a b
hash l j a@(QRel (EO False _) _ _) b@(isInsRel -> False) = startRel l j a b
hash l j a@(isInsRel -> False) b@(QRel (EO True l') _ _)
  | l < l' = error "Higher level should not have been evaluated first."
  | l == l' = leftConcat j a b -- I suspect this won't happen either
  | l > l' = startRel l j a b
hash l j a@(QRel (EO True l') _ _) b@(isInsRel -> False)
  | l < l' = error "Higher level should not have been evaluated first."
  | l == l' = rightConcat j b a -- but this will
  | l > l' = startRel l j a b
hash l j a@(QRel ea _ _) b@(QRel eb _ _) =
  let e = EO True l
      msg = unlines [ "Joint should have been evaluated earlier."
                    , "level: " ++ show l
                    , "joint: " ++ show j
                    , "left: " ++ show a
                    , "right: " ++ show b ]
  in if e <= eb then error msg
     else if e > ea then startRel l j a b
     else if e == ea then rightConcat j b a
     else error msg

-- == the QNode parser
expr :: Parser QNode
expr = makeExprParser term [ [InfixL $ try $ pHash n] | n <- [1..8] ]

term :: Parser QNode
term = QQLeaf <$> leaf
       <|> close <$> parens expr
       <|> absent where
  absent :: Parser QNode
  absent = const Absent <$> f <?> "Intended to \"find\" nothing."
  f = lookAhead $ const () <$> satisfy (== '#') <|> eof
    -- the Absent parser should look for #, but not ), because
    -- parentheses get consumed in pairs in an outer (earlier) context



pHashUnlabeled :: Int -> Parser ()
pHashUnlabeled n = const () <$> f
  where f = string (replicate n '#') <* notFollowedBy (char '#')

pHash :: Int -> Parser (QNode -> QNode -> QNode)
pHash n = lexeme $ do
  pHashUnlabeled n
  label <- option "" $ anyWord <|> parens phrase
  return $ hash n $ Joint label

leaf :: Parser Expr
leaf = do p <- some anyWord
          return $ case elem "_" p of True ->  mkTplt . f $ p
                                      False -> Word   . f $ p
  where f = concat . intersperse " " 
