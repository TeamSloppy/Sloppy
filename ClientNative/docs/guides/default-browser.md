# Default browser

Sloppy accepts external HTTP and HTTPS links and opens each in a new Browse tab. Existing tabs and the connected workspace remain available. Browsing does not require a Core instance, sign-in, or completion of the welcome screen. The `sloppy://` connection and navigation links continue to use their existing handlers.

## macOS

Open **Settings → General → Default browser → Make Default**, then confirm the system prompt. The section shows when Sloppy handles both HTTP and HTTPS and refreshes when the settings scene becomes active.

Both the standalone and TestFlight app bundles declare the web URL schemes. Launch an installed `.app` bundle so Launch Services can register it; a bare SwiftPM executable cannot act as an installed browser. Incoming URLs use the root scene's SwiftUI URL handler and restore the main window.

## iOS and iPadOS

Open **Settings → General → Default browser → Open Default Browser Settings**, then select Sloppy in **Default Browser App**. iPhone and iPad targets declare HTTP/HTTPS and the managed `com.apple.developer.web-browser` entitlement.

Apple must approve the [default browser entitlement](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser) for `team.sloppy.client`. Enable it for the App ID and regenerate provisioning profiles before signing a device or distribution build. Adding the entitlement in this repository alone does not grant approval or make an unapproved build appear in the system's browser list. Simulator builds can validate routing and UI without granting that device capability.

## Verification

- Run `swift test --filter DefaultBrowserTests` for link routing, tab preservation, first-launch behavior and bundle registration.
- Run `SLOPPY_RUN_INTERACTIVE_UI_TESTS=1 swift test --filter DesktopSettingsTests` for the settings entry point (opens a test window).
- Build the macOS and iOS app targets after regenerating the Xcode project with `xcodegen generate`.
- With an installed macOS app, open two HTTP/HTTPS links explicitly in Sloppy, including while its window is closed. After choosing Sloppy as the system default, open a link from another app and verify that it reaches the same Browse surface.

Changing the machine's default browser is a user action; builds and automated tests do not perform it.
