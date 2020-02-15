open Core

type t =
  | Signature_item of Parsetree.signature_item
  | Structure_item of Parsetree.structure_item
  | Sequence of t list * t * t list

(* Huet's zipper for asts *)
type zipper =
  | Top
  | Node of {below: t list; parent: zipper; above: t list; }

type location =
  | MkLocation of t * zipper

let rec unwrap_module_type
    ({ pmty_desc; _ (* pmty_loc; pmty_attributes *) }: Parsetree.module_type) : _ option =
  begin match pmty_desc with
    (* | Parsetree.Pmty_ident _ -> (??) *)
    | Parsetree.Pmty_signature (h :: t) ->
      Some (Sequence ( [], Signature_item h, List.map ~f:(fun x -> Signature_item x) t))
    | Parsetree.Pmty_functor (_, o_mt, mt) ->
      begin match Option.bind ~f:unwrap_module_type o_mt with
        | Some v -> unwrap_module_type mt
                    |> Option.map ~f:(fun m -> Sequence ([],v,[m]))
        | None -> unwrap_module_type mt
                  |> Option.map ~f:(fun m -> Sequence ([], m,[]))
      end
    (* | Parsetree.Pmty_with (_, _) -> (??)
     * | Parsetree.Pmty_typeof _ -> (??)
     * | Parsetree.Pmty_extension _ -> (??)
     * | Parsetree.Pmty_alias _ -> (??) *)
    | _ -> None
  end 

let rec unwrap_module_expr
    ({ pmod_desc; _ (* pmod_loc; pmod_attributes *) }: Parsetree.module_expr)  =
  match pmod_desc with
  (* | Parsetree.Pmod_ident _ -> (??) *) (* X *)
  | Parsetree.Pmod_structure (m :: mt) ->
    Some (Sequence ([], Structure_item m, List.map ~f:(fun x -> Structure_item x) mt))
  (* struct ... end *)
  | Parsetree.Pmod_functor (_, o_mt, me) ->
    let o_mt = Option.bind ~f:unwrap_module_type o_mt in
    let o_me = unwrap_module_expr me in
    let expr = [o_mt; o_me] |> List.map ~f:(Option.to_list) |> ListLabels.flatten in
    begin match expr with
    | [h;r] -> Some (Sequence ([], h, [r]))
    | [h] -> Some (Sequence ([], h, []))
    | _ -> None
    end
  | Parsetree.Pmod_apply (mexp1, mexp2) ->
    let expr = [mexp1;mexp2]
               |> List.map ~f:unwrap_module_expr
               |> List.map ~f:Option.to_list
               |> ListLabels.flatten in
    begin match expr with
    | [h;r] -> Some (Sequence ([], h, [r]))
    | [h] -> Some (Sequence ([], h, []))
    | _ -> None
    end
  | Parsetree.Pmod_constraint (mexp1, mtyp1) ->
    let (let+) x f = Option.bind ~f x in
    let+ mexp1 = unwrap_module_expr mexp1 in
    let+ mtyp1 = unwrap_module_type mtyp1 in
    Some (Sequence ([], mexp1, [mtyp1]))
  (* | Parsetree.Pmod_unpack _ -> (??) *)
  (* | Parsetree.Pmod_extension _ -> (??) *)
  | _ -> None


let t_descend = function
  | Signature_item ({ psig_desc; _ } as si) -> begin match psig_desc with
      (* | Parsetree.Psig_value _ -> (??) *) (* val x: T *)
      (* | Parsetree.Psig_type (_, _) -> (??) *)  (* type t1 = ... and tn = ... *)
      (* | Parsetree.Psig_typesubst _ -> (??) *) (* type t1 = ... and tn = ... *)
      (* | Parsetree.Psig_typext _ -> (??) *) (* type t1 += ... *)
      (* | Parsetree.Psig_exception _ -> (??) *) (* type exn *)
      | Parsetree.Psig_module {
          (* pmd_name; *)
          pmd_type=pmd_type;
          (* pmd_attributes;
           * pmd_loc *) _ } ->
        unwrap_module_type pmd_type |> Option.value ~default:(Signature_item si)
      | _ -> Signature_item si
      (* | Parsetree.Psig_modsubst _ -> (??) *)
      (* | Parsetree.Psig_recmodule _ -> (??) *)
      (* | Parsetree.Psig_modtype _ -> (??) *)
      (* | Parsetree.Psig_open _ -> (??) *)
      (* | Parsetree.Psig_include _ -> (??) *)
      (* | Parsetree.Psig_class _ -> (??) *)
      (* | Parsetree.Psig_class_type _ -> (??) *)
      (* | Parsetree.Psig_attribute _ -> (??) *)
      (* | Parsetree.Psig_extension (_, _) -> (??)) *)
    end
  | Structure_item ({ pstr_desc; _ } as si) -> begin match pstr_desc with
      (* | Parsetree.Pstr_eval (_, _) -> (??) *) (* E *)
      (* | Parsetree.Pstr_value (_, _) -> (??) *)  (* let P1 = E1 and ... and Pn = EN *)
      (* | Parsetree.Pstr_primitive _ -> (??) *)
      (* | Parsetree.Pstr_type (_, _) -> (??) *)
      (* | Parsetree.Pstr_typext _ -> (??) *)
      (* | Parsetree.Pstr_exception _ -> (??) *)
      | Parsetree.Pstr_module { (* pmb_name; *) pmb_expr; _ (* pmb_attributes; pmb_loc *) } ->
        unwrap_module_expr pmb_expr |> Option.value ~default:(Structure_item si)
      (* | Parsetree.Pstr_recmodule _ -> (??) *)
      (* | Parsetree.Pstr_modtype _ -> (??) *)
      (* | Parsetree.Pstr_open _ -> (??) *)
      (* | Parsetree.Pstr_class _ -> (??) *)
      (* | Parsetree.Pstr_class_type _ -> (??) *)
      (* | Parsetree.Pstr_include _ -> (??) *)
      (* | Parsetree.Pstr_attribute _ -> (??) *)
      (* | Parsetree.Pstr_extension (_, _) -> (??) *)
      | _ -> Structure_item si
    end
  | v -> v

