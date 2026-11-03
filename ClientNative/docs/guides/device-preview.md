# Device preview

On macOS, open the right tool dock, choose **Devices** from its tools menu (or the browser start page), then choose the **iOS Simulator** or **Android** card. The preview bridge runs on the Mac displaying Sloppy, including when the chat uses a remote Core.

The first start downloads a pinned bridge into `~/Library/Application Support/Sloppy/DeviceBridges/`. Node.js 20+ and npm must already be installed. Sloppy currently checks the inherited PATH, Homebrew, Homebrew Node 22/24 and `/usr/local/bin`.

- **iOS:** Xcode, an installed simulator runtime, and Apple Silicon. Uses [serve-sim 0.1.46](https://github.com/EvanBacon/serve-sim).
- **Android:** Android SDK Platform-Tools; local emulator preview also needs a configured AVD. Uses [serve-avd 0.1.3](https://github.com/hsandhu/serve-avd). The bridge also supports connected ADB devices. SDK discovery follows `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or the standard macOS SDK location.

The embedded preview provides a device selector, touch/drag gestures, keyboard input, Home, rotation and platform-specific controls. It uses automatic codec selection (H.264 where available, MJPEG fallback). Open its devices sidebar to select or boot another device. Input support follows the selected bridge and runtime; some keyboard layouts and complex gestures have upstream limitations.

Choose **Annotate** to capture a device's original frame. When multiple devices are streaming, Sloppy asks which one to capture. It reads one bounded JPEG frame from the bridge and converts it to PNG, avoiding WebKit's black video/canvas snapshots. The frozen image opens in the existing editor with arrows, rectangles, drawing and comments. Device name, ID, platform and capture time accompany the image. **Add to chat** attaches it to the draft; sending remains a separate action.

The destination is bound when capture begins. If the chat changes or cannot accept the image, the edited capture remains available through **Review captured frame**. Reviewing binds it to the currently open chat. The capture can also be discarded.

**Disconnect**, closing a Devices tab, or quitting Sloppy stops its owned foreground bridges. The simulator/emulator keeps running. Hiding the dock preserves its connection. Each owned bridge has separate temporary runtime state so it does not remove another tool's bridge registrations.

## Connect Android on the local network

Use **Android over network**, enter the device's ADB address, such as `192.168.3.172:55555`, and choose **Connect Android**. The remote device or emulator host must expose an ADB TCP connection port reachable from this Mac. No local AVD is required.

Sloppy runs `adb connect <host>:<port>`, verifies that the device is online, and starts a local preview bridge targeting that exact device. It finds ADB through `ANDROID_HOME`, `ANDROID_SDK_ROOT`, the standard macOS SDK location, or PATH. Disconnecting stops Sloppy's preview bridge; it leaves the shared ADB connection and the remote device running.

For Android Wireless debugging, pair the Mac in Terminal first with `adb pair <host>:<pairing-port>` and the pairing code shown on the device. Then enter the **connection** address in Sloppy. Pairing and connection ports can differ. See the [Android ADB documentation](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi).

An ADB address is different from a web preview URL. Do not enter an ADB port in **Existing local bridge**. If a connection is refused, check the remote host's published ADB port, TCP forwarding and firewall. A port such as `55555` may be a host mapping; use the port actually configured on that host.

## Connect an existing local bridge

For sandboxed builds, or to manage the bridge yourself, run one of these in Terminal:

```sh
npx --yes serve-sim@0.1.46 --host 127.0.0.1 --codec auto --panes none
npx --yes serve-avd@0.1.3 --host 127.0.0.1 --codec auto --panes none
```

Expand **Existing local bridge**, choose the platform and enter the printed URL, such as `http://127.0.0.1:3200`. Only local HTTP origins are accepted. Disconnecting this connection leaves the externally managed bridge running. Use separate ports when running both platforms concurrently.

For a sandboxed build, connect the network device in Terminal with `adb connect <host>:<port>` before starting `serve-avd`. Then use **Existing local bridge**. The direct network flow, like the local start cards, requires a build that can launch local tools.

## Agent-controlled preview

In a Work chat connected to the macOS client, the agent can use `devices.preview` instead of computer use to open its own Devices tab:

```json
{"operation":"start","platform":"iOS"}
```

Use `Android` for an Android emulator, add `deviceId` to target a specific simulator UUID, AVD identifier or connected serial, or use `androidAddress` for an Android ADB address on the network. With no device specified, the pinned preview bridge chooses and boots its default available simulator/emulator.

Start returns immediately, including during the first bridge installation. Poll `{"operation":"status"}` until `devicePreview.state` is `ready` or `failed`. The response lists streaming device IDs. Use `{"operation":"screenshot","deviceId":"<observed ID>"}` to capture a real frame; the tool returns a PNG path that the agent can inspect with `images.inspect`.

Each conversation owns its preview. `{"operation":"stop"}` or closing the chat's client connection stops its bridge, leaving the simulator running. Other conversations and manually opened previews stay separate. The tool requires a client advertising `devices_v1`; an older or disconnected client produces an error rather than launching a simulator on Core's host.

This flow uses the preview bridge and does not require desktop Accessibility or Screen Recording permission. Normal agent tool approval policy still applies. Direct tap/swipe/type actions and installing or launching an app are not exposed by this tool yet.

## Validation

```sh
swift test --filter 'WorkspaceDeviceStateTests|WorkspaceDockStateTests|ChatAnnotationTests'
SLOPPY_RUN_INTERACTIVE_UI_TESTS=1 swift test --filter WorkspaceDeviceTests
```

Optional live checks use `SLOPPY_DEVICE_PREVIEW_URL=http://127.0.0.1:<port>` for an existing bridge, `SLOPPY_DEVICE_PREVIEW_PLATFORM=Android` for Android metadata (defaults to iOS), `SLOPPY_DEVICE_BRIDGE_ROOT=<directory containing node_modules>` for owned iOS bridge lifecycle checks, and `SLOPPY_DEVICE_SCREENSHOTS=<existing output directory>` for captured PNGs. Live checks require a running device; the owned bridge check requires a booted iOS simulator. Ordinary tests use a local HTTP fixture with an actual multipart JPEG frame.
