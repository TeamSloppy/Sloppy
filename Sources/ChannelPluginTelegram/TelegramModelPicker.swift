import Foundation
import Protocols

/// Inline keyboard + callback helpers for `/model` in Telegram (`callback_data` ≤ 64 bytes).
enum TelegramModelPicker {
    struct ProviderEntry: Equatable {
        let id: String
        let title: String
        let count: Int
    }

    static let pageSize = 6
    static let providerPageSize = 8
    static let maxCallbackBytes = 64
    static let maxButtonLabel = 36

    static func filterModels(_ models: [ProviderModelOption], query: String, providerId selectedProviderId: String? = nil) -> [ProviderModelOption] {
        let scoped = models.filter { selectedProviderId == nil || providerId(for: $0) == selectedProviderId }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return scoped }
        let lower = q.lowercased()
        return scoped.filter { m in
            m.id.lowercased().contains(lower) || m.title.lowercased().contains(lower)
        }
    }

    static func providerEntries(from models: [ProviderModelOption]) -> [ProviderEntry] {
        let grouped = Dictionary(grouping: models, by: providerId(for:))
        return grouped.keys.sorted().map { provider in
            ProviderEntry(
                id: provider,
                title: providerTitle(provider),
                count: grouped[provider]?.count ?? 0
            )
        }
    }

    static func providerId(for model: ProviderModelOption) -> String {
        let parts = model.id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[0]) : "configured"
    }

    static func providerTitle(_ providerId: String) -> String {
        switch providerId.lowercased() {
        case "anthropic":
            return "Anthropic"
        case "gemini":
            return "Gemini"
        case "ollama":
            return "Ollama"
        case "openai-api":
            return "OpenAI API"
        case "openai-oauth":
            return "OpenAI Codex"
        case "opencode":
            return "OpenCode"
        case "openrouter":
            return "OpenRouter"
        case "configured":
            return "Configured"
        default:
            return providerId
                .split(separator: "-")
                .map { segment in
                    segment.prefix(1).uppercased() + segment.dropFirst()
                }
                .joined(separator: " ")
        }
    }

    static func buttonLabel(for model: ProviderModelOption) -> String {
        let raw = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = raw.isEmpty ? model.id : raw
        if base.count <= maxButtonLabel { return base }
        return String(base.prefix(maxButtonLabel - 1)) + "…"
    }

    static func buildProviderPickerText(
        currentModelId: String?,
        filter: String,
        page: Int,
        totalPages: Int,
        totalProviders: Int
    ) -> String {
        let current = currentModelId.map { "Текущая модель: \($0)" } ?? "Текущая модель: по умолчанию"
        let filterLine = filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Фильтр: нет (все провайдеры)"
            : "Фильтр: \(filter) — провайдеров \(totalProviders)"
        let pageLine = totalPages > 0 ? "Страница \(page + 1) / \(totalPages)" : "Страница 0 / 0"
        return """
        \(current)

        Сначала выберите провайдера.
        \(filterLine)
        \(pageLine)

        Выберите провайдера кнопкой, затем модель.

        Подсказка: /model gpt — сначала сузить провайдеров по подстроке в id или названии модели.
        """
    }

    static func buildPickerText(
        currentModelId: String?,
        filter: String,
        providerTitle: String,
        page: Int,
        totalPages: Int,
        totalMatches: Int
    ) -> String {
        let current = currentModelId.map { "Текущая модель: \($0)" } ?? "Текущая модель: по умолчанию"
        let filterLine: String
        if filter.isEmpty {
            filterLine = "Фильтр: нет (все модели провайдера)"
        } else {
            filterLine = "Фильтр: \(filter) — найдено \(totalMatches)"
        }
        let pageLine = totalPages > 0 ? "Страница \(page + 1) / \(totalPages)" : "Страница 0 / 0"
        return """
        \(current)

        Провайдер: \(providerTitle)
        \(filterLine)
        \(pageLine)

        Выберите модель кнопкой или укажите id: /model provider:model-id

        Подсказка: /model gpt — отфильтровать список по подстроке в id или названии.
        """
    }

    static func buildProviderKeyboard(
        providers: [ProviderEntry],
        messageId: Int64,
        page: Int
    ) -> [[[String: String]]] {
        let totalPages = max(1, providers.isEmpty ? 1 : Int(ceil(Double(providers.count) / Double(providerPageSize))))
        let clampedPage = providers.isEmpty ? 0 : min(max(0, page), totalPages - 1)
        let start = clampedPage * providerPageSize
        let slice = Array(providers.dropFirst(start).prefix(providerPageSize))

        var rows: [[[String: String]]] = slice.map { provider in
            [[
                "text": providerButtonLabel(provider),
                "callback_data": callbackProvider(messageId: messageId, providerId: provider.id, page: clampedPage)
            ]]
        }

        if totalPages > 1 {
            let prevPage = max(0, clampedPage - 1)
            let nextPage = min(totalPages - 1, clampedPage + 1)
            rows.append([
                buttonDict(label: "◀︎", data: callbackProvidersPage(messageId: messageId, page: prevPage)),
                buttonDict(label: "▶︎", data: callbackProvidersPage(messageId: messageId, page: nextPage))
            ])
        }

        return rows
    }

    static func buildKeyboard(
        models: [ProviderModelOption],
        messageId: Int64,
        providerPage: Int,
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

        var navRow: [[String: String]] = [
            buttonDict(label: "↩︎ Провайдеры", data: callbackBackToProviders(messageId: messageId, page: providerPage))
        ]
        if totalPages > 1 {
            let prevPage = max(0, clampedPage - 1)
            let nextPage = min(totalPages - 1, clampedPage + 1)
            navRow.append(buttonDict(label: "◀︎", data: callbackPage(messageId: messageId, page: prevPage)))
            navRow.append(buttonDict(label: "▶︎", data: callbackPage(messageId: messageId, page: nextPage)))
        }
        rows.append(navRow)

        return rows
    }

    private static func providerButtonLabel(_ provider: ProviderEntry) -> String {
        let base = "\(provider.title) (\(provider.count))"
        if base.count <= 48 { return base }
        return String(base.prefix(47)) + "…"
    }

    private static func buttonDict(label: String, data: String) -> [String: String] {
        ["text": label, "callback_data": data]
    }

    /// `M|msgId|PP|page`
    static func callbackProvidersPage(messageId: Int64, page: Int) -> String {
        truncateCallback("M|\(messageId)|PP|\(page)")
    }

    /// `M|msgId|B|page`
    static func callbackBackToProviders(messageId: Int64, page: Int) -> String {
        truncateCallback("M|\(messageId)|B|\(page)")
    }

    /// `M|msgId|P|page`
    static func callbackPage(messageId: Int64, page: Int) -> String {
        truncateCallback("M|\(messageId)|P|\(page)")
    }

    /// `M|msgId|S|idx`
    static func callbackSelect(messageId: Int64, globalIndex: Int) -> String {
        truncateCallback("M|\(messageId)|S|\(globalIndex)")
    }

    /// `M|msgId|R|provider`
    static func callbackProvider(messageId: Int64, providerId: String, page: Int) -> String {
        truncateCallback("M|\(messageId)|R|\(page)|\(providerId)")
    }

    private static func truncateCallback(_ s: String) -> String {
        if s.count <= maxCallbackBytes { return s }
        return String(s.prefix(maxCallbackBytes))
    }

    enum ParsedCallback {
        case providersPage(messageId: Int64, page: Int)
        case backToProviders(messageId: Int64, page: Int)
        case provider(messageId: Int64, providerId: String, page: Int)
        case page(messageId: Int64, page: Int)
        case select(messageId: Int64, index: Int)
        case unknown
    }

    static func parseCallback(_ data: String) -> ParsedCallback {
        let parts = data.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, parts[0] == "M", let msgId = Int64(parts[1]) else {
            return .unknown
        }
        switch parts[2] {
        case "PP":
            guard parts.count == 4, let page = Int(parts[3]) else { return .unknown }
            return .providersPage(messageId: msgId, page: page)
        case "B":
            guard parts.count == 4, let page = Int(parts[3]) else { return .unknown }
            return .backToProviders(messageId: msgId, page: page)
        case "P":
            guard parts.count == 4, let page = Int(parts[3]) else { return .unknown }
            return .page(messageId: msgId, page: page)
        case "S":
            guard parts.count == 4, let index = Int(parts[3]) else { return .unknown }
            return .select(messageId: msgId, index: index)
        case "R":
            guard parts.count >= 5, let page = Int(parts[3]) else { return .unknown }
            let providerId = parts.dropFirst(4).joined(separator: "|")
            guard !providerId.isEmpty else { return .unknown }
            return .provider(messageId: msgId, providerId: providerId, page: page)
        default:
            return .unknown
        }
    }
}
