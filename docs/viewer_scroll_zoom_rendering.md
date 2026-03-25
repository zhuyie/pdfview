# Viewer Scroll, Zoom, and Rendering

This document explains the current behavior of the PDF viewer around:

- page layout
- scroll state
- current-page tracking
- zoom / fit-mode changes
- visible-page rendering
- cache reuse and discard rules

The goal is to make the control flow explicit. This area has accumulated a fair amount of logic because the viewer needs to feel stable during:

- continuous scrolling
- repeated zoom changes
- fit-width / fit-page switching
- asynchronous page rendering

## Files Involved

Core logic:

- `src/core/document_view_model.h`
- `src/core/document_view_model.cpp`
- `src/core/viewport.h`
- `src/core/viewport.cpp`
- `src/core/page_cache.h`
- `src/core/page_cache.cpp`
- `src/core/view_state.h`

macOS platform glue:

- `src/mac/app_delegate.mm`
- `src/mac/render_coordinator.mm`
- `src/mac/tab_context.h`
- `src/mac/tab_context.mm`
- `src/mac/page_view_host.mm`
- `src/mac/image_bridge.mm`

## High-Level Model

The viewer is split into two layers.

Core is responsible for behavior:

- document page sizes
- current zoom mode
- page layout
- visible rect
- current page tracking
- viewport anchor capture / restore
- page cache planning
- page render planning

macOS is responsible for native objects:

- `NSScrollView`
- `NSClipView`
- `NSImageView`
- menu / toolbar input
- dispatch queues
- converting `Bitmap` to `NSImage`

The current design intent is:

- core decides what should happen
- mac applies it to AppKit objects

## Main State Objects

### `pdfview::core::ViewState`

This is the durable reading state:

- `scale_mode`
- `zoom`
- `scroll_x`
- `scroll_y`
- `current_page`

It is owned by `DocumentViewModel`.

### `pdfview::core::DocumentViewModel`

This is the main cross-platform reading model. It owns:

- document pointer
- per-page original sizes
- page cache slot states
- current `ViewState`
- current layout result
- viewport size
- device scale

Important methods:

- `fit_width_scale()`
- `fit_page_scale()`
- `current_logical_scale()`
- `current_render_scale()`
- `relayout()`
- `set_scroll_origin(...)`
- `capture_viewport_anchor()`
- `restored_scroll_y_for_anchor(...)`
- `update_current_page_from_scroll()`
- `scroll_y_for_current_page()`
- `page_cache_plan(...)`
- `page_render_plan()`

### `PDFTabContext`

This is the macOS per-tab shell. It mainly holds:

- `DocumentViewModel`
- `NSScrollView`
- `FlippedDocumentView`
- page `NSImageView`s
- page image cache entries

It should not contain heavy reading logic.

### `PDFRenderCoordinator`

This object executes render plans:

- compares the latest visible-page plan
- discards out-of-range pages
- submits asynchronous PDF renders
- drops stale requests
- applies rendered images on the main thread

## Layout Model

Layout is continuous vertical layout computed in core.

The current layout constants are in `DocumentViewModel::relayout()`:

- top margin: `20`
- side margin: `16`
- page gap: `24`

The layout result contains:

- `page_frames`
- `document_width`
- `document_height`

`page_frames` are in document-view coordinates, not platform window coordinates.

## Scale Model

There are three scale modes:

- `Manual`
- `FitWidth`
- `FitPage`

### Logical Scale

Logical scale is the UI-visible zoom level used for layout.

- manual mode: `ViewState.zoom`
- fit-width mode: computed from widest page and viewport width
- fit-page mode: computed from current page width and height against viewport

### Render Scale

Render scale is:

- `logical_scale * device_scale`

This is the bitmap rasterization scale.

On Retina displays this is larger than logical scale.

### Interactive Downscaling

During active scrolling / resize, macOS may reduce device scale temporarily for expensive pages.

This is a platform optimization, not a core rule:

- small pages render at normal scale
- only sufficiently costly pages are downscaled interactively
- when interaction settles, a full-quality visible update is triggered

## Scroll State

`NSClipView` is the source of truth for platform scrolling, but core owns the mirrored reading state.

The synchronization rule is:

1. AppKit scroll changes `NSClipView.bounds.origin`
2. mac updates `DocumentViewModel::set_scroll_origin(...)`
3. core recalculates `current_page` when needed

This means:

