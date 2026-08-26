import SloppyClientCore

@MainActor
extension MainViewModel {
    static func preview() -> MainViewModel {
        MainViewModel(
            endpoint: .direct(baseURL: .debugURL),
            settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: .debugURL),
            onOpenSettings: { _ in },
            onOpenWorkspace: {}
        )
    }
}
