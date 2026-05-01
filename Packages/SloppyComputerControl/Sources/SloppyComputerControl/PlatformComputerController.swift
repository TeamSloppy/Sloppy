import Foundation

#if os(macOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct PlatformComputerController: ComputerControlling {
    public init() {}

    public func click(_ payload: ComputerClickPayload) async throws -> ComputerControlValue {
        try validateClickPayload(payload)
        let point = clickPoint(from: payload)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            throw ComputerControlError.operationFailed("Failed to create mouse events.")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .object(["x": .number(Double(point.x)), "y": .number(Double(point.y))])
    }

    public func typeText(_ payload: ComputerTypeTextPayload) async throws -> ComputerControlValue {
        guard !payload.text.isEmpty else {
            throw ComputerControlError.invalidArguments("`text` is required.")
        }
        for codeUnit in payload.text.utf16 {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                throw ComputerControlError.operationFailed("Failed to create keyboard event.")
            }
            var value = UniChar(codeUnit)
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            event.post(tap: .cghidEventTap)

            guard let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw ComputerControlError.operationFailed("Failed to create keyboard release event.")
            }
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            up.post(tap: .cghidEventTap)
        }
        return .object(["characters": .number(Double(payload.text.count))])
    }

    public func key(_ payload: ComputerKeyPayload) async throws -> ComputerControlValue {
        let key = payload.key.lowercased()
        guard let code = macKeyCodes[key] else {
            throw ComputerControlError.invalidArguments("Unsupported key '\(payload.key)'.")
        }
        let flags = macFlags(from: payload.modifiers)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        else {
            throw ComputerControlError.operationFailed("Failed to create keyboard events.")
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .object(["key": .string(key), "modifiers": .array(payload.modifiers.map { .string($0) })])
    }

    public func screenshot(_ payload: ComputerScreenshotPayload) async throws -> ComputerScreenshotResult {
        let displayID = CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayID) else {
            throw ComputerControlError.permissionDenied("Failed to capture display. Grant Screen Recording permission to SloppyNode.")
        }
        let outputURL = URL(fileURLWithPath: payload.outputPath ?? defaultScreenshotPath(extension: "png"))
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ComputerControlError.operationFailed("Failed to create screenshot destination.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ComputerControlError.operationFailed("Failed to write screenshot.")
        }
        return ComputerScreenshotResult(
            path: outputURL.path,
            width: image.width,
            height: image.height,
            mediaType: "image/png",
            displayId: String(displayID)
        )
    }
}

private func clickPoint(from payload: ComputerClickPayload) -> CGPoint {
    CGPoint(
        x: CGFloat(payload.x + ((payload.width ?? 0) / 2)),
        y: CGFloat(payload.y + ((payload.height ?? 0) / 2))
    )
}

private func macFlags(from modifiers: [String]) -> CGEventFlags {
    var flags = CGEventFlags()
    for modifier in modifiers.map({ $0.lowercased() }) {
        switch modifier {
        case "command", "cmd", "meta":
            flags.insert(.maskCommand)
        case "shift":
            flags.insert(.maskShift)
        case "option", "alt":
            flags.insert(.maskAlternate)
        case "control", "ctrl":
            flags.insert(.maskControl)
        default:
            continue
        }
    }
    return flags
}

private let macKeyCodes: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
    "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
    "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
    "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47
]

#elseif os(Windows)

public struct PlatformComputerController: ComputerControlling {
    public init() {}

    public func click(_ payload: ComputerClickPayload) async throws -> ComputerControlValue {
        try validateClickPayload(payload)
        let pointX = Int(payload.x + ((payload.width ?? 0) / 2))
        let pointY = Int(payload.y + ((payload.height ?? 0) / 2))
        let script = """
        Add-Type -AssemblyName System.Windows.Forms;
        Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class Native { [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y); [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo); }';
        [Native]::SetCursorPos(\(pointX), \(pointY)) | Out-Null;
        [Native]::mouse_event(0x0002, 0, 0, 0, 0);
        [Native]::mouse_event(0x0004, 0, 0, 0, 0);
        """
        _ = try runPowerShell(script)
        return .object(["x": .number(Double(pointX)), "y": .number(Double(pointY))])
    }

