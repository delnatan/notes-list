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

Notes in subdirectories are collected recursively. Each note's folder (e.g.
`notes/python`) acts as a category alongside FILETAGS, so you can narrow the
list to a folder or a tag.

## Dependencies

- Emacs 27.1+
- `org` (built-in)
- Optional: [`nerd-icons`](https://github.com/rainstormstudio/nerd-icons.el)
  to display each note's `#+ICON:` (e.g. `material/notebook`)

## Usage

```elisp
(require 'notes-list)
(setq notes-list-directories '("~/notes"))
M-x notes-list
```

The first call opens a "Notes" frame with the list on the left; later calls
raise that frame again instead of creating a new one. Set
`notes-list-use-frame` to nil to show the list as a side window in the current
frame instead. Notes open in the main window, so the list stays visible.

The list updates by itself when you save a note.

## Keybindings

| Key            | Action                                            |
|----------------|---------------------------------------------------|
| `n` `p` `↑` `↓` | Next / previous note (also `C-n` `C-p`)          |
| `<` `>`        | First / last note                                 |
| `RET` `TAB`    | Open note in the main window and switch to it     |
| `SPC`          | Preview note in the main window, stay in the list |
| `/`            | Filter as you type (title, summary, tags, folder) |
| `c`            | Show one folder (ending in `/`) or tag            |
| `ESC`          | Clear all active filters                          |
| `S`            | Cycle sort: modified → date → title → accessed    |
| `s`            | Reverse sort order                                |
| `+`            | New note (asks for title, folder, tags, summary)  |
| `m` `u` `U`    | Mark / unmark / unmark all                        |
| `x`            | Move marked notes to the trash                    |
| `t` `d`        | Toggle tags / dates                               |
| `g` `r`        | Reload notes from disk                            |
| `q` / `Q`      | Close the list / close the list and its frame     |
| `?`            | Help                                              |

## Note format

Only `#+TITLE:` is required. All other keywords have sensible defaults:

- **TITLE** — defaults to filename (without extension)
- **DATE** — `2024-01-15` or an org timestamp `<2024-01-15 Mon>`;
  defaults to file modification time
- **SUMMARY** — defaults to empty string
- **FILETAGS** — space separated (`emacs org`) or org style (`:emacs:org:`);
  defaults to no tags
- **ICON** — `material/NAME`, shown with nerd-icons; defaults to
  `notes-list-default-icon`

## Customization

```elisp
;; Directories to search (recursively; hidden folders are skipped)
(setq notes-list-directories '("~/notes" "~/work/notes"))

;; Sort by title, creation, access, or modification time
(setq notes-list-sort-function #'notes-list-compare-title)
(setq notes-list-sort-order 'ascending)

;; Which timestamp to display, and how
(setq notes-list-date-display 'modification) ; or 'creation, 'access
(setq notes-list-date-format 'relative)      ; or e.g. "%Y-%m-%d"

;; Toggle display elements
(setq notes-list-display-tags t)
(setq notes-list-display-date t)
(setq notes-list-display-category nil)
(setq notes-list-display-icons t)

;; Window layout
(setq notes-list-use-frame t)
(setq notes-list-window-width 0.35)

;; Move deleted notes to the trash (nil deletes permanently)
(setq notes-list-delete-to-trash t)
```
