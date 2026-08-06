import Foundation
import SloppyClientCore
import SloppyClientUI
import SwiftUI

struct ChatInputDraftAnswer: Equatable {
    var selectedOptionID: String?
    var customAnswer = ""
}

enum ChatInputResponseBuilder {
    enum ValidationError: LocalizedError, Equatable {
        case missingAnswer(String)
        case invalidOption(String)
        case customAnswerNotAllowed(String)

        var errorDescription: String? {
            switch self {
            case .missingAnswer(let question):
                "Answer “\(question)” before submitting."
            case .invalidOption(let question):
                "Choose one of the available answers for “\(question)”."
            case .customAnswerNotAllowed(let question):
                "Choose one of the available answers for “\(question)”."
            }
        }
    }

    static func answers(
        for request: ChatPlanInputRequest,
        drafts: [String: ChatInputDraftAnswer]
    ) throws -> [ChatPlanInputAnswer] {
        try request.questions.map { question in
            let draft = drafts[question.id] ?? ChatInputDraftAnswer()
            let customAnswer = draft.customAnswer.trimmingCharacters(in: .whitespacesAndNewlines)

            if !customAnswer.isEmpty {
                guard question.allowCustomAnswer else {
                    throw ValidationError.customAnswerNotAllowed(question.question)
                }
                return ChatPlanInputAnswer(
                    questionId: question.id,
                    customAnswer: customAnswer
                )
            }

            guard let selectedOptionID = draft.selectedOptionID else {
                throw ValidationError.missingAnswer(question.question)
            }
            guard question.options.contains(where: { $0.id == selectedOptionID }) else {
                throw ValidationError.invalidOption(question.question)
            }
            return ChatPlanInputAnswer(
                questionId: question.id,
                selectedOptionId: selectedOptionID
            )
        }
    }
}

@MainActor
struct ChatInputRequestView: View {
    let request: ChatPlanInputRequest
    let isSubmitting: Bool
    let errorMessage: String?
    let onSubmit: @MainActor ([ChatPlanInputAnswer]) -> Void
    let onCancel: @MainActor () -> Void

    @State private var drafts: [String: ChatInputDraftAnswer] = [:]
    @State private var validationMessage: String?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            header

            ForEach(request.questions) { question in
                questionView(question)
            }

            if let visibleErrorMessage {
                Label(visibleErrorMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: theme.typography.caption))
                    .foregroundStyle(theme.colors.statusBlocked)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceRaised.opacity(0.94 as CGFloat))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.colors.borderBold.opacity(0.72 as CGFloat), lineWidth: theme.borders.thin)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.title ?? "Agent needs your input")
        .accessibilityIdentifier("chat.input-request.\(request.id)")
        .onChange(of: request.id) { _, _ in
            drafts = [:]
            validationMessage = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s) {
            Image(systemName: "questionmark.bubble.fill")
                .foregroundStyle(theme.colors.accentCyan)
            Text(request.title ?? "Agent needs your input")
                .font(.system(size: theme.typography.body, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func questionView(_ question: ChatPlanInputQuestion) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            if let header = question.header?.trimmingCharacters(in: .whitespacesAndNewlines),
               !header.isEmpty {
                Text(header.uppercased())
                    .font(.system(size: theme.typography.micro, weight: .semibold))
                    .foregroundStyle(theme.colors.textMuted)
            }

            Text(question.question)
                .font(.system(size: theme.typography.body, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: theme.spacing.s) {
                ForEach(question.options) { option in
                    optionButton(option, question: question)
                }
            }

            if question.allowCustomAnswer {
                customAnswerField(question)
            }
        }
        .padding(.top, theme.spacing.xs)
    }

    private func optionButton(
        _ option: ChatPlanInputOption,
        question: ChatPlanInputQuestion
    ) -> some View {
        let isSelected = drafts[question.id]?.selectedOptionID == option.id
            && drafts[question.id]?.customAnswer.isEmpty != false

        return Button {
            drafts[question.id] = ChatInputDraftAnswer(selectedOptionID: option.id)
            validationMessage = nil
        } label: {
            HStack(alignment: .top, spacing: theme.spacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? theme.colors.accentCyan : theme.colors.textMuted)

                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(option.label)
                        .font(.system(size: theme.typography.body, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: theme.typography.caption))
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? theme.colors.accentCyan.opacity(0.12 as CGFloat)
                    : theme.colors.surface.opacity(0.7 as CGFloat),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? theme.colors.accentCyan : theme.colors.border,
                        lineWidth: theme.borders.thin
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityLabel(accessibilityLabel(for: option))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("chat.input-request.\(request.id).\(question.id).\(option.id)")
    }

    private func customAnswerField(_ question: ChatPlanInputQuestion) -> some View {
        let text = Binding(
            get: { drafts[question.id]?.customAnswer ?? "" },
            set: { newValue in
                drafts[question.id] = ChatInputDraftAnswer(customAnswer: newValue)
                validationMessage = nil
            }
        )

        return TextField("Or type your own answer", text: text, axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .font(.system(size: theme.typography.body))
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
            .background(theme.colors.surface.opacity(0.74 as CGFloat))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: theme.borders.thin)
            }
            .disabled(isSubmitting)
            .accessibilityLabel("Custom answer for \(question.question)")
            .accessibilityIdentifier("chat.input-request.\(request.id).\(question.id).custom")
    }

    private var actions: some View {
        HStack(spacing: theme.spacing.s) {
            Button("Cancel request", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Button(action: submit) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Send answers", systemImage: "arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.colors.accent)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityIdentifier("chat.input-request.submit")
        }
        .disabled(isSubmitting)
    }

    private var visibleErrorMessage: String? {
        errorMessage ?? validationMessage
    }

    private func submit() {
        do {
            let answers = try ChatInputResponseBuilder.answers(for: request, drafts: drafts)
            validationMessage = nil
            onSubmit(answers)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func accessibilityLabel(for option: ChatPlanInputOption) -> String {
        guard let description = option.description, !description.isEmpty else {
            return option.label
        }
        return "\(option.label). \(description)"
    }
}
