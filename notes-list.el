;;; notes-list.el --- Notes list -*- lexical-binding: t -*-

;; Copyright (C) 2023 Free Software Foundation, Inc.

;; Maintainer: Nicolas P. Rougier <Nicolas.Rougier@inria.fr>
;; URL: https://github.com/rougier/notes-list
;; Version: 0.3.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: convenience

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Notes list collects notes in user-defined directories and populates a buffer
;; with a two-line summary for each note. Notes are parsed to extract title,
;; date, summary, tags and icon. A typical org note header is:
;;
;;  #+TITLE:    Emacs hacking
;;  #+DATE:     2023-03-17
;;  #+FILETAGS: HACK EMACS CODE
;;  #+SUMMARY:  Notes about emacs hacking ideas
;;  #+ICON:     material/notebook
;;
;; Notes in subdirectories are collected recursively. Each note's folder
;; (e.g. "notes/python") acts as a category alongside FILETAGS. Press '/' to
;; filter as you type, 'c' to pick a folder or tag, '+' to create a note and
;; '?' for help.

;;; News
;;
;;  Version 0.3.0
;;  Live filtering, new-note command, sort cycling, nerd-icons support,
;;  auto-refresh on save, reusable frame, faster header-only parsing,
;;  trash instead of permanent delete.
;;
;;  Version 0.2.0
;;  Remove svg-lib/stripes dependencies; add search, category browsing,
;;  subdirectory-aware collection, plain-text tags.
;;
;;  Version 0.1.0
;;  Initial version
;;
;;; Code:
(require 'cl-lib)
(require 'subr-x)

(declare-function nerd-icons-mdicon "ext:nerd-icons")

(defgroup notes-list nil
  "Note list"
  :group 'convenience)

(defcustom notes-list-directories '("~/Library/CloudStorage/Dropbox/org/notes")
  "List of directories where to search notes"
  :type '(repeat directory)
  :group 'notes-list)

(defcustom notes-list-sort-function #'notes-list-compare-modification-time
  "Criterion for sorting notes"
  :type '(choice (const :tag "Title"             notes-list-compare-title)
                 (const :tag "Access time"       notes-list-compare-access-time)
                 (const :tag "Creation time"     notes-list-compare-creation-time)
                 (const :tag "Modification time" notes-list-compare-modification-time))
  :group 'notes-list)

(defcustom notes-list-sort-order 'descending
  "Notes sorting order"
  :type '(choice (const :tag "Ascending"  ascending)
                 (const :tag "Descending" descending))
  :group 'notes-list)

(defcustom notes-list-date-display 'modification
  "Which date to display in the list"
  :type '(choice (const :tag "Access time"       access)
                 (const :tag "Creation time"     creation)
                 (const :tag "Modification time" modification))
  :group 'notes-list)

(defcustom notes-list-date-format 'relative
  "How dates are displayed.
Either `relative' (\"Today\", \"Yesterday\", \"Mar 04\" within the
current year, \"Mar 04, 2023\" otherwise) or a `format-time-string'
format such as \"%Y-%m-%d\"."
  :type '(choice (const :tag "Relative" relative)
                 (string :tag "Format string"))
  :group 'notes-list)

(defcustom notes-list-display-tags t
  "Display tags (bottom right)"
  :type 'boolean
  :group 'notes-list)

(defcustom notes-list-display-date t
  "Display date (top right)"
  :type 'boolean
  :group 'notes-list)

(defcustom notes-list-display-category nil
  "Display each note's folder (bottom right, before the tags)."
  :type 'boolean
  :group 'notes-list)

(defcustom notes-list-display-icons t
  "Display each note's #+ICON when the `nerd-icons' package is available.
Icons are written COLLECTION/NAME, as in \"material/notebook\"; NAME is
looked up among nerd-icons' Material Design icons."
  :type 'boolean
  :group 'notes-list)

(defcustom notes-list-default-icon "material/notebook"
  "Icon for notes without #+ICON; also written into new notes."
  :type '(choice (const :tag "None" nil) string)
  :group 'notes-list)

(defcustom notes-list-use-frame t
  "When non-nil, `notes-list' shows the list in a frame of its own.
The frame is created on first use and reused afterwards.  When nil,
the list is shown as a side window in the selected frame."
  :type 'boolean
  :group 'notes-list)

(defcustom notes-list-frame-parameters '((name . "Notes") (width . 120) (height . 40))
  "Frame parameters for the frame created by `notes-list'."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'notes-list)

(defcustom notes-list-window-width 0.35
  "Width of the notes list side window, as a fraction of the frame."
  :type 'number
  :group 'notes-list)

(defcustom notes-list-delete-to-trash t
  "When non-nil, deleted notes are moved to the trash instead of erased."
  :type 'boolean
  :group 'notes-list)

(defface notes-list-face-title
  '((t (:inherit bold)))
  "Face for notes title"
  :group 'notes-list)

(defface notes-list-face-tags
  '((t (:inherit font-lock-constant-face)))
  "Face for notes tags"
  :group 'notes-list)

(defface notes-list-face-summary
  '((t (:inherit default)))
  "Face for notes summary"
  :group 'notes-list)

(defface notes-list-face-time
  '((t (:inherit shadow)))
  "Face for notes time"
  :group 'notes-list)

(defface notes-list-face-category
  '((t (:inherit shadow)))
  "Face for notes folder"
  :group 'notes-list)

(defface notes-list-face-icon
  '((t (:inherit shadow)))
  "Face for notes icon"
  :group 'notes-list)

(defface notes-list-face-stripe
  '((t (:inherit highlight :extend t)))
  "Face for alternating note rows.")

(defface notes-list-face-highlight
  '((t (:inherit hl-line :extend t)))
  "Face for the currently selected note background.")

(defface notes-list-face-indicator
  '((t (:inherit font-lock-keyword-face)))
  "Face for the left-edge selection indicator character.")

(defface notes-list-face-marked
  '((t (:extend t)))
  "Face for notes marked for deletion.")

(defconst notes-list--buffer-name "*notes-list*")

(defvar notes-list--filter nil
  "Current text filter string, or nil for no filter.")

(defvar notes-list--marked nil
  "List of filenames marked for deletion.")

(defvar notes-list--category nil
  "Current folder (ending in \"/\") or tag filter, or nil for all.")

(defvar-local notes-list--selection-overlays nil
  "Overlays drawing the current selection.")

(defvar-local notes-list--last-width nil
  "Window width the list was last drawn for.")

(defvar notes-list--icon-cache (make-hash-table :test #'equal)
  "Icon strings, keyed by #+ICON value.")

(defvar notes-list-collect-notes-function #'notes-list-collect-org-notes
  "Function to used to build list of notes to display. Customize
this combined with `notes-list-open-function' to adapt notes-list
to your favourite notes solution.")

(defvar notes-list-open-function #'find-file
  "Function used to open notes. Customize this combined with
`notes-list-collect-notes-function' to adapt notes-list to your
favourite notes solution.")

(defconst notes-list--sort-keys
  '((notes-list-compare-modification-time "modified" descending modification)
    (notes-list-compare-creation-time     "date"     descending creation)
    (notes-list-compare-title             "title"    ascending  nil)
    (notes-list-compare-access-time       "accessed" descending access))
  "Sort criteria cycled by `notes-list-cycle-sort'.
Each entry is (FUNCTION NAME ORDER DATE-DISPLAY).")

(defun notes-list--get (note key)
  (cdr (assoc key note)))


;;; Formatting

(defun notes-list-format-tags (tags)
  "Format TAGS as lower case #hashtags."
  (mapconcat (lambda (tag)
               (propertize (concat "#" (downcase tag))
                           'face 'notes-list-face-tags))
             tags " "))

(defun notes-list-format-title (title)
  (propertize title 'face 'notes-list-face-title))

(defun notes-list--format-date (time)
  (if (stringp notes-list-date-format)
      (format-time-string notes-list-date-format time)
    (let ((days (- (time-to-days (current-time)) (time-to-days time))))
      (cond ((= days 0) "Today")
            ((= days 1) "Yesterday")
            ((string= (format-time-string "%Y" time) (format-time-string "%Y"))
             (format-time-string "%b %d" time))
            (t (format-time-string "%b %d, %Y" time))))))

(defun notes-list-format-time (time)
  (propertize (if time (notes-list--format-date time) "")
              'face 'notes-list-face-time))

(defun notes-list-format-summary (summary)
  (propertize summary 'face 'notes-list-face-summary))

(defvar notes-list--icon-family 'unknown
  "Font family icons are drawn with, nil if none is installed.")

(defun notes-list--icon-family ()
  "Return an installed Nerd Font family to draw icons with, or nil.
Prefers `nerd-icons-font-family', then any \"... Nerd Font Mono\",
then any other Nerd Font, since they all contain the icons."
  (when (eq notes-list--icon-family 'unknown)
    (let ((families (font-family-list)))
      (setq notes-list--icon-family
            (or (car (member (bound-and-true-p nerd-icons-font-family) families))
                (cl-find-if (lambda (family) (string-match-p "Nerd Font Mono\\'" family))
                            families)
                (cl-find-if (lambda (family) (string-match-p "Nerd Font" family))
                            families)))))
  notes-list--icon-family)

(defun notes-list--make-icon (name)
  "Return a nerd-icons string for NAME, written as in \"material/notebook\"."
  (let* ((lookup (lambda (base)
                   (ignore-errors
                     (nerd-icons-mdicon
                      (concat "nf-md-" (replace-regexp-in-string "-" "_" base))))))
         (glyph (and (not (string-empty-p name))
                     (or (funcall lookup (file-name-nondirectory name))
                         (funcall lookup "notebook"))))
         (family (and (display-graphic-p) (notes-list--icon-family))))
    (if glyph
        (propertize (substring-no-properties glyph) 'face
                    (if family
                        `(:family ,family :inherit notes-list-face-icon)
                      'notes-list-face-icon))
      " ")))

(defun notes-list--icon (note)
  "Return NOTE's icon, or nil when icons are not displayed.
In graphical frames icons need an installed Nerd Font."
  (when (and notes-list-display-icons
             (require 'nerd-icons nil t)
             (or (not (display-graphic-p)) (notes-list--icon-family)))
    (let ((name (or (notes-list--get note "ICON") notes-list-default-icon "")))
      (or (gethash name notes-list--icon-cache)
          (puthash name (notes-list--make-icon name) notes-list--icon-cache)))))

(defun notes-list--display-time (note)
  (notes-list--get note (pcase notes-list-date-display
                          ('creation "TIME-CREATION")
                          ('access   "TIME-ACCESS")
                          (_         "TIME-MODIFICATION"))))

(defun notes-list--window-width ()
  (let ((window (get-buffer-window (current-buffer) t)))
    (if window (window-max-chars-per-line window) 80)))

(defun notes-list--slot (slot)
  "A one-column gutter cell that overlays can draw SLOT into."
  (propertize " " 'notes-list-slot slot))

(defun notes-list--align-right (string width)
  "Space that makes STRING end at column WIDTH."
  (propertize " " 'display
              `(space :align-to ,(max 0 (- width (string-width string))))))

(defun notes-list-format (note)
  "Format a NOTE as a two-line string.
Line 1: icon and title (left), date (right).
Line 2: summary (left), folder and tags (right).
Both lines start with gutter cells for the selection bar and mark."
  (let* ((width (1- (notes-list--window-width)))
         (filename (notes-list--get note "FILENAME"))
         (icon (notes-list--icon note))
         (indent (if icon (concat icon " ") ""))
         (gutter (+ 3 (string-width indent)))

         (time-str (if notes-list-display-date
                       (notes-list-format-time (notes-list--display-time note))
                     ""))
         (title-str (truncate-string-to-width
                     (notes-list-format-title (or (notes-list--get note "TITLE") ""))
                     (max 1 (- width gutter (string-width time-str) 2))
                     nil nil "…"))

         (right-str (string-join
                     (delq nil
                           (list (and notes-list-display-category
                                      (propertize (or (notes-list--get note "CATEGORY") "")
                                                  'face 'notes-list-face-category))
                                 (and notes-list-display-tags
                                      (notes-list--get note "TAGS")
                                      (notes-list-format-tags (notes-list--get note "TAGS")))))
                     " "))
         (right-str (truncate-string-to-width
                     right-str (max 0 (/ (- width gutter) 2)) nil nil "…"))
         (summary (notes-list--get note "SUMMARY"))
         (summary-str (truncate-string-to-width
                       (if (and summary (not (string-empty-p summary)))
                           (notes-list-format-summary summary)
                         (propertize (file-name-nondirectory filename)
                                     'face 'notes-list-face-time))
                       (max 1 (- width gutter (string-width right-str) 2))
                       nil nil "…")))
    (propertize (concat (notes-list--slot 'bar) (notes-list--slot 'mark)
                        (propertize " " 'display '(raise 0.25))
                        indent title-str
                        (notes-list--align-right time-str width) time-str
                        (propertize " " 'display "\n")
                        (notes-list--slot 'bar) " "
                        (propertize " " 'display '(raise -0.25))
                        (make-string (string-width indent) ?\s) summary-str
                        (notes-list--align-right right-str width) right-str)
                'filename filename
                'help-echo (abbreviate-file-name filename))))


;;; Parsing and collecting

(defun notes-list--read-keywords (filename)
  "Return an alist of the #+KEYWORD: values at the top of FILENAME.
Only the first few kilobytes are read, so this is fast even for big notes."
  (with-temp-buffer
    (insert-file-contents filename nil 0 8192)
    (goto-char (point-min))
    (let ((case-fold-search t)
          (keywords nil))
      (while (re-search-forward "^#\\+\\([[:alnum:]_]+\\):[ \t]*\\(.*\\)$" nil t)
        (let ((key (upcase (match-string-no-properties 1)))
              (value (string-trim (match-string-no-properties 2))))
          (unless (or (assoc key keywords) (string-empty-p value))
            (push (cons key value) keywords))))
      keywords)))

(defun notes-list--parse-date (string)
  "Return the time of the first YYYY-MM-DD date in STRING, or nil.
Accepts plain dates as well as org timestamps like <2024-02-26 Mon>."
  (when (and string
             (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{1,2\\}\\)-\\([0-9]\\{1,2\\}\\)"
                           string))
    (encode-time (list 0 0 0
                       (string-to-number (match-string 3 string))
                       (string-to-number (match-string 2 string))
                       (string-to-number (match-string 1 string))
                       nil -1 nil))))

(defun notes-list--category-of (filename root-directory)
  "Folder of FILENAME, named relative to ROOT-DIRECTORY's parent.
For example \"notes\" for a note at the top of ~/org/notes and
\"notes/python\" for one in ~/org/notes/python."
  (let ((dir (directory-file-name (file-name-directory (expand-file-name filename))))
        (root (and root-directory
                   (directory-file-name (expand-file-name root-directory)))))
    (if (and root (file-in-directory-p dir root))
        (let ((rel (file-relative-name dir root)))
          (concat (file-name-nondirectory root)
                  (if (member rel '("." "./")) "" (concat "/" rel))))
      (file-name-nondirectory dir))))

(defun notes-list-parse-org-note (filename &optional root-directory)
  "Parse an org file and extract title, date, summary, tags and icon.

Keywords need to be defined at top level. Provides sensible defaults
for any missing keywords:
- TITLE:    Defaults to the filename (without extension).
- DATE:     Defaults to the file's modification time.
- SUMMARY:  Defaults to an empty string.
- FILETAGS: Defaults to an empty list.  Space or colon separated.
- ICON:     Defaults to `notes-list-default-icon'.

CATEGORY is the note's folder, see `notes-list--category-of'."
  (let* ((attributes (file-attributes filename))
         (modification-time (file-attribute-modification-time attributes))
         (keywords (notes-list--read-keywords filename))
         (tags (cdr (assoc "FILETAGS" keywords))))
    (list (cons "FILENAME" filename)
          (cons "TITLE" (or (cdr (assoc "TITLE" keywords))
                            (file-name-base filename)))
          (cons "TIME-CREATION" (or (notes-list--parse-date (cdr (assoc "DATE" keywords)))
                                    modification-time))
          (cons "TIME-MODIFICATION" modification-time)
          (cons "TIME-ACCESS" (file-attribute-access-time attributes))
          (cons "SUMMARY" (or (cdr (assoc "SUMMARY" keywords)) ""))
          (cons "TAGS" (and tags (split-string tags "[ \t:]+" t)))
          (cons "ICON" (cdr (assoc "ICON" keywords)))
          (cons "CATEGORY" (notes-list--category-of filename root-directory)))))


(defun notes-list-compare-creation-time (note-1 note-2)
  (time-less-p (cdr (assoc "TIME-CREATION" note-1))
               (cdr (assoc "TIME-CREATION" note-2))))

(defun notes-list-compare-access-time (note-1 note-2)
  (time-less-p (cdr (assoc "TIME-ACCESS" note-1))
               (cdr (assoc "TIME-ACCESS" note-2))))

(defun notes-list-compare-modification-time (note-1 note-2)
  (time-less-p (cdr (assoc "TIME-MODIFICATION" note-1))
               (cdr (assoc "TIME-MODIFICATION" note-2))))

(defun notes-list-compare-title (note-1 note-2)
  (string-collate-lessp (cdr (assoc "TITLE" note-1))
                        (cdr (assoc "TITLE" note-2))
                        nil t))

(defun notes-list-note-p (filename)
  "Return t if FILENAME names a note file."
  (and (file-regular-p filename)
       (not (string-prefix-p "." (file-name-nondirectory filename)))))

(defun notes-list--visible-directory-p (directory)
  "Return non-nil unless DIRECTORY is hidden (.git, .ob-jupyter, ...)."
  (not (string-prefix-p "." (file-name-nondirectory (directory-file-name directory)))))

(defvar notes-list--notes nil
  "List of collected notes")

(defun notes-list-collect-notes ()
  "Collect notes from note directories"
  (setq notes-list--notes (funcall notes-list-collect-notes-function)))

(defun notes-list-collect-org-notes ()
  (let ((notes nil))
    (dolist (directory notes-list-directories)
      (let ((root (expand-file-name directory)))
        (if (not (file-directory-p root))
            (message "notes-list: skipping missing directory %s" directory)
          (dolist (filename (directory-files-recursively
                             root "\\.org\\'" nil #'notes-list--visible-directory-p))
            (when (notes-list-note-p filename)
              (push (notes-list-parse-org-note filename root) notes))))))
    notes))

(defun notes-list--root-of (filename)
  "Return the entry of `notes-list-directories' containing FILENAME."
  (cl-find-if (lambda (directory) (file-in-directory-p filename directory))
              notes-list-directories))

(defun notes-list--update-note (filename)
  "Re-read FILENAME into the list if it is an org note in a notes directory."
  (let ((filename (expand-file-name filename))
        (root (notes-list--root-of filename)))
    (when (and root
               (eq notes-list-collect-notes-function #'notes-list-collect-org-notes)
               (string-match-p "\\.org\\'" filename)
               (notes-list-note-p filename))
      (setq notes-list--notes
            (cons (notes-list-parse-org-note filename (expand-file-name root))
                  (cl-remove-if (lambda (note)
                                  (file-equal-p (notes-list--get note "FILENAME") filename))
                                notes-list--notes)))
      (notes-list-refresh))))

(defun notes-list--after-save ()
  "Keep the notes list up to date when a note is saved."
  (when (and buffer-file-name (get-buffer notes-list--buffer-name))
    (notes-list--update-note buffer-file-name)))


;;; Navigation and opening

(defun notes-list--note-at-point ()
  (get-text-property (point) 'filename))

(defun notes-list--require-note ()
  (or (notes-list--note-at-point)
      (user-error "No note at point")))

(defun notes-list--entry-bounds ()
  (cons (line-beginning-position)
        (min (1+ (line-end-position)) (point-max))))

(defun notes-list-quit ()
  "Close the notes list."
  (interactive)
  (kill-buffer (current-buffer)))

(defun notes-list-quit-frame ()
  "Close the notes list, and its frame if `notes-list' created one."
  (interactive)
  (let ((frame (selected-frame)))
    (notes-list-quit)
    (when (and (frame-live-p frame)
               (frame-parameter frame 'notes-list)
               (cdr (visible-frame-list)))
      (delete-frame frame))))

(defun notes-list-next-note ()
  (interactive)
  (forward-line 1)
  (unless (notes-list--note-at-point)
    (goto-char (point-min))))

(defun notes-list-prev-note ()
  (interactive)
  (if (bobp)
      (notes-list-last-note)
    (forward-line -1)))

(defun notes-list-first-note ()
  (interactive)
  (goto-char (point-min)))

(defun notes-list-last-note ()
  (interactive)
  (goto-char (point-max))
  (forward-line -1))

(defun notes-list--goto-note (filename)
  "Move point to FILENAME's entry and return non-nil, if it is listed."
  (goto-char (point-min))
  (while (and (not (eobp))
              (not (equal (notes-list--note-at-point) filename)))
    (forward-line 1))
  (not (eobp)))

(defun notes-list--target-window ()
  "Return the window notes are opened in: the last one used, or a new one."
  (or (get-mru-window nil nil t)
      (split-window (selected-window) nil 'right)))

(defun notes-list-open (filename)
  (funcall notes-list-open-function filename))

(defun notes-list-open-note ()
  "Open the note at point in the main window and switch to it."
  (interactive)
  (let ((filename (notes-list--require-note)))
    (select-window (notes-list--target-window))
    (notes-list-open filename)))

(defun notes-list-preview-note ()
  "Show the note at point in the main window, staying in the list."
  (interactive)
  (let ((filename (notes-list--require-note)))
    (with-selected-window (notes-list--target-window)
      (notes-list-open filename))))

(defalias 'notes-list-open-note-other-window #'notes-list-open-note)
(defalias 'notes-list-show-note-other-window #'notes-list-preview-note)

(defun notes-list--on-window-resize (window)
  "Redraw the list when WINDOW, which shows it, changes width."
  (with-current-buffer (window-buffer window)
    (unless (eql (window-max-chars-per-line window) notes-list--last-width)
      (notes-list-refresh))))


;;; Selection, stripes and marks

(defun notes-list--slots (slot beg end)
  "Positions of the SLOT gutter cells between BEG and END."
  (let ((positions nil)
        (pos beg))
    (while (setq pos (text-property-any pos end 'notes-list-slot slot))
      (push pos positions)
      (setq pos (1+ pos)))
    (nreverse positions)))

(defun notes-list--map-entries (function)
  "Call FUNCTION with point on each entry and the entry's index."
  (save-excursion
    (goto-char (point-min))
    (let ((i 0))
      (while (not (eobp))
        (when (notes-list--note-at-point)
          (funcall function i)
          (setq i (1+ i)))
        (forward-line 1)))))

(defun notes-list--apply-stripes ()
  "Apply alternating background face to every other note entry."
  (notes-list--map-entries
   (lambda (i)
     (when (cl-oddp i)
       (let ((ov (make-overlay (line-beginning-position)
                               (min (1+ (line-end-position)) (point-max)))))
         (overlay-put ov 'face 'notes-list-face-stripe)
         (overlay-put ov 'priority 1))))))

(defun notes-list--update-selection ()
  "Draw the selection on the note at point.
The selection bar is drawn into the gutter cells, so text never shifts."
  (when (derived-mode-p 'notes-list-mode)
    (mapc #'delete-overlay notes-list--selection-overlays)
    (setq notes-list--selection-overlays nil)
    (when (notes-list--note-at-point)
      (let* ((bounds (notes-list--entry-bounds))
             (ov (make-overlay (car bounds) (cdr bounds))))
        (overlay-put ov 'face 'notes-list-face-highlight)
        (overlay-put ov 'priority 50)
        (push ov notes-list--selection-overlays)
        (dolist (pos (notes-list--slots 'bar (car bounds) (cdr bounds)))
          (let ((ov (make-overlay pos (1+ pos))))
            (overlay-put ov 'display
                         (propertize "▌" 'face '(notes-list-face-indicator
                                                 notes-list-face-highlight)))
            (overlay-put ov 'priority 60)
            (push ov notes-list--selection-overlays)))))))

(defun notes-list--draw-mark ()
  "Draw or erase the mark of the entry at point."
  (let ((bounds (notes-list--entry-bounds)))
    (remove-overlays (car bounds) (cdr bounds) 'notes-list-mark t)
    (when (member (notes-list--note-at-point) notes-list--marked)
      (let ((ov (make-overlay (car bounds) (cdr bounds))))
        (overlay-put ov 'face 'notes-list-face-marked)
        (overlay-put ov 'priority 2)
        (overlay-put ov 'notes-list-mark t))
      (dolist (pos (notes-list--slots 'mark (car bounds) (cdr bounds)))
        (let ((ov (make-overlay pos (1+ pos))))
          (overlay-put ov 'display (propertize "*" 'face 'font-lock-warning-face))
          (overlay-put ov 'notes-list-mark t))))))

(defun notes-list--apply-marks ()
  "Draw the marks of all marked notes."
  (when notes-list--marked
    (notes-list--map-entries (lambda (_) (notes-list--draw-mark)))))

(defun notes-list-mark-note ()
  "Toggle mark on the note at point and advance to the next note."
  (interactive)
  (let ((filename (notes-list--require-note)))
    (if (member filename notes-list--marked)
        (setq notes-list--marked (delete filename notes-list--marked))
      (push filename notes-list--marked))
    (notes-list--draw-mark)
    (notes-list-next-note)))

(defun notes-list-unmark-note ()
  "Unmark the note at point and advance to the next note."
  (interactive)
  (let ((filename (notes-list--require-note)))
    (setq notes-list--marked (delete filename notes-list--marked))
    (notes-list--draw-mark)
    (notes-list-next-note)))

(defun notes-list-unmark-all ()
  "Unmark all marked notes."
  (interactive)
  (setq notes-list--marked nil)
  (remove-overlays (point-min) (point-max) 'notes-list-mark t))

(defun notes-list-delete-marked ()
  "Delete all marked notes after confirmation.
Notes go to the trash when `notes-list-delete-to-trash' is non-nil."
  (interactive)
  (setq notes-list--marked (cl-remove-if-not #'file-exists-p notes-list--marked))
  (if (null notes-list--marked)
      (message "No notes marked (press m to mark one).")
    (let* ((files notes-list--marked)
           (count (length files))
           (plural (if (= count 1) "" "s"))
           (trash notes-list-delete-to-trash))
      (when (yes-or-no-p (format "%s %d note%s (%s)? "
                                 (if trash "Move to trash" "Permanently delete")
                                 count plural
                                 (mapconcat #'file-name-nondirectory files ", ")))
        (let ((delete-by-moving-to-trash trash))
          (dolist (filename files)
            (let ((buffer (find-buffer-visiting filename)))
              (when buffer (kill-buffer buffer)))
            (delete-file filename trash)))
        (setq notes-list--marked nil)
        (notes-list-reload)
        (message "%s %d note%s." (if trash "Trashed" "Deleted") count plural)))))


;;; Filtering and sorting

(defun notes-list--match-filter-p (note)
  "Non-nil if every word of the text filter occurs somewhere in NOTE."
  (or (null notes-list--filter)
      (let ((haystack (downcase
                       (string-join
                        (append (list (notes-list--get note "TITLE")
                                      (notes-list--get note "SUMMARY")
                                      (notes-list--get note "CATEGORY")
                                      (file-name-base (notes-list--get note "FILENAME")))
                                (notes-list--get note "TAGS"))
                        " "))))
        (cl-every (lambda (word) (string-match-p (regexp-quote word) haystack))
                  (split-string (downcase notes-list--filter) nil t)))))

(defun notes-list--match-category-p (note)
  "Non-nil if NOTE is in the selected folder (and below) or has the selected tag."
  (let ((category notes-list--category))
    (or (null category)
        (if (string-suffix-p "/" category)
            (string-prefix-p category (concat (notes-list--get note "CATEGORY") "/"))
          (member category (mapcar #'downcase (notes-list--get note "TAGS")))))))

(defun notes-list--visible-notes ()
  "Notes to display, sorted and filtered."
  (let ((notes (sort (copy-sequence notes-list--notes) notes-list-sort-function)))
    (when (eq notes-list-sort-order 'descending)
      (setq notes (nreverse notes)))
    (cl-remove-if-not (lambda (note)
                        (and (notes-list--match-filter-p note)
                             (notes-list--match-category-p note)))
                      notes)))

(defun notes-list--set-filter (query)
  (let ((query (and query (string-trim query))))
    (when (equal query "")
      (setq query nil))
    (unless (equal query notes-list--filter)
      (setq notes-list--filter query)
      (notes-list-refresh))))

(defun notes-list-filter ()
  "Filter notes as you type.
Every word must occur in the title, summary, tags, folder or file
name.  RET keeps the filter, \\[keyboard-quit] restores the previous
one and an empty filter shows all notes."
  (interactive)
  (let ((previous notes-list--filter)
        (done nil))
    (unwind-protect
        (progn
          (notes-list--set-filter
           (minibuffer-with-setup-hook
               (lambda ()
                 (add-hook 'post-command-hook
                           (lambda ()
                             (notes-list--set-filter (minibuffer-contents-no-properties)))
                           nil t))
             (read-string "Filter: " notes-list--filter)))
          (setq done t))
      (unless done
        (notes-list--set-filter previous)))))

(defun notes-list-filter-clear ()
  "Clear all active filters (text and category)."
  (interactive)
  (setq notes-list--filter nil)
  (setq notes-list--category nil)
  (notes-list-refresh))

(defun notes-list--count-alist (table)
  (let ((alist nil))
    (maphash (lambda (key count) (push (cons key count) alist)) table)
    (sort alist (lambda (a b) (string< (car a) (car b))))))

(defun notes-list--categories ()
  "Return an alist of (CATEGORY . COUNT) over all notes.
Folders come first and end in \"/\"; tags follow, in lower case."
  (let ((folders (make-hash-table :test #'equal))
        (tags (make-hash-table :test #'equal)))
    (dolist (note notes-list--notes)
      (let ((prefix ""))
        (dolist (part (split-string (or (notes-list--get note "CATEGORY") "") "/" t))
          (setq prefix (concat prefix part "/"))
          (cl-incf (gethash prefix folders 0))))
      (dolist (tag (delete-dups (mapcar #'downcase (notes-list--get note "TAGS"))))
        (cl-incf (gethash tag tags 0))))
    (append (notes-list--count-alist folders)
            (notes-list--count-alist tags))))

(defun notes-list-browse-category ()
  "Show only the notes in a folder (and below) or with a tag.
Empty input shows all notes."
  (interactive)
  (let* ((categories (notes-list--categories))
         (table (lambda (string predicate action)
                  (if (eq action 'metadata)
                      `(metadata
                        (display-sort-function . identity)
                        (annotation-function
                         . ,(lambda (candidate)
                              (let ((count (cdr (assoc candidate categories))))
                                (and count (format "  (%d)" count))))))
                    (complete-with-action action categories string predicate))))
         (choice (completing-read "Folder/ or tag (empty for all): " table nil t)))
    (setq notes-list--category (if (string-empty-p choice) nil choice))
    (notes-list-refresh)))

(defun notes-list-reverse-sort-order ()
  "Reverse sort order (ascending <-> descending)"
  (interactive)
  (setq notes-list-sort-order
        (if (eq notes-list-sort-order 'ascending) 'descending 'ascending))
  (notes-list-refresh))

(defun notes-list-cycle-sort ()
  "Sort by the next criterion: modified, date, title, accessed.
The displayed date follows the criterion."
  (interactive)
  (let* ((current (assq notes-list-sort-function notes-list--sort-keys))
         (next (or (cadr (memq current notes-list--sort-keys))
                   (car notes-list--sort-keys))))
    (setq notes-list-sort-function (nth 0 next)
          notes-list-sort-order (nth 2 next))
    (when (nth 3 next)
      (setq notes-list-date-display (nth 3 next)))
    (notes-list-refresh)
    (message "Sorted by %s" (nth 1 next))))


;;; Creating notes

(defun notes-list--note-directories ()
  "Notes directories followed by the folders that contain notes."
  (let ((roots (mapcar (lambda (directory)
                         (file-name-as-directory (abbreviate-file-name
                                                  (expand-file-name directory))))
                       notes-list-directories))
        (folders nil))
    (dolist (note notes-list--notes)
      (cl-pushnew (abbreviate-file-name
                   (file-name-directory (notes-list--get note "FILENAME")))
                  folders :test #'string=))
    (append roots (sort (cl-set-difference folders roots :test #'string=) #'string<))))

(defun notes-list--all-tags ()
  (let ((tags nil))
    (dolist (note notes-list--notes)
      (dolist (tag (notes-list--get note "TAGS"))
        (cl-pushnew tag tags :test (lambda (a b) (string= (downcase a) (downcase b))))))
    (sort tags #'string<)))

(defun notes-list--slugify (title)
  (string-trim (replace-regexp-in-string "[^[:alnum:]]+" "_" (downcase title)) "_+" "_+"))

;;;###autoload
(defun notes-list-new-note ()
  "Create a note, prompting for title, folder, tags and summary.
The folder defaults to that of the selected note."
  (interactive)
  (unless notes-list--notes
    (notes-list-collect-notes))
  (let* ((title (string-trim (read-string "Title: ")))
         (slug (if (string-empty-p (notes-list--slugify title))
                   (user-error "A note needs a title")
                 (notes-list--slugify title)))
         (current (and (derived-mode-p 'notes-list-mode) (notes-list--note-at-point)))
         (default (if current
                      (abbreviate-file-name (file-name-directory current))
                    (car (notes-list--note-directories))))
         (directory (completing-read (format "Folder (default %s): " default)
                                     (notes-list--note-directories)
                                     nil nil nil nil default))
         (directory (if (string-empty-p directory) default directory))
         (filename (expand-file-name (concat slug ".org") directory))
         (_ (when (file-exists-p filename)
              (user-error "%s already exists" (abbreviate-file-name filename))))
         (tags (completing-read-multiple "Tags (comma separated): " (notes-list--all-tags)))
         (summary (string-trim (read-string "Summary: "))))
    (make-directory directory t)
    (with-temp-file filename
      (insert (format "#+TITLE: %s\n" title)
              (format "#+DATE: %s\n" (format-time-string "%Y-%m-%d"))
              (format "#+FILETAGS: %s\n" (string-join tags " "))
              (format "#+SUMMARY: %s\n" summary)
              (if notes-list-default-icon
                  (format "#+ICON: %s\n" notes-list-default-icon)
                "")
              "\n"))
    (when (get-buffer notes-list--buffer-name)
      (notes-list--update-note filename))
    (when (derived-mode-p 'notes-list-mode)
      (select-window (notes-list--target-window)))
    (notes-list-open filename)
    (goto-char (point-max))))


;;; Drawing

(defun notes-list--header-line (shown total)
  "Header line summarizing SHOWN of TOTAL notes, the sort and the filters."
  (let* ((filtered (or notes-list--filter notes-list--category))
         (sort-name (or (nth 1 (assq notes-list-sort-function notes-list--sort-keys))
                        "custom"))
         (left (string-join
                (delq nil
                      (list (if filtered
                                (format "%d of %d notes" shown total)
                              (format "%d note%s" total (if (= total 1) "" "s")))
                            (format "%s %s" sort-name
                                    (if (eq notes-list-sort-order 'ascending) "↑" "↓"))
                            (and notes-list--category
                                 (propertize notes-list--category
                                             'face 'notes-list-face-tags))
                            (and notes-list--filter
                                 (propertize (format "“%s”" notes-list--filter)
                                             'face 'notes-list-face-tags))))
                " · "))
         (right (if filtered "ESC clear " "? help "))
         (room (- (notes-list--window-width) (string-width left) 2)))
    (replace-regexp-in-string
     "%" "%%"
     (concat " " left
             (when (>= room (string-width right))
               (concat (propertize " " 'display
                                   `(space :align-to (- right ,(string-width right))))
                       (propertize right 'face 'shadow))))
     t t)))

(defun notes-list--empty-message ()
  (propertize
   (cond (notes-list--notes
          "  No notes match.  Press ESC to clear filters.")
         (t
          (format "  No notes found in %s.\n  Press + to create one."
                  (string-join notes-list-directories ", "))))
   'face 'shadow))

(defun notes-list-reload ()
  "Rebuild the note list"
  (interactive)
  (notes-list-collect-notes)
  (setq notes-list--marked (cl-remove-if-not #'file-exists-p notes-list--marked))
  (notes-list-refresh))

(defun notes-list-refresh ()
  "Rebuild the note list display (no reload from disk)"
  (interactive)
  (let ((buffer (get-buffer notes-list--buffer-name)))
    (when buffer
      (with-current-buffer buffer
        (let* ((notes (notes-list--visible-notes))
               (filename (notes-list--note-at-point))
               (line (count-lines (point-min) (line-beginning-position)))
               (inhibit-read-only t))
          (mapc #'delete-overlay (overlays-in (point-min) (point-max)))
          (setq notes-list--selection-overlays nil)
          (erase-buffer)
          (insert (if notes
                      (mapconcat #'notes-list-format notes "\n")
                    (notes-list--empty-message))
                  "\n")
          (notes-list--apply-stripes)
          (notes-list--apply-marks)
          (unless (and filename (notes-list--goto-note filename))
            (goto-char (point-min))
            (forward-line (min line (max 0 (1- (length notes))))))
          (dolist (window (get-buffer-window-list buffer nil t))
            (set-window-point window (point)))
          (setq notes-list--last-width (notes-list--window-width))
          (setq header-line-format
                (notes-list--header-line (length notes) (length notes-list--notes)))
          (notes-list--update-selection))))))

(defun notes-list-help ()
  "Show a help buffer describing notes-list keybindings and note format."
  (interactive)
  (with-help-window "*notes-list help*"
    (princ "notes-list — quick reference\n")
    (princ "════════════════════════════\n\n")
    (princ "Navigation\n")
    (princ "  n / C-n / ↓    Next note\n")
    (princ "  p / C-p / ↑    Previous note\n")
    (princ "  < / >          First / last note\n\n")
    (princ "Opening notes\n")
    (princ "  RET / TAB      Open note in the main window and switch to it\n")
    (princ "  double-click   Same as RET\n")
    (princ "  SPC            Preview note in the main window, stay in the list\n\n")
    (princ "Search & filter\n")
    (princ "  /              Filter as you type (title, summary, tags, folder)\n")
    (princ "  c              Show one folder (ending in /) or tag\n")
    (princ "  ESC            Clear all active filters\n\n")
    (princ "Sorting & display\n")
    (princ "  S              Cycle sort: modified → date → title → accessed\n")
    (princ "  s              Reverse sort order\n")
    (princ "  t              Toggle tag display\n")
    (princ "  d              Toggle date display\n\n")
    (princ "Creating & deleting\n")
    (princ "  +              New note (asks for title, folder, tags, summary)\n")
    (princ "  m              Toggle mark on note, advance to next\n")
    (princ "  u              Unmark note, advance to next\n")
    (princ "  U              Unmark all marked notes\n")
    (princ (format "  x              %s marked notes (asks confirmation)\n\n"
                   (if notes-list-delete-to-trash "Move to trash" "Delete")))
    (princ "Other\n")
    (princ "  g / r          Reload notes from disk (saving a note updates it too)\n")
    (princ "  q              Close the list\n")
    (princ "  Q              Close the list and its frame\n")
    (princ "  ?              Show this help\n\n")
    (princ "Note format (org keywords)\n")
    (princ "──────────────────────────\n")
    (princ "  #+TITLE:    My note title        (defaults to filename)\n")
    (princ "  #+DATE:     2024-01-15           (defaults to modification time)\n")
    (princ "  #+SUMMARY:  One-line description (optional)\n")
    (princ "  #+FILETAGS: TAG1 TAG2            (optional; used for tag filter)\n")
    (princ "  #+ICON:     material/notebook    (optional; needs nerd-icons)\n\n")
    (princ "Notes in subdirectories are collected recursively.\n")
    (princ "Each note's folder can be picked with c, like a tag.\n")))

(defun notes-list-toggle-date ()
  "Toggle date display"
  (interactive)
  (setq notes-list-display-date (not notes-list-display-date))
  (notes-list-refresh))

(defun notes-list-toggle-tags ()
  "Toggle tags display"
  (interactive)
  (setq notes-list-display-tags (not notes-list-display-tags))
  (notes-list-refresh))

(defun notes-list-buffer ()
  "Return the notes list buffer, creating it if needed."
  (or (get-buffer notes-list--buffer-name)
      (with-current-buffer (get-buffer-create notes-list--buffer-name)
        (notes-list-mode)
        (current-buffer))))

(defvar notes-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "d") #'notes-list-toggle-date)
    (define-key map (kbd "t") #'notes-list-toggle-tags)
    (define-key map (kbd "r") #'notes-list-reload)
    (define-key map (kbd "g") #'notes-list-reload)
    (define-key map (kbd "q") #'notes-list-quit)
    (define-key map (kbd "Q") #'notes-list-quit-frame)
    (define-key map (kbd "s") #'notes-list-reverse-sort-order)
    (define-key map (kbd "S") #'notes-list-cycle-sort)
    (define-key map (kbd "/") #'notes-list-filter)
    (define-key map (kbd "c") #'notes-list-browse-category)
    (define-key map (kbd "<escape>") #'notes-list-filter-clear)
    (define-key map (kbd "+") #'notes-list-new-note)
    (define-key map (kbd "SPC") #'notes-list-preview-note)
    (define-key map (kbd "TAB") #'notes-list-open-note)
    (define-key map (kbd "RET") #'notes-list-open-note)
    (define-key map (kbd "<double-mouse-1>") #'notes-list-open-note)
    (define-key map (kbd "n") #'notes-list-next-note)
    (define-key map (kbd "p") #'notes-list-prev-note)
    (define-key map (kbd "C-n") #'notes-list-next-note)
    (define-key map (kbd "C-p") #'notes-list-prev-note)
    (define-key map (kbd "<down>") #'notes-list-next-note)
    (define-key map (kbd "<up>") #'notes-list-prev-note)
    (define-key map (kbd "<") #'notes-list-first-note)
    (define-key map (kbd ">") #'notes-list-last-note)
    (define-key map (kbd "m") #'notes-list-mark-note)
    (define-key map (kbd "u") #'notes-list-unmark-note)
    (define-key map (kbd "U") #'notes-list-unmark-all)
    (define-key map (kbd "x") #'notes-list-delete-marked)
    (define-key map (kbd "?") #'notes-list-help)
    map)
  "Keymap for `notes-list-mode'.")

(define-derived-mode notes-list-mode special-mode "Notes"
  "Major mode for browsing notes.  Press \\[notes-list-help] for help.

\\{notes-list-mode-map}"
  (setq-local cursor-type nil)
  (setq-local buffer-undo-list t)
  (setq-local revert-buffer-function (lambda (&rest _) (notes-list-reload)))
  (add-hook 'post-command-hook #'notes-list--update-selection nil t)
  (add-hook 'window-size-change-functions #'notes-list--on-window-resize nil t)
  (add-hook 'after-save-hook #'notes-list--after-save))

(defun notes-list--frame ()
  "Return the live frame created by `notes-list', if any."
  (cl-find-if (lambda (frame) (frame-parameter frame 'notes-list))
              (frame-list)))

;;;###autoload
(defun notes-list ()
  "Show the notes list as a side window on the left.
With `notes-list-use-frame', the list lives in a frame of its own,
created on first use and raised on later calls."
  (interactive)
  (let ((buffer (notes-list-buffer)))
    (when notes-list-use-frame
      (select-frame-set-input-focus
       (or (notes-list--frame)
           (make-frame (cons '(notes-list . t) notes-list-frame-parameters)))))
    (select-window
     (or (get-buffer-window buffer)
         (display-buffer-in-side-window
          buffer `((side . left)
                   (slot . 0)
                   (window-width . ,notes-list-window-width)
                   (preserve-size . (t . nil))))))
    (notes-list-reload)))


(provide 'notes-list)
;;; notes-list.el ends here
