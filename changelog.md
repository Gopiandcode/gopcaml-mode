# Gopcaml Changelog

- Version 0.0.2 - Unicode-lovers & Refactoring release
  - *Updated to work with OCaml 4.12.0*
    - Updated to depend on ocaml-migrate-parsetree, back-porting support back to OCaml.4.08.0+
  - *Improved support for jumping to nearest pattern*
    - Pressing C-c C-p will now jump to the nearest enclosing wildcard or pattern if no wildcard exists
    - C-c C-o operates as normal for jumping to the nearest let definition
  - *Added support for moving within patterns*
  - *Added support for moving within types*
  - *improved quality of main Ast_zipper code*
    - more comments
    - refactoring TextRegion module to a separate file so it may be
      reused for other analyses
  - *Added support for excluding files*
    - Now does not complain when opening ocamllex or menhir files
    - see `gopcaml-ignored-extensions` variable for more information
  - *Fixed ordering of parameters when using optional arguments*
    - previously optional arguments would appear before their bindings
  - *Added better support for multi-byte strings*
    - previously, use of multi-byte strings would cause overlays to
      desynchronise with the code
    - the OCaml parser represents offsets and ranges in terms of byte
      offsets, while the conversion functions being used in the
      program (Position.of_int_exn) assumed they were code points
    - the existing code would function correctly on buffers using only
      single-byte characters, but would fail on buffers with
      multi-byte buffers
    - now our unicode using foriegn-language friends can too enjoy the
      power of Gopcaml mode!
  - *Fixed bug with transpose expression*

- Version 0.0.1 - Initial release
