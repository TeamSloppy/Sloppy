import Foundation

enum SloppyTUITaskReferenceTokens {
    struct Token: Equatable {
        var rawToken: String
        var query: String
        var line: Int
        var startColumn: Int
        var endColumn: Int
    }

    static func tokenBeforeCursor(lines: [String], cursorLine: Int, cursorColumn: Int) -> Token? {
        guard lines.indices.contains(cursorLine) else {
            return nil
        }
        let line = lines[cursorLine]
        let endColumn = min(cursorColumn, line.count)
        let end = line.index(line.startIndex, offsetBy: endColumn)
        return tokens(in: line, lineNumber: cursorLine, end: end).last
    }

    private static func tokens(in line: String, lineNumber: Int, end: String.Index) -> [Token] {
        var result: [Token] = []
        var tokenStart: String.Index?
        var index = line.startIndex

        while index < end {
            let character = line[index]
            if tokenStart != nil {
                if character.isWhitespace {
                    tokenStart = nil
                }
            } else if character == "#" {
                tokenStart = index
            }
            index = line.index(after: index)
        }

        if let start = tokenStart {
            appendToken(in: line, lineNumber: lineNumber, start: start, end: end, to: &result)
        }
        return result
    }

    private static func appendToken(
        in line: String,
        lineNumber: Int,
        start: String.Index,
        end: String.Index,
        to result: inout [Token]
    ) {
        let rawToken = String(line[start..<end])
        guard rawToken.hasPrefix("#") else {
            return
        }
        result.append(Token(
            rawToken: rawToken,
            query: String(rawToken.dropFirst()),
            line: lineNumber,
            startColumn: line.distance(from: line.startIndex, to: start),
            endColumn: line.distance(from: line.startIndex, to: end)
        ))
    }
}

struct SloppyTUITaskReferenceSearchSuppression: Equatable {
    var rawToken: String
    var line: Int
    var startColumn: Int

    init(token: SloppyTUITaskReferenceTokens.Token) {
        self.rawToken = token.rawToken
        self.line = token.line
        self.startColumn = token.startColumn
    }

    init(rawToken: String, line: Int, startColumn: Int) {
        self.rawToken = rawToken
        self.line = line
        self.startColumn = startColumn
    }

    func matches(_ token: SloppyTUITaskReferenceTokens.Token?) -> Bool {
        guard let token,
              token.line == line,
              token.startColumn == startColumn
        else {
            return false
        }

        return token.rawToken.hasPrefix(rawToken) || rawToken.hasPrefix(token.rawToken)
    }
}