- AppKit owns actual scrolling
- core owns semantic reading state

## Current Page Tracking

Current page is not "the page whose top is visible".

The default tracking rule is:

- choose the page nearest to the viewport center

This is used by:

- toolbar state
- page navigation
- fit-page scale selection

There is separate logic for zoom anchoring, where "viewport top" matters more than "viewport center".

## Zoom Anchor Model

Zoom changes should preserve reading position. That sounds simple, but it is not enough to keep raw `scroll_y`.

When scale changes:

- page heights change
- total document height changes
- page gaps and top margin remain fixed
- the same `scroll_y` may now point to a different page or a different place in the page

The viewer therefore uses a dedicated viewport-anchor model.

### Why Viewport-Center Anchoring Was Not Enough

Earlier implementations anchored using the viewport center or current page only. That produced bugs such as:

- switching fit modes near the bottom of a page jumped to the next page
- deep documents jumped to the last page after a zoom change
- repeated fit-width / fit-page switching slowly drifted vertically
- the first page's top margin disappeared during zoom

### Current Anchor Rule

Core captures a `ViewportAnchor` from the viewport top:

- determine which page the viewport top belongs to
- if the top is inside a page, keep the relative offset inside that page
- if the top is above the page in the margin / gap, keep the absolute offset to the page top

This distinction is important:

- page-internal offsets should scale with page height
- page-external gaps should not scale

### Relevant Core APIs

- `find_page_at_viewport_top(...)`
- `capture_viewport_anchor(...)`
- `restore_viewport_anchor(...)`
- `DocumentViewModel::capture_viewport_anchor()`
- `DocumentViewModel::restored_scroll_y_for_anchor(...)`

## Zoom Transaction Flow

The zoom / fit-mode transaction currently lives in `AppDelegate::applyScaleChangeForContext`.

The order is:

1. cancel interactive rendering timer
2. sync current scroll origin into `DocumentViewModel`
3. update current page from scroll
4. capture viewport anchor from the old layout
5. mutate zoom mode or manual zoom
6. optionally invalidate rendered pages
7. temporarily suppress scroll notifications
8. relayout by calling `renderTabContext`
9. restore `current_page` to the captured anchor page
10. ask core for the restored scroll position
11. scroll the `NSClipView`
12. sync the new scroll origin back into core
13. recompute current page from the new scroll position
14. update visible pages
15. re-enable scroll notifications

Important detail:

- programmatic scrolling is wrapped by `suppressScrollTracking_`

Without that guard, intermediate programmatic scroll events can overwrite `current_page` or trigger duplicate visible updates during relayout.

## Plain Scrolling Flow

Normal user scrolling is simpler:

1. `NSClipView` posts bounds-changed notification
2. `tabClipViewDidScroll:` finds the owning tab
3. mac syncs scroll origin into `DocumentViewModel`
4. core recomputes current page
5. mac starts / refreshes the interactive-render timer
6. mac asks `PDFRenderCoordinator` for a visible update

## Page Navigation Flow

Page navigation uses `current_page`, not viewport anchor math.

For next / previous page:

1. increment or decrement `current_page`
2. ask core for `scroll_y_for_current_page()`
3. scroll the clip view to that position
4. sync scroll origin back into core
5. update visible pages

This keeps page navigation behavior deterministic and cross-platform.

## Rendering Model

Rendering is intentionally split into:

- layout / planning in core
- execution in platform code

### Step 1: Layout

`renderTabContext` updates:

- viewport size
- device scale
- scroll origin

Then core recomputes:

- layout result
- visible rect
- current logical scale
- current render scale

### Step 2: Visible-Page Plan

`PDFRenderCoordinator::updateVisiblePagesForContext` asks core for:

- `PageCachePlan`
- `PageRenderPlan`

The plan distinguishes:

- `visible_range`
- `preload_range`
- `keep_range`

The current behavior is:

- render pages in `preload_range`
- keep pages in a slightly wider `keep_range`
- discard loaded or pending pages outside `keep_range`

This wider keep range is important because it reduces "just scrolled away, immediately discard, then rerender" churn.

### Step 3: Request Deduplication

Before submitting work, the platform layer checks:

- is the plan unchanged since the previous visible update
- is the page already pending at a covering scale
- is the page already loaded at a covering scale and still has an image

If so, submission is skipped.

This avoids:

- duplicate visible updates
- duplicate page submissions
- stale requests piling up behind newer ones

