# Architecture

## Module Layout

### `src/core`

Platform-independent logic:

- Document loading abstraction
- Page layout
- Coordinate transforms
- Annotation data model
- View state

This layer should not depend directly on AppKit or Win32. The goal is to prevent platform UI code from taking over core logic.

### `src/mac`

Native macOS UI:

- `NSApplication`
- `NSWindow`
- `NSView`
- Input event bridging
- Retina / backing-scale handling

This layer should use Objective-C++ and hold the C++ core as ordinary objects.

### `src/win`

Native Windows UI:

- Win32 window class
- Message loop
- Mouse and keyboard input
- DPI awareness
- Drawing surface management

## Key Design Decisions

### 1. Rendering Layers

The rendering path should be split into three layers:

- `PdfDocument`
  - A thin wrapper around PDFium that manages document/page/text-page lifetimes
- `PageRasterizer`
  - Takes a page, zoom level, and clip region, then outputs a bitmap
- `DocumentViewModel`
  - Determines page layout, scroll offset, visible pages, and coordinate conversion

The point is to keep PDFium responsible only for document interpretation and rasterization, not for UI interaction logic.

### 2. Annotation Model

The first annotation implementation should use a sidecar file instead of modifying the PDF directly:

- File naming: `example.pdf.annotations.json`
- Benefits:
  - No need to handle incremental PDF writes
  - Faster iteration on the annotation data structure
  - Smaller failure surface

The initial schema should contain at least:

- `id`
- `page_index`
- `kind`
- `quad_points` or `rect`
- `color`
- `author`
- `created_at`
- `modified_at`

### 3. Coordinate System Discipline

Coordinate conversion is one of the easiest places for complexity to spread. Keep exactly three coordinate spaces:

- PDF page space
- View content space
- Window space

All annotation hit testing, selection rendering, and text selection should go through shared conversion functions rather than ad hoc math in each layer.

### 4. Text Selection

Text selection should rely on the PDFium text-page API rather than trying to infer glyph boundaries manually.

Basic flow:

1. Hit-test the page from the mouse location
2. Convert view coordinates into page coordinates
3. Use the text-page API to get the character index
4. Compute the selection range
5. Convert character quads back into view coordinates for overlay rendering

### 5. Cache Strategy

Keep the first version lightweight with a simple cache:

- Full-resolution cache for the current page
- Pre-render one page before and after the current page
- Separate cache for thumbnails

Do not introduce a complex multi-level tile cache in phase one. For typical documents with a moderate page count, a simple strategy is sufficient.

## Technology Choice

### Why C++ Instead of Zig

C++ is the stronger default choice at this stage:

- PDFium's ecosystem and examples are naturally closer to C++
- Objective-C++ and C++ interoperability is mature
- Win32 with C++ is the lowest-friction path
- CMake is more stable for this cross-platform setup

If Zig is introduced later, better roles would be:

- Packaging scripts
- Auxiliary tools
- Isolated experimental modules

It is not recommended to make Zig responsible for both the main UI layer and the PDFium bridge at the start.

## Recommended Milestones

### Milestone 1

- Open a PDF
- Render a single page
- Zoom and pan

### Milestone 2

- Continuous scrolling
- Text selection
- Page navigation

### Milestone 3

- Highlight / underline / rectangle annotations
- Sidecar save/load

### Milestone 4

- Search
- Outline
- Thumbnail panel
