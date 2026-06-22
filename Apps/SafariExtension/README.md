# SafariExtension

SafariExtension is a standalone Apple app project that packages the Sloppy Safari Web Extension.

## Build Settings Code

```bash
cd Apps/SafariExtension
swift test
```

## Generate Xcode Project

Requires XcodeGen:

```bash
cd Apps/SafariExtension
xcodegen generate
open SafariExtension.xcodeproj
```

## Runtime

macOS defaults to `http://127.0.0.1:25101`.

iOS, iPadOS, and visionOS need a LAN URL for the Mac or host running Sloppy Core, such as `http://192.168.1.50:25101`.

## Verify

```bash
cd Apps/SafariExtension
swift test
xcodegen generate
xcodebuild -project SafariExtension.xcodeproj -scheme SafariExtension-macOS build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

```bash
cd Apps/SafariExtension/Extension
npm test
```

From the repository root:

```bash
swift test --filter BrowserContextModelsTests
swift test --filter browserContextMessageEndpoint
swift build -c release --product sloppy
```

## Manual Smoke

Start Sloppy Core on the Mac or LAN host, launch the generated `SafariExtension-macOS` app, enable the extension in Safari, select text on a web page, open the SafariExtension toolbar action, enter a prompt, and send it to Core.
