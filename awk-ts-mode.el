;;; awk-ts-mode.el --- Major mode for awk -*- lexical-binding: t; -*-

;; This is free and unencumbered software released into the public domain.

;; Author: Noah Peart <noah.v.peart@gmail.com>
;; URL: https://github.com/nverno/awk-ts-mode
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1"))
;; Created: 27 September 2023
;; Keywords: awk languages tree-sitter

;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;;; Description:
;;
;; This package defines a tree-sitter enabled major modes awk that provides
;; support for indentation, font-locking, imenu, and structural navigation.
;;
;; The tree-sitter grammar compatible with this package can be found at
;; https://github.com/Beaglefoot/tree-sitter-awk.
;;
;;; Installation:
;;
;; For a simple way to install the tree-sitter grammar libraries,
;; add the following entry to `treesit-language-source-alist':
;;    
;;     (add-to-list
;;      'treesit-language-source-alist
;;      '(awk "https://github.com/Beaglefoot/tree-sitter-awk")
;;
;; and call `treesit-install-language-grammar' to do the installation.
;;
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'treesit)

(defcustom awk-ts-mode-indent-level 2
  "Number of spaces for each indententation step."
  :group 'awk
  :type 'integer
  :safe 'integerp)

;;; Syntax
;; cc-awk.el syntax table
(defvar awk-ts-mode--syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?\\ "\\" st)
    (modify-syntax-entry ?\n ">   " st)
    (modify-syntax-entry ?\r ">   " st)
    (modify-syntax-entry ?\f ">   " st)
    (modify-syntax-entry ?\# "<   " st)
    (modify-syntax-entry ?/ "." st)
    (modify-syntax-entry ?* "." st)
    (modify-syntax-entry ?+ "." st)
    (modify-syntax-entry ?- "." st)
    (modify-syntax-entry ?= "." st)
    (modify-syntax-entry ?% "." st)
    (modify-syntax-entry ?< "." st)
    (modify-syntax-entry ?> "." st)
    (modify-syntax-entry ?& "." st)
    (modify-syntax-entry ?| "." st)
    (modify-syntax-entry ?_ "_" st)
    (modify-syntax-entry ?\' "." st)
    (modify-syntax-entry ?$ "'" st)
    st)
  "Syntax table in use in AWK Mode buffers.")

;;; Indentation

(defvar awk-ts-mode--indent-rules
  '((awk
     ((parent-is "program") parent 0)
     ((node-is ")") parent-bol 0)
     ((node-is "}") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is "block") parent-bol 0)
     ((parent-is "block") parent-bol awk-ts-mode-indent-level)
     ((node-is "else") parent-bol 0)
     (no-node parent-bol awk-ts-mode-indent-level)
     (catch-all parent-bol awk-ts-mode-indent-level)))
  "Tree-sitter indentation rules for awk.")

;;; Font-Lock

(defvar awk-ts-mode--feature-list
  '(( comment definition)
    ( keyword string builtin)
    ( assignment namespace constant literal escape-sequence)
    ( bracket delimiter operator error function variable))
  "`treesit-font-lock-feature-list' for `awk-ts-mode'.")

(defvar awk-ts-mode--keywords
  ;; Others that are nodes in grammar: "break" "continue" "nextfile" "next"
  '("BEGIN" "BEGINFILE" "END" "ENDFILE"
    "case" "default" "delete"
    "do" "else" "exit" "for" "func" "function" "getline" "if" "in" 
    "return" "switch" "while")
  "Awk keywords for tree-sitter font-locking.")

(defvar awk-ts-mode--builtin-functions
  (rx string-start
      (or "adump" "and" "asort" "asorti" "atan2" "bindtextdomain" "close"
          "compl" "cos" "dcgettext" "dcngettext" "exp" "extension" "fflush"
          "gensub" "gsub" "index" "int" "isarray" "length" "log" "lshift"
          "match" "mktime" "or" "patsplit" "print" "printf" "rand" "rshift"
          "sin" "split" "sprintf" "sqrt" "srand" "stopme"
          "strftime" "strtonum" "sub" "substr"  "system"
          "systime" "tolower" "toupper" "typeof" "xor")
      string-end)
  "Awk builtin functions for tree-sitter font-locking.")

(defvar awk-ts-mode--builtin-variables
  (rx string-start
      (or "ARGC" "ARGIND" "ARGV" "BINMODE" "CONVFMT" "ENVIRON"
          "ERRNO" "FIELDWIDTHS" "FILENAME" "FNR" "FPAT" "FS" "FUNCTAB"
          "IGNORECASE" "LINT" "NF" "NR" "OFMT" "OFS" "ORS" "PREC"
          "PROCINFO" "RLENGTH" "ROUNDMODE" "RS" "RSTART" "RT" "SUBSEP"
          "SYNTAB" "TEXTDOMAIN")
      string-end)
  "Awk builtin variables for tree-sitter font-lock.")

(defvar awk-ts-mode--operators
  '("=" "+=" "-=" "*=" "/=" "%=" "^="
    "<" "<=" ">" ">=" "==" "!=" "~" "!~" "!"
    "+" "-" "*" "/" "%" "^" "**"
    "&&" "||"
    "|" "|&"
    "--" "++")
  "Awk operators for tree-sitter font-lock.")

(defvar awk-ts-mode--assignment-query
  (when (treesit-available-p)
    (treesit-query-compile 'awk '((identifier) @id)))
  "Query to capture identifiers in assignment_exp.")

