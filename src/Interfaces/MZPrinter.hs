{-|
Module      : MZPrinter
Description : MiniZinc pretty-printer
Copyright   : (c) Some Guy, 2013
                  Someone Else, 2014
License     : BSD3
Maintainer  : Klara Marntirosian <klara.mar@cs.kuleuven.be>
Stability   : experimental

This module provides a pretty-printer of MiniZinc models represented through the "MZAST" module.
This pretty-printer is based on the "Text.PrettyPrint" module.
-}

module Interfaces.MZPrinter(
  Interfaces.MZAST.MZModel,
  printModel,
  printItem,
  printNakedExpr,
  printExpr
) where

import Text.PrettyPrint
import Data.List
import Interfaces.MZAST
import Interfaces.MZBuiltIns
  
-- | Prints the represented MiniZinc model. Essentially, this function applies 'printItem' on
-- each element of the specified model.
printModel :: MZModel -> Doc
printModel = foldl1 ($+$) . map printItem -- foldR1?

-- | Prints an item of the represented model. Example:
-- 
-- >>> printItem $ Pred "even" [(Dec, Int, "x")] (Just (Bi Eq (Bi Mod (Var "x") (IConst 2)) (IConst 0)))
-- predicate even(var int: x) =
--   x mod 2 = 0;
printItem :: Item -> Doc
printItem (Empty)                 = text ""
printItem (Comment str)           = text "%" <+> text str
printItem (Include file)          = text "include" <+> doubleQuotes (text file) <> semi
printItem (Declare p ans me)      = printParam p
                                    <> printBody me
                                    <> semi
printItem (Constraint c)          = text "constraint" 
                                    <+> printExpr c 
                                    <> semi
printItem (Assign var expr)       = text var 
                                    <+> equals
                                    <> printBody (Just expr)
                                    <> semi
printItem (Output e)              = text "output" 
                                    <+> printNakedExpr e 
                                    <> semi
printItem (AnnotDec name ps)      = text "annotation" 
                                    <+> text name 
                                    <> parens (printParams ps) 
                                    <> semi
printItem (Solve ans s)           = text "solve" 
                                    <+> printAnnotations ans
                                    <+> printSolve s 
                                    <> semi
printItem (Pred name ps ans me)   = text "predicate" 
                                    <+> text name 
                                    <> parens (printParams ps)
                                    <+> printAnnotations ans
                                    <> printBody me
                                    <> semi
printItem (Test name ps ans me)   = text "test" 
                                    <+> text name 
                                    <> parens (printParams ps)
                                    <+> printAnnotations ans
                                    <> printBody me
                                    <> semi
printItem (Function p ps ans me)  = text "function" 
                                    <+> printParam p 
                                    <> parens (printParams ps) 
                                    <+> printAnnotations ans
                                    <> printBody me
                                    <> semi

printBody :: Maybe NakedExpr -> Doc
printBody Nothing   = empty
printBody (Just e)  = space <> equals $+$ nest 2 (printNakedExpr e)

printExpr :: Expr -> Doc
printExpr (Expr e ans) = printNakedExpr e <> printAnnotations ans

-- | Prints the represented MiniZinc expressions of a model. Examples:
-- 
-- >>> printNakedExpr $ SetComp (Bi Times (IConst 2) (Var "i")) ([(["i"], Range (IConst 1) (IConst 5))], Nothing)
-- {2 * i | i in 1..5}
-- 
-- >>> printNakedExpr $ Let [Declare Dec Int "x" (Just (IConst 3)), Declare Dec Int "y" (Just (IConst 4))] (Bi BPlus (Var "x") (Var "y"))
-- let {var int: x = 3;
--      var int: y = 4;}
-- in x + y
printNakedExpr :: NakedExpr -> Doc
printNakedExpr AnonVar             = text "_"
printNakedExpr (Var v)             = text v
printNakedExpr (BConst b)
  | b                         = text "true"
  | otherwise                 = text "false"
printNakedExpr (IConst n)          = int n
printNakedExpr (FConst x)          = float x
printNakedExpr (SConst str)        = doubleQuotes $ text (escape str)
printNakedExpr (Range e1 e2)       = printParensNakedExpr 0 e1 
                                     <> text ".." 
                                     <> (printParensNakedExpr 0 e2)
printNakedExpr (SetLit es)         = braces $ commaSepExpr es
printNakedExpr (SetComp e ct)      = braces (
                                       printNakedExpr e 
                                       <+> text "|" 
                                       <+> printCompTail ct
                                     )
printNakedExpr (ArrayLit es)       = brackets $ commaSepExpr es
printNakedExpr (ArrayLit2D ess)    = brackets (foldl1 ($+$) (map (\x -> text "|" <+> commaSepExpr x) ess) <> text "|")
printNakedExpr (ArrayComp e ct)    = brackets (printNakedExpr e <+> text "|" <+> printCompTail ct)
printNakedExpr (ArrayElem v es)    = text v <> brackets (commaSepExpr es)
printNakedExpr (U op e)            = printUop op <+> (if isAtomic e then printNakedExpr e else parens (printNakedExpr e))
printNakedExpr (Bi op e1 e2)       = printParensNakedExpr (opPrec op) e1 <+> printBop op <+> printParensNakedExpr (opPrec op) e2
printNakedExpr (Call f es)         = printFunc f <> parens (commaSepExpr es)
printNakedExpr (ITE [(e1, e2)] e3) = text "if" <+> printNakedExpr e1 <+> text "then" <+> printNakedExpr e2 
                                     $+$ text "else" <+> printNakedExpr e3 <+> text "endif"
