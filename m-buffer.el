;;; m-buffer.el --- Buffer Manipulation Functions -*- lexical-binding: t -*-

;; This file is not part of Emacs

;; Author: Phillip Lord <phillip.lord@newcastle.ac.uk>
;; Maintainer: Phillip Lord <phillip.lord@newcastle.ac.uk>
;; Version: 0.2-SNAPSHOT

;; The contents of this file are subject to the GPL License, Version 3.0.
;;
;; Copyright (C) 2014, Phillip Lord, Newcastle University
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This file provides a set of list orientated functions for operating over
;; the contents of buffers. Functions are generally purish: i.e. they may
;; change the state of one buffer by side-effect, but should not affect point,
;; current buffer, match data or so forth. Generally, markers are returned
;; rather than point locations, so that it is possible for example, to search
;; for regexp matches, and then replace them all without the early replacement
;; invalidating the location of the later ones.
;;

;;; Status:
;;
;; This library is early release at the moment. I write it become I got fed up
;; with writing (while (re-search-forward) do-stuff) forms. I found that it
;; considerably simplified writing `linked-buffer'. I make no guarantees about
;; the API at the moment.

;;; Code:
(require 'dash)

;;
;; Regexp matching
;;
(defun m-buffer-match-data (&rest match)
  "Return a list of `match-data' for all matches based on MATCH.
MATCH may be of the forms:
BUFFER REGEXP &optional MATCH-OPTIONS
WINDOW REGEXP &optional MATCH-OPTIONS
MATCH-OPTIONS

If BUFFER is given, search this buffer. If WINDOW is given search
the visible window. MATCH-OPTIONS is a plist with any of the
following keys:
:buffer -- the buffer to search
:regexp -- the regexp to search with
:beginning -- the start of the region to search
:end -- the end of the region to search
:post-match -- function called after a match

If options are expressed in two places, the plist form takes
precedence over positional args. So calling with both a first
position buffer and a :buffer arg will use the second. Likewise,
if a window is given as first arg and :end is given, then
the :end value will be used.

REGEXP should advance point (i.e. not be zero-width) or the
function will loop infinitely. POST-MATCH can be used to avoid
this. The buffer is searched forward."
  (apply 'm-buffer-match-data-1
         (m-buffer-normalize-args match)))

