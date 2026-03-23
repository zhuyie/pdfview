# Test Fixtures

`tests/fixtures/smoke.pdf` is a tiny single-page PDF checked into the repository for smoke tests.
`tests/fixtures/multipage.pdf` is a tiny three-page PDF for scrolling and page navigation tests.

It is intentionally simple:

- One page
- Built-in Helvetica font
- Plain text content
- A stroked rectangle

Use it to verify:

- Document loading
- First-page raster rendering
- Basic layout and scaling

Use `tests/fixtures/multipage.pdf` to verify:

- Continuous scrolling
- Current-page tracking
- Page navigation shortcuts
