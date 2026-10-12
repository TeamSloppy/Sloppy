import Foundation
import Observation
import SwiftUI
import SloppyClientUI
import SloppyClientCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif


struct ComposerContextUsageView: View {
    let usage: ChatContextUsage?

    @State private var isDetailsPresented = false
    @Environment(\.theme) private var theme

    var body: some View {
        ProgressView(value: usage?.fraction ?? 0, total: 1)
            .progressViewStyle(.circular)
            .controlSize(.small)
            .tint(progressColor)
            .frame(width: 20, height: 20)
            .contentShape(Circle())
            .onHover { isHovering in
                isDetailsPresented = isHovering && usage != nil
            }
            .popover(isPresented: $isDetailsPresented, arrowEdge: .bottom) {
                if let usage {
                    contextDetails(usage)
                }
            }
            .accessibilityLabel("Context usage")
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("chat.composer.context-usage")
    }

    private var progressColor: Color {
        guard let usage else { return theme.colors.statusNeutral }
        if usage.fraction >= 0.9 {
            return theme.colors.statusBlocked
        }
        if usage.fraction >= 0.75 {
            return theme.colors.statusWarning
        }
        return theme.colors.textSecondary
    }

    private var accessibilityValue: String {
        guard let usage else { return "Unavailable" }
        var value = "\(usage.percentage) percent, \(usage.usedTokens) of \(usage.limitTokens) tokens"
        if let jev = usage.semanticDecisionUsage {
            value += ", routing \(jev.requestCount) decisions, \(formattedJEVCost(jev))"
        }
        return value
    }

    private func contextDetails(_ usage: ChatContextUsage) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Text("Context usage")
                .font(.system(size: theme.typography.body, weight: .semibold))
                .foregroundColor(theme.colors.textPrimary)

            Text("\(usage.percentage)%")
                .font(.system(size: theme.typography.title, weight: .semibold, design: .rounded))
                .foregroundColor(progressColor)
                .monospacedDigit()

            Grid(alignment: .leading, horizontalSpacing: theme.spacing.l, verticalSpacing: theme.spacing.xs) {
                GridRow {
                    Text("Used")
                        .foregroundColor(theme.colors.textMuted)
                    Text(usage.usedTokens.formatted(.number.grouping(.automatic)))
                        .foregroundColor(theme.colors.textPrimary)
                        .monospacedDigit()
                }
                GridRow {
                    Text("Limit")
                        .foregroundColor(theme.colors.textMuted)
                    Text(usage.limitTokens.formatted(.number.grouping(.automatic)))
                        .foregroundColor(theme.colors.textPrimary)
                        .monospacedDigit()
                }
            }
            .font(.system(size: theme.typography.caption))

            if let jev = usage.semanticDecisionUsage {
                Divider()

                Text("Routing usage")
                    .font(.system(size: theme.typography.caption, weight: .semibold))
                    .foregroundColor(theme.colors.textSecondary)

                Grid(alignment: .leading, horizontalSpacing: theme.spacing.l, verticalSpacing: theme.spacing.xs) {
                    GridRow {
                        Text("Decisions")
                            .foregroundColor(theme.colors.textMuted)
                        Text(jev.requestCount.formatted(.number.grouping(.automatic)))
                            .foregroundColor(theme.colors.textPrimary)
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Input")
                            .foregroundColor(theme.colors.textMuted)
                        Text("\(jev.inputTokens.formatted(.number.grouping(.automatic))) tokens")
                            .foregroundColor(theme.colors.textPrimary)
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Cost")
                            .foregroundColor(theme.colors.textMuted)
                        Text(formattedJEVCost(jev))
                            .foregroundColor(theme.colors.textPrimary)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: theme.typography.caption))
            }
        }
        .padding(theme.spacing.m)
        .frame(minWidth: 210, alignment: .leading)
    }

    private func formattedJEVCost(_ usage: ChatSemanticDecisionUsage) -> String {
        let prefix = usage.includesEstimatedCost ? "~" : ""
        let amount = usage.totalCostUSD
        if amount > 0, amount < 0.01 {
            return prefix + String(format: "$%.4f", amount)
        }
        return prefix + String(format: "$%.2f", amount)
    }
}

