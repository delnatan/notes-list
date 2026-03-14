# Notes list

Notes list collects notes in user-defined directories and populates a buffer
with a two-line summary for each note. Notes are parsed to extract title, date,
summary and tags. A typical org note header is:

```
#+TITLE:    Emacs hacking
#+DATE:     2023-03-17
#+FILETAGS: HACK EMACS CODE
#+SUMMARY:  Notes about emacs hacking ideas
```

Notes in subdirectories are collected recursively. The subdirectory name acts
as a category alongside FILETAGS, enabling category-based browsing.

## Dependencies

- Emacs 27.1+
- `org` (built-in)

No external packages required.

## Usage

```elisp
(require 'notes-list)
(setq notes-list-directories '("~/notes"))
M-x notes-list
```

This opens a new frame with the notes list on the left and `*scratch*` on the right.

## Keybindings

| Key     | Action                          |
|---------|---------------------------------|
| `RET`   | Open note                       |
| `TAB`   | Open note in other window       |
| `SPC`   | Show note in other window       |
| `/`     | Filter by title/summary text    |
| `c`     | Browse and filter by category   |
| `ESC`   | Clear all active filters        |
| `t`     | Toggle tags display             |
| `d`     | Toggle date display             |
| `s`     | Reverse sort order              |
| `r`     | Reload notes from disk          |
| `g`     | Refresh display                 |
| `q`     | Quit                            |
| `↑/↓`  | Navigate notes                  |

## Note format

Only `#+TITLE:` is required. All other keywords have sensible defaults:

- **TITLE** — defaults to filename (without extension)
- **DATE** — defaults to file modification time
- **SUMMARY** — defaults to empty string
- **FILETAGS** — defaults to no tags

## Customization

```elisp
;; Directories to search (recursively)
(setq notes-list-directories '("~/notes" "~/work/notes"))

;; Sort by title, creation, access, or modification time
(setq notes-list-sort-function #'notes-list-compare-title)
(setq notes-list-sort-order 'ascending)

;; Which timestamp to display
(setq notes-list-date-display 'modification) ; or 'creation, 'access

;; Toggle display elements
(setq notes-list-display-tags t)
(setq notes-list-display-date t)
```
