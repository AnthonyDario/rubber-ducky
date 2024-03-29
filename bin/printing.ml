open List

open Tree
open Interval
open Segment
open Eterm

(* Concrete Domain *)
let str_cval v =
    match v with
    | CInt i -> Int.to_string i
    | CFloat f -> Float.to_string f ;;

let rec str_caexp exp = 
    match exp with
    | CVal v      -> str_cval v
    | CVar (n, _) -> n
    | CAdd (l, r) -> str_caexp l ^ " + " ^ str_caexp r
    | CSub (l, r) -> str_caexp l ^ " - " ^ str_caexp r
    | CMul (l, r) -> str_caexp l ^ " * " ^ str_caexp r
    | CDiv (l, r) -> str_caexp l ^ " / " ^ str_caexp r ;;

let str_cbexp exp =
    match exp with
    | CLt (l, r) -> str_caexp l ^ " < "  ^ str_caexp r
    | CLe (l, r) -> str_caexp l ^ " <= " ^ str_caexp r
    | CEq (l, r) -> str_caexp l ^ " = "  ^ str_caexp r
    | CNe (l, r) -> str_caexp l ^ " != " ^ str_caexp r
    | CGe (l, r) -> str_caexp l ^ " >= "  ^ str_caexp r
    | CGt (l, r) -> str_caexp l ^ " > " ^ str_caexp r ;;

let rec str_cstmt stmt = 
    match stmt with
    | CAsgn (n, v) -> 
        n ^ " = " ^ str_caexp v
    | CIf (b, t, e) -> 
        "if (" ^ str_cbexp b ^ ")\nthen " ^ str_cstmt t ^ "\nelse " ^ str_cstmt e
    | CFor (i, c, a, b) ->
        "for (" ^ str_cstmt i ^ "; " ^ str_cbexp c ^ "; " ^ str_cstmt a ^ ")\n" ^
        str_cstmt b
    | CCol (f, s) -> str_cstmt f ^ ";\n" ^ str_cstmt s 
    | CRet aexp ->
        "return " ^ str_caexp aexp ^ ";"
    ;;

(* Abstract Domain *)
let str_interval i = 
    "[" ^ Format.sprintf "%f" i.l ^ 
    " ; " ^ Format.sprintf "%f" i.u ^ "]" ;;

let str_intr intr =
    match intr with
    | Intr i -> str_interval i
    | IntrErr -> "IntrErr"
    | IntrBot -> "_|_" ;;

let str_intrs is =
    fold_left (fun acc i -> acc ^ str_intr i ^ ", ") "{" is ^ "}" ;;

let str_iInterval i =
        "[" ^ Int.to_string i.l ^ 
        " ; " ^ Int.to_string i.u ^ "]" ;;

let str_iIntr intr =
    match intr with
    | Intr i -> str_iInterval i
    | IntrErr -> "IntrErr"
    | IntrBot -> "_|_" ;;

let str_seg ie =
    "(" ^ str_intr ie.int ^ ", " ^ Format.sprintf "%20.30f" ie.err ^ ")" ;;

let str_segs segs =
    fold_left (fun acc s -> acc ^ str_seg s ^ ", ") "{" segs ^ "}" ;;

let str_eterm trm = 
    match trm with
    | Eterm ies -> str_segs ies
    | Bot       -> "_" ;;

let str_id (id : id) = 
    match id with
    | Id n -> n
    | Const -> "Const" ;;

let str_aval v =
    match v with
    | AInt i -> str_iIntr i
    | AFloat Bot -> "_|_"
    | AFloat trm -> str_eterm trm ;;

let rec str_aaexp exp = 
    match exp with
    | AVal v      -> str_aval v
    | AVar (n, _) -> n
    | AAdd (l, r) -> str_aaexp l ^ " + " ^ str_aaexp r
    | ASub (l, r) -> str_aaexp l ^ " - " ^ str_aaexp r
    | AMul (l, r) -> str_aaexp l ^ " * " ^ str_aaexp r
    | ADiv (l, r) -> str_aaexp l ^ " / " ^ str_aaexp r ;;

let str_abexp exp =
    match exp with
    | ALt (l, r) -> str_aaexp l ^ " < "  ^ str_aaexp r
    | ALe (l, r) -> str_aaexp l ^ " <= " ^ str_aaexp r
    | AEq (l, r) -> str_aaexp l ^ " = "  ^ str_aaexp r
    | ANe (l, r) -> str_aaexp l ^ " != " ^ str_aaexp r
    | AGe (l, r) -> str_aaexp l ^ " >= "  ^ str_aaexp r
    | AGt (l, r) -> str_aaexp l ^ " > " ^ str_aaexp r ;;

let rec str_astmt stmt = 
    match stmt with
    | AAsgn (n, v) -> n ^ 
        " = " ^ str_aaexp v
    | AIf (b, t, e) -> 
        "if " ^ str_abexp b ^ "\nthen " ^ str_astmt t ^ "\nelse " ^ str_astmt e
    | AFor (i, c, a, b) ->
        "for (" ^ str_astmt i ^ "; " ^ str_abexp c ^ "; " ^ str_astmt a ^ ")\n" ^
        str_astmt b
    | ACol (f, s) -> str_astmt f ^ ";\n" ^ str_astmt s 
    | ARet aexp -> "return " ^ str_aaexp aexp ^ ";" ;;

let str_avar n amem = 
    match amem.lookup n with
    | Some (AInt ii) -> n ^ " -> " ^ str_iIntr ii
    | Some (AFloat et) -> n ^ " -> " ^ str_eterm et
    | None -> n ^ " -> _" ;;

let str_amem amem =
    fold_left (fun acc x -> acc ^ "\n" ^ (str_avar x amem))
              "" (SS.elements amem.dom) ;;

(* For CSV output *)
let csv_interval i = 
    "[" ^ Format.sprintf "%f" i.l ^ 
    " ; " ^ Format.sprintf "%f" i.u ^ "]" ;;

let csv_intr intr =
    match intr with
    | Intr i -> csv_interval i
    | IntrErr -> "IntrErr,"
    | IntrBot -> "_|_" ;;

let csv_iInterval i = Int.to_string i.l ^ "," ^ Int.to_string i.u ^ ",0.0";;

let csv_iIntr intr =
    match intr with
    | Intr i -> csv_iInterval i
    | IntrErr -> "IntrErr,IntrErr,0.0"
    | IntrBot -> "IntrBot,IntrBot,0.0" ;;

let csv_seg ie =
    Format.sprintf "%20.30e" (lower ie.int) ^ "," ^
    Format.sprintf "%20.30e" (upper ie.int) ^ "," ^
    Format.sprintf "%20.30e" ie.err;;

let csv_segs name segs =
    fold_left (fun acc s -> acc ^ name ^ ",flt," ^ csv_seg s ^ "\n") "" segs ;;

let csv_eterm name trm = 
    match trm with
    | Eterm ies -> csv_segs name ies
    | Bot       -> name ^ ",flt,Bot,Bot,0.0" ;;

let csv_avar n amem = 
    match amem.lookup n with
    | Some (AInt ii) -> n ^ ",int," ^ csv_iIntr ii
    | Some (AFloat et) -> csv_eterm n et
    | None -> n ^ " -> _" ;;

let csv_amem amem =
    fold_left (fun acc x -> acc ^ (csv_avar x amem) ^ "\n")
              "var,type,low,high,err\n" (SS.elements amem.dom) ;;
