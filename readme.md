
# NOTE: THIS IS A MIRROR
Please submit issues, feature requests and PRs to https://gitlab.com/gopiandcode/gopcaml-mode

# Gopcaml Ocaml Emacs Major Mode

The ultimate ocaml editing mode.

## Features
- AST-based code navigation - `C-M-n, C-M-p, C-M-u, C-M-d, C-M-f, C-M-b`

![ast-code-navigation](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_move_expression_example.gif?inline=false)

- AST-based code transformation -`C-M-N, C-M-P, C-M-F, C-M-B`

![ast-code-transform](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_move_function_example.gif?inline=false)

- Fixed move-to-defun, move-to-end-defun -`C-M-a, C-M-e`

![move-to-defun](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_move_to_defun_example.gif?inline=false)

- Jump to type hole - `TAB`

![jump-to-type-hole](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_move_to_type_hole.gif?inline=false)

- Automatic let binding expansion (i.e adds in automatically if defining let inside a let)

![automatic-let-bindings](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_auto_let_binding_example.gif?inline=false)

- Mark exp - `C-M-SPC`

![mark-sexp](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_mark_sexp.gif?inline=false)

- Move to nearest parameter - `C-c C-p`

![move-to-param](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_move_to_parameter.gif?inline=false)

- Move to nearest let def - `C-c C-o`

![move-to-let-def](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_move_to_nearest_letdef.gif?inline=false)

- Extract expression into letdef - `C-c C-e`

