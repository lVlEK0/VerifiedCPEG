theory VeriCPEG
imports Main "~~/src/HOL/Nominal/Nominal"

begin

section{* Syntax of CPEG *}

(* baseTypes are given each literals of leafs *)
datatype baseTypes = bString | bInt | bBool

(* Here is the syntax of CPEG*)
datatype cpegExp = 
  empty
  | terminal char
  | nonterm cpegExp
  | seq cpegExp cpegExp
  | alt cpegExp cpegExp
  | rep cpegExp
  | not cpegExp
  | leaf baseTypes cpegExp
  | capture string "nodeExp list"
  | foldCap string cpegExp string "nodeExp list"  (* \<nu>0: string, e0: cpegExp,  L: string, [\<xi>]: nodeExp list *)
and  nodeExp =
  subtree string cpegExp
  | absorb cpegExp

(* To difine well-formed CPEG Expressions, we introduce a kind system *)
datatype cpegKind = treekind | stringkind
                
section{* Parsing Semantics *}
(** parsing results *)

(* tree is a final value of parsing result of well-formed expressions*)
datatype tree =
  baseValString string
  | baseValInt int
  | baseValBool bool
  | nodeVal string "(string \<times> tree) list"  

(* outputP includes final value and intermediate*)
datatype outputP = 
  fail                                                 
  | simbols string
  | ast tree

(* parsing function*)
(*
Each input cpegExp for paring must be a well-formed expression.
How to describe this conditioning in the type of parsing?
*)

type_synonym subtrees = "(string\<times>tree) list"

fun leftAssocTreeConstructor :: "string \<Rightarrow> tree \<Rightarrow> string \<Rightarrow> (subtrees list) \<Rightarrow> tree"
  where
  "leftAssocTreeConstructor nu0 d0 l (theta1#[]) = nodeVal l ((nu0,d0)#theta1)"
| "leftAssocTreeConstructor nu0 d0 l (thetaTl#theta) = nodeVal l ((nu0,leftAssocTreeConstructor nu0 d0 l theta)#thetaTl)"
| "leftAssocTreeConstructor nu0 d0 l [] = baseValString ''null Subtrees Theta was given''"


export_code leftAssocTreeConstructor in Haskell module_name LeftAssocTreeConstr file Haskell




function parsing :: "cpegExp \<Rightarrow> string \<Rightarrow> (outputP \<times> string)"
  and evalCapturedSubterm :: "(nodeExp list) \<Rightarrow> string \<Rightarrow> (subtrees \<times> string) option"
  and greedyRsTreeGene :: "nodeExp list \<Rightarrow> ((subtrees list) \<times> string) \<Rightarrow> ((subtrees list) \<times> string)"
  where
  "parsing empty xs = (simbols [],xs)"
| "parsing (terminal a) (x#xs) = (if a = x then (simbols ''a'',xs) else (fail, (x#xs)))"
| "parsing (terminal _) [] = (fail, [])"
| "parsing (nonterm e) xs =  parsing e xs"
| "parsing (seq e1 e2) xs = (case parsing e1 xs of
                             (fail,_) \<Rightarrow> (fail,xs)
                           | (simbols x,ys) \<Rightarrow> (case parsing e2 ys of
                                                (fail,_) \<Rightarrow> (fail,xs)
                                              | (simbols y,zs) \<Rightarrow> (simbols (x@y),zs)
                                              )
                           (* if e1 and e2 are well-formed expressions, they will not derive a value ast (TODO: SHOW IT!) *)
                          )"
| "parsing (alt e1 e2) xs = (case parsing e1 xs of
                             (fail,_) \<Rightarrow> parsing e2 xs
                           | (simbols x, ys) \<Rightarrow> (simbols x, ys)
                           | (ast t, ys) \<Rightarrow> (ast t, ys)
                            )"
| "parsing (not e) xs = (case parsing e xs of
                          (fail,_) \<Rightarrow> (simbols [],xs)
                        | (_, _) \<Rightarrow> (fail, xs)
                        )"
| "parsing (rep e) xs = (case parsing e xs of
                          (fail, _) \<Rightarrow> (simbols [],xs)
                        | (simbols x, ys) \<Rightarrow> (case parsing (rep e) ys of
                                               (fail, _) \<Rightarrow> (simbols x, ys)
                                             | (simbols y, zs) \<Rightarrow> (simbols (x@y), zs)
                                             )
                        )"
| "parsing (leaf ty e) xs = (case parsing e xs of
                          (fail, _) \<Rightarrow> (fail, xs)
                        | (simbols x, ys) \<Rightarrow> (case ty of
                                               bString \<Rightarrow> (ast (baseValString x), ys)
                                             | bInt    \<Rightarrow> (ast (baseValInt 1), ys)
                                             | bBool   \<Rightarrow> (ast (baseValBool True), ys)
                                             )
                        )"
                        (* if e is a well-formed expression it will not derive a value ast (TODO: SHOW IT!) *)
| "parsing (capture l xis) xs = (case evalCapturedSubterm xis xs of
                                  None \<Rightarrow> (fail, xs)
                                | Some (subtrees, ys) \<Rightarrow> (ast (nodeVal l subtrees),ys)
                                )"
| "evalCapturedSubterm [] xs = Some ([], xs)"
| "evalCapturedSubterm (e#es) xs = (case e of
                                     subtree \<nu> eSub \<Rightarrow> (case parsing eSub xs of
                                                          (fail, _) \<Rightarrow> None
                                                        | (ast d, ys) \<Rightarrow> (case evalCapturedSubterm es ys of
                                                                            None \<Rightarrow> None
                                                                          | Some (dyss,zs) \<Rightarrow> Some ((\<nu>, d)#dyss,zs)
                                                                         )
                                                       )
                                   | absorb eSub \<Rightarrow> (case parsing eSub xs of
                                                       (fail,_) \<Rightarrow> None
                                                     | (simbols x, ys) \<Rightarrow> Some ([],ys)
                                                    )
                                   )"
  (* \<nu>0: string, e0: cpegExp,  L: string, [\<xi>]: nodeExp list *)
| "parsing (foldCap nu0 e0 l xis) xs = (case parsing e0 xs of
                                              (fail, _) \<Rightarrow> (fail, xs)  (* E-Leftfolding2 *)
                                            | (ast d, ys) \<Rightarrow> (case evalCapturedSubterm xis ys of
                                                              None \<Rightarrow> (ast d, ys) (* E-Leftfolding3 *)
                                                            | Some (dyss, zs) \<Rightarrow> (\<lambda> (\<Theta>,zt). (ast (leftAssocTreeConstructor nu0 d l \<Theta>) , zt) ) (greedyRsTreeGene xis ([dyss],zs))
                                                             )
                                            )"
| "greedyRsTreeGene xis (theta,xs) = (case evalCapturedSubterm xis xs of
                                              None \<Rightarrow> (theta,xs)
                                            | Some (thetaHd,ys) \<Rightarrow> greedyRsTreeGene xis ((thetaHd#theta),ys)
                                            )"
sorry

fun fparse
  where
"fparse a b = parsing a b"

export_code fparse in Haskell



end