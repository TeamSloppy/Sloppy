import Foundation
import Protocols

enum SloppyTUITurnDiffDisplay {
    static func lines(_ diff: AgentTurnDiff, expanded: Bool, width: Int) -> [String] {
        let additions = diff.files.reduce(0) { $0 + $1.additions }
        let deletions = diff.files.reduce(0) { $0 + $1.deletions }
        let hint = expanded ? "" : " · Ctrl+O"
        let header = "Changes this turn · \(diff.files.count) files · +\(additions) −\(deletions)\(hint)"
        var lines = [SloppyTUITheme.fittedLine(header, width: width)]
        if diff.truncated {
            lines.append(SloppyTUITheme.fittedLine("Some changes exceeded the diff limit.", width: width))
        }
        for file in diff.files {
            let reason: String
            switch file.attribution {
            case .verified: reason = ""
            case .interleaved: reason = " · changed outside this turn"
            case .limited: reason = " · diff limit reached"
            }
            if expanded || !reason.isEmpty {
                let path = safeText(file.path).replacingOccurrences(of: "\n", with: "\\n")
                lines.append(SloppyTUITheme.fittedLine(path + reason, width: width))
            }
            if expanded, let patch = file.patch {
                lines.append(contentsOf: SloppyTUITheme.diffLines(safeText(patch), width: width))
            }
        }
        return lines
    }

    private static func safeText(_ text: String) -> String {
        let stripped = SloppyTUISelectionRenderer.stripANSI(text)
        return String(String.UnicodeScalarView(stripped.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0)
        }))
    }
}
