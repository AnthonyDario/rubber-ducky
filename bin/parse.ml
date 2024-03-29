(* Uses CIL to parse the C AST *)
module U = Util

open List
open GoblintCil
open Tree

module E = Errormsg
module F = Frontc
module C = Cil

exception ParseError of string ;;

let parse_file fname = 
    let _, cil = F.parse_with_cabs fname () in
    Rmtmps.removeUnusedTemps cil ;
    cil ;;

let transform_const c =
    match c with
    | CReal (f,_,_) ->
        CVal (CFloat f)
    | CInt (i,_,_) ->
        CVal (CInt (Cilint.int_of_cilint i))
    | CStr (_,_) ->
        raise (ParseError "CStr\n")
    | CWStr (_,_) ->
        raise (ParseError "CWStr\n")
    | CChr _ ->
        raise (ParseError "CChr\n")
    | CEnum (_,_,_) ->
        raise (ParseError "CEnum")
    ;;

let rec transform_arith_binop op l r =
    let new_l, new_r = (transform_aexp l, transform_aexp r) in
    match op with
    | PlusA ->
        CAdd (new_l, new_r)
    | MinusA ->
        CSub (new_l, new_r)
    | Mult ->
        CMul (new_l, new_r)
    | Div ->
        CDiv (new_l, new_r)
    | _ -> 
        raise (ParseError "Expected Arithmetic Binop\n") ; 
        (*
    | Lt ->
        CLt (new_l, new_r)
    | Gt ->
        CGt (new_l, new_r)
    | Le ->
        CLe (new_l, new_r)
    | Ge ->
        CGe (new_l, new_r)
    | Eq ->
        CEq (new_l, new_r)
    | Ne ->
        CNe (new_l, new_r)
        *)
    (*
    | LAnd ->
    | LOr ->
    *)
    
and transform_aexp e =
    match e with
    | Cil.Const c ->
        transform_const c
    | BinOp (op, l, r, _) ->
        transform_arith_binop op l r
    | Lval lv -> 
        let v = transform_lval lv in
        CVar (fst v, snd v)
    | CastE (ty, e) -> (
        match ty with
        | TInt _ | TFloat _ ->  (* TODO: note the loss of precision for float -> int casts *)
            transform_aexp e
        | _ -> raise (ParseError "Unsupported Cast\n") );
    | Real _ ->
        raise (ParseError "Real unsupported\n") 
    | AddrOf (_) ->
        raise (ParseError "AddrOf unsupported\n")
    | SizeOf _ ->
        raise (ParseError "SizeOf unsupported\n")
    | Imag _ ->
        raise (ParseError "Imag unsupported\n")
    | SizeOfE _ ->
        raise (ParseError "SizeOfE unsupported\n")
    | SizeOfStr _ ->
        raise (ParseError "SizeOfStr unsupported\n")
    | AlignOf _ ->
        raise (ParseError "AlignOf unsupported\n")
    | UnOp (_,_,_) ->
        raise (ParseError "UnOp unsupported\n")
    | Question (_,_,_,_) ->
        raise (ParseError "Question unsupported\n")
    | AddrOfLabel _ ->
        raise (ParseError "AddrOfLabel unsupported\n")
    | StartOf _ ->
        raise (ParseError "StartOf unsupported\n")
    | AlignOfE _ ->
        raise (ParseError "AlignOfE unsupported\n")

(* Gets the name of the variable *)
and transform_lval ((lhost, _) : lval) : (string * ctyp) =
    match lhost with
    | Var vi -> (vi.vname, get_type vi)
    | _ -> 
        raise (ParseError "lvalues of type [T] not supported\n") ;

and get_type (vi : varinfo) =
    match vi.vtype with
    | TInt (_,_) -> IntTyp
    | TFloat (_,_) -> FloatTyp
    | _ -> raise (ParseError "Unsupported variable type")
    ;;


(* TODO: Figure out how true/false is represented, possibly as 1 and 0 consts *)
let rec transform_bexp e =
    match e with
    | BinOp (op, l, r, _) ->
        transform_bool_binop op l r
    (*
    | Cil.Const c ->
        transform_const c
    *)
    | _ -> 
        raise (ParseError "Unknown exp\n") ;
    
and transform_bool_binop op l r =
    let new_l, new_r = (transform_aexp l, transform_aexp r) in
    match op with
    | Lt ->
        CLt (new_l, new_r)
    | Gt ->
        CGt (new_l, new_r)
    | Le ->
        CLe (new_l, new_r)
    | Ge ->
        CGe (new_l, new_r)
    | Eq ->
        CEq (new_l, new_r)
    | Ne ->
        CNe (new_l, new_r)
    | _ -> 
        raise (ParseError "Expected comparison operator\n") ;;
    (*
    | LAnd ->
    | LOr ->
    *)
    

