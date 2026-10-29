import AdaEngine

extension View {
    /// Match text controls to the current client theme, including the source editor primitive.
    public func sloppyTextInputStyle(_ colors: AppColors) -> some View {
        textFieldStyle(PlainTextFieldStyle())
            .textEditorColors(TextEditorColors(
                background: colors.surface,
                border: colors.border,
                focusedBorder: colors.borderBold,
                gutter: colors.textMuted,
                gutterRule: colors.border,
                currentLineBackground: colors.surfaceRaised,
                selection: colors.accentCyan.opacity(0.28 as Float)
            ))
    }
}
