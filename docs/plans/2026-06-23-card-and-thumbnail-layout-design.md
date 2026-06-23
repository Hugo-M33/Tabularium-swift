# Card & thumbnail layout — design

Date: 2026-06-23
Status: approved, implementing

## Problem

Two layout bugs surfaced during the first TestFlight build:

1. **Card mode (`Cartes`)** — a wide photo with little height shows up massively
   zoomed in, so you can't tell what it is and can't classify it. Cause: the image
   is cropped *twice* — the PhotoKit fetch uses `contentMode: .aspectFill` at the
   card's tall portrait size (pre-cropping a vertical strip), then SwiftUI applies
   `.scaledToFill()` into the same tall frame (zooming that strip further).

2. **Home folder thumbnails** — some covers look stretched/distorted. Cause: the
   fetch (`PhotoLibrary.image(for:targetSize:)`) is called with a **square**
   `600×600` target and `contentMode: .aspectFill`. Square-fill on a non-square
   photo returns an off-aspect bitmap, which reads as distortion once placed in a
   landscape card. `.scaledToFill()` itself never stretches — it crops — so the
   defect is in the fetch parameters, not the SwiftUI side.

## Decisions

- **Card mode: cards match the photo's aspect ratio.** No cropping — the whole
  photo is always visible. The card resizes to the largest rectangle of the
  photo's aspect ratio that fits the available area.
- **Keep the swipe zone large.** The gesture area stays full-size and transparent;
  the visible photo-shaped card is centered inside it. You can grab and fling
  anywhere, even when the card is short (wide photo) or narrow (tall photo).
- **Behind cards get a slight, stable tilt.** A few degrees of rotation on the
  non-top card preserves the stacked-deck feel that photo-shaped cards would
  otherwise lose.
- **Home covers keep the fill/crop look.** Folder covers *should* fill (like Apple
  Photos albums); we only fix the fetch so the source bitmap has the right aspect.

## Implementation

### 1. `SwipeCardView.swift` — photo-shaped card, full gesture zone

- Read the aspect ratio from `PHAsset.pixelWidth / pixelHeight`. This is available
  instantly, before the image loads, so the card is correctly shaped from frame one
  and the photo simply fades in (no reflow/flicker).
- Structure:
  - The `GeometryReader` area stays full-size, transparent, and owns the drag
    gesture, `offset`, and `rotationEffect`.
  - A centered, photo-shaped rounded card holds the background, image, border,
    shadow, and the GARDER / SUPPRIMER decision labels.
- Compute the fitted card size: given the area and the photo aspect, take the
  larger rectangle that fits within both width and height.
- Fetch the image at the fitted card size (× screen scale) instead of the tall
  full-screen size, so PhotoKit stops pre-cropping. Display with `.scaledToFit()`.

### 2. `SorterScreen.swift` — behind-card rotation

- In `cardStack`, add a small `.rotationEffect` to non-top cards (`!entry.isTop`),
  keeping the existing `0.94` scale and `0.6` opacity.
- The angle is derived **deterministically from the card's `id`** (a stable hash
  of the identifier string), not a per-render random — otherwise the tilt would
  jitter on every redraw. Range: a few degrees either side of vertical.

### 3. `HomeScreen.swift` — `AlbumThumbnail` fetch target

- Request a **landscape** target size matching the card's real shape (roughly the
  card width × 170) instead of a square `600×600`. Keep `.scaledToFill()` on
  display — the cover look is intended. `aspectFill` then crops cleanly with no
  distortion.

## Out of scope

- No change to the shared `PhotoLibrary.image(for:targetSize:)` signature — callers
  pass the right `targetSize`.
- No blurred-backdrop treatment (the photo-shaped card removes the need for it).
