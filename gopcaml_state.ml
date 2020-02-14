open Core
open Ecaml

module State = struct

  module Filetype = struct
    (** records whether the current file is an interface or implementation  *)
    type s = Interface | Implementation [@@deriving sexp]

    module Enum : Ecaml.Value.Type.Enum with type t = s = struct
      type t = s
      let all = [Interface; Implementation]
      let sexp_of_t = sexp_of_s
    end

    let ty =
      let to_ecaml file_type =
        match file_type with
        | Interface -> Value.intern "interface"
        | Implementation -> Value.intern "implementation" in
      Value.Type.enum
        (Sexp.Atom "filetype")
        (module Enum)
        to_ecaml

    let to_string  = function
      | Interface -> "interface"
      | Implementation -> "implementation"

    type t = s
  end

  module DirtyRegion = struct

    (** tracks dirty extent of the current buffer as a range
        (in relation to the current buffer)

        we don't track it in relation to the ast due to the
        markers delimiting each structure item
        use automatically updating to buffer changes
    *)
    type t = { min: int; max: int; }

    let create bs be l =
      {min = bs; max = be + l}


    let update {min; max} (bs,be,l) =
      message (Printf.sprintf "updating dirty region from %d-%d to %d-%d on  s:%d-%d l:%d"
                 min max
                 (Int.min bs min)
                 (Int.max (be + l) (max + l))
                 bs be l);
      {min = (Int.min bs min); max = (Int.max (be + l) (max + l));}
  end


  (** region of the buffer  *)
  type region = {
    start_mark: Marker.t;
    end_mark: Marker.t ;
    (** denotes the start and end of the region  *)
    logical_start: Line_and_column.t;
    logical_end: Line_and_column.t 
  }

  (** holds the parse tree for the current file  *)
  type 'a ast_tree =
    (** the variant simply defines the type of ast.
        the value is a list of the top-level items, where each item is
        reported as: region * ast in that region

        when a change occurs, we:
        - find region containing change,
        - reparse region, update element 
        - if that fails (could be that toplevel structure changed),
          then parse from region start to end of file,
          update rest of list
    *)
    | Impl : (region * Parsetree.structure_item) list  -> Parsetree.structure_item ast_tree
    | Intf : (region * Parsetree.signature_item) list -> Parsetree.signature_item ast_tree

  type parse_tree =
    | MkParseTree : 'a ast_tree -> parse_tree

  type 'a ast_item =
    | ImplIt : (region * Parsetree.structure_item) -> Parsetree.structure_item ast_item
    | IntfIt : (region * Parsetree.signature_item)  -> Parsetree.signature_item ast_item

  type parse_item =
    | MkParseItem : 'a ast_item -> parse_item

  (** type of state of plugin - pre-validation *)
  type t = {
    (** file type of the current buffer *)
    file_type: Filetype.t;
    (** parse tree of the current buffer + any dirty regions *)
    parse_tree: (parse_tree * (DirtyRegion.t option)) option;
  }

  module Validated = struct
    (** type of valid state of plugin  *)
    type s = {
      (** file type of the current buffer *)
      file_type: Filetype.t;
      (** parse tree of the current buffer *)
      parse_tree: parse_tree;
    } 

    let of_state (state: t) =

      let (let+) x f = Option.bind ~f x in
      let+ (parse_tree, region) = state.parse_tree in
      assert (Option.is_none region);
      Some {file_type=state.file_type; parse_tree}

    type t = s

  end


  (** elisp type for state of system  *)
  let ty : t Value.Type.t =
    Caml_embed.create_type
      (Type_equal.Id.create
         ~name:"gopcaml-state"
         Sexplib0.Sexp_conv.sexp_of_opaque)

  let default = {
    file_type = Interface;
    parse_tree = None;
  }

end

let unwrap_current_buffer current_buffer =
  match current_buffer with Some v -> v | None -> Current_buffer.get () 

(** builds the abstract tree for the current buffer buffer  *)
let build_abstract_tree f g h ?current_buffer value =
  let current_buffer = unwrap_current_buffer current_buffer in
  let lexbuf = Lexing.from_string ~with_positions:true value in
  let items =
    f lexbuf
    |> List.map ~f:(fun item ->
        let (iterator,get_result) = Ast_transformer.bounds_iterator () in
        g iterator item;
        let ((min_line,min_column), (max_line,max_column)) = get_result () in
        let start_marker,end_marker = Marker.create (), Marker.create () in
        let get_position line column = 
          message (Printf.sprintf "getting position %d %d" line column);
          Position.of_int_exn (column + 1)
        in
        (* Point.goto_line_and_column Line_and_column.{line;column};
         * Point.get () in *)

        Marker.set start_marker current_buffer (get_position min_line min_column);
        Marker.set end_marker current_buffer (get_position max_line max_column);
        State.{start_mark=start_marker;
               end_mark=end_marker;
               logical_start = Line_and_column.{line=min_line;column=min_column}; 
               logical_end = Line_and_column.{line=min_line;column=min_column};
              },item)
  in
  try Either.First (h items) with
    Syntaxerr.Error e -> Either.Second e


