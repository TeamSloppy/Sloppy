// Swift 6.3 on Windows crashes during optimized IR generation when the standard
// continuation functions inline into actor-isolated callers. These small thunks
// preserve actor isolation and the runtime's checked-continuation diagnostics.
#if os(Windows)
@inline(never)
@_optimize(none)
#endif
func withPlatformCheckedContinuation<T>(
    isolation: isolated (any Actor)? = #isolation,
    function: String = #function,
    _ body: (CheckedContinuation<T, Never>) -> Void
) async -> sending T {
    await withCheckedContinuation(isolation: isolation, function: function, body)
}

#if os(Windows)
@inline(never)
@_optimize(none)
#endif
func withPlatformCheckedThrowingContinuation<T>(
    isolation: isolated (any Actor)? = #isolation,
    function: String = #function,
    _ body: (CheckedContinuation<T, any Error>) -> Void
) async throws -> sending T {
    try await withCheckedThrowingContinuation(isolation: isolation, function: function, body)
}
