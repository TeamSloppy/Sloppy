# Browser page memory

Browse unloads eligible background pages after **one hour without being visible**. A maintenance task checks once a minute, so unloading can occur up to a minute after the threshold. Selecting a tab restarts its inactivity interval. Favorites use the same policy; their saved entries and folders remain intact.

The tab itself stays in the sidebar. Before releasing its WebView, Sloppy saves the current URL and WebKit interaction state. Selecting it creates a new WebView and restores the page and navigation state. A moon icon identifies ordinary tabs waiting to load. Restoration can require a network connection; this is not an offline page archive or a complete JavaScript heap snapshot.

## Protection

Sloppy retains:

- The selected page and every visible Split View panel, including temporary mobile swipe previews.
- Pages currently presented in a view, loading, showing an element annotation, or owned by a connected agent browser session.
- Pages with input/change events in forms or editors, or pointer activity in a canvas/contenteditable editor.
- Pages playing media, capturing camera/microphone (including muted capture), or holding WebRTC peer connections.
- Pages with active agent commands or possible edits from type/click/evaluate commands. Agent access also grants a one-minute grace period.

Form tracking is conservative: edits remain protected until the document navigates or reloads. Sloppy does not guess when an arbitrary web app has autosaved. Monitoring sends booleans and frame identities to the app, never field values.

Before unloading, an isolated script probes the main document and recursively checks all subframes, including cross-origin frames. If a frame or WebKit fails to respond within two seconds, or monitoring is unavailable, the page stays resident. Visibility, ownership and activity are checked again after the asynchronous probe.

## Memory pressure

On macOS, OS warning/critical memory-pressure events trigger earlier reclamation. On iOS, the corresponding trigger is the application memory warning. Eligible pages are considered oldest first, with a one-minute inactivity grace. All protection rules still apply. iOS may suspend the app’s maintenance work while it is in the background.

Actual memory returned to the OS depends on WebKit’s own process and cache management; Sloppy releases its WebView/runtime ownership rather than merely hiding the page.
