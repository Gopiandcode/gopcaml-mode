open Core
open Ecaml

let version = 0.1
let gopcaml_version = "0.0"

module Variables = struct

  let state_var = Buffer_local.defvar
      ("gopcaml-state" |> Symbol.intern)
      [%here]
      ~docstring:{|
    Holds gopcaml-mode state.
    |}
      ~type_: (Value.Type.option Gopcaml_state.State.ty)
      ~default_value:(None)
      ()

  let zipper_var = Buffer_local.defvar
      ("gopcaml-zipper" |> Symbol.intern)
      [%here]
      ~docstring:{|
    Holds the zipper used to enable gopcaml-mode "zipper mode".
    |}
      ~type_: (Value.Type.option Gopcaml_state.State.Zipper.ty)
      ~default_value:(None)
      ()

end

module Customizable = struct

  let gopcaml_group =
    Customization.Group.defgroup "gopcaml"
      [%here]
      ~docstring:{|
      Gopcaml mode customization
    |}
      ~parents:[]

  let interface_extensions_var = Customization.defcustom
      ~show_form:true
      ("gopcaml-interface-extensions" |> Symbol.intern)
      [%here]
      ~group:gopcaml_group
      ~docstring:{|
      List of extensions to be automatically assumed to be interface files.
    |}
      ~type_: (Value.Type.list Value.Type.string)
      ~customization_type:(Customization.Type.Repeat Customization.Type.String)
      ~standard_value:["mli"]
      ()

  let implementation_extensions_var = Customization.defcustom
      ~show_form:true
      ("gopcaml-implementation-extensions" |> Symbol.intern)
      [%here]
      ~group:gopcaml_group
      ~docstring:{|
      List of extensions to be automatically assumed to be implementation files.
    |}
      ~type_: (Value.Type.list Value.Type.string)
      ~customization_type:(Customization.Type.Repeat Customization.Type.String)
      ~standard_value:["ml"]
      ()
end