printNakedExpr (ITE (te:tes) d)    = text "if" <+> printNakedExpr (fst te) <+> text "then" <+> printNakedExpr (snd te) 
                                     $+$ printEITExpr tes 
                                     $+$ text "else" <+> printNakedExpr d <+> text "endif"
printNakedExpr (Let is e)          = text "let" <+> braces (nest 4 (vcat (map printItem is))) $+$ text "in" <+> printNakedExpr e
printNakedExpr (GenCall f ct e)    = printFunc f <> parens (printCompTail ct)
                                     $+$ nest 2 (parens (printNakedExpr e))

-- Only helps for printing if-then-elseif-then-...-else-endif expressions
printEITExpr :: [(NakedExpr, NakedExpr)] -> Doc
printEITExpr [] = empty
printEITExpr (te:tes) = text "elseif" <+> printNakedExpr (fst te) <+> text "then" <+> printNakedExpr (snd te) $+$ printEITExpr tes
{-
printParensExpr :: Int -> Expr -> Doc
printParensExpr n (Expr e ans)
  = case e of
      U op e' -> printNakedExpr e <+> hsep (map printAnnotation ans)
-}
-- This function together with prec are used for placing parentheses in expressions
printParensNakedExpr :: Int -> NakedExpr -> Doc
printParensNakedExpr n e@(Bi op _ _)
  | n < opPrec op  = parens (printNakedExpr e)
  | otherwise    = printNakedExpr e
printParensNakedExpr _ e@(U _ ue) = if isAtomic ue then printNakedExpr ue else parens (printNakedExpr ue)
printParensNakedExpr _ e          = printNakedExpr e

printType :: Type -> Doc
printType Bool             = text "bool"
printType Float            = text "float"
printType Int              = text "int"
printType String           = text "string"
printType (Set t)          = text "set of" <+> printType t
printType (Array ts ti)    = text "array" <> brackets (commaSep printType ts) <+> text "of" <+> printTypeInst ti
printType (List ti)        = text "list of" <+> printTypeInst ti
printType (Opt t)          = text "opt" <+> printType t
printType (Ann)            = text "ann"
printType (Interval e1 e2) = printNakedExpr e1 <> text ".." <> printNakedExpr e2
printType (Elems es)       = braces $ commaSepExpr es
printType (AOS name)       = text name
printType (VarType name)   = text "$" <> text name

printCompTail :: CompTail -> Doc
printCompTail (gs, Nothing) = commaSep printGenerator gs
printCompTail (gs, Just wh) = commaSep printGenerator gs <+> text "where" <+> printNakedExpr wh

printGenerator :: Generator -> Doc
printGenerator (es, r) = text (intercalate ", " es) <+> text "in" <+> printNakedExpr r

printInst :: Inst -> Doc
printInst Dec = text "var"
printInst Par = text "par"

printFunc :: Func -> Doc
printFunc (CName name) = text name
printFunc (PrefBop op) = text "`" <> printBop op <> text "`"

printAnnotations :: [Annotation] -> Doc
printAnnotations ans = hsep (map printAnnotation ans)

printAnnotation :: Annotation -> Doc
printAnnotation (AName name es) = colon <> colon <+> text name <> parens (commaSepExpr es)

printBop :: Bop -> Doc
printBop (Bop b) = text b

printUop :: Uop -> Doc
printUop (Uop op) = text op

printSolve :: Solve -> Doc
printSolve Satisfy      = text "satisfy"
printSolve (Minimize e) = text "minimize" <+> printExpr e
printSolve (Maximize e) = text "maximize" <+> printExpr e

printParams :: [Param] -> Doc
printParams ps = commaSep printParam ps

-- Prints the parameters of call expressions (predicates, tests and functions) or annotations
printParam :: Param -> Doc
printParam (i, t, n) = printTypeInst (i, t) <> colon <+> text n

-- Prints the instantiation (var or par) and the type in a variable declaration. If the
-- type is Array or String, it does not print the inst, since these types are of fixed
-- inst. Same with @Ann@ type, but for other reasons.
printTypeInst :: (Inst, Type) -> Doc
printTypeInst (_, t@(Array _ _)) = printType t
printTypeInst (_, String)        = printType String
printTypeInst (_, Ann)           = printType Ann
printTypeInst (i, t)             = printInst i <+> printType t

-- Horizontally concatinates Docs while also putting a comma-space (", ") in between
commaSepDoc :: [Doc] -> Doc
commaSepDoc = hsep . punctuate comma

-- Vertically prints expressions, one per line
-- lineSepExpr :: [Expr] -> Doc
-- lineSepExpr = vcat . map printNakedExpr

-- First, map a function to a list and produce a list of Docs and then apply commaSepDoc
commaSep :: (a -> Doc) -> [a] -> Doc
commaSep f ls = commaSepDoc $ map f ls

-- Special case of commaSep, where f = printNakedExpr
commaSepExpr :: [NakedExpr] -> Doc
commaSepExpr = commaSep printNakedExpr

isAtomic :: NakedExpr -> Bool
isAtomic AnonVar    = True
isAtomic (Var _)    = True
isAtomic (BConst _) = True
isAtomic (IConst _) = True
isAtomic (FConst _) = True
isAtomic (SConst _) = True
isAtomic (SetLit _) = True
isAtomic _          = False

escape:: String -> String
escape str = concatMap escapeChar str

escapeChar :: Char -> String
escapeChar '\n' = "\\n"
escapeChar '\t' = "\\t"
escapeChar '\r' = "\\r"
escapeChar '\\' = "\\\\"
escapeChar '\f' = "\\f"
escapeChar '\a' = "\\a"
escapeChar c = [c]