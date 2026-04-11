import Foundation
import Protocols

/// Inline keyboard + callback helpers for `/model` in Telegram (`callback_data` ≤ 64 bytes).
enum TelegramModelPicker {
    static let pageSize = 6
    static let maxCallbackBytes = 64
    static let maxButtonLabel = 36

    static func filterModels(_ models: [ProviderModelOption], query: String) -> [ProviderModelOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return models }
        let lower = q.lowercased()
        return models.filter { m in
            m.id.lowercased().contains(lower) || m.title.lowercased().contains(lower)
        }
    }

    static func buttonLabel(for model: ProviderModelOption) -> String {
        let raw = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = raw.isEmpty ? model.id : raw
        if base.count <= maxButtonLabel { return base }
        return String(base.prefix(maxButtonLabel - 1)) + "…"
    }

    static func buildPickerText(
        currentModelId: String?,
        filter: String,
        page: Int,
        totalPages: Int,
        totalMatches: Int
    ) -> String {
        let current = currentModelId.map { "Текущая модель: \($0)" } ?? "Текущая модель: по умолчанию"
        let filterLine: String
        if filter.isEmpty {
            filterLine = "Фильтр: нет (все модели)"
        } else {
            filterLine = "Фильтр: \(filter) — найдено \(totalMatches)"
        }
        let pageLine = totalPages > 0 ? "Страница \(page + 1) / \(totalPages)" : "Страница 0 / 0"
        return """
        \(current)

        \(filterLine)
        \(pageLine)

        Выберите модель кнопкой или укажите id: /model provider:model-id

        Подсказка: /model gpt — отфильтровать список по подстроке в id или названии.
        """
    }

    static func buildKeyboard(
        models: [ProviderModelOption],
        messageId: Int64,
        page: Int
    ) -> [[[String: String]]] {
        let totalPages = max(1, models.isEmpty ? 1 : Int(ceil(Double(models.count) / Double(pageSize))))
        let clampedPage = models.isEmpty ? 0 : min(max(0, page), totalPages - 1)
        let start = clampedPage * pageSize
        let slice = Array(models.dropFirst(start).prefix(pageSize))

        var rows: [[[String: String]]] = []
        var i = 0
        while i < slice.count {
            var row: [[String: String]] = [
                buttonDict(
                    label: buttonLabel(for: slice[i]),
                    data: callbackSelect(messageId: messageId, globalIndex: start + i)
                )
            ]
            if i + 1 < slice.count {
                row.append(
                    buttonDict(
                        label: buttonLabel(for: slice[i + 1]),
                        data: callbackSelect(messageId: messageId, globalIndex: start + i + 1)
                    )
                )
                i += 2
            } else {
                i += 1
            }
            rows.append(row)
        }

        if totalPages > 1 {
            let prevPage = max(0, clampedPage - 1)
            let nextPage = min(totalPages - 1, clampedPage + 1)
            rows.append([
                buttonDict(label: "◀︎", data: callbackPage(messageId: messageId, page: prevPage)),
                buttonDict(label: "▶︎", data: callbackPage(messageId: messageId, page: nextPage))
            ])
        }

        return rows
    }

    private static func buttonDict(label: String, data: String) -> [String: String] {
        ["text": label, "callback_data": data]
    }

    /// `M|msgId|P|page`
    static func callbackPage(messageId: Int64, page: Int) -> String {
        let s = "M|\(messageId)|P|\(page)"
        return truncateCallback(s)
    }

    /// `M|msgId|S|idx` — index in the **filtered** model array stored for this message.
    static func callbackSelect(messageId: Int64, globalIndex: Int) -> String {
        let s = "M|\(messageId)|S|\(globalIndex)"
        return truncateCallback(s)
    }

    private static func truncateCallback(_ s: String) -> String {
        if s.count <= maxCallbackBytes { return s }
        return String(s.prefix(maxCallbackBytes))
    }

    enum ParsedCallback {
        case page(messageId: Int64, page: Int)
        case select(messageId: Int64, index: Int)
        case unknown
    }

    static func parseCallback(_ data: String) -> ParsedCallback {
        let parts = data.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "M",
              let msgId = Int64(parts[1]),
              let v = Int(parts[3])
        else {
            return .unknown
        }
        switch parts[2] {
        case "P":
            return .page(messageId: msgId, page: v)
        case "S":
            return .select(messageId: msgId, index: v)
        default:
            return .unknown
        }
    }
}
