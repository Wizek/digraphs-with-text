Table of Contents (eventually this format is Haskell)
    pre: Find all nodes using a leaf (even a Tplt)
    matchQRelspecNodes: find all relationships using the Nodes (ignore the variables) specified by a QRelspec
    Find all gold nodes (from Freeplane)

-- Find all nodes using a leaf, even a Tplt
    > labfilter (== mkTplt "_ uses font-> _") g
      mkGraph [(24,Tplt 2 [""," uses font-> ",""])] []
    > putStr $ view g $ pre g 24
      [The links here to Default Style could be deleted.]
    > putStrLn $ view g [7,8]
    (7,"_ #can _")
    (8,"turtles ##can swim")

--  matchQRelspecNodes: find all relationships using the Nodes (ignore the variables) specified by a QRelspec
    > let s = M.fromList [(TpltRole,QNodeSpec 7),(Mbr 1,QVarSpec Any),(Mbr 2,QVarSpec Any)]
    >  matchQRelspecNodes g s
    Right [8]

-- Find all gold nodes (from Freeplane)
    In Freeplane, I see the node with this text
        = already big enough to sort within
    is gold.
    > labfilter (== Word "= already big enough to sort within") g
      1182
    > putStr $ view g $ pre g 1182
      1526:24 [1182: = already big enough to sort within] uses font-> [7: AutomaticLayout.level,2]
        ..
    > let gold = 7 :: Dwt.Node
    > putStr $ view g $ pre g gold