let build_implementation_tree =
  build_abstract_tree
    Parse.implementation
    (fun iterator item -> iterator.structure_item iterator item)
    (fun x -> State.Impl x)

let build_interface_tree =
  build_abstract_tree
    Parse.interface
    (fun iterator item -> iterator.signature_item iterator item)
    (fun x -> State.Intf x)



(** determines the file-type of the current file based on its extension *)
let retrieve_current_file_type ~implementation_extensions ~interface_extensions =
  Current_buffer.file_name ()
  |> Option.bind ~f:(fun file_name ->
      String.split ~on:'.' file_name
      |> List.last
      |> Option.bind ~f:(fun ext ->
          message (Printf.sprintf "extension of %s is %s" file_name ext);
          message (Printf.sprintf "impls: %s, intfs: %s"
                     (String.concat ~sep:", " implementation_extensions)
                     (String.concat ~sep:", " interface_extensions)
                  );

          if List.mem ~equal:String.(=) implementation_extensions ext
          then begin
            message "filetype is implementation";
            Some State.Filetype.Implementation
          end
          else if List.mem ~equal:String.(=) interface_extensions ext
          then begin
            message "filetype is interface";
            Some State.Filetype.Interface
          end
          else None
        )
    )


(** attempts to parse the current buffer according to the inferred file type  *)
let parse_current_buffer ?start ?end_ file_type =
  let perform_parse () = 
  (* retrieve the text for the entire buffer *)
  let buffer_text =
    Current_buffer.contents ?start ?end_ () |> Text.to_utf8_bytes  in
  let _ = let open State.Filetype in
    match file_type with
    | Interface -> message "filetype is interface."
    | Implementation -> message "filetype is implementation." in
  message "Building parse tree - may take a while if the file is large...";
  let start_time = Time.now () in
  let parse_tree =
    let map ~f = Either.map ~second:(fun x -> x) ~first:(fun x -> f x) in
    let open State.Filetype in
    match file_type with
    | Implementation -> map ~f:(fun x -> State.MkParseTree x) @@
      build_implementation_tree buffer_text
    | Interface -> map ~f:(fun x -> State.MkParseTree x) @@
      build_interface_tree buffer_text
  in
  match parse_tree with
  | Either.Second e -> 
    message ("Could not build parse tree: " ^ ExtLib.dump e);
    None
  | Either.First tree ->
    let end_time = Time.now () in
    message (Printf.sprintf
               "Successfully built parse tree (%f ms)"
               ((Time.diff end_time start_time) |> Time.Span.to_ms)
            );
    Some tree
  in
  try perform_parse ()
  with Parser.Error -> 
       message (Printf.sprintf "parsing got error parse.error");
       None
     | Syntaxerr.Error err ->
       message (Printf.sprintf "parsing got error %s" (ExtLib.dump err));
       None


(** sets up the gopcaml-mode state - intended to be called by the startup hook of gopcaml mode*)
let setup_gopcaml_state
    ~state_var ~interface_extension_var ~implementation_extension_var =
  let current_buffer = Current_buffer.get () in
  (* we've set these values in their definition, so it doesn't make sense for them to be non-present *)
  let interface_extensions =
    Customization.value interface_extension_var in
  let implementation_extensions =
    Customization.value implementation_extension_var in
  let file_type =
    let inferred = retrieve_current_file_type
        ~implementation_extensions ~interface_extensions in
    match inferred with
    | Some vl -> vl
    | None ->
      message "Could not infer the ocaml type (interface or \
               implementation) of the current file - will attempt
               to proceed by defaulting to implementation.";
      State.Filetype.Implementation
  in
  let parse_tree = parse_current_buffer file_type in
  if Option.is_none parse_tree then
    message "Could not build parse tree - please ensure that the \
             buffer is syntactically correct and call \
             gopcaml-initialize to enable the full POWER of syntactic \
             editing.";
  let state = State.{
      file_type = file_type;
      parse_tree = Option.map ~f:(fun parse_tree -> (parse_tree,None)) parse_tree;
    } in
  Buffer_local.set state_var (Some state) current_buffer

(** retrieve the gopcaml state *)
let get_gopcaml_file_type ?current_buffer ~state_var () =
  let current_buffer = match current_buffer with Some v -> v | None -> Current_buffer.get () in
  let state = Buffer_local.get_exn state_var current_buffer in
  let file_type_name = State.Filetype.to_string state.State.file_type in
  file_type_name