let transform_instr i =
    match i with
    | Set (lv, e, _, _) ->
        CAsgn (fst (transform_lval lv), (transform_aexp e))
    | VarDecl (_,_) ->
        raise (ParseError "Variable declarations are not supported") ;
    | Call (_,_,_,_,_) ->
        raise (ParseError "Function calls are not supported\n") ;
    | Asm (_,_,_,_,_,_) ->
        raise (ParseError "Assembly is not supported\n") ;
    ;;

let rec transform_stmt s =
    match s.skind with
    | Instr is ->
        transform_instrs is
    | If (c, b1, b2,_,_) -> 
        CIf (transform_bexp c, transform_block b1, transform_block b2)
    | Return (e, _) -> (
        match e with
        | Some exp -> CRet (transform_aexp exp)
        (* | _ -> raise (ParseError "Empty return not supported")) *)
        | _ -> CRet (CVal (CInt 1)))
    | Loop (body, _,_, _, _) ->
        transform_loop body (hd s.preds)
    | Goto (_,_) ->
        raise (ParseError "Goto unsupported\n")
    | ComputedGoto (_,_) ->
        raise (ParseError "ComputedGoto unsupported\n")
    | Break _ -> 
        raise (ParseError "Break unsupported\n")
    | Continue _ ->
        raise (ParseError "Continue unsupported\n")
    | Switch (_,_,_,_,_) ->
        raise (ParseError "Switch unsupported\n")
    | Block _ ->
        raise (ParseError "Block unsupported\n")

and transform_instrs is =
    match is with
    | i1 :: is ->
        List.fold_left 
            (fun acc i -> CCol (acc, transform_instr i)) 
            (transform_instr i1) 
            is
    | [] -> raise (ParseError "Empty Instr") 

and transform_block b = 
    let stmts = 
        List.filter (fun s -> 
                        match s.skind with
                        | Break _ -> false 
                        | _ -> true) 
                    b.bstmts in
    match to_cstmts stmts with
    | s1 :: [] -> s1
    | s1 :: s ->
        List.fold_left (fun acc s -> CCol (acc, s)) s1 s
    | [] -> raise (ParseError "Empty block")


(* This "disgusting bespoke for-loop mangling" Is needed to get the
   initialization statment from the previous Instr list *)
and to_cstmts stmts = 
    List.mapi 
        (fun i s ->
            try let next_stmt = nth stmts (i + 1) in
                match s.skind, next_stmt.skind with
                | Instr is, Loop _ ->
                    next_stmt.preds <- [s] ; (* let the loop know about the init *)
                    transform_instrs (U.remove_last is)
                | _ -> transform_stmt s
            with (Failure _) -> transform_stmt s)
        stmts


and transform_loop block init = 
    let last_instr is = 
        match is.skind with
        | Instr is -> U.last is
        | _ -> raise (ParseError "Expected instructions at end of loop") in
    let init_instr = 
        match init.skind with
        | Instr is -> U.last is
        | _ -> raise (ParseError "Init instruction not added to beginning of loop") in
    let stmts = block.bstmts in
    CFor (transform_instrs [init_instr],
          extract_condition (hd stmts),
          transform_instr (last_instr (U.last stmts)),
          transform_loop_block {battrs = block.battrs ; bstmts = (tl stmts)})

(* Need to remove the last instruction from the last statment *)
and transform_loop_block block =
    let cleaned = 
        match (U.last block.bstmts).skind with
        | Instr is -> 
            (U.remove_last block.bstmts) @ [mkStmt (Instr (U.remove_last is))]
        | _ -> raise 
            (ParseError "Expected an Instr at the end of the loop body") 
    in
        transform_block {battrs = block.battrs ; bstmts = cleaned}

and extract_condition stmt =
    match stmt.skind with
    | If (c, _, _, _, _) -> transform_bexp c
    | _ -> raise (ParseError "Expected if condition from for loop")
    ;;

let transform_fun f =
    let { sformals = _; sbody = body ; _ } = f in
    transform_block body ;;

let transform_global g =
    match g with
    | GFun (dec,_) ->
        transform_fun dec
    | _ -> 
        raise (ParseError "Non-function globals not supported\n") ;
    (*
    | GType (_,_) -> 
        E.log "GType"
    | GCompTag (_,_) ->
        E.log "GCompTag"
    | GCompTagDecl (_,_) ->
        E.log "GCompTagDecl"
    | GEnumTag (_,_) ->
        E.log "GEnumTag"
    | GEnumTagDecl (_,_) ->
        E.log "GEnumTagDecl"
    | GVarDecl (_,_) ->
        E.log "GVarDecl"
    | GVar (_,_,_) ->
        E.log "GVar"
    | GAsm (_,_) ->
        E.log "GAsm"
    | GPragma (_,_) ->
        E.log "GPragma"
    | GText _ ->
        E.log "GText"
    *)
    ;;

let transform file fun_name = 
    transform_global 
        (List.find (fun g -> 
            match g with
            | GFun (dec,_) -> dec.svar.vname = fun_name
            | _ -> false) 
        file.globals ) ;;
