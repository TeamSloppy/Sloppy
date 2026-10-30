# Safari Web Extensions in Browse

On macOS, open the puzzle-piece menu at the bottom of the Browse sidebar and
choose **Manage Web Extensions…**. **Add Web Extension…** accepts a containing
Safari extension `.app`, a Safari Web Extension `.appex`, or an unpacked folder
with `manifest.json`. Legacy Safari App Extensions are not supported.

An import starts disabled and grants no browser permissions or website access.
Choose the requested permissions and websites, then enable the extension.
`All websites` represents the extension's explicit `<all_urls>` request; it is
not granted automatically. Reload a page after changing website access or
disabling an extension. Toggle an extension off and on to restart its background
code after changing its browser permissions.

Sloppy remembers installations, enablement and explicit permission grants on the
Mac. The source stays in its original location and is accessed using a read-only
security-scoped bookmark. Removing or moving the source may require removing and
adding the extension again. Safari's enablement and permissions are separate.

Enabled extensions can inject content on authorized sites, query browser tabs,
activate or close tabs, navigate/open HTTP(S) tabs, present an action popup, and
open their options in a separate window. Use the extension's name in the
puzzle-piece menu to invoke its action. An extension may request more access;
Sloppy shows a permission dialog before granting it. Private windows, additional
browser windows, legacy Safari APIs and arbitrary extension-scheme tabs are not
implemented. Native companion communication depends on WebKit and the original
Safari app-extension bundle; unpacked extensions have no Sloppy native host.
Compatibility with every Safari extension is not implied.

The host uses Apple's public
[WKWebExtensionController](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)
API, available since macOS 15.4. This client targets macOS 26 and later.

## Passwords on macOS

Focus-triggered Apple Passwords autofill for arbitrary websites is **not
implemented** by this extension host. Passwords and Web Extensions are separate
capabilities. Sloppy does not read the user's password database or store website
credentials.

The public `ASAuthorizationPasswordProvider` request has no website argument;
shared website credentials require an app/site association. A local verification
on macOS 26.6.1 using the existing Sloppy development profile and application
identifier returned `ASAuthorizationError` 1001, `No credentials available for
login`. This does not establish that the user has no saved passwords, or that
system AutoFill settings are disabled. It establishes that this request did not
provide the desired arbitrary-site picker in the tested configuration.

See Apple's [app access to saved passwords](https://support.apple.com/guide/security/app-access-to-saved-passwords-sec8762eb992/web)
and [Password AutoFill](https://developer.apple.com/documentation/security/password-autofill).
Browser passkey permissions are a separate API and are not a substitute for
password autofill. No private WebKit selectors or unapproved browser entitlements
have been added to simulate this behavior.

## Verification

`BrowserExtensionsTests` exercises disabled installation, explicit permissions,
scope isolation, restoration, removal, duplicate imports and invalid sources.
`BrowserExtensionRuntimeTests` opts into interactive Mac testing with
`SLOPPY_RUN_INTERACTIVE_UI_TESTS=1`; it checks content injection before/after site
permission, action popup access to the selected tab, and opening a new tab.

Debug builds accept `--browser-ui-fixture` to launch the actual Browse surface
without Core authentication or personal tabs. Optional
`--browser-fixture-url=<HTTP(S) URL>` and
`--browser-fixture-extension=<local path>` supply a test page and an extension.
The fixture imports the extension disabled and grants no permissions. It uses
the isolated `team.sloppy.browser.qa` preferences suite.

### Results on 2026-10-30

- Mac Debug build and signing passed. The shared browser cohort passed 49 tests
  in 10 suites, including both extension suites. The three manager tests also
  passed independently in a temporary package using the same source files.
- In the launched Mac QA app, a synthetic extension restored its explicit
  loopback grant, injected visible content, displayed an action popup containing
  the selected tab's title, and opened a new browser tab from its popup button.
  QA permissions were seeded only in the isolated test profile; no personal
  browsing profile or Safari permissions were changed.
- An actual installed `Obsidian Web Clipper.app` (1.7.1) imported successfully
  through its Safari `.appex` bundle and remained disabled without grants. Its
  clipping/native companion workflows were not exercised.
- With an empty HTML login field focused in the running QA app, macOS's standard
  Edit → AutoFill → Passwords command was disabled. The same check for the
  password field did not make the command available. No saved credential was
  selected, read or filled. Focus-triggered Passwords autofill remains unfinished.
