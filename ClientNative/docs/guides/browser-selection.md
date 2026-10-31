# Text selection in the native browser

Select text on a page to show a small Sloppy button next to the last line of the
selection. Click the button to open its actions, following the interaction in
`Apps/SloppySafari/Extension/Resources/contentScript.js`.

The button is 20 px with the existing monochrome Sloppy symbol. It scales up by
10% on hover, with the transition disabled for Reduce Motion. The menu uses the
desktop charcoal palette, neutral focus rings and gray hover states.

- Enter a request or choose **Fact check**, **Define**, **Summarize**, or
  **Translate** to prepare an agent draft containing the selection and source.
  In Browse this opens Assistant beside the page and appends to its current
  draft. Nothing is sent automatically.
- **Add as annotation** appears when a receiving chat is visible. In Work, this
  can be the chat beside an embedded browser. In Browse, the open Assistant
  panel receives it; an expanded floating agent chat remains a fallback.
  A hidden Work tab is not a destination.
- The annotation retains the selected text, page URL and title. Text entered in
  the menu becomes its annotation comment. Existing draft text is preserved.
- The destination is bound when the menu opens. Closing the receiving chat,
  changing its session/agent, or changing the selected Work tab prevents stale
  delivery; the menu asks you to reopen it rather than inserting into another chat.
- Escape, scrolling, resizing, clearing the selection, navigating, or hiding a
  browser page dismisses its selection UI. Moving focus into the menu preserves
  the original selected text.

The page UI is isolated in a closed shadow root and a private `WKContentWorld`.
Selection text is not interpreted as HTML or executable JavaScript. The native
bridge accepts only its own web view's main frame and current HTTP(S) page.
Constructed stylesheets keep the controls styled without weakening the page's
Content Security Policy, including sites that prohibit inline styles.
Editable fields and iframe selections are excluded. Selections over 12,000 UTF-16
code units do not show the bubble; custom requests/comments are limited to 4,000
characters. Annotation source metadata is preserved in the existing versioned
chat annotation envelope.

`WorkspaceBrowserSelectionTests` runs the actual WebKit script and bridge in a
Mac window with a local HTTP fixture. It opens only the test shadow root to drive
the DOM controls; the message channel remains in the private content world.
`BrowserTextAnnotationTests` covers source metadata, draft preservation and
rejection after a destination change.

## Verification on 2026-10-30

- Final browser and annotation regression: 71 tests in 15 suites passed.
- Focused selection checks: 6 tests passed, including strict `style-src 'none'`,
  a 280-point viewport, hidden Work chats, source metadata and destination changes.
- Existing `ChatAnnotationTests` and `ChatSentAnnotationsTests`: 11 tests passed.
- The Mac Release build passed and was installed in `/Applications/Sloppy.app`
  with the existing Developer ID requirement, a recoverable previous app copy,
  signature verification and a successful launch.
- In a separately signed, launched Mac QA app, the closed-shadow selection
  button and menu were visually inspected on both ordinary and strict-CSP local
  pages. The QA profile contained no personal browser tabs or message drafts.
  Positive annotation delivery uses the real chat view model in the WebKit tests;
  no real agent message was sent during verification.

## Element annotations in Browse (macOS)

Open **Assistant**, then choose **Annotate element** below **Add page**. Hover to
highlight an HTML element, click it, add a comment and choose **Add to chat**.
Escape or **Cancel annotation** exits the picker.

The annotation adds a page screenshot and the selected region to the current
Assistant draft, together with the page URL/title, CSS selector, HTML tag, id and
classes. The editor shows the element details before adding it. Existing draft
text and annotations are preserved; use Send in the composer to deliver them.
You can repeat the action to annotate several elements.

Closing Assistant, switching pages or conversations, leaving Browse, and page
navigation cancel an unfinished selection. The receiver also checks the original
page and conversation before accepting the annotation. Picking an element does
not activate its links or buttons. DOM inspection runs in a private WebKit
content world; iframe contents are not traversed.

### Element annotation verification on 2026-10-31

- 14 annotation and Assistant tests passed, including the real Browse panel,
  native pointer picking, PNG capture, HTML metadata, draft preservation and
  cancellation after hiding Assistant, changing conversations or navigating.
- 15 related tests passed for text selection, strict site CSP, split rendering,
  browser content insets, Assistant rendering and annotation history.
- The full non-interactive client run executed 1,057 tests and reported six
  source-assertion failures in `ChatBubbleRenderingTests`,
  `ChatInitialLoadSourceTests`, `MainTabsSourceTests` and
  `ChatConversationNavigatorLayoutTests`; the full suite is not green.
- The macOS Release build passed with signing disabled. Changes are local;
  the installed application was not updated as part of this change.