(** update the file type of the variable   *)
let set_gopcaml_file_type ?current_buffer ~state_var file_type =
  let current_buffer = match current_buffer with Some v -> v | None -> Current_buffer.get () in
  let state = Buffer_local.get_exn state_var current_buffer in
  let state = State.{state with file_type = file_type } in
  Buffer_local.set state_var (Some state) current_buffer

let find_enclosing_structure (state: State.Validated.t) point : State.parse_item option =
  let open State in
  let open Validated in
  let find_enclosing_expression list = 
    List.find list ~f:(fun (region,_) ->
        let (let+) v f = Option.bind ~f v in
        let contains = 
          let+ start_position = Marker.position region.start_mark in
          let+ end_position = Marker.position region.end_mark in           
          Some (Position.between ~low:start_position ~high:end_position point) in
        Option.value ~default:false contains) in
  match state.parse_tree with 
  | (State.MkParseTree (State.Impl si_list)) ->
    find_enclosing_expression si_list  |> Option.map ~f:(fun x -> State.MkParseItem (State.ImplIt x))
  | (State.MkParseTree (State.Intf si_list)) ->
    find_enclosing_expression si_list |> Option.map ~f:(fun x -> State.MkParseItem (State.IntfIt x))

(** returns a tuple of points enclosing the current structure *)
let find_enclosing_structure_bounds (state: State.Validated.t) ~point =
  find_enclosing_structure state point
  |> Option.bind ~f:begin fun expr -> let (State.MkParseItem expr) = expr in
    let region = match expr with
      | ImplIt (r,_) -> r
      | IntfIt (r,_) -> r in
    match Marker.position region.start_mark,Marker.position region.end_mark with
    | Some s, Some e -> Some (Position.add s 0, Position.add e 0)
    | _ -> None
  end

let calculate_region mi ma structure_list _ (* dirty_region *) =
  let open State in
  (* first split the list of structure-items by whether they are invalid or not  *)
  let is_invalid ms2 me2 =
    let region_contains s1 e1 s2 e2  =
      let open Position in
      (((s1 <= s2) && (s2 <= e1)) ||
       ((s1 <= e2) && (e2 <= e1)) ||
       ((s2 <= s1) && (s1 <= e2)) ||
       ((s2 <= e1) && (e1 <= e2))
      ) in
    match Marker.position ms2, Marker.position me2 with
    | Some s2, Some e2 ->
      region_contains mi ma s2 e2
    | _ -> true in
  let (pre, invalid) =
    List.split_while ~f:(fun ({ start_mark; end_mark; _ }, _) ->
        not @@ is_invalid start_mark end_mark
      ) structure_list in
  let invalid = List.rev invalid in
  let (post, inb) =
    List.split_while ~f:(fun ({ start_mark; end_mark; _ }, _) ->
        not @@ is_invalid start_mark end_mark
      ) invalid in
  let post = List.rev post in
  (pre,inb,post) 

let calculate_start_end f mi ma pre_edit_region invalid_region post_edit_region =
    let start_region =
      match List.last pre_edit_region with
      | Some (_, st) ->
        let (iterator,get_bounds) =  Ast_transformer.bounds_iterator () in
        f iterator st;
        let ((_,_),(_,c)) = get_bounds () in
        Position.of_int_exn (c + 1)
      | None ->
        match invalid_region with
        | (_,st) :: _ ->
          let (iterator,get_bounds) =  Ast_transformer.bounds_iterator () in
          f iterator st;
          let ((_,_),(_,c)) = get_bounds () in
          Position.of_int_exn (c + 1)
        | [] -> mi
    in
    let end_region =
      match post_edit_region with
      | (_, st) :: _ ->
        let (iterator,get_bounds) =  Ast_transformer.bounds_iterator () in
        f iterator st;
        let ((_,_),(_,c)) = get_bounds () in
        Position.of_int_exn (c + 1)
      | [] ->
        match List.last invalid_region with
        | Some (_,st) ->
          let (iterator,get_bounds) =  Ast_transformer.bounds_iterator () in
          f iterator st;
          let ((_,_),(_,c)) = get_bounds () in
          Position.of_int_exn (c + 1)
        | None -> ma in
    (start_region,end_region)



let rebuild_region f start_region end_region pre_edit_region post_edit_region  =
  (* first, attempt to parse the exact modified region *)
  match parse_current_buffer
          ~start:start_region ~end_:end_region State.Filetype.Interface
  with
  | Some v -> let reparsed_range = f v in pre_edit_region @ reparsed_range @ post_edit_region
  | None ->
    (* otherwise, try to reparse from the start to the end *)
    match parse_current_buffer
            ~start:start_region State.Filetype.Interface
    with
    | Some v -> let reparsed_range = f v in pre_edit_region @ reparsed_range
    | None ->
      (* otherwise, try to reparse from the start to the end *)
      match parse_current_buffer State.Filetype.Interface
      with
      | Some v -> let reparsed_range = f v in reparsed_range
      | None -> pre_edit_region @ post_edit_region


