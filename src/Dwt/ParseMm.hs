-- usually folded
  -- TODO
   -- ? Work with the Eithers and Nothings rather than fighting them
   -- ? use safe Map lookups
  -- CREDITS: uses some functions by Jake Wheat
    -- https://github.com/JakeWheat/intro_to_parsing
    -- parse2 below is what Wheat called parseWithLeftOver
   -- styles|fonts: incomplete
    -- within-node ones, e.g. LOCALIZED_STYLE_REF="styles.topic", this captures
    -- but <font ...> tags outside of a node applicable to it, this does not

-- lang, modules
    {-# LANGUAGE FlexibleContexts #-}
    module Dwt.ParseMm
      ( module Text.Parsec
      , module Text.Parsec.String
      , module Dwt.ParseMm
      ) where
    import Text.Parsec
    import Text.Parsec.String (Parser)
    import Control.Monad.Except
    import qualified Data.Map as Map
    import qualified Data.Maybe as Mb
    import qualified Data.Time as T
    import qualified Data.List as L

    import Dwt.Graph

-- types
    type MmNode = Int

    data MlTag = MlTag { title :: String 
                       , isStart :: Bool -- starting < is start; </ is not
                       , isEnd :: Bool   -- ending /> is end; > is not
                       , mlMap :: Map.Map String String
                       } | Comment deriving (Eq, Show)

    data MmNLab = MmNLab { text :: String
                         , mmId :: MmNode
                         , style :: Maybe String
                         , created :: T.UTCTime
                         , modified :: T.UTCTime } deriving (Eq, Show)

    data MmELab = TreeEdge | ArrowEdge deriving (Eq, Show)

    data MmObj = MmText MmNLab | MmArrow {dest ::  MmNode}
      deriving (Eq, Show)
      -- the xml is an interleaved nested list of nodes and arrows
        -- the nesting matters; it lets succesion be implicit
      -- to process such a list, I need a type that unifies those two things

    type DwtSpec = ( [MmNLab], [(MmNode,MmNode,MmELab)] )

-- constructors
    mmNLabDummy :: MmNLab
    mmNLabDummy = MmNLab "hi" 0 Nothing t t
      where t = T.UTCTime (T.fromGregorian 1989 11 30) 0

    meMapLookup :: (Ord k, Show k, MonadError String me) -- TODO ? BAD
      => k -> Map.Map k a -> me a
    meMapLookup k m = case Map.lookup k m of
      Just a -> return a
      Nothing -> throwError $ "meMapLookup: " ++ show k ++ " not in map."

-- parsing
  -- Parser a -> String -> _
    parseWithEof :: Parser a -> String -> Either ParseError a
    parseWithEof p = parse (p <* eof) ""

    eParse :: Parser a -> String -> Either ParseError a
    eParse p = parse p ""

    eParse2 :: Parser a -> String -> Either ParseError (a,String)
    eParse2 p = parse ((,) <$> p <*> leftOver) ""
      where leftOver = manyTill anyToken eof

  -- parsing the .mm format
   -- elements of the mlTag parser
    lexeme :: Parser a -> Parser a
    lexeme p = p <* spaces

    mmEscapedChar :: Parser Char
    mmEscapedChar = mmLeftAngle <|> mmNewline <|> mmRightAngle 
        <|> mmCaret <|> mmAmpersand <|> mmApostrophe
      where sandwich s = try $ string $ "&" ++ s ++ ";"
            mmLeftAngle = pure '<' <* sandwich "lt"
            mmNewline = pure '\n' <* sandwich "#xa"
            mmRightAngle = pure '>' <* sandwich "gt"
            mmCaret = pure '"' <* sandwich "quot"
            mmAmpersand = pure '&' <* sandwich "amp"
            mmApostrophe = pure '\'' <* sandwich "apos"

    mmStr = between quot quot 
      $ many $ mmEscapedChar <|> satisfy (/= '"')
      where quot = char '"'

    word :: Parser String -- that is, a Word outside of an MmNLab
    word = many1 $ alphaNum <|> char '_'

    keyValPair :: Parser (String,String)
    keyValPair = (,) <$> (lexeme word <* lexeme (char '=')) <*> lexeme mmStr

   -- parsing tags and comments
    mlTag :: Parser MlTag -- IS tested but strangely
    mlTag = do isStart <- startsItself
               title <- lexeme word
               pairs <- many $ lexeme keyValPair
               isEnd <- endsItself -- not use lexeme here, rather a level up
               return $ MlTag { title = title
                              , isStart = isStart
                              , isEnd = isEnd
                              , mlMap = Map.fromList pairs
                              }
      where endsItself =     (string "/>" >> return True) 
                         <|> (string ">" >> return False) :: Parser Bool
            startsItself  =  (try $ string "</" >> return False)
                         <|> (string "<" >> return True) :: Parser Bool

    comment :: Parser MlTag -- found in Text.ParserCombinators.Parsec.Combinator
    comment  = do string "<!--"
                  manyTill anyChar (try $ string "-->")
                  return Comment

    strip :: Parser a -> Parser [Char]
    strip p = many $ (skipMany $ try p) >> anyChar

    parseMmFile :: String -> Either ParseError [MlTag]
      -- MYST ? how to unify this two-parse strategy with the usual parser idiom
    parseMmFile f = case eParse (strip comment) f of 
        Right f' ->  eParse (many $ lexeme mlTag) f'
        Left e -> throwError e

-- functions of type (Functor f => f MlTag -> _), and their helpers
  -- helpers
    parseIdUsf :: String -> Either ParseError MmNode -- TODO: not really Usf
      -- rather, the other should be prefixed "Me" (MonadError)
    parseIdUsf s = read <$> eParse (string "ID_" *> many digit) s

    parseId :: (MonadError String m) => String -> m MmNode
    parseId s = let e = parseIdUsf s
      in case e of Right n -> return n
                   Left e -> throwError $ show e

    fromRight :: Either a b -> b -- TODO ? BAD
    fromRight (Right b) = b
    fromRight (Left _) = error "fromRight: Left"

    mmTimeToTime :: Int -> T.UTCTime
    mmTimeToTime mt = T.addUTCTime dur start
      where seconds = floor $ fromIntegral mt / 1000
            dur = realToFrac $ T.secondsToDiffTime seconds
            start = T.UTCTime (T.fromGregorian 1970 1 1) 0

  -- MlTag -> _
    tagToKeep :: MlTag -> Bool
    tagToKeep t = elem (title t) ["node","arrowlink"]

    readMmNLabUsf :: MlTag -> MmNLab -- this process is lossy
      -- that is, the ml tag has more info than I use
    readMmNLabUsf tag = 
      let m = mlMap tag
          text = m Map.! "TEXT"
          mmId = fromRight $ parseIdUsf $ m Map.! "ID"
          style = if Map.member "LOCALIZED_STYLE_REF" m
                    then Just $ m Map.! "LOCALIZED_STYLE_REF"
                    else Nothing
          created = mmTimeToTime $ read $ m Map.! "CREATED"
          modified = mmTimeToTime $ read $ m Map.! "MODIFIED"
      in MmNLab text mmId style created modified

    readMmNLab :: (MonadError String me) => MlTag -> me MmNLab
    readMmNLab tag = 
      let m = mlMap tag
          style = Map.lookup "LOCALIZED_STYLE_REF" m -- style stays Maybe
          parseTime = mmTimeToTime . read
      in do text <- meMapLookup "TEXT" m
            mmId <- meMapLookup "ID" m >>= parseId
            created <- meMapLookup "CREATED" m
            modified <- meMapLookup "MODIFIED" m
            return $ MmNLab text mmId style (parseTime created) 
                                            (parseTime modified)

    mlArrowDest :: MlTag -> Either ParseError MmNode
    mlArrowDest m = parseIdUsf $ mlMap m Map.! "DESTINATION"

  -- dwtSpec :: [MlTag] -> Either String DwtSpec
    dwtSpec :: [MlTag] -> Either String DwtSpec
    dwtSpec [] = Right ([],[]) -- silly case; could arguably return Left
    dwtSpec tags =
      let relevantTags = filter (flip elem ["node","arrowlink"] . title) tags
          rootLab = readMmNLabUsf $ head relevantTags
            -- Assumes the first tag is a node, because it can't be an arrow.
      in dwtSpec' [mmId rootLab] (tail relevantTags) ([rootLab], [])

    dwtSpec' :: [MmNode] -> [MlTag] -> DwtSpec -> Either String DwtSpec
    dwtSpec' [] [] spec = Right spec
    dwtSpec' _ [] spec = Left "ran out of MmTags but not ancestors."
    dwtSpec' ancestry tags spec@(nLabs,lEdges) = case title ht of
      "node" -> case isStart ht of
        False -> dwtSpec' (tail ancestry) (tail tags) spec
        True -> case isEnd ht of
          False -> dwtSpec' (mmId newNLab : ancestry) (tail tags) newSpec
          True ->  dwtSpec'                 ancestry  (tail tags) newSpec
          where newNLab = readMmNLabUsf ht
                newLEdge = (head ancestry, mmId newNLab, TreeEdge)
                newSpec = (newNLab : nLabs, newLEdge : lEdges)
      "arrowlink" -> let Right dest = mlArrowDest ht
                         newLEdge = (head ancestry, dest, ArrowEdge)
        in dwtSpec' ancestry (tail tags) (nLabs, newLEdge:lEdges)
      _ -> Left "MmTag neither a node nor an arrow"
      where ht = head tags

-- DwtSpec -> _
    styles :: DwtSpec -> [String]
    styles = L.nub . Mb.mapMaybe style . fst

    -- make the graph frame
      -- make a node for each style. number them 1-k. save k.
      -- make a "mmStyles" category node, holding those
      -- make "_ mm-succeeds _" and "_ mm-arrow _" rels
      -- make a "mmEdge" category node, holding those
      -- make a "mmSystem" category node, holding those categories
      -- make "_ was created on _" and "_ was last modified on _" nodes
      -- make a "system: time" category, holding those
        -- this is not exclusive to the .mm format
      -- multiply all Nodes by (-1)
        -- this way no existing IDs will overlap them
      -- return the graph and a Map [String] Int for the fonts
        -- Map.fromList $ zip strings $ (*(-1)) <$> [1..]

    -- load into the frame
      -- for each MmNLab
        -- add it keeping its ID intact
        -- connect it to the corresponding style node
        -- create two more nodes for its created-on and modified-on times
        -- connect it to those
