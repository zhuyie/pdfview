# pdfview

A lightweight desktop PDF reader targeting macOS and Windows, with support for:

- PDF viewing and zooming
- Text selection
- Basic annotations
- Minimal reliance on heavy third-party libraries

## Technical Direction

The recommended mainline stack is:

- Language: C++
- Rendering: PDFium
- Build system: CMake
- macOS UI: AppKit + Objective-C++
- Windows UI: Win32

Zig is not the recommended primary implementation language for phase one. This is not because Zig is incapable, but because the combination of PDFium, native system UI, and cross-platform build integration is lower friction with C++, especially for:

- Direct integration with the PDFium C/C++ API
- Mixing Objective-C++ with native macOS window/view code
- Managing the Win32 message loop and drawing pipeline
- Adding platform-specific features later such as printing, clipboard, IME, and file dialogs

Zig would be more suitable later as a build helper or small tooling language, rather than as the initial foundation of this project.

## Architecture Principles

- Keep `core` and `platform` separate
- Separate PDF rendering from the annotation data model
- Use sidecar persistence for the first annotation version instead of writing back into the PDF
- Stabilize the reading experience first, then add write-back, search, outline, and thumbnails incrementally

## Phase One Scope

The MVP should include only:

- Open local PDF files
- Single-page and continuous-scroll viewing
- Zooming, panning, and page navigation
- Text selection
- Three annotation types: highlight, underline, and rectangle
- Annotation sidecar save/load

Not included initially:

- Rich text notes
- Collaborative sync
- Form filling
- Digital signatures
- Writing annotations back into the PDF

## Directory Layout

```text
.
├── CMakeLists.txt
├── README.md
├── docs/
│   └── architecture.md
└── src/
    ├── core/
    │   ├── annotation.h
    │   ├── document.h
    │   └── view_state.h
    ├── mac/
    └── win/
```

## Next Steps

Recommended implementation order:

1. Integrate PDFium and render a single page into a native window
2. Implement unified viewport, zoom, and page layout logic
3. Add text hit testing and selection
4. Add annotation overlays and sidecar persistence
5. Add search, outline, and thumbnail panels

## PDFium Integration

The repository now includes a PDFium-backed document loader scaffold behind a CMake option.

By default, CMake will look for a vendored PDFium distribution under `3rdparty/pdfium` on macOS and Windows.

To fetch the pinned binaries:

```bash
./scripts/vendor_pdfium.sh
```

Then configure with PDFium enabled:

```bash
cmake -S . -B build -DPDFVIEW_ENABLE_PDFIUM=ON
cmake --build build
```

If you need a non-vendored PDFium build, override `PDFIUM_ROOT` manually:

```bash
cmake -S . -B build \
  -DPDFVIEW_ENABLE_PDFIUM=ON \
  -DPDFIUM_ROOT=/path/to/pdfium
cmake --build build
```

Expected layout under `PDFIUM_ROOT`:

```text
pdfium/
├── include/
│   └── fpdfview.h
└── lib/
    └── libpdfium.dylib   # macOS example
```

Alternative library directories such as `lib/mac`, `lib/win`, and `bin` are also checked.
