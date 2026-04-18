import AnyLanguageModel

/// Anthropic Messages API ``LanguageModel`` from AnyLanguageModel.
///
/// With the default session from ``AnthropicModelProvider`` (no custom `URLSession`), outgoing requests are rewritten for OAuth / Claude Code–compatible headers via ``OAuthAnthropicURLSession``.
public typealias OAuthAnthropicLanguageModel = AnthropicLanguageModel