![extract-expression](https://gitlab.com/gopiandcode/gopcaml-mode/-/raw/master/images/gopcaml_extraction_expressions.gif?inline=false)


## Installation
Gopcaml mode is implemented using a mixture of ocaml and elisp.

Make sure your emacs is compiled with dynamic modules support (you may need to build emacs from source with the `--with-modules` option).

*Note:* If you get an error about ELF headers this means that your emacs doesn't support dynamic modules - you'll need to build emacs from source (takes ~5 minutes usually).

- Install the project via opam:
```sh
opam install gopcaml-mode
```
- install merlin, ocp-indent and tuareg mode
- load the project in your init.el
```elisp
 (let ((opam-share (ignore-errors (car (process-lines "opam" "config" "var" "share")))))
	   (when (and opam-share (file-directory-p opam-share))
	     ;; Register Gopcaml mode
	     (add-to-list 'load-path (expand-file-name "emacs/site-lisp" opam-share))
         (autoload 'gopcaml-mode "gopcaml-mode" nil t nil)
         (autoload 'tuareg-mode "tuareg" nil t nil)
         (autoload 'merlin-mode "merlin" "Merlin mode" t)
	     ;; Automatically start it in OCaml buffers
	     (setq auto-mode-alist
		   (append '(("\\.ml[ily]?$" . gopcaml-mode)
			     ("\\.topml$" . gopcaml-mode))
			   auto-mode-alist))
	     ))
```

Enjoy your ultimate editing experience.

## Extras
- For some additional features that aren't included in the main release, see the extras folder
## Development
If you want to tinker with this project/extend it/build your own version, see below:
### Project Structure
The core project laid out as follows: 
```
├── gopcaml.ml
├── gopcaml_state.ml
├── ast_zipper.ml
├── ast_analysis.ml
├── ast_transformer.ml
├── gopcaml-mode.el
├── gopcaml-multiple-cursors.el
└── gopcaml-smartparens.el

```
The purpose of each file is defined as follows (in the order in which you'd probably want to look at them):
- *gopcaml.ml* 
  - defines the main entrypoint for the module
  - this is where all the functions bindings to emacs are setup
- *gopcaml_state.ml*
  - defines functions to parse and track a copy of the AST for use in other components
- *ast_zipper.ml* 
  - defines a huet-style scarred zipper for the OCaml AST.
  - the zipper operates in a lazy fashion - i.e the AST is only
    expanded into the zipper type when the user expicitly requests it
- *ast_analysis.ml*
  - contains functions that perform analysis over the AST (i.e things like finding the free variables in an expression, etc.)
  - *ast_transformer.ml* should be moved into here at some point

- *gopcaml-mode.el* 
  - main elisp plugin file
  - takes the functions exported by gopcaml.ml and provides wrappers to make them more robust
- *gopcaml-\*.el* 
  - optional features that are loaded in when the required packages are also loaded
  - allows for better compatibility with other emacs packages (i.e for
    example, disabling ast-movement when at the start of a parens so
    smartparens can work )

### Architecture
- There are two main interesting components to gopcaml-mode
- *Tracking OCaml Ast* 
  - in order to work, gopcaml mode needs to have a copy of the ocaml
    ast that (typically*) needs to be up to date with the buffer
    contents
  - to achieve this while maintaining a fluid user experience this is achieved
	through to measures:
	  - invalidating on changes:
	      - when any change is made to the buffer, the state is invalidiated
		    (see `gopcaml_state.ml/State/DirtyRegion/update`)
		  - if the user runs a command that requires the ast and the ast is
		    invalidated, then we try and rebuild the ast 
			(see `gopcaml_state.ml/State/Validated/of_state.ml`).
	  - periodic rebuilding:
		  - when gopcaml-mode is started, an idle timer is setup to
            periodically check if the AST is out of date and rebuild
            it when the user doesn't perform any changes for a while
		  - this just means that we can perform AST reconstruction
            during idle time, and reduces the cost of moving after
            changes
    *sometimes we don't care if the ast is out of date/we're doing analysis
	 during a time when we know the ast will not be constructable (i.e for 
	 example if implementing a function to check whether we are writing text
	 inside a letbinding (see `gopcaml_state.ml/inside_let_def`)) - in this
	 case we can try and retrieve an old copy of the state
	 (see `gopcaml_state.ml/State/Validated/of_state_immediate`)
- *Zipper-mode*
  - zipper-mode is the terminology given to the transient mode that is
	entered when the user performs strucutural movement.
  - when a structural command is run for the first time, we retrieve
    the ast and create a zipper and store it in a
    buffer-local-varaible (see `gopcaml_state.ml/build_zipper_enclosing_point`)
  - all subsequent movement commands retrieve the zipper from this variable and
    use it to move the emacs cursor and the overlay highlighting the selected item
  - transformation operations also use the zipper to update the
    buffer, but have to take extra care to ensure that they also
    update the state of the zipper to reflect the changes in the ast
    (as the zipper, unlike the ast isn't periodically updated)
	(see `ast_zipper.ml/move_(left|right|up|down)`)
  - when any command that isn't a structural editing one is pressed,
    the transient mode ends, and the zipper variable is cleared.
  - Note: the fact that the zipper is in a separate variable from the
    ast deliberately means that the zipper may become desynchronized
    from the ast - for example, if we perform an AST transformation
    using the zipper, then the original ast will not be up to
    date. This is mainly just to avoid unnecassary work - rather than
    writing transformation functions twice for the ast and zipper, we
    write them once for the zipper (taking sure to ensure that the
    meta-information stored in the zipper is kept up to date), and
    then let the automatic rebuilding functionality handle updating
    the original ast.

### Setting up the development environment
Being an emacs plugin, the development environment setup is tailored
for emacs.

- Clone the repo from gitlab https://gitlab.com/gopiandcode/gopcaml-mode
- Build the project with `dune build`
- in your init.el where gopmacs is loaded, add the following:
```elisp
(add-to-list
	'command-switch-alist
	(cons "gopdev"  (lambda (__) nil)))
	
(if (member "-gopdev" command-line-args) (setq gopcaml-dev-mode t))

(if (or (not (boundp 'gopcaml-dev-mode)) (not gopcaml-dev-mode))
   ... ;; run normal gopcaml initialization code (i.e from the install instructions)
)
```
- Now launch emacs passing the flag `-gopdev` and open any file inside
  the project directory.
- When prompted press `y` or `!` to setup the development variables for the file.
- Now this instance of emacs will use your local branch to load
  gopcaml-mode (It's quite nice developing in this way, as any changes
  you make will be reflected in your editor, and can quickly be tried
  out**.
  
Note: My typical development setup is to have a command prompt open in
the background and execute `dune build && emacs -gopdev ./<some-file>.ml`.
I make some changes, use merlin to ensure there
are no issues, exit and press up on my terminal to reload the prior
command and press enter.

Note\*: The reason for the complicated setup is that gopcaml-mode uses
dynamic modules to call out to ocaml mode from emacs, and dynamic
modules can only be loaded into an emacs instance once - thus each
time you make a change, you'll need to restart emacs.


