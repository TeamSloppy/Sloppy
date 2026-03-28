import Foundation

enum CLIFormat: String {
    case json
    case table
}

enum CLIFormatters {
    static func output(_ data: Data, format: CLIFormat) {
        switch format {
        case .json:
            printJSON(data)
        case .table:
            printJSON(data)
        }
    }

    static func printJSON(_ data: Data) {
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            print(str)
        } else if let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    static func resolveFormat(_ rawFormat: String) -> CLIFormat {
        CLIFormat(rawValue: rawFormat.lowercased()) ?? .json
    }

    static func printTable<T>(
        rows: [T],
        columns: [(header: String, value: (T) -> String)]
    ) {
        guard !rows.isEmpty else {
            print(CLIStyle.dim("(no results)"))
            return
        }
        var widths = columns.map { $0.header.count }
        for row in rows {
            for (i, col) in columns.enumerated() {
                widths[i] = max(widths[i], col.value(row).count)
            }
        }
        let header = columns.enumerated().map { i, col in
            CLIStyle.bold(col.header.padding(toLength: widths[i], withPad: " ", startingAt: 0))
        }.joined(separator: "  ")
        print(header)
        let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "  ")
        print(CLIStyle.dim(separator))
        for row in rows {
            let line = columns.enumerated().map { i, col in
                col.value(row).padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            print(line)
        }
    }
}
