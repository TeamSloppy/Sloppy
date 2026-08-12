# Local Textual patches

This directory vendors Textual 0.5.0 (`01b51875a5406eefc95f52a058cb059e7bc94dc4`).
It keeps the upstream renderer and styles while applying four streaming/layout-stability fixes:

- Default Markdown parsing runs on a serialized background actor; cancelled streaming parses never publish stale output.
- `TextBuilder.sizeChanged` does not publish a new `Text` when attachment sizes are unchanged.
- `TextSelectionBackground` does not install its AppKit geometry overlay unless Textual selection is enabled.
- `AppKitTextSelectionView` does not write duplicate selection rectangles into SwiftUI state.

The upstream examples, snapshots, and test suite are intentionally omitted from the vendored runtime copy.
Local regression tests cover the streaming-specific patches maintained here.