(defun awk-ts-mode--fontify-assignment-lhs (node override start end &rest _)
  "Fontify the lhs NODE of an assignment_exp.
For OVERRIDE, START, END, see `treesit-font-lock-rules'."
  (dolist (node (treesit-query-capture
                 node awk-ts-mode--assignment-query nil nil t))
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     (pcase (treesit-node-type node)
       ("identifier" 'font-lock-variable-use-face))
     override start end)))

;; from `c-ts-mode--fontify-variable'
(defun awk-ts-mode--fontify-variable (node override start end &rest _)
  "Fontify an identifier node if it is a variable.
Don't fontify if it is a function identifier.  For NODE,
OVERRIDE, START, END, and ARGS, see `treesit-font-lock-rules'."
  (when (not (equal (treesit-node-type
                     (treesit-node-parent node))
                    "func_call"))
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     'font-lock-variable-use-face override start end)))

(defvar awk-ts-mode--function-name-query ()
  (when (treesit-available-p)
    (treesit-query-capture 'awk '((identifier) @id
                                  (ns_qualified_name (namespace)) @id))))

(defvar awk-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'awk
   :feature 'comment
   '((comment) @font-lock-comment-face)

   :language 'awk
   :feature 'string
   '((string) @font-lock-string-face
     (regex
      "/" @font-lock-regexp-face
      pattern: (regex_pattern) @font-lock-regexp-face
      "/" @font-lock-regexp-face))
   
   :language 'awk
   :feature 'keyword
   `([,@awk-ts-mode--keywords] @font-lock-keyword-face
     [(break_statement) (continue_statement) (next_statement) (nextfile_statement)]
     @font-lock-keyword-face
     ["@include" "@namespace"] @font-lock-preprocessor-face)

   ;; before fontifying function names
   :language 'awk
   :feature 'namespace
   ;; :override t
   '((ns_qualified_name
      (namespace) @font-lock-type-face
      "::" @font-lock-punctuation-face))

   :language 'awk
   :feature 'builtin
   `(((identifier) @var (:match ,awk-ts-mode--builtin-functions @var))
     @font-lock-builtin-face
     ["print" "printf"] @font-lock-builtin-face
     ((identifier) @var (:match ,awk-ts-mode--builtin-variables @var))
     @font-lock-variable-name-face)

   :language 'awk
   :feature 'definition
   '((func_def
      name: [(ns_qualified_name) (identifier)] @font-lock-function-name-face
      (param_list (identifier) @font-lock-variable-name-face) :?))

   :language 'awk
   :feature 'function
   '((func_call
      name: [(identifier) (ns_qualified_name)] @font-lock-function-call-face
      (args (identifier) @font-lock-variable-use-face) :?))
   
   :language 'awk
   :feature 'assignment
   '((assignment_exp
      left: (_) @awk-ts-mode--fontify-assignment-lhs))
   
   :language 'awk
   :feature 'literal
   '((number) @font-lock-number-face
     [(regex_constant) (regex_flags)] @font-lock-constant-face)

   :language 'awk
   :feature 'variable
   '((identifier) @awk-ts-mode--fontify-variable)
   
   :language 'awk
   :feature 'bracket
   '(["(" ")" "{" "}" "[" "]"] @font-lock-bracket-face)

   :language 'awk
   :feature 'operator
   `(["!"] @font-lock-negation-char-face
     [,@awk-ts-mode--operators] @font-lock-operator-face
     (ternary_exp ["?" ":"] @font-lock-operator-face))

   ;; after 'operator for ":" in ternary
   :language 'awk
   :feature 'delimiter
   '(["," ";" ":"] @font-lock-delimiter-face)

   :language 'awk
   :feature 'escape-sequence
   :override t
   '((escape_sequence) @font-lock-escape-face)

   :language 'awk
   :feature 'error
   :override t
   '((ERROR) @font-lock-warning-face))
  "Tree-sitter font-lock settings for awk.")

;;; Navigation
;;; TODO:
(defun awk-ts-mode--defun-name (node)
  (treesit-node-text
   (treesit-node-child-by-field-name node "identifier")))

(defvar awk-ts-mode--sentence-nodes nil)
(defvar awk-ts-mode--sexp-nodes nil)
(defvar awk-ts-mode--text-nodes nil)

(define-derived-mode awk-ts-mode prog-mode "Awk"
  "Major mode for editing awk source code."
  :group 'awk
  :syntax-table awk-ts-mode--syntax-table
  (when (treesit-ready-p 'awk)
    (treesit-parser-create 'awk)

    (setq-local comment-start "#")
    (setq-local comment-end "")
    (setq-local comment-start-skip "#+[ \t]*")
    (setq-local parse-sexp-ignore-comments t)

    ;; Indentation
    (setq-local treesit-simple-indent-rules awk-ts-mode--indent-rules)

    ;; Electric-indent.
    (setq-local electric-indent-chars
                (append "{}():;,<>/" electric-indent-chars))
    (setq-local electric-layout-rules
	        '((?\; . after) (?\{ . after) (?\} . before)))

    ;; Font-Locking
    (setq-local treesit-font-lock-settings awk-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list awk-ts-mode--feature-list)

    ;; Navigation
    (setq-local treesit-defun-prefer-top-level t)
    (setq-local treesit-defun-name-function #'awk-ts-mode--defun-name)
    (setq-local treesit-defun-type-regexp nil)
    
    ;; navigation objects
    (setq-local treesit-thing-settings
                `((awk
                   (sexp ,awk-ts-mode--sexp-nodes)
                   (sentence ,awk-ts-mode--sentence-nodes)
                   (text ,awk-ts-mode--text-nodes))))

    ;; Imenu
    (setq-local treesit-simple-imenu-settings nil)

    (treesit-major-mode-setup)))

(if (treesit-ready-p 'awk)
    (add-to-list 'auto-mode-alist '("\\.[mg]?awk\\'" . awk-ts-mode)))

(provide 'awk-ts-mode)
;; Local Variables:
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:
;;; awk-ts-mode.el ends here
