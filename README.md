# command-chain.el

This package is an integration and generalization of `smartchr.el`
and `sequential-command.el`, allows one to use multiple commands on
one key like `C-l` in Emacs default.

`smartchr.el`, porting of `smartchr` on vim, provides different insertions
for pressing one key multiple times.
`sequential-command.el` execute different commands with buffer and
point unchanged.
They are essentially the same so this package provides that.



## What is the differnt (except for integration)?

- There was no feature like `:loop`.
- There was no feature like `:prefix-fallback` in `smartchr.el`.
- Point movement of `sequential-command.el` is not preferable for me.
  Alternatively we can write same feature by using list of functions and it's easy to control.



## Requirement

ERFI (`erfi-macros.el`, `erfi-srfi-1.el`)



## Installation

### With el-get

Write the below to your .emacs file:

	(setq el-get-sources
	      (append el-get-sources
	              '((:name erfi
	                 :type github
	                 :website "https://github.com/kenoss/erfi"
	                 :description "Emacs Lisp Reconstruction for Indivisuals"
	                 :pkgname "kenoss/erfi")
	                (:name command-chain
	                 :type github
	                 :website "https://github.com/kenoss/command-chain"
	                 :description "Multiple commands on one key"
	                 :pkgname "kenoss/erfi"))))
	(require 'command-chain)

### Manual install

At the terminal,

	$ git clone https://github.com/kenoss/erfi
    $ git clone https://github.com/kenoss/command-chain

Or download zip file and extract.  Write the below to your .emacs file:

	(setq load-path
	      (append load-path '("/path/to/erfi" "/path/to/command-chain")))
	(require 'command-chain)



## Examples

`command-chain` takes a list of items and return interactive function.
Items must be the following forms:

  - Keyword `:loop`
  - Struct `command-chain-fnpair`
  - String
  - Pair of strings `(str1 . str2)`
  - Function
  - List of the above things

For string, returned function insert it.  Command sequence ends as list ends.
As the command sequence proceed, inserted text are deleted and point are recovered.

config:

	(define-key global-map (kbd ";") (command-chain '("a" "b" "c")))

effect:

	;      =>  a
	;;     =>  b
	;;;    =>  c
	;;;;   =>  
	;;;;;  =>  a  (new command sequence start)


### Keyword `:loop`

Key word `:loop` indicates following items of this keyword constitute a loop.

config:

	(define-key global-map (kbd ";") (command-chain '(:loop "a" "b" "c")))

effect:

	;      =>  a
	;;     =>  b
	;;;    =>  c
	;;;;   =>  a
	;;;;;  =>  b

config:

	(define-key global-map (kbd ";") (command-chain '("a" :loop "b" "c")))

effect:

	;      =>  a
	;;     =>  b
	;;;    =>  c
	;;;;   =>  b
	;;;;;  =>  c

Key word `:loop` may appear at most once.

invalid config:

	(define-key global-map (kbd ";") (command-chain '("a" :loop "b" "c" :loop a)))


### String

The variable `command-chain-cursor-regexp` in string indicate where point should move after insertion.
Default is "\_|\_".  One can use pairs alternatively.

config:

	(define-key global-map (kbd ";") (command-chain '("a" "b_|_b" ("c" . "c"))))

effect:

	;      =>  a_|_   (here _|_ is the point)
	;;     =>  b_|_b
	;;;    =>  c_|_c
	;;;;   =>  _|_
	;;;;;  =>  a_|_


### Function

For function, returned function execute it.

config:

	(define-key global-map (kbd ";")
	  (command-chain '(beginning-of-line
	                   end-of-line
	                   " hoge ")))

effect:

	       =>  some_|_thing  (assume buffer contents is such thing)
	;      =>  _|_something
	;;     =>  something_|_
	;;;    =>  some hoge _|_thing  (recall that point is recovered each time)
	;;;;   =>  some_|_thing


### List

How do we write inserting text in the beginnig of line?
For list of items (not restricted to string nor function), returned function execute that sequence at one key pressing.

config:

	(define-key global-map (kbd ";")
	  (command-chain '(beginning-of-line
	                   (beginning-of-line "just a ")
	                   (end-of-line " wrong" beginning-of-line))))

effect:

	       =>  some_|_thing
	;      =>  just a _|_something
	;;     =>  _|_something wrong
	;;;    =>  some_|_thing

Of course text recovery works correctly.

config:

	(define-key global-map (kbd ";")
	  (command-chain '(" a "
	                   (" b_|_b " " c_|_c " " d ")
                       (" e_|_e " " f " beginning-of-line "hoge "))))

effect:

	       =>  some_|_thing
	;      =>  some a _|_thing
	;;     =>  some b c d _|_c b thing
	;;;    =>  hoge _|_some e f e thing
	;;;;   =>  some_|_thing


### Struct `command-chain-fnpair`

The above examples are expanded to this form.  One can use this for full control.  (See below.)


## Optional keywords

`:prefix-fallback` designate a fall-back function used in the case prefix numerical argument (not equal to 1) given.

config:

	(define-key global-map (kbd ";") (command-chain '("a" "b" "c") :prefix-fallback ";"))

effect:

	;      =>  a
	C-u ;  =>  ;

config:

	(define-key global-map (kbd ";") (command-chain '("a" "b" "c") :prefix-fallback 'self-insert-command))

effect:

	;         =>  a
	C-u ;     =>  ;;;;
    ;; C-u ;  =>  b;;;;a



## More examples

The above examples all recover point.  One can write as following to realize "insertion loop".

config:

	(define-key global-map (kbd ";")
	  (command-chain '("a" "b"
	                   :loop
	                   (:insert-fn (lambda ()
	                                 (command-chain-turn-off-point-recovery)
	                                 (insert (apply 'concat (make-list (prefix-numeric-value current-prefix-arg) "A"))))
	                    :cleanup-fn nil))))

effect:

	;      =>  a
	;;     =>  b
	;;;    =>  A
	;;;;   =>  AA
	;;;;;  =>  AAA


Like `C-l`, one may want `C-w` to do `kill-region` and do nothing modulo 2, and `kill-ring-save` with prefix `C-u`:

	(define-key global-map (kbd "C-w")
	  (command-chain '((:insert-fn (lambda () (interactive)
	                                 (prog1 nil
	                                   (call-interactively 'kill-region)))
	                    :cleanup-fn undo))
	                 :prefix-fallback 'kill-ring-save))

The above register region to kill-ring as much as one repeats.  The right definition is the following:

	(define-key global-map (kbd "C-w")
	  (command-chain '((:insert-fn (lambda () (interactive)
	                                 (prog1 nil
	                                   (call-interactively 'kill-region)))
	                    :cleanup-fn undo)
	                   :loop
	                   (:insert-fn nil :cleanup-fn nil)
	                   (:insert-fn (lambda () (interactive)
	                                 (prog1 nil
	                                   (call-interactively 'kill-region)
	                                   (setcdr kill-ring (cddr kill-ring))))
	                    :cleanup-fn undo))
	                 :prefix-fallback 'kill-ring-save))
