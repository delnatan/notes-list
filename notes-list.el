;;; notes-list.el --- Notes list -*- lexical-binding: t -*-

;; Copyright (C) 2023 Free Software Foundation, Inc.

;; Maintainer: Nicolas P. Rougier <Nicolas.Rougier@inria.fr>
;; URL: https://github.com/rougier/notes-list
;; Version: 0.2.0
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
;; date, summary and tags. A typical org note header is:
;;
;;  #+TITLE:    Emacs hacking
;;  #+DATE:     2023-03-17
;;  #+FILETAGS: HACK EMACS CODE
;;  #+SUMMARY:  Notes about emacs hacking ideas
;;
;; Notes in subdirectories are collected recursively. The subdirectory name
;; acts as a category alongside FILETAGS. Press 'c' to browse by category,
;; '/' to filter by text, ESC to clear filters.

;;; News
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

(defcustom notes-list-sort-order #'descending
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

(defcustom notes-list-display-tags t
  "Display tags (bottom right)"
  :type 'boolean
  :group 'notes-list)

(defcustom notes-list-display-date t
  "Display date (top right)"
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

(defface notes-list-face-stripe
  `((t (:inherit highlight)))
  "Face to use for alternating note style in list.")

(defface notes-list-face-highlight
  `((t (:inherit region)))
  "Face to use for selected note style in list.")

(defvar notes-list--filter nil
  "Current text filter string, or nil for no filter.")

(defvar notes-list--category nil
  "Current category filter string, or nil for all categories.")

(defvar notes-list-collect-notes-function #'notes-list-collect-org-notes
  "Function to used to build list of notes to display. Customize
this combined with `notes-list-open-function' to adapt notes-list
to your favourite notes solution.")

(defvar notes-list-open-function #'find-file
  "Function used to open notes. Customize this combined with
`notes-list-collect-notes-function' to adapt notes-list to your
favourite notes solution.")

(defun notes-list-format-tags (tags)
  "Format TAGS as bracketed plain text strings."
  (mapconcat (lambda (tag)
               (propertize (format "[%s]" (upcase tag))
                           'face 'notes-list-face-tags))
             tags " "))

(defun notes-list-format-title (title)
  (propertize title 'face 'notes-list-face-title))

(defun notes-list-format-time (time)
  (let ((time (format-time-string "%B %d, %Y" time)))
    (propertize time 'face 'notes-list-face-time)))

(defun notes-list-format-summary (summary)
  (propertize summary 'face 'notes-list-face-summary))


(defun notes-list-format (note)
  "Format a NOTE as a two-line string.
Line 1: title (left) and date (right).
Line 2: summary (left) and tags (right)."

  (let* ((window (get-buffer-window (notes-list-buffer)))
         (width (- (window-width window) 1))
         (filename (cdr (assoc "FILENAME" note)))

         (tags (or (cdr (assoc "TAGS" note)) '()))
         (tags-str (if notes-list-display-tags
                       (notes-list-format-tags tags)
                     ""))

         (time (or (cond ((eq notes-list-date-display 'creation)
                          (cdr (assoc "TIME-CREATION" note)))
                         ((eq notes-list-date-display 'access)
                          (cdr (assoc "TIME-ACCESS" note)))
                         (t
                          (cdr (assoc "TIME-MODIFICATION" note))))
                   ""))
         (time-str (if notes-list-display-date
                       (notes-list-format-time time)
                     ""))

         (title (or (cdr (assoc "TITLE" note)) ""))
         (title-str (notes-list-format-title title))
         (title-str (concat (propertize " " 'display '(raise 0.25)) title-str))
         (title-str (truncate-string-to-width
                     title-str
                     (- width (length time-str) 1) nil nil "…"))

         (summary (or (cdr (assoc "SUMMARY" note)) ""))
         (summary-str (notes-list-format-summary summary))
         (summary-str (concat (propertize " " 'display '(raise -0.25)) summary-str))
         (summary-str (truncate-string-to-width
                       summary-str
                       (- width (length tags-str) 1) nil nil "…"))

         (top-filler (propertize " " 'display
                                 `(space :align-to (- right ,(length time-str) 1))))
         (bottom-filler (propertize " " 'display
                                    `(space :align-to (- right ,(length tags-str) 1)))))
    (propertize (concat title-str top-filler time-str
                        (propertize " " 'display "\n")
                        summary-str bottom-filler tags-str)
                'filename filename)))


(defun notes-list-parse-org-note (filename &optional root-directory)
  "Parse an org file and extract title, date, summary and tags.

Keywords need to be defined at top level. Provides sensible defaults
for any missing keywords:
- TITLE:    Defaults to the filename (without extension).
- DATE:     Defaults to the file's modification time.
- SUMMARY:  Defaults to an empty string.
- FILETAGS: Defaults to an empty list.

CATEGORY is derived from the relative subdirectory path within
ROOT-DIRECTORY, defaulting to \"general\" for root-level files."

  (let ((keep (find-buffer-visiting filename)))
    (with-current-buffer (find-file-noselect filename)
      (let* ((attributes (file-attributes filename))
             (access-time (file-attribute-access-time attributes))
             (modification-time (file-attribute-modification-time attributes))
             (info (org-collect-keywords '("TITLE"
                                           "DATE"
                                           "SUMMARY"
                                           "FILETAGS")))

             (title (or (cadr (assoc "TITLE" info))
                        (file-name-sans-extension (file-name-nondirectory filename))))

             (date (cadr (assoc "DATE" info)))
             (time (if date
                       (let ((parsed (parse-time-string date)))
                         (encode-time
                          (let ((n 0))
                            (mapcar (lambda (x)
                                      (if (< (setq n (1+ n)) 7) (or x 0) x))
                                    parsed))))
                     modification-time))

             (summary (or (cadr (assoc "SUMMARY" info)) ""))

             (tags-string (cadr (assoc "FILETAGS" info)))
             (tags (if tags-string (split-string tags-string) '()))

             (category (if root-directory
                           (let ((rel (file-relative-name
                                       (file-name-directory filename)
                                       (expand-file-name root-directory))))
                             (if (or (string= rel "./") (string= rel "."))
                                 "general"
                               (directory-file-name
                                (replace-regexp-in-string "/$" "" rel))))
                         "general")))

        (unless keep (kill-buffer))
        (list (cons "FILENAME" filename)
              (cons "TITLE" title)
              (cons "TIME-CREATION" time)
              (cons "TIME-MODIFICATION" modification-time)
              (cons "TIME-ACCESS" access-time)
              (cons "SUMMARY" summary)
              (cons "TAGS" tags)
              (cons "CATEGORY" category))))))


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
  (string-lessp (cdr (assoc "TITLE" note-1))
                (cdr (assoc "TITLE" note-2))))

(defun notes-list-note-p (filename)
  "Return t if FILENAME names a note file."
  (file-regular-p filename))

(defvar notes-list--notes nil
  "List of collected notes")

(defun notes-list-collect-notes ()
  "Collect notes from note directories"
  (let ((recentf-list-saved recentf-list)
        (notes (funcall notes-list-collect-notes-function)))
    (setq notes-list--notes notes)
    (setq recentf-list recentf-list-saved))
  notes-list--notes)


(defun notes-list-collect-org-notes ()
  (let ((notes nil))
    (dolist (directory notes-list-directories)
      (dolist (filename (directory-files-recursively
                         (expand-file-name directory) "\\.org$"))
        (when (notes-list-note-p filename)
          (let ((note (notes-list-parse-org-note filename directory)))
            (push note notes)))))
    notes))

(defun notes-list-quit ()
  (interactive)
  (kill-buffer))

(defun notes-list-next-note ()
  (interactive)
  (forward-line 1)
  (when (eq (point) (point-max))
    (goto-char (point-min))))

(defun notes-list-prev-note ()
  (interactive)
  (if (eq (point) (point-min))
      (goto-char (- (point-max) 1))
    (forward-line -1)))


(defun notes-list-open (filename)
  (funcall notes-list-open-function filename))

(defun notes-list-open-note ()
  (interactive)
  (let ((filename (get-text-property (point) 'filename)))
    (notes-list-open filename)))


(defun notes-list-open-note-other-window ()
  (interactive)
  (let ((filename (get-text-property (point) 'filename)))
    (other-window 1)
    (notes-list-open filename)))

(defun notes-list-show-note-other-window ()
  (interactive)
  (let ((filename (get-text-property (point) 'filename)))
    (with-selected-window (next-window)
      (find-file filename))))

(defvar notes-list--buffer-width nil
  "Notes list buffer width")

(defun notes-list--resize-hook (frame)
  "Refresh notes list if necessary"

  (when-let* ((window (get-buffer-window (notes-list-buffer))))
    (let ((window-width (window-width window)))
      (unless (eq window-width notes-list--buffer-width)
        (notes-list-refresh))
      (setq notes-list--buffer-width window-width))))

(defun notes-list--apply-stripes ()
  "Apply alternating background face to every other note entry."
  (save-excursion
    (goto-char (point-min))
    (let ((i 0))
      (while (not (eobp))
        (when (cl-oddp i)
          (let ((ov (make-overlay (line-beginning-position)
                                  (min (1+ (line-end-position)) (point-max)))))
            (overlay-put ov 'face 'notes-list-face-stripe)
            (overlay-put ov 'notes-list-stripe t)))
        (setq i (1+ i))
        (forward-line 1)))))

(defun notes-list--remove-stripes ()
  "Remove all stripe overlays from the buffer."
  (remove-overlays (point-min) (point-max) 'notes-list-stripe t))

(defun notes-list--categories ()
  "Return a sorted list of all unique categories and tags from collected notes."
  (let ((cats nil))
    (dolist (note notes-list--notes)
      (let ((cat (cdr (assoc "CATEGORY" note)))
            (tags (cdr (assoc "TAGS" note))))
        (when (and cat (not (string= cat "general")))
          (cl-pushnew cat cats :test #'string=))
        (dolist (tag tags)
          (cl-pushnew (downcase tag) cats :test #'string=))))
    (sort cats #'string<)))

(defun notes-list-filter ()
  "Prompt for a text filter and show only notes whose title or summary match."
  (interactive)
  (let ((query (read-string "Filter: " notes-list--filter)))
    (setq notes-list--filter (if (string-empty-p query) nil query))
    (notes-list-refresh)))

(defun notes-list-filter-clear ()
  "Clear all active filters (text and category)."
  (interactive)
  (setq notes-list--filter nil)
  (setq notes-list--category nil)
  (notes-list-refresh))

(defun notes-list-browse-category ()
  "Select a category to filter notes. Empty selection clears the filter."
  (interactive)
  (let* ((categories (notes-list--categories))
         (choice (completing-read "Category (empty for all): "
                                  categories nil nil)))
    (setq notes-list--category (if (string-empty-p choice) nil choice))
    (notes-list-refresh)))

(defun notes-list-reload ()
  "Rebuild the note list"

  (interactive)
  (notes-list-collect-notes)
  (notes-list-refresh))

(defun notes-list-reverse-sort-order ()
  "Reverse sort order (ascending <-> descending)"

  (interactive)
  (if (eq notes-list-sort-order 'ascending)
      (setq notes-list-sort-order 'descending)
    (setq notes-list-sort-order 'ascending))
  (notes-list-refresh))


(defun notes-list-refresh ()
  "Rebuild the note list display (no reload from disk)"

  (interactive)

  (let* ((notes (sort (copy-sequence notes-list--notes) notes-list-sort-function))
         (notes (if (eq notes-list-sort-order #'ascending)
                    notes
                  (reverse notes)))
         (notes (if notes-list--filter
                    (cl-remove-if-not
                     (lambda (note)
                       (let ((q (downcase notes-list--filter)))
                         (or (string-match-p q (downcase (or (cdr (assoc "TITLE" note)) "")))
                             (string-match-p q (downcase (or (cdr (assoc "SUMMARY" note)) ""))))))
                     notes)
                  notes))
         (notes (if notes-list--category
                    (cl-remove-if-not
                     (lambda (note)
                       (let ((cat (cdr (assoc "CATEGORY" note)))
                             (tags (mapcar #'downcase
                                           (or (cdr (assoc "TAGS" note)) '()))))
                         (or (and cat (string= notes-list--category cat))
                             (member notes-list--category tags))))
                     notes)
                  notes)))
    (with-current-buffer (notes-list-buffer)
      (let ((filename (get-text-property (point) 'filename)))
        (beginning-of-line)
        (let ((line (count-lines 1 (point)))
              (inhibit-read-only t))
          (erase-buffer)
          (notes-list--remove-stripes)
          (insert (mapconcat #'notes-list-format notes "\n"))
          (insert "\n")
          (notes-list--apply-stripes)
          (goto-char (point-min))
          (let ((match (text-property-search-forward 'filename filename t)))
            (if match
                (goto-char (prop-match-beginning match))
              (forward-line line)))
          (beginning-of-line)
          (setq header-line-format
                (let ((parts nil))
                  (when notes-list--category
                    (push (format "Category: %s" notes-list--category) parts))
                  (when notes-list--filter
                    (push (format "Filter: %s" notes-list--filter) parts))
                  (when parts
                    (concat "  " (string-join (reverse parts) "  |  ")
                            "  [ESC to clear]")))))))))

(defun notes-list-toggle-date ()
  "Toggle date display"

  (interactive)
  (if notes-list-display-date
      (setq notes-list-display-date nil)
    (setq notes-list-display-date t))
  (notes-list-refresh))

(defun notes-list-toggle-tags ()
  "Toggle tags display"

  (interactive)
  (if notes-list-display-tags
      (setq notes-list-display-tags nil)
    (setq notes-list-display-tags t))
  (notes-list-refresh))

(defun notes-list-buffer ()
  "Return the notes list buffer"

  (get-buffer-create "*notes-list*"))

(define-minor-mode notes-list-mode
  "A minor mode for browsing note list"

  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "d") #'notes-list-toggle-date)
            (define-key map (kbd "t") #'notes-list-toggle-tags)
            (define-key map (kbd "r") #'notes-list-reload)
            (define-key map (kbd "g") #'notes-list-refresh)
            (define-key map (kbd "q") #'notes-list-quit)
            (define-key map (kbd "s") #'notes-list-reverse-sort-order)
            (define-key map (kbd "/") #'notes-list-filter)
            (define-key map (kbd "c") #'notes-list-browse-category)
            (define-key map (kbd "ESC") #'notes-list-filter-clear)
            (define-key map (kbd "SPC") #'notes-list-show-note-other-window)
            (define-key map (kbd "<tab>") #'notes-list-open-note-other-window)
            (define-key map (kbd "<RET>") #'notes-list-open-note)
            (define-key map (kbd "<left>") nil)
            (define-key map (kbd "<right>") nil)
            (define-key map (kbd "<up>") #'notes-list-prev-note)
            (define-key map (kbd "<down>") #'notes-list-next-note)
            map)
  (when notes-list-mode
    (setq hl-line-overlay-priority 100)
    (hl-line-mode t)
    (face-remap-add-relative 'hl-line :inherit 'notes-list-face-highlight)
    (setq-local cursor-type nil)
    (read-only-mode t)
    (add-hook 'window-size-change-functions #'notes-list--resize-hook)))

;;;###autoload
(defun notes-list ()
  "Open a new frame split into two windows: notes-list on the left, scratch on the right."
  (interactive)
  (let ((fixed-frame-width 120)
        (fixed-frame-height 40))
    (let ((new-frame (make-frame `((width . ,fixed-frame-width)
                                   (height . ,fixed-frame-height)))))
      (select-frame-set-input-focus new-frame)
      (let ((right-window-width (round (* fixed-frame-width 0.35))))
        (split-window-right right-window-width))
      (switch-to-buffer (notes-list-buffer))
      (notes-list-reload)
      (notes-list-mode 1)
      (other-window 1)
      (switch-to-buffer "*scratch*"))))


(provide 'notes-list)
;;; notes-list.el ends here
