import Foundation

struct SloppyTUIThemeLoadWarning: Equatable, Sendable {
    var fileName: String
    var message: String
}

struct SloppyTUIThemeCatalog: Equatable, Sendable {
    var themes: [SloppyTUIResolvedTheme]
    var warnings: [SloppyTUIThemeLoadWarning]

    func theme(id: String) -> SloppyTUIResolvedTheme? {
        themes.first { $0.id == id }
    }
}

struct SloppyTUIThemeStore {
    var workspaceRoot: URL
    var fileManager: FileManager = .default

    static let opencodeThemeFileName = "opencode.json"
    static let opencodeThemeJSON = """
    {
      "name": "OpenCode",
      "colors": {
        "accent": "#78dce8",
        "accentBright": "#a6e3ff",
        "foreground": "#e6e6e6",
        "muted": "#8b94a7",
        "blue": "#7aa2f7",
        "green": "#9ece6a",
        "yellow": "#e0af68",
        "orange": "#ff9e64",
        "red": "#f7768e",
        "panelBackground": "#151515",
        "userMessageBackground": "#242424",
        "toolBackground": "#1e2428",
        "thinkingBackground": "#1b1b1b",
        "attachmentBackground": "#162325",
        "textBackground": "#101010",
        "truncatedBackground": "#101010"
      }
    }
    """

    var themesURL: URL {
        workspaceRoot
            .appendingPathComponent("tui", isDirectory: true)
            .appendingPathComponent("themes", isDirectory: true)
    }

    func ensureSeedThemes() throws {
        try fileManager.createDirectory(at: themesURL, withIntermediateDirectories: true)
        let opencodeURL = themesURL.appendingPathComponent(Self.opencodeThemeFileName)
        guard !fileManager.fileExists(atPath: opencodeURL.path) else { return }
        try Data((Self.opencodeThemeJSON + "\n").utf8).write(to: opencodeURL, options: .atomic)
    }

    func loadCatalog() -> SloppyTUIThemeCatalog {
        var themes = [SloppyTUIResolvedTheme.default]
        var warnings: [SloppyTUIThemeLoadWarning] = []

        guard let files = try? fileManager.contentsOfDirectory(
            at: themesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SloppyTUIThemeCatalog(themes: themes, warnings: warnings)
        }

        for file in files.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            guard file.pathExtension.lowercased() == "json" else { continue }
            do {
                let resourceValues = try file.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile != false else { continue }
                let theme = try loadCustomTheme(at: file)
                themes.append(theme)
            } catch {
                warnings.append(SloppyTUIThemeLoadWarning(
                    fileName: file.lastPathComponent,
                    message: String(describing: error)
                ))
            }
        }

        return SloppyTUIThemeCatalog(themes: themes, warnings: warnings)
    }

    func resolvedTheme(id: String) -> SloppyTUIResolvedTheme {
        loadCatalog().theme(id: id) ?? .default
    }

    private func loadCustomTheme(at url: URL) throws -> SloppyTUIResolvedTheme {
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(CustomThemeFile.self, from: data)
        let fileID = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let id = "custom:\(fileID.isEmpty ? "theme" : fileID)"
        let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name?.isEmpty == false ? name! : (fileID.isEmpty ? url.lastPathComponent : fileID)
        return try raw.colors.resolved(
            id: id,
            name: displayName,
            source: url.lastPathComponent,
            base: .default
        )
    }
}

private struct CustomThemeFile: Decodable {
    var name: String?
    var colors: CustomThemeColors

    enum CodingKeys: String, CodingKey {
        case name
        case colors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        colors = try container.decodeIfPresent(CustomThemeColors.self, forKey: .colors) ?? CustomThemeColors()
    }
}

private struct CustomThemeColors: Decodable {
    var accent: String?
    var accentBright: String?
    var foreground: String?
    var muted: String?
    var blue: String?
    var green: String?
    var yellow: String?
    var orange: String?
    var red: String?
    var panelBackground: String?
    var userMessageBackground: String?
    var toolBackground: String?
    var thinkingBackground: String?
    var attachmentBackground: String?
    var textBackground: String?
    var truncatedBackground: String?

    init() {}

    func resolved(
        id: String,
        name: String,
        source: String,
        base: SloppyTUIResolvedTheme
    ) throws -> SloppyTUIResolvedTheme {
        SloppyTUIResolvedTheme(
            id: id,
            name: name,
            source: source,
            accent: try color(accent, fallback: base.accent),
            accentBright: try color(accentBright, fallback: base.accentBright),
            foreground: try color(foreground, fallback: base.foreground),
            muted: try color(muted, fallback: base.muted),
            blue: try color(blue, fallback: base.blue),
            green: try color(green, fallback: base.green),
            yellow: try color(yellow, fallback: base.yellow),
            orange: try color(orange, fallback: base.orange),
            red: try color(red, fallback: base.red),
            panelBackground: try color(panelBackground, fallback: base.panelBackground),
            userMessageBackground: try color(userMessageBackground, fallback: base.userMessageBackground),
            toolBackground: try color(toolBackground, fallback: base.toolBackground),
            thinkingBackground: try color(thinkingBackground, fallback: base.thinkingBackground),
            attachmentBackground: try color(attachmentBackground, fallback: base.attachmentBackground),
            textBackground: try color(textBackground, fallback: base.textBackground),
            truncatedBackground: try color(truncatedBackground, fallback: base.truncatedBackground)
        )
    }

    private func color(_ raw: String?, fallback: SloppyTUIColor) throws -> SloppyTUIColor {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return try SloppyTUIColor(hex: raw)
    }
}
