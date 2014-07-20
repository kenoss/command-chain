;;; command-chain.el --- Multiple commands on one key -*- lexical-binding: t -*-

;; Copyright (C) 2014  Ken Okada

;; Author: Ken Okada <keno.ss57@gmail.com>
;; Keywords: convenience
;; URL: https://github.com/kenoss/command-chain
;; Package-Requires: ((emacs "24"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package is an integration and generalization of `smartchr.el'
;; and `sequencial-command.el', allows one to use multiple commands on
;; one key like "C-l" in Emacs default.  `smartchr.el' provides
;; different insertion for pressing one key multiple times, and
;; `sequencial-command.el' does different commands without buffer and
;; point recovered.  They are essentially the same so this package
;; provides that.
;;
;; For more documentation and examples, see ./README.md .

;; Thanks the above two packages and their authors.

;;; Code:



(eval-when-compile
  (require 'erfi-macros)
  (erfi:use-short-macro-name))

(require 'erfi-srfi-1)



(defgroup command-chain nil
  "command-chain group"
  :group 'command-chain)

(defcustom command-chain-cursor-regexp "_|_"
  "Designator for point moved after insertion."
  :group 'command-chain)



;; Internal variable, but modification allowed to control point.
(defvar *command-chain-command-start-position* nil
  "Functions created by `command-chain' will set this variable to point
for each time command sequence starts.  For each time clean up previous command,
restore point to this variable unless it is nil.

To set nil to this variable, use `command-chain-turn-off-point-recovery'.")


;; Internal variable
(defvar *command-chain-terminated*)



(defstruct command-chain-fnpair insert-fn cleanup-fn)
;;   insert-fn  :: nothing -> val
;;   cleanup-fn :: val -> nothing
;; Typically, val is list (start end) representing inserted region.
;; In the most case, buffer contents after calling composite of them should be equal to
;; the original one.
;; Point may differ the original one.  `command-chain' recover it aautomatically.
;; If one want to move point, use the variable `*command-chain-command-start-position*'.



;;;
;;; Auxiliary functions
;;;

(defun command-chain%elem->fnpair (elem)
  (cond ((command-chain-fnpair-p elem)
         elem)
        ((stringp elem)
         (command-chain%string->fnpair elem))
        ((and (consp elem) (atom (cdr elem))
              (stringp (car elem)) (stringp (cdr elem)))
         (command-chain%string-pair->fnpair (car elem) (cdr elem)))
        ((functionp elem)
         (make-command-chain-fnpair :insert-fn (lambda () (call-interactively elem)) :cleanup-fn nil))
        ((and (listp elem) (= 4 (length elem)) (memq :insert-fn elem) (memq :cleanup-fn elem))
         (apply 'make-command-chain-fnpair elem))
        ((listp elem)
         (let1 fnpair-list (mapcar 'command-chain%elem->fnpair elem)
           (make-command-chain-fnpair
            :insert-fn
            (let1 fn-list (mapcar 'command-chain-fnpair-insert-fn fnpair-list)
              (lambda ()
                (erfi:map-in-order (lambda (f) (when f (funcall f)))
                                   fn-list)))
            :cleanup-fn
            (let1 fn-list (reverse (mapcar 'command-chain-fnpair-cleanup-fn fnpair-list))
              (lambda (arg)
               (erfi:for-each (lambda (f x) (when f (funcall f x)))
                              fn-list (reverse arg)))))))
        (t
         (lwarn 'command-chain :error "Invalid element: `%s'" elem)
         (error "Invalid element: `%s'" elem))))

(defun command-chain%string->fnpair (str)
  (apply 'command-chain%string-pair->fnpair (split-string str command-chain-cursor-regexp)))
(defun command-chain%string-pair->fnpair (str1 &optional str2)
  (let* ((str (concat str1 (or str2 "")))
         (len (length str))
         (len2 (length str2)))
    (make-command-chain-fnpair :insert-fn (lambda ()
                                            (let1 p (point)
                                              (insert str)
                                              (backward-char len2)
                                              `(,p ,(+ p len))))
                               :cleanup-fn (lambda (x) (apply 'delete-region x)))))



;;;
;;; Core
;;;

(defun command-chain (spec &rest args)
  "Return interactive function that allows multiple commands on one key.

When one call the returned function multiple time sequentially, it call
different functions as specified by SPEC.

SPEC must be a list of the following form:

  Keyword :loop
    This designate following items of this keyword constitute a loop.
    This may occur at most once.

  Struct `command-chain-fnpair'
    When this is called, call :insert-fn of it.  When the next one is
    called, call :cleanup-fn of it before processing the next one.
    Point will be recovered after :cleanup-fn called.
    (c.f. `*command-chain-command-start-position*')
    Values of :insert-fn and :cleanup-fn may be non-interactive functions.
    The followings are converted to this struct.

  String
    Insert string and move to point designated by
    `command-chain-cursor-regexp'.  Inserted string will be cleaned up
    when the next command called.

  Pair of strings (str1 . str2)
    Same to the above but string = str1 + \"cursor\" + str2 .

  Function
    Call it.  No clean up.  (Point will be recovered as usual.)

  List of the above things
    Call sequentially :insert-fn of it and clean up by calling
    :cleanup-fn in reverse order.


Suported keywords:

  :prefix-fallback interactive-function
    Default is nil.  If this is non-nil, function returned by
    `command-chain' fall back to this function in the case that it is
    called with prefix argument (not equal to 1).
"
  (let1 prefix-fallback (if-let1 m (memq :prefix-fallback args)
                          (command-chain-fnpair-insert-fn (command-chain%elem->fnpair (cadr m)))
                          nil)
    (erfi%list-receive (lis c) (erfi:break (cut 'eq :loop <>) spec)
      (let1 circ (cdr-safe c)
        (when (memq :loop circ)
         (lwarn 'command-chain :error "Designater :loop may occur at most once. `%s'" spec)
         (error "Designater :loop may occur at most once. `%s'" spec))
        (let ((command-list (let1 null-funpair (make-command-chain-fnpair :insert-fn nil :cleanup-fn nil)
                              `(,null-funpair
                                ,@(mapcar 'command-chain%elem->fnpair lis)
                                ,@(if (null circ)
                                      (list null-funpair)
                                      (apply 'erfi:circular-list
                                             (mapcar 'command-chain%elem->fnpair circ))))))
              (current-command-list nil)
              (last-command-return-value nil))
          (lambda () (interactive)
            (if (and prefix-fallback
                     (not (= 1 (prefix-numeric-value current-prefix-arg))))
                (progn
                  (funcall prefix-fallback)
                  (command-chain-terminate))
                (progn
                  (when (or (not (eq this-command real-last-command))
                            *command-chain-terminated*
                            (null (cdr current-command-list)))
                    (setq *command-chain-terminated* nil
                          current-command-list command-list
                          *command-chain-command-start-position* (point)))
                  (if-let1 c (command-chain-fnpair-cleanup-fn (car current-command-list))
                    (if (eq 'command-chain-undefined last-command-return-value)
                        (funcall c)
                        (funcall c last-command-return-value)))
                  (when *command-chain-command-start-position*
                    (goto-char *command-chain-command-start-position*))
                  (pop! current-command-list)
                  (setq last-command-return-value
                        (if-let1 c (command-chain-fnpair-insert-fn (car current-command-list))
                          (funcall c)
                          'command-chain-undefined))))))))))


(defun command-chain-terminate ()
  "Terminate command sequence."
  (setq *command-chain-terminated* t))

(defun command-chain-turn-off-point-recovery ()
  "For full control of point, use the variable
`*command-chain-command-start-position*'."
  (setq *command-chain-command-start-position* nil))



(provide 'command-chain)
;;; command-chain.el ends here