struct ComposerOptionsMenuView: View {
    let selectedModelId: String
    let models: [ChatModelOption]
    let selectedEffort: ChatReasoningEffort
    let supportsReasoningEffort: Bool
    let selectedAgent: APIAgentRecord?
    let agents: [APIAgentRecord]
    let onSelectModel: (ChatModelOption) -> Void
    let onSelectEffort: (ChatReasoningEffort) -> Void
    let onSelectAgent: (APIAgentRecord) -> Void
    let onRefreshModels: @MainActor () async -> Void
    let onEditModels: @MainActor () -> Void

    @State private var isPresented = false
    @State private var isModelPickerPresented = false
    @State private var searchText = ""
    @State private var isRefreshing = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            isModelPickerPresented = !supportsReasoningEffort
            isPresented.toggle()
        } label: {
            HStack(spacing: theme.spacing.xs) {
                Text(selectedModelTitle)
                    .font(.system(size: theme.typography.body, weight: .medium))
                    .foregroundColor(theme.colors.textPrimary)
                    .lineLimit(1)

                if supportsReasoningEffort {
                    Text("· \(selectedEffort.title)")
                        .font(.system(size: theme.typography.caption, weight: .medium))
                        .foregroundColor(theme.colors.textSecondary)
                        .lineLimit(1)
                }

                Icons.symbol(.expandMore, size: 14)
                    .foregroundColor(theme.colors.textSecondary)
            }
            .padding(.horizontal, theme.spacing.s)
            .frame(height: Constants.modelPickerRowHeight)
        }
        .buttonStyle(.plain)
        .help("Model · \(selectedModelId)")
        .accessibilityLabel("Model \(selectedModelTitle), reasoning \(selectedEffort.title)")
        .accessibilityIdentifier("chat.composer.model-picker")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            pickerContent
                .presentationCompactAdaptation(.popover)
        }
    }

    private var selectedModelTitle: String {
        guard let selected = models.first(where: { $0.id == selectedModelId }) else {
            return selectedModelId.isEmpty ? "Model" : selectedModelId
        }
        return selected.title
    }

    private var filteredModels: [ChatModelOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return models
        }
        return models.filter {
            $0.title.localizedStandardContains(query) || $0.id.localizedStandardContains(query)
        }
    }

    private var groupedModels: [ComposerModelGroup] {
        var groups: [ComposerModelGroup] = []
        for model in filteredModels {
            let provider = providerTitle(for: model.id)
            if let index = groups.firstIndex(where: { $0.title == provider }) {
                groups[index].models.append(model)
            } else {
                groups.append(ComposerModelGroup(title: provider, models: [model]))
            }
        }
        return groups
    }

    private var pickerContent: some View {
        Group {
            if isModelPickerPresented {
                modelPickerContent
            } else {
                effortPickerContent
            }
        }
        .frame(width: isModelPickerPresented ? 440 : 360)
    }

    private var effortPickerContent: some View {
        VStack(spacing: 12) {
            ZStack {
                Button {
                    isModelPickerPresented = true
                } label: {
                    VStack(spacing: theme.spacing.xs) {
                        HStack(spacing: theme.spacing.xs) {
                            Text(selectedEffort.title)
                                .font(.system(size: theme.typography.heading, weight: .medium))
                                .foregroundColor(
                                    ComposerEffortPalette.color(for: selectedEffort, theme: theme)
                                )
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(theme.colors.textMuted)
                        }

                        Text(selectedModelTitle)
                            .font(.system(size: theme.typography.body))
                            .foregroundColor(theme.colors.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(models.isEmpty)
                .accessibilityLabel("Select model, current model \(selectedModelTitle)")

                HStack {
                    Spacer(minLength: 0)

                    Button {
                        onSelectEffort(.default)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(theme.colors.textMuted)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedEffort == .default)
                    .help("Reset effort to Default")
                    .accessibilityLabel("Reset effort to Default")
                }
            }

            ComposerEffortScale(
                selection: selectedEffort,
                onSelect: onSelectEffort
            )
            .disabled(!supportsReasoningEffort)

            if !agents.isEmpty {
                Divider()
                agentPicker
            }
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, 14)
        .accessibilityIdentifier("chat.composer.effort-picker")
    }

    private var modelPickerContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s) {
                Button {
                    if supportsReasoningEffort {
                        isModelPickerPresented = false
                    } else {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: supportsReasoningEffort ? "chevron.left" : "xmark")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.colors.textSecondary)

                Text("Select model")
                    .font(.system(size: theme.typography.heading + 2, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(height: 50)

            HStack(spacing: theme.spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.colors.textMuted)
                TextField("Search models", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(height: 46)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.xs) {
                    if groupedModels.isEmpty {
                        Text(models.isEmpty ? "No models available" : "No matching models")
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(theme.colors.textMuted)
                            .frame(maxWidth: .infinity, minHeight: 90)
                    } else {
                        ForEach(groupedModels) { group in
                            Text(group.title)
                                .font(.system(size: theme.typography.caption, weight: .semibold))
                                .foregroundColor(theme.colors.textMuted)
                                .padding(.horizontal, theme.spacing.m)
                                .padding(.top, theme.spacing.s)

                            ForEach(group.models) { model in
                                modelRow(model)
                            }
                        }
                    }
                }
                .padding(.vertical, theme.spacing.s)
            }
            .frame(minHeight: 160, maxHeight: 380)

            Divider()
            modelPickerActions
        }
        .onAppear {
            searchText = ""
            isSearchFocused = true
        }
        .accessibilityIdentifier("chat.composer.model-list")
    }

    private func modelRow(_ model: ChatModelOption) -> some View {
        Button {
            onSelectModel(model)
            if model.supportsReasoningEffort {
                isModelPickerPresented = false
            } else {
                isPresented = false
            }
        } label: {
            HStack(spacing: theme.spacing.s) {
                Text(model.title)
                    .foregroundColor(theme.colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: theme.spacing.s)
                if selectedModelId == model.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(theme.colors.textPrimary)
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                selectedModelId == model.id
                    ? theme.colors.accent.opacity(0.14 as CGFloat)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    private var modelPickerActions: some View {
        HStack(spacing: theme.spacing.s) {
            Button {
                Task {
                    isRefreshing = true
                    await onRefreshModels()
                    isRefreshing = false
                }
            } label: {
                Label(
                    isRefreshing ? "Refreshing…" : "Refresh",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)

            Spacer(minLength: 0)

            Button {
                isPresented = false
                onEditModels()
            } label: {
                Label("Edit Models…", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: theme.typography.caption, weight: .medium))
        .foregroundColor(theme.colors.textSecondary)
        .padding(.horizontal, theme.spacing.m)
        .frame(height: 46)
    }

    private var agentPicker: some View {
        Menu {
            ForEach(agents) { agent in
                Button {
                    onSelectAgent(agent)
                } label: {
                    ComposerMenuItem(
                        title: agent.displayName,
                        isSelected: selectedAgent?.id == agent.id
                    )
                }
            }
        } label: {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "person")
                    .frame(width: 20)
                Text(selectedAgent?.displayName ?? "Agent")
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(theme.colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func providerTitle(for modelID: String) -> String {
        let rawProvider = modelID.split(whereSeparator: { $0 == ":" || $0 == "/" }).first.map(String.init) ?? "Models"
        return rawProvider
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }
}

struct ComposerEffortScale: View {
    let selection: ChatReasoningEffort
    let onSelect: (ChatReasoningEffort) -> Void

    @Environment(\.theme) private var theme

    private let height: CGFloat = 36
    private let thumbSize: CGFloat = 24
    private let dotSize: CGFloat = 6
    private let fillTrailingSpacing: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let efforts = ChatReasoningEffort.allCases
            let segmentWidth = proxy.size.width / CGFloat(efforts.count)
            let selectedIndex = efforts.firstIndex(of: selection) ?? 0
            let thumbCenter = segmentWidth * (CGFloat(selectedIndex) + 0.5)
            let isMaximumEffort = selectedIndex == efforts.count - 1
            let fillWidth = isMaximumEffort
                ? proxy.size.width
                : min(
                    proxy.size.width,
                    thumbCenter + thumbSize / 2 + fillTrailingSpacing
                )
            let levelColor = ComposerEffortPalette.color(for: selection, theme: theme)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.colors.surfaceRaised)

                Capsule()
                    .fill(levelColor)
                    .frame(width: fillWidth)

                HStack(spacing: 0) {
                    ForEach(Array(efforts.enumerated()), id: \.element.id) { index, effort in
                        ZStack {
                            Circle()
                                .fill(index < selectedIndex ? Color.white.opacity(0.36) : theme.colors.textMuted)
                                .frame(width: dotSize, height: dotSize)

                            if effort == selection {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: thumbSize, height: thumbSize)
                                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                            }
                        }
                        .frame(width: segmentWidth, height: height)
                        .accessibilityHidden(true)
                    }
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(theme.colors.borderBold, lineWidth: theme.borders.thin)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        selectEffort(at: value.location.x, width: proxy.size.width)
                    }
                    .onEnded { value in
                        selectEffort(at: value.location.x, width: proxy.size.width)
                    }
            )
            .animation(.easeOut(duration: 0.12), value: selection)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reasoning effort")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("chat.composer.effort-slider")
        .accessibilityAdjustableAction(adjustEffort)
    }

    private func selectEffort(at location: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let efforts = ChatReasoningEffort.allCases
        let normalizedLocation = min(max(location / width, 0), 0.999_999)
        let index = min(Int(normalizedLocation * CGFloat(efforts.count)), efforts.count - 1)
        onSelect(efforts[index])
    }

    private func adjustEffort(_ direction: AccessibilityAdjustmentDirection) {
        let efforts = ChatReasoningEffort.allCases
        let selectedIndex = efforts.firstIndex(of: selection) ?? 0
        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(selectedIndex + 1, efforts.count - 1)
        case .decrement:
            nextIndex = max(selectedIndex - 1, 0)
        @unknown default:
            return
        }
        onSelect(efforts[nextIndex])
    }
}

enum ComposerEffortPalette {
    static func color(for effort: ChatReasoningEffort, theme: Theme) -> Color {
        switch effort {
        case .default:
            theme.colors.statusNeutral
        case .low:
            theme.colors.accentCyan
        case .medium:
            theme.colors.accent
        case .high:
            theme.colors.statusWarning
        }
    }
}

struct ComposerModelGroup: Identifiable {
    let title: String
    var models: [ChatModelOption]

    var id: String { title }
}

extension ChatReasoningEffort {
    var compactTitle: String {
        switch self {
        case .default: "Auto"
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        }
    }
}

struct ComposerMenuChip: View {
    let title: String
    var isEnabled: Bool = true

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            Text(title)
                .font(.system(size: theme.typography.body, weight: .semibold))
                .foregroundColor(theme.colors.textPrimary.opacity(isEnabled ? 1 : 0.48))
                .lineLimit(1)

            Icons.symbol(.expandMore, size: 14)
                .foregroundColor(theme.colors.textSecondary.opacity(isEnabled ? 1 : 0.48))
        }
    }
}