### Step 4: Async Rasterization

Actual page rasterization happens on a serial dispatch queue.

Each request gets a monotonically increasing `requestId`.

Before rendering starts, the worker re-checks on the main thread:

- page index still matches
- request id still matches
- request is still marked pending at the same scale

If not, the request is dropped as stale.

### Step 5: Main-Thread Image Apply

After rasterization:

1. `Bitmap` is converted to `NSImage`
2. image is stored in the page cache entry
3. cache slot state is marked loaded
4. image is applied to the page `NSImageView`

## Cache Rules

The cache is page-based, not tile-based.

Each page slot tracks:

- `loaded`
- `pending`
- `render_scale`

### Covering-Scale Reuse

The viewer does not require an exact render-scale match.

A higher-resolution page may temporarily satisfy a lower target scale if it is not too much larger.

The current covering-scale threshold is:

- up to `1.5x` the target render scale

Examples:

- cached `1.4x` for target `1.0x`: reuse
- cached `3.0x` for target `1.0x`: rerender lower

This policy exists to balance:

- responsiveness during zoom-out
- avoiding permanent oversized bitmap retention

### Why Old Images May Be Reused

After a zoom-out, the old image may still be displayed briefly or reused if:

- it still covers the target scale
- it remains within `keep_range`

This is intentional. The goal is to avoid immediate rerender churn.

However, very oversized images are no longer kept forever. They are rerendered at a more appropriate scale.

## Why `NSImageView` Still Matters

Even with correct cache logic, there is a display-layer concern:

- layout changes can happen before replacement bitmaps are ready

To avoid old images visually spilling out of resized page frames, `PDFPageViewHost` configures page image views with:

- proportional image scaling
- layer-backed clipping (`masksToBounds = YES`)

Without this, old images can continue drawing at their previous pixel size after the page frame shrinks.

## Profiling

Profiling is now shared infrastructure in core, even though most sample points are currently emitted by the macOS path.

Important event types:

- `render_tab`
- `visible_update`
- `visible_update_skip`
- `page_submit_skip`
- `page_skip`
- `page_render`
- `session_summary`

Useful environment variables:

- `PDFVIEW_PROFILE_RENDER=1`
- `PDFVIEW_PROFILE_RENDER_FILE=/path/to/file`

The logs are intended to answer:

- are we relayouting too much
- are visible updates empty or duplicated
- are page requests stale
- are large pages rendered too often
- is cache retention too narrow

## Known Complexity / Tradeoffs

This subsystem is complicated because it has to satisfy conflicting goals:

- keep reading position stable during zoom
- avoid visible stale content
- avoid submitting duplicate renders
- avoid holding huge bitmaps forever
- preserve smooth interaction during active scrolling

Some important tradeoffs:

### High-level bitmap reuse vs memory

Reusing slightly oversized bitmaps:

- reduces rerender work
- improves zoom-out responsiveness

But:

- increases local memory usage near the viewport

That is why the current rule allows modest oversizing, but not unlimited oversizing.

### Stable zoom anchoring vs simple math

Keeping raw `scroll_y` across scale changes is simpler, but wrong.

Keeping a page-relative anchor is more complex, but prevents:

- jumps to the wrong page
- gradual drift during repeated fit-mode switches
- losing page-top margin on the first page

### Platform scroll view vs core reading state

The platform scroll view always remains the real scrolling mechanism.

But semantic behavior should continue to live in core:

- current page
- visible rect
- page anchor
- page render planning

That separation is what makes Windows reuse possible.

## Practical Guidance for Future Changes

When changing this subsystem:

1. Decide whether the rule is behavioral or platform-specific.
   Behavioral rules belong in core.
2. Do not add new page-position math directly in AppKit event handlers unless it is truly platform-only.
3. If zoom behavior changes, add or update a core test.
4. If render behavior changes, inspect profiling logs before and after.
5. Preserve the distinction between:
   - current-page tracking
   - zoom anchor selection
   - page cache planning

Those three concepts are related, but they are not the same rule.

## Recommended Next Refactors

The current structure is much better than before, but this area is still not fully abstracted.

The next sensible steps would be:

- move the remaining zoom-transaction orchestration into a core helper
- make current-page selection strategy explicit in core
- add more pure-core tests for long-document zoom and scroll scenarios
- eventually let Windows call the same `DocumentViewModel` transaction helpers directly