    public func typeText(_ payload: ComputerTypeTextPayload) async throws -> ComputerControlValue {
        guard !payload.text.isEmpty else {
            throw ComputerControlError.invalidArguments("`text` is required.")
        }
        let encoded = Data(payload.text.utf8).base64EncodedString()
        let script = """
        Add-Type -AssemblyName System.Windows.Forms;
        $text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(encoded)'));
        [System.Windows.Forms.SendKeys]::SendWait($text);
        """
        _ = try runPowerShell(script)
        return .object(["characters": .number(Double(payload.text.count))])
    }

    public func key(_ payload: ComputerKeyPayload) async throws -> ComputerControlValue {
        let sequence = try windowsSendKeysSequence(payload)
        let script = """
        Add-Type -AssemblyName System.Windows.Forms;
        [System.Windows.Forms.SendKeys]::SendWait('\(sequence)');
        """
        _ = try runPowerShell(script)
        return .object(["key": .string(payload.key), "modifiers": .array(payload.modifiers.map { .string($0) })])
    }

    public func screenshot(_ payload: ComputerScreenshotPayload) async throws -> ComputerScreenshotResult {
        let path = payload.outputPath ?? defaultScreenshotPath(extension: "png")
        let escapedPath = path.replacingOccurrences(of: "'", with: "''")
        let script = """
        Add-Type -AssemblyName System.Windows.Forms;
        Add-Type -AssemblyName System.Drawing;
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds;
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height;
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap);
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size);
        $bitmap.Save('\(escapedPath)', [System.Drawing.Imaging.ImageFormat]::Png);
        $graphics.Dispose();
        $bitmap.Dispose();
        Write-Output "$($bounds.Width),$($bounds.Height)";
        """
        let output = try runPowerShell(script).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = output.split(separator: ",").compactMap { Int($0) }
        return ComputerScreenshotResult(
            path: path,
            width: parts.first ?? 0,
            height: parts.dropFirst().first ?? 0,
            mediaType: "image/png",
            displayId: "primary"
        )
    }
}

private func windowsSendKeysSequence(_ payload: ComputerKeyPayload) throws -> String {
    let key = payload.key.lowercased()
    let mapped: String
    switch key {
    case "enter", "return":
        mapped = "{ENTER}"
    case "tab":
        mapped = "{TAB}"
    case "escape", "esc":
        mapped = "{ESC}"
    case "backspace":
        mapped = "{BACKSPACE}"
    case "delete":
        mapped = "{DELETE}"
    case "left":
        mapped = "{LEFT}"
    case "right":
        mapped = "{RIGHT}"
    case "up":
        mapped = "{UP}"
    case "down":
        mapped = "{DOWN}"
    default:
        guard key.count == 1 else {
            throw ComputerControlError.invalidArguments("Unsupported key '\(payload.key)'.")
        }
        mapped = key
    }

    var prefix = ""
    for modifier in payload.modifiers.map({ $0.lowercased() }) {
        switch modifier {
        case "control", "ctrl":
            prefix += "^"
        case "shift":
            prefix += "+"
        case "alt", "option":
            prefix += "%"
        default:
            continue
        }
    }
    return prefix + mapped
}

private func runPowerShell(_ script: String) throws -> String {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
    process.arguments = ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script]
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        let message = String(decoding: stderrData, as: UTF8.self)
        throw ComputerControlError.operationFailed(message.isEmpty ? "PowerShell computer control failed." : message)
    }
    return String(decoding: stdoutData, as: UTF8.self)
}

#else

public struct PlatformComputerController: ComputerControlling {
    public init() {}

    public func click(_: ComputerClickPayload) async throws -> ComputerControlValue {
        throw unsupported()
    }

    public func typeText(_: ComputerTypeTextPayload) async throws -> ComputerControlValue {
        throw unsupported()
    }

    public func key(_: ComputerKeyPayload) async throws -> ComputerControlValue {
        throw unsupported()
    }

    public func screenshot(_: ComputerScreenshotPayload) async throws -> ComputerScreenshotResult {
        throw unsupported()
    }
}

private func unsupported() -> ComputerControlError {
    ComputerControlError.unsupportedPlatform("Computer control is currently supported on macOS and Windows.")
}

#endif