let rec t_to_bounds = function
  | Signature_item si ->
    let (iter,get) = Ast_transformer.bounds_iterator () in
    iter.signature_item iter si;
    get ()
  | Structure_item si ->
    let (iter,get) = Ast_transformer.bounds_iterator () in
    iter.structure_item iter si;
    get ()
  (* if its a sequence, take the union *)
  | Sequence (left,elem,right) ->
    List.map ~f:t_to_bounds (left @ right)
    |> List.fold ~f:(fun (x1,y1) (x2,y2) -> (min x1 x2, max y1 y2)) ~init:(t_to_bounds elem)

let t_list_to_bounds ls =
  match ls with
  | h :: t ->
    List.map ~f:t_to_bounds t
    |> List.fold ~f:(fun (x1,y1) (x2,y2) -> (min x1 x2, max y1 y2)) ~init:(t_to_bounds h)
    |> fun x -> Some x
  | _ -> None

(** converts a zipper to the bounds of the current item *)
let to_bounds (MkLocation (current,_)) = 
  t_to_bounds current

(** updates the bounds of the zipper by a fixed offset *)
let update_bounds ~(diff:int) state =
  let mapper = {Ast_mapper.default_mapper with location = (fun _ { loc_start; loc_end; loc_ghost } ->
      Location.{
        loc_start={loc_start with pos_cnum = (if loc_start.pos_cnum = -1
                                              then -1
                                              else loc_start.pos_cnum + diff)};
        loc_end={loc_end with pos_cnum = (if loc_end.pos_cnum = -1
                                          then -1
                                          else loc_end.pos_cnum + diff)};
        loc_ghost=loc_ghost}
    ) } in
  let rec update state = 
    match state with
    | Signature_item si -> Signature_item (mapper.signature_item mapper si)
    | Structure_item si -> Structure_item (mapper.structure_item mapper si)
    | Sequence (l,c,r) ->
      let update_ls = List.map ~f:update in
      Sequence (update_ls l, update c, update_ls r) in
  update state

let make_zipper_intf left intf right =
  let left = List.map ~f:(fun x -> Signature_item x) left in
  let right = List.map ~f:(fun x -> Signature_item x) right in
  let intf = Signature_item intf in
  MkLocation (Sequence (List.rev left, intf, right), Top)

let make_zipper_impl left impl right =
  let left = List.map ~f:(fun x -> Structure_item x) left in
  let right = List.map ~f:(fun x -> Structure_item x) right in
  let impl = Structure_item impl in
  MkLocation (Sequence (List.rev left, impl, right), Top)

