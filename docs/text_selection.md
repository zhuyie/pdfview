# Text Selection

This document describes the current text-selection behavior in the macOS
viewer, with emphasis on double-click word selection and selection highlight
visibility.

## Current Scope

Current text selection supports:

- single-page drag selection
- copy via `Cmd+C` / `Edit > Copy`
- double-click token selection

It does not yet support:

- multi-page drag selection
- auto-scroll while extending a selection
- language-aware word segmentation

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

## Known Limitations

- Chinese and other non-whitespace languages do not use dictionary-based word
  segmentation yet.
- Double-clicking non-ASCII text uses shared heuristics rather than
  language-specific tokenization.
- PDF text hit-testing still depends on PDFium's text stream and may differ
  from the exact visual grouping in some PDFs.