(defun m-buffer-match-data-1 (buffer regexp beginning end post-match)
  "Return a list of `match-data' for all matches.

This is an internal function: please prefer `m-buffer-match-data'.

BUFFER -- the buffer.
REGEXP -- the regexp.
BEGINNING -- the start of the region to search
END -- the end of the region to search
POST-MATCH -- function to run after each match
POST-MATCH is useful for zero-width matches which will otherwise cause
infinite loop. The buffer is searched forward."
  (save-match-data
    (save-excursion
      (with-current-buffer
          buffer
        (let ((rtn nil)
              (post-match-return t))
          (goto-char
           (or beginning
               (point-min)))
          (while
              (and
               post-match-return
               (re-search-forward
                regexp
                (or end (point-max))
                t))
            (setq rtn
                  (cons
                   (match-data)
                   rtn))
            (when post-match
              (setq post-match-return (funcall post-match))))
          (reverse rtn))))))

(defun m-buffer-normalize-args (match-with)
  "Manipulate args into a standard form and return as a list.

This is an internal function."
  (let* (
         ;; split up into keyword and non keyword limits
         (args
          (-take-while
           (lambda (x) (not (keywordp x)))
           match-with))
         (pargs
          (-drop-while
           (lambda (x) (not (keywordp x)))
           match-with))
         ;; sort actual actual parameters
         (first (car args))
         ;; buffer may be first
         (buffer
          (or (plist-get pargs :buffer)
              (and (bufferp first) first)))
         ;; or window may be first
         (window
          (or (plist-get pargs :window)
              (and (windowp first) first)))
         ;; regexp always comes second
         (regexp
          (or (plist-get pargs :regexp)
              (nth 1 args)))
         ;; beginning depends on other arguments
         (beginning
          (or (plist-get pargs :beginning)
              (and window (window-start window))))
         ;; end depends on other arguments
         (end
          (or (plist-get pargs :end)
              (and window (window-end window))))
         ;; pm
         (post-match
          (plist-get pargs :post-match)))
    (list buffer regexp beginning end post-match)))

(defun m-buffer-ensure-match (&rest match)
  "Ensure that we have match data.
If a single arg, assume it is match data and return. If multiple
args, assume they are of the form accepted by
`m-buffer-match-data'."
  (cond
   ;; we have match data
   ((= 1 (length match))
    (car match))
   ((< 1 (length match))
    (apply 'm-buffer-match-data match))
   (t
    (error "Invalid arguments"))))

(defun m-buffer-match-beginning-n (n &rest match)
  "Return markers to the start of the match to the nth group.
MATCH may be of any form accepted by `m-buffer-ensure-match'. Use
`m-buffer-nil-markers' after the markers have been finished with
or they will slow future use of the buffer until garbage collected."
  (-map
   (lambda (m)
     (nth
      (* 2 n) m))
   (apply 'm-buffer-ensure-match match)))

(defun m-buffer-match-beginning-n-pos (n &rest match)
  "Return positions of the start of the match to the nth group.
MATCH may be of any form accepted by `m-buffer-ensure-match'. If
`match-data' is passed markers will be set to nil after this
function. See `m-buffer-nil-markers' for details."
  (m-buffer-markers-to-pos-nil
   (apply 'm-buffer-match-beginning-n
          n match)))

(defun m-buffer-match-beginning (&rest match)
  "Returns a list of markers to the start of matches.
MATCH may of any form accepted by `m-buffer-ensure-match'. Use
`m-buffer-nil-markers' after the markers have been used or they
will slow future changes to the buffer."
  (apply 'm-buffer-match-beginning-n 0 match))

(defun m-buffer-match-beginning-pos (&rest match)
  "Returns a list of positions at the start of matcher.
MATCH may be of any form accepted by `m-buffer-ensure-match'.
If `match-data' is passed markers will be set to nil after this
function. See `m-buffer-nil-markers' for details."
  (apply 'm-buffer-match-beginning-n-pos 0 match))

(defun m-buffer-match-end-n (n &rest match)
  "Returns markers to the end of the match to the nth group.
MATCH may be of any form accepted by `m-buffer-ensure-match'.
If `match-data' is passed markers will be set to nil after this
function. See `m-buffer-nil-markers' for details."
  (-map
   (lambda (m)
     (nth
      (+ 1 (* 2 n))
      m))
   (apply 'm-buffer-ensure-match match)))

(defun m-buffer-match-end-n-pos (n &rest match)
  "Return positions of the end of the match to the nth group.
MATCH may be of any form accepted by `m-buffer-ensure-match'.
If `match-data' is passed markers will be set to nil after this
function. See `m-buffer-nil-markers' for details."
  (m-buffer-markers-to-pos-nil
   (apply 'm-buffer-match-end-n-pos
          n match)))

(defun m-buffer-match-end (&rest match)
  "Returns a list of markers to the end of matches to regexp in buffer.
MATCH may be of any form accepted by `m-buffer-ensure-match'. Use
`m-buffer-nil-markers' after the markers have been used or they
will slow future changes to the buffer."
  (apply 'm-buffer-match-end-n 0 match))

(defun m-buffer-match-end-pos (&rest match)
  "Returns a list of positions to the end of the matches.
MATCH may be of any form accepted by `m-buffer-ensure-match'.
If `match-data' is passed markers will be set to nil after this
function. See `m-buffer-nil-markers' for details."
  (m-buffers-markers-to-pos-nil
   (apply 'm-buffer-match-end match)))

;; marker/position utility functions
(defun m-buffer-nil-markers (markers)
  "Takes a (nested) list of markers and nils them all.
Markers slow buffer movement while they are pointing at a
specific location, until they have been garbage collected. Niling
them prevents this. See Info node `(elisp) Overview of Markers'."
  (-map
   (lambda (marker)
     (set-marker marker nil))
   (-flatten markers)))

(defun m-buffer-markers-to-pos (markers &optional postnil)
  "Transforms a list of markers to a list of positions.
If the markers are no longer needed, set postnil to true, or call
`m-buffer-nil-markers' manually after use to speed future buffer
movement. Or use `m-buffer-markers-to-pos-nil'."
  (-map
   (lambda (marker)
     (prog1
         (marker-position marker)
       (when postnil
         (set-marker marker nil))))
   markers))

(defun m-buffer-markers-to-pos-nil (markers)
  "Transforms a list of MARKERS to a list of positions then nils.
See also `m-buffer-nil-markers'"
  (m-buffer-markers-to-pos markers t))

(defun m-buffer-pos-to-markers (buffer positions)
  "In BUFFER translates a list of POSITIONS to markers."
  (-map
   (lambda (pos)
     (set-marker
      (make-marker) pos buffer))
   positions))

(defun m-buffer-replace-match (match-data replacement &optional subexp)
  "Given a list of MATCH-DATA, replace with REPLACEMENT.
SUBEXP should be a number indicating the regexp group to replace."
  (-map
   (lambda (match)
     (with-current-buffer
         (marker-buffer (car match))
       (save-match-data
         (set-match-data match)
         (replace-match
          replacement nil nil nil
          (or subexp 0)))))
   match-data))

(defun m-buffer-match-string (match-data &optional subexp)
  "Given a list of MATCH-DATA return the string matches optionally
of group SUBEXP."
  (-map
   (lambda (match)
     (with-current-buffer
         (marker-buffer (car match))
       (save-match-data
         (set-match-data match)
         (match-string
          (or subexp 0)))))
   match-data))

(defun m-buffer-match-string-no-properties (match-data &optional subexp)
  "Given a list of MATCH-DATA return string matches without properties
optionally of group SUBEXP."
  (-map
   'substring-no-properties
   (m-buffer-match-string
    matches subexp)))

;;;
;;; Block things detection
;;;
(defun m-buffer-apply-snoc (fn list &rest element)
  "Apply function to list and all elements."
  (apply
   fn (append list element)))

(defun m-buffer-match-page (&rest match)
  "Return a list of match data to all pages in MATCH.
MATCH is of form BUFFER-OR-WINDOW MATCH-OPTIONS. See
`m-buffer-match-data' for further details."
  (m-buffer-apply-snoc 'm-buffer-match-data
                       match :regexp page-delimiter))

(defun m-buffer-match-paragraph-separate (&rest match)
  "Returns a list of match data to `paragraph-separate' in MATCH.
MATCH is of form BUFFER-OR-WINDOW MATCH-OPTIONS. See
`m-buffer-match-data' for futher details."
  (m-buffer-apply-snoc
   'm-buffer-match-data match :regexp paragraph-separate
   :post-match 'm-buffer-post-match-forward-line))

(defun m-buffer-match-line-start (&rest match)
  "Returns a list of match data to all line starts.
MATCH is of form BUFFER-OR-WINDOW MATCH-OPTIONS. See
`m-buffer-match-data' for further details."
  (m-buffer-apply-snoc
   'm-buffer-match-beginning
   match :regexp  "^"
   :post-match 'm-buffer-post-match-forward-char))

(defun m-buffer-match-line-end (&rest match)
  "Returns a list of matches to line end.
MATCH is of form BUFFER-OR-WINDOW MATCH-OPTIONS. See
`m-buffer-match-data' for further details."
  (m-buffer-apply-snoc
   'm-buffer-match-beginning
   match :regexp "$"
   :post-match 'm-buffer-post-match-forward-char))

(defun m-buffer-match-sentence-end (&rest match)
  "Returns a list of matches to sentence end.
MATCH is of the form BUFFER-OR-WINDOW MATCH-OPTIONS. See
`m-buffer-match-data' for further details."
  (m-buffer-apply-snoc
   'm-buffer-match-beginning
   match :regexp (sentence-end)))

(defun m-buffer-match-word (&rest match)
  "Returns a list of matches to all words.
MATCH is of the form BUFFER-OR-WINDOW MATCH-OPTIONS. See
`m-buffer-match-data' for further details."
  (m-buffer-apply-snoc
   'm-buffer-match-data
   match :regexp "\\\w+"))

;; Useful post-match functions
(defun m-buffer-post-match-forward-line ()
  "Attempt to move forward one line, return true if success."
  (= 0 (forward-line)))

(defun m-buffer-post-match-forward-char ()
  "Attempts to move forward one char and returns true if
succeeds."
  (condition-case e
      (progn
        (forward-char)
        t)
    (error 'end-of-buffer
           nil)))

(provide 'm-buffer)
;;; m-buffer.el ends here
