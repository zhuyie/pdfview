# Vendored PDFium

This directory vendors a fixed PDFium binary distribution for local development and reproducible builds.

## Upstream

- Source: [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries)
- Chosen release: `PDFium 148.0.7749.0`
- Release branch tag: `chromium/7749`

## Vendored Targets

- macOS universal: `pdfium-mac-univ.tgz`
- Windows x64: `pdfium-win-x64.tgz`

These archives are unpacked into:

- `3rdparty/pdfium/mac-univ`
- `3rdparty/pdfium/win-x64`

## Refresh Process

Run:

```bash
./scripts/vendor_pdfium.sh
```

The script downloads the pinned release assets, verifies SHA-256 checksums, and unpacks them into the expected layout.

Vendoring metadata lives in `3rdparty/pdfium/vendor.env`.

## Notes

- Builds use the vendored directory by default on macOS and Windows.
- If you need a different PDFium build, override `PDFIUM_ROOT` at CMake configure time.