let define_functions () =
  defun
    ("gopcaml-version" |> Symbol.intern)
    [%here]
    ~docstring:{|
    Returns gopcaml version number.
    |}
    (Returns Value.Type.string_cached)
    (let open Defun.Let_syntax in
     return (Printf.sprintf "%s" gopcaml_version)
    );
  defun
    ("gopcaml-set-file-type" |> Symbol.intern)
    [%here]
    ~docstring:{|
                       Configure gopcaml to treat current buffer as FILE-TYPE
                       |}
    (Returns Value.Type.unit)
    (let open Defun.Let_syntax in
     let%map_open file_type = required "file-type" Gopcaml_state.State.Filetype.ty in
     Gopcaml_state.set_gopcaml_file_type
       ~state_var:Variables.state_var
       file_type
    );
  defun
    ("gopcaml-get-file-type" |> Symbol.intern)
    [%here]
    ~docstring:{|
                       Retrieve gopcaml's stored file type for the current buffer.
                       |}
    (Returns Value.Type.string)
    (let open Defun.Let_syntax in
     let%map_open getter = return (Gopcaml_state.get_gopcaml_file_type
                                     ~state_var:Variables.state_var) in
     (getter ()));
  defun
    ("gopcaml-update-dirty-region" |> Symbol.intern)
    [%here]
    ~docstring:{|
        Notify gopcaml-mode of change to dirty region.
                       |}
    (Returns Value.Type.unit)
    (let open Defun.Let_syntax in
     let%map_open st = required "start" (Value.Type.int)
     and ed = required "end" (Value.Type.int) 
     and len = required "length" (Value.Type.int) in
     Gopcaml_state.update_dirty_region ~state_var:Variables.state_var (st,ed,len)
    );
  defun
    ("gopcaml-get-dirty-region" |> Symbol.intern)
    [%here]
    ~docstring:{|
        Retrieve gopcaml-mode's dirty region bounds.
                       |}
    (Returns (Value.Type.option (Value.Type.tuple Value.Type.int Value.Type.int)))
    (let open Defun.Let_syntax in
     let%map_open getter = return (Gopcaml_state.get_dirty_region ~state_var:Variables.state_var) in
     getter () 
    );
  defun
    ("gopcaml-get-enclosing-structure-bounds" |> Symbol.intern)
    [%here]
    ~docstring:{| Retrieve a pair of points enclosing the structure item at the current point |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open point = required "point" (Position.type_) in
     Gopcaml_state.retrieve_enclosing_structure_bounds
       ~state_var:Variables.state_var
       point
     |> Option.map ~f:(fun (a,b) -> [a;b])
    );
  defun
    ("gopcaml-get-enclosing-bounds" |> Symbol.intern)
    [%here]
    ~docstring:{| Retrieve a pair of points enclosing the expression at the current point |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open point = required "point" (Position.type_) in
     Gopcaml_state.retrieve_enclosing_bounds
       ~state_var:Variables.state_var
       point
     |> Option.map ~f:(fun (a,b) -> [a; b])
    );
  defun
    ("gopcaml-ensure-updated-state" |> Symbol.intern)
    [%here]
    ~docstring:{| Ensure that the gopcaml-state is up to date. |}
    (Returns (Value.Type.unit))
    (let open Defun.Let_syntax in
     let%map_open getter = return @@ Gopcaml_state.retrieve_gopcaml_state ~state_var:Variables.state_var in
     ignore (getter ())
    );
  defun
    ("gopcaml-build-zipper" |> Symbol.intern)
    [%here]
    ~docstring:{| Builds an ast zipper around the current point. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open point = required "point" (Position.type_)
     and line = required "line" Value.Type.int in
     Gopcaml_state.build_zipper_enclosing_point 
       ~state_var:Variables.state_var ~zipper_var:Variables.zipper_var point line
     |> Option.map ~f:(fun (a,b) -> [a; b])
    );
  defun
    ("gopcaml-delete-zipper" |> Symbol.intern)
    [%here]
    ~docstring:{| Deletes the zipper if it exists. |}
    (Returns Value.Type.unit)
    (let open Defun.Let_syntax in
     let%map_open op = return @@ Gopcaml_state.delete_zipper ~zipper_var:Variables.zipper_var in
     op () 
    );
  defun
    ("gopcaml-retrieve-zipper-bounds" |> Symbol.intern)
    [%here]
    ~docstring:{| Retrieves the bounds represented by the current zipper. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.retrieve_zipper_bounds ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun (a,b) -> [a; b])
    );
  defun
    ("gopcaml-move-zipper-left" |> Symbol.intern)
    [%here]
    ~docstring:{| Moves the current zipper left and returns its bounds. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.move_zipper_left ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun (a,b) -> [a; b])
    );
  defun
    ("gopcaml-move-zipper-right" |> Symbol.intern)
    [%here]
    ~docstring:{| Moves the current zipper right and returns its bounds. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.move_zipper_right ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun (a,b) -> [a; b])
    );
  defun
    ("gopcaml-move-zipper-up" |> Symbol.intern)
    [%here]
    ~docstring:{| Moves the current zipper up and returns its bounds. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.move_zipper_up ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun (a,b) -> [a; b])
    );
  defun
    ("gopcaml-move-zipper-down" |> Symbol.intern)
    [%here]
    ~docstring:{| Moves the current zipper down and returns its bounds. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.move_zipper_down ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun (a,b) -> [a; b])
    );
  defun
    ("gopcaml-begin-zipper-swap" |> Symbol.intern)
    [%here]
    ~docstring:{| Updates the current zipper to swap the current element - returning
    the range to be swapped. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.zipper_swap ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun ((a,b),(c,d)) -> [a; b;c;d])
    );
  defun
    ("gopcaml-begin-zipper-swap-forwards" |> Symbol.intern)
    [%here]
    ~docstring:{| Updates the current zipper to swap the current element forwards - returning
    the range to be swapped. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.zipper_swap_forwards ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun ((a,b),(c,d)) -> [a; b;c;d])
    );
  defun
    ("gopcaml-begin-zipper-swap-backwards" |> Symbol.intern)
    [%here]
    ~docstring:{| Updates the current zipper to swap the current element forwards - returning
    the range to be swapped. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.zipper_swap_backwards ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun ((a,b),(c,d)) -> [a; b;c;d])
    );
  defun
    ("gopcaml-begin-zipper-delete" |> Symbol.intern)
    [%here]
    ~docstring:{| Updates the current zipper to delete the current element - returning
    the range to be deleted. |}
    (Returns (Value.Type.option (Value.Type.list Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open op =
       return @@ Gopcaml_state.zipper_delete_current ~zipper_var:Variables.zipper_var in
     op ()
     |> Option.map ~f:(fun ((a,b)) -> [a; b]));
  defun
    ("gopcaml-find-defun-start" |> Symbol.intern)
    [%here]
    ~docstring:{| Returns the start of the nearest defun to POINT. |}
    (Returns (Value.Type.option Value.Type.int))
    (let open Defun.Let_syntax in
     let%map_open point = required "point" Position.type_
     and line = required "line" Value.Type.int
     and op = return @@  Gopcaml_state.find_nearest_defun ~state_var:Variables.state_var in
     op point line);
  defun
    ("gopcaml-find-defun-end" |> Symbol.intern)
    [%here]
    ~docstring:{| Returns the start of the nearest defun to POINT. |}
    (Returns (Value.Type.option Value.Type.int))
    (let open Defun.Let_syntax in
     let%map_open point = required "point" Position.type_
     and line = required "line" Value.Type.int
     and op = return @@  Gopcaml_state.find_nearest_defun_end ~state_var:Variables.state_var in
     op point line);
  defun
    ("gopcaml-zipper-insert-let-def-start" |> Symbol.intern)
    [%here]
    ~docstring:{| Uses the zipper to insert a let-def. |}
    (Returns (Value.Type.option (Value.Type.tuple Value.Type.string Position.type_)))
    (let open Defun.Let_syntax in
     let%map_open column_no = required "point" Value.Type.int  in
     let op = Gopcaml_state.zipper_insert_let_def ~zipper_var:Variables.zipper_var column_no in
     op ());
  defun
    ("gopcaml-is-inside-let-def" |> Symbol.intern)
    [%here]
    ~docstring:{| Determines whether the current item is inside a let-def. |}
    (Returns (Value.Type.option Value.Type.bool))
    (let open Defun.Let_syntax in
     let%map_open point = required "point" Value.Type.int  in
     let op = Gopcaml_state.inside_defun ~state_var:Variables.state_var in
     op point)


let gopcaml_mode =
  Major_mode.define_derived_mode
    ("gopcaml-mode" |> Symbol.intern)
    [%here]
    ~docstring:"OCaml major mode for structural syntax-aware \
                editing. OCaml editing on steriods!"
    ~mode_line:"GopCaml"
    ~parent:Major_mode.Tuareg.major_mode
    ~initialize:((Returns Value.Type.unit),
                 fun () ->
                   message "Building initial state";
                   let _ =  (Gopcaml_state.setup_gopcaml_state
                               ~state_var:Variables.state_var
                               ~interface_extension_var:Customizable.interface_extensions_var
                               ~implementation_extension_var:Customizable.implementation_extensions_var
                            ) in
                   define_functions ()
                )
    ()





(* Finally, provide the gopcaml symbol  *)
let () =
  provide ("gopcaml" |> Symbol.intern)   


