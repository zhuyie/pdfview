# Text Selection

This document describes the current text-selection behavior in the macOS
viewer, including drag selection, double-click token selection, copy/select-all
actions, and the current implementation split between core and macOS layers.

## Current Scope

Current text selection supports:

- single-page and multi-page drag selection
- gap fallback between pages while dragging
- auto-scroll while extending a selection near the viewport edge
- copy via `Cmd+C` / `Edit > Copy`
- select all via `Cmd+A` / `Edit > Select All`
- double-click token selection
- selection context menu with `Copy`

It does not yet support:

- triple-click line selection
- selecting a word on right-click before opening the context menu
- language-aware word segmentation
- richer context-menu actions such as search or lookup

## Double-Click Token Rules

Double-click selection is intentionally rule-based and lightweight.

### 1. ASCII word characters

The following characters are grouped together as a single token:

- letters
- digits
- underscore (`_`)

Examples:

- `hello`
- `hello_world`
- `abc123`

### 2. ASCII symbol runs

ASCII punctuation characters are grouped into symbol runs.

Examples:

- `++`
- `&&`
- `->`
- `...`

ASCII symbol runs do not merge with ASCII word characters.

Examples:

- double-clicking `C` in `C++` selects `C`
- double-clicking `+` in `C++` selects `++`

### 3. Non-ASCII text runs

Non-ASCII text is grouped into a run until one of these boundaries is reached:

- any ASCII character
- CJK punctuation

This keeps short Chinese phrases together without merging them into adjacent
Latin text or punctuation.

### 4. CJK punctuation

CJK punctuation is selected as a single character.

Examples:

- `，`
- `、`
- `：`
- `）`

Adjacent CJK punctuation marks do not merge into one token.

## Highlight Visibility Rules

Selection highlights use a filled overlay. For very thin glyphs, the highlight
rect is expanded so it remains visible.

Current minimum visible size:

- width: `5px`
- height: `5px`

This is mainly to keep narrow vertical or horizontal glyphs legible in the
selection overlay.

Examples:

- `I`
- `l`
- `-`

## Interaction Details

- Drag selection can begin from page whitespace. The anchor is created when the
  drag first hits selectable text.
- While dragging inside a page, if the pointer moves into whitespace that does
  not directly hit text, selection falls back to nearby text on the same page.
  In practice this means:
  - whitespace to the left or right of a short line snaps toward that line's
    start or end
  - whitespace between nearby lines snaps to the nearest line before choosing a
    character boundary
  - whitespace above or below all text on the page snaps to the page's first or
    last character
- Multi-page drag selection can extend across page gaps. When the pointer is in
  whitespace between pages, selection falls back to the next page start or the
  previous page end based on drag direction.
- Auto-scroll is enabled while dragging near the top or bottom of the visible
  document area.
- The context menu only appears when right-clicking inside the current
  selection.

## Implementation Layout

The current implementation is split across three layers.

### `src/core`

- tokenization and double-click boundary rules
- page/view coordinate conversion helpers
- cross-page selection normalization and text/span assembly
- page-local whitespace fallback based on PDFium character boxes

Key files:

- `src/core/text_selection.h`
- `src/core/text_selection.cpp`

### `src/mac/text_selection_controller.mm`

- page hit-testing against the active document view model
- drag-update and double-click selection orchestration
- select-all behavior for the current tab

### `src/mac/document_interaction_controller.mm`

- selection auto-scroll timer and edge-trigger behavior
- scroll-driven interaction coordination shared with the viewer

### `src/mac/tab_context.mm`

- current selection state storage for a tab
- overlay synchronization from selection spans into page views

## Known Limitations

- Chinese and other non-whitespace languages do not use dictionary-based word
  segmentation yet.
- Double-clicking non-ASCII text uses shared heuristics rather than
  language-specific tokenization.
- PDF text hit-testing still depends on PDFium's text stream and may differ
  from the exact visual grouping in some PDFs.