let rec move_zipper_to_point point = function
  | MkLocation (Sequence (l,c,r), parent) ->
    move_zipper_to_point point (MkLocation (c, Node {below=l;parent; above=r;}))
  | v -> v

let go_up (MkLocation (current,parent)) =
  match parent with
  | Top -> None
  | Node { below; parent; above } ->
    let current = Sequence (below,current,above) in
    Some (MkLocation (current,parent))

let go_down (MkLocation (current,parent)) =
  match t_descend current with
  | Sequence (left,focused,right) ->
    Some (MkLocation (focused, Node {below=left;parent;above=right;}))
  | _ -> None

let go_left (MkLocation (current,parent)) =
  match parent with
  | Node { below=l::left; parent; above } ->
    Some (MkLocation (l, Node {below=left; parent; above=current::above}))
  | _ -> None

let go_right (MkLocation (current,parent)) =
  match parent with
  | Node { below; parent; above=r::right } ->
    Some (MkLocation (r, Node {below=current::below; parent; above=right}))
  | _ -> None

(** deletes the current element of the zipper  *)
let calculate_zipper_delete_bounds (MkLocation (current,_) as loc) =
  let current_bounds =  t_to_bounds current in
  let diff = fst current_bounds - snd current_bounds in
  let update_bounds = update_bounds ~diff in
  (* update parent *)
  let rec update_parent parent = match parent with
    | Top -> Top
    | Node {below;parent;above} ->
      let above = List.map ~f:update_bounds above in
      let parent = update_parent parent in 
      Node {below; parent; above} in
  (* returns a zipper with the first element removed *)
  let rec remove_current  (MkLocation (current,parent)) = 
    match parent with
    | Top -> None
    | Node {below; parent=up; above=r::right} ->
      let r = update_bounds r in
      let right = List.map ~f:update_bounds right in
      let up = update_parent up in
      Some (MkLocation(r, Node{below;parent=up;above=right}))
    | Node {below=l::left; parent=up; above=right} ->
      let right = List.map ~f:update_bounds right in
      let up = update_parent up in
      Some (MkLocation(l, Node{below=left;parent=up;above=right}))
    | Node {below=[]; parent=up; above=[]} ->
      remove_current (MkLocation (current, up)) in
  remove_current loc |> Option.map ~f:(fun v -> v,current_bounds) 

(** swaps two elements at the same level, returning the new location  *)
let calculate_swap_bounds (MkLocation (current,parent)) =
  match parent with
  | Node { below=l::left; parent; above=r::right; } ->
    let current_bounds =  t_to_bounds current in
    let prev_bounds = t_to_bounds l in
    let prev_diff = snd current_bounds - snd prev_bounds in
    let current_diff = fst prev_bounds - fst current_bounds in
    Some (
      current_bounds,
      prev_bounds,
      (MkLocation (
          r,
          (Node {
              below=(update_bounds ~diff:prev_diff l)::(update_bounds ~diff:current_diff current)::left;
              parent;
              above=right
            }))))
  | _ -> None

(** swaps two elements forward at the same level, returning the new location  *)
let calculate_swap_forward_bounds (MkLocation (current,parent)) =
  match parent with
  | Node { below=left; parent; above=r::right; } ->
    let current_bounds =  t_to_bounds current in
    let prev_bounds = t_to_bounds r in
    let prev_diff = fst current_bounds - fst prev_bounds in
    let current_diff = snd prev_bounds - snd current_bounds in
    Some (
      current_bounds,
      prev_bounds,
      MkLocation (
        (update_bounds ~diff:current_diff current),
        (Node {
            below=(update_bounds ~diff:prev_diff r)::left;
            parent;
            above=right;
          })))
  | _ -> None

(** swaps two elements forward at the same level, returning the new location  *)
let calculate_swap_backwards_bounds (MkLocation (current,parent)) =
  match parent with
  | Node { below=l::left; parent; above=right; } ->
    let current_bounds =  t_to_bounds current in
    let prev_bounds = t_to_bounds l in
    let prev_diff = snd current_bounds - snd prev_bounds in
    let current_diff = fst prev_bounds - fst current_bounds in
    Some (
      current_bounds,
      prev_bounds,
      MkLocation (
        (update_bounds ~diff:current_diff current),
        (Node {
            below=left;
            parent;
            above=(update_bounds ~diff:prev_diff l)::right;
          })))
  | _ -> None
