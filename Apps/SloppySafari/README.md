# SloppySafari

SloppySafari is a standalone Apple app project that packages the Sloppy Safari Web Extension.

## Build Settings Code

```bash
cd Apps/SloppySafari
swift test
```

## Generate Xcode Project

Requires XcodeGen:

```bash
cd Apps/SloppySafari
xcodegen generate
open SloppySafari.xcodeproj
```

## Runtime

macOS defaults to `http://127.0.0.1:25101`.

iOS, iPadOS, and visionOS need a LAN URL for the Mac or host running Sloppy Core, such as `http://192.168.1.50:25101`.

## Mesh Runtime

The extension can join Sloppy mesh directly. Paste a bundled `slp_mesh_...` invite into the Mesh section of the extension settings, click Join mesh, then set the target node id that exposes the agent Core API.

Mesh mode stores the extension node identity in Safari extension storage and sends Core API requests through relay `core.http` RPC. Streaming chat falls back to a complete non-streaming response in the first mesh increment.

## Verify

```bash
cd Apps/SloppySafari
swift test
xcodegen generate
xcodebuild -project SloppySafari.xcodeproj -scheme SloppySafari-macOS build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

```bash
cd Apps/SloppySafari/Extension
npm test
```

From the repository root:

```bash
swift test --filter BrowserContextModelsTests
swift test --filter browserContextMessageEndpoint
swift build -c release --product sloppy
```

## Manual Smoke

Start Sloppy Core on the Mac or LAN host, launch the generated `SloppySafari-macOS` app, enable the extension in Safari, select text on a web page, open the SloppySafari toolbar action, enter a prompt, and send it to Core.