let rebuild_intf_parse_tree structure_list dirty_region =
  let State.DirtyRegion.{min;max} = dirty_region in
  let mi,ma = Position.of_int_exn min, Position.of_int_exn max in
  let (pre_edit_region,invalid_region,post_edit_region) =
    calculate_region mi ma structure_list dirty_region in
  let (start_region,end_region) =
    calculate_start_end
      (fun iterator st -> iterator.signature_item iterator st)
      mi ma pre_edit_region invalid_region post_edit_region in
  let open State in 
  rebuild_region
    (fun (MkParseTree tree) -> 
       match tree with
       | Impl _ -> assert false
       | Intf reparsed_range -> reparsed_range)
    start_region end_region pre_edit_region post_edit_region

let rebuild_impl_parse_tree structure_list dirty_region =
  let State.DirtyRegion.{min;max} = dirty_region in
  let mi,ma = Position.of_int_exn min, Position.of_int_exn max in
  let (pre_edit_region,invalid_region,post_edit_region) =
    calculate_region mi ma structure_list dirty_region in
  let (start_region,end_region) =
    calculate_start_end
      (fun iterator st -> iterator.structure_item iterator st)
      mi ma pre_edit_region invalid_region post_edit_region in
  let open State in 
  rebuild_region
    (fun (MkParseTree tree) -> 
       match tree with
       | Impl reparsed_range -> reparsed_range
       | Intf _ -> assert false)
    start_region end_region pre_edit_region post_edit_region


(** updates the dirty region of the parse tree *)
let update_dirty_region ?current_buffer ~state_var (s,e,l) =
  message (Printf.sprintf "updating dirty region with s:%d-%d l:%d" s e l);
  let open State in
  let current_buffer = match current_buffer with Some v -> v | None -> Current_buffer.get () in
  let state = Buffer_local.get_exn state_var current_buffer in
  match state.parse_tree with
  | None ->
    message "no parse tree not updating dirty region";
    ()                  (* no parse tree, no point tracking dirty regions *)
  | Some ((MkParseTree tree), Some dr) ->
    message "dirty region present, removing";
    let parse_tree =
      Some (MkParseTree tree, Some (State.DirtyRegion.update dr (s,e,l))) in
    let state = {state with parse_tree = parse_tree} in
    Buffer_local.set state_var (Some state) current_buffer
  | Some (MkParseTree tree, None) ->
    let dr = State.DirtyRegion.create s e l in
    let parse_tree =
      Some (MkParseTree tree, Some (State.DirtyRegion.update dr (s,e,l))) in
    let state = {state with parse_tree = parse_tree} in
    Buffer_local.set state_var (Some state) current_buffer

(** retrieves the dirty region if it exists *)
let get_dirty_region ?current_buffer ~state_var ()  =
  let open State in
  let current_buffer = match current_buffer with Some v -> v | None -> Current_buffer.get () in
  let state = Buffer_local.get_exn state_var current_buffer in
  match state.parse_tree with
  | None -> None
  | Some ((MkParseTree _), Some { min; max }) -> Some (min,max)
  | Some (MkParseTree _, None) -> None

(** retrieves the gopcaml state value, attempting to construct the
    parse tree if it has not already been made *)
let retrieve_gopcaml_state ?current_buffer ~state_var =
  let open State in 
  let current_buffer = match current_buffer with Some v -> v | None -> Current_buffer.get () in
  let state = Buffer_local.get_exn state_var current_buffer in
  match state.parse_tree with
  | None ->
    message "Buffer AST not built - rebuilding...";
    let parse_tree = parse_current_buffer state.file_type
                     |> Option.map ~f:(fun parse_tree -> parse_tree,None) in
    let state = {state with parse_tree = parse_tree} in
    Buffer_local.set state_var (Some state) current_buffer;
    State.Validated.of_state state
  | Some (MkParseTree tree,Some dr) ->
    let open State.Filetype in
    let tree = begin match state.file_type,tree  with
      | Interface, Intf ls -> MkParseTree (Intf (rebuild_intf_parse_tree ls dr))
      | Implementation, Impl ls -> MkParseTree (Impl (rebuild_impl_parse_tree ls dr))
      | _ -> assert false
    end
    in
    let state = {state with parse_tree = Some (tree,None)} in
    Buffer_local.set state_var (Some state) current_buffer;
    State.Validated.of_state state
  | ((Some (_,None)  )) ->
    State.Validated.of_state state

(** retrieve the points enclosing structure at the current position *)
let retrieve_enclosing_structure_bounds ?current_buffer ~state_var point =
  retrieve_gopcaml_state ?current_buffer ~state_var
  |> Option.bind ~f:(find_enclosing_structure_bounds ~point)

