(* 
 * Adapted from Matt Might's blog post:
 * How to compile with continuations
 * http://matt.might.net/articles/cps-conversion/
 *)

(*
 * Input language: the lambda calculus
 *)
structure Lambda =
struct
   datatype expr = Var of string
                 | App of expr * expr
                 | Lam of string * expr
end

(*
 * Target CPS form
 *
 * Atomic expressions always produce a value and have no side effects
 * Complex expressions may not terminate and may have side effects
 *)
structure CPS =
struct
   datatype aexp = Lam of string list * cexp
                 | Var of string
        and cexp = App of aexp * aexp list
end

local
   val id = ref 0
in
   fun gensym s =
       let
          val n = !id before id := !id + 1
       in
          s ^ Int.toString n
       end
end

(* Naive transformation. *)

(*
 * M : Lambda.expr -> CPS.aexp
 * "converts an atomic value (a variable or a lambda term) into an atomic CPS value"
 *)
fun M (Lambda.Lam (x, body)) =
    let
       val k = gensym "$k"
    in
       CPS.Lam ([x, k], T (body, CPS.Var k))
    end
  | M (Lambda.Var x) = CPS.Var x
  | M _ = raise Match

(*
 * T : Lambda.expr * CPS.aexp -> CPS.cexp
 * "takes an expression and a syntactic continuation, and applies the continuation to a CPS-converted version of the expression."
 *)
and T (Lambda.App (f, e), cont) =
    let
       val f' = gensym "$f"
       val e' = gensym "$e"
    in
       T (f, CPS.Lam ([f'],
                      T (e, CPS.Lam ([e'],
                                     CPS.App (CPS.Var f', [CPS.Var e', cont])))))
    end
  | T (expr, cont) = CPS.App (cont, [M expr])

(* The higher-order transform. *)

(*
 * T : Lambda.expr * (CPS.aexp -> CPS.cexp) -> CPS.cexp
 * "T ... will receive a function instead of a syntactic continuation; this callback function will be passed an atomized version of the expression, and it is expected to produce a complex CPS form that utilizes it"
 *)
fun T (Lambda.App (f, e), k) =
    let
       val rv = gensym "$rv"
       val cont = CPS.Lam ([rv], k (CPS.Var rv))
    in
       T (f, fn f' =>
                T (e, fn e' =>
                         CPS.App (f', [e', cont])))
    end
  | T (expr, k) = k (M expr)

(*
 * M : Lambda.expr -> CPS.aexp
 *)
and M (Lambda.Lam (x, body)) =
    let
       val k = gensym "$k"
    in
       CPS.Lam ([x, k], T (body, fn rv => CPS.App (CPS.Var k, [rv])))
    end
  | M (e as Lambda.Var x) = CPS.Var x
  | M _ = raise Match

(* A hybrid transform. *)

(*
 * Tc : expr * aexp -> cexp
 * Tk : expr * (aexp -> cexp) => cexp
 * M : expr => aexp
 *)

(* Tk expects a higher-order continuation in k *)
fun Tk (Lambda.App (f, e), k) =
    let
       val rv = gensym "$rv"
       val cont = CPS.Lam ([rv], k (CPS.Var rv))
    in
       Tk (f, fn f' =>
                 Tk (e, fn e' =>
                           CPS.App (f', [e', cont])))
    end
  | Tk (expr, k) = k (M expr)

(* Tc expects a syntactic continuation in c *)
and Tc (Lambda.App (f, e), cont) =
    Tk (f, fn f' =>
              Tk (e, fn e' =>
                        CPS.App (f', [e', cont])))
  | Tc (expr, cont) = CPS.App (cont, [M expr])

and M (Lambda.Lam (x, body)) =
    let
       val k = gensym "$k"
    in
       CPS.Lam ([x, k], Tc (body, CPS.Var k))
    end
  | M (Lambda.Var x) = CPS.Var x
  | M _ = raise Match
