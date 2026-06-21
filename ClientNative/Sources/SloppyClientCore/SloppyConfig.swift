import Foundation

public struct SloppyConfig: Codable, Sendable {
    public struct Listen: Codable, Sendable {
        public var host: String
        public var port: Int

        public init(host: String = "0.0.0.0", port: Int = 25101) {
            self.host = host
            self.port = port
        }
    }

    public struct Workspace: Codable, Sendable {
        public var name: String
        public var basePath: String

        public init(name: String = ".sloppy", basePath: String = ".") {
            self.name = name
            self.basePath = basePath
        }
    }

    public struct Auth: Codable, Sendable {
        public var token: String

        public init(token: String = "dev-token") {
            self.token = token
        }
    }

    public struct Onboarding: Codable, Sendable {
        public var completed: Bool

        public init(completed: Bool = false) {
            self.completed = completed
        }
    }

    public struct ModelConfig: Codable, Sendable {
        public var title: String
        public var apiKey: String
        public var apiUrl: String
        public var model: String
        public var disabled: Bool
        public var providerCatalogId: String?

        enum CodingKeys: String, CodingKey {
            case title
            case apiKey
            case apiUrl
            case model
            case disabled
            case providerCatalogId
        }

        public init(
            title: String,
            apiKey: String,
            apiUrl: String,
            model: String,
            disabled: Bool = false,
            providerCatalogId: String? = nil
        ) {
            self.title = title
            self.apiKey = apiKey
            self.apiUrl = apiUrl
            self.model = model
            self.disabled = disabled
            self.providerCatalogId = providerCatalogId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            apiKey = try container.decode(String.self, forKey: .apiKey)
            apiUrl = try container.decode(String.self, forKey: .apiUrl)
            model = try container.decode(String.self, forKey: .model)
            disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
            providerCatalogId = try container.decodeIfPresent(String.self, forKey: .providerCatalogId)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(apiKey, forKey: .apiKey)
            try container.encode(apiUrl, forKey: .apiUrl)
            try container.encode(model, forKey: .model)
            try container.encode(disabled, forKey: .disabled)
            try container.encodeIfPresent(providerCatalogId, forKey: .providerCatalogId)
        }
    }

    public struct PluginConfig: Codable, Sendable {
        public var title: String
        public var apiKey: String
        public var apiUrl: String
        public var plugin: String

        public init(title: String, apiKey: String, apiUrl: String, plugin: String) {
            self.title = title
            self.apiKey = apiKey
            self.apiUrl = apiUrl
            self.plugin = plugin
        }
    }

    public struct Memory: Codable, Sendable {
        public struct Retrieval: Codable, Sendable {
            public var topK: Int
            public var semanticWeight: Double
            public var keywordWeight: Double
            public var graphWeight: Double

            public init(topK: Int = 8, semanticWeight: Double = 0.55, keywordWeight: Double = 0.35, graphWeight: Double = 0.10) {
                self.topK = topK
                self.semanticWeight = semanticWeight
                self.keywordWeight = keywordWeight
                self.graphWeight = graphWeight
            }
        }

        public struct Retention: Codable, Sendable {
            public var episodicDays: Int
            public var todoCompletedDays: Int
            public var bulletinDays: Int

            public init(episodicDays: Int = 90, todoCompletedDays: Int = 30, bulletinDays: Int = 180) {
                self.episodicDays = episodicDays
                self.todoCompletedDays = todoCompletedDays
                self.bulletinDays = bulletinDays
            }
        }

        public var backend: String
        public var retrieval: Retrieval
        public var retention: Retention

        public init(backend: String = "sqlite-local-vectors", retrieval: Retrieval = Retrieval(), retention: Retention = Retention()) {
            self.backend = backend
            self.retrieval = retrieval
            self.retention = retention
        }

        private enum CodingKeys: String, CodingKey {
            case backend, retrieval, retention
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            backend = try container.decode(String.self, forKey: .backend)
            retrieval = try container.decodeIfPresent(Retrieval.self, forKey: .retrieval) ?? Retrieval()
            retention = try container.decodeIfPresent(Retention.self, forKey: .retention) ?? Retention()
        }
    }

    public struct ChannelConfig: Codable, Sendable {
        public struct Telegram: Codable, Sendable {
            public var botToken: String

            public init(botToken: String = "") {
                self.botToken = botToken
            }
        }

        public struct Discord: Codable, Sendable {
            public var botToken: String
            public var guildId: String

            public init(botToken: String = "", guildId: String = "") {
                self.botToken = botToken
                self.guildId = guildId
            }
        }

        public var telegram: Telegram?
        public var discord: Discord?

        public init(telegram: Telegram? = nil, discord: Discord? = nil) {
            self.telegram = telegram
            self.discord = discord
        }
    }

    public struct SearchTools: Codable, Sendable {
        public struct Provider: Codable, Sendable {
            public var apiKey: String

            public init(apiKey: String = "") {
                self.apiKey = apiKey
            }
        }

        public struct Providers: Codable, Sendable {
            public var brave: Provider
            public var perplexity: Provider

            public init(brave: Provider = Provider(), perplexity: Provider = Provider()) {
                self.brave = brave
                self.perplexity = perplexity
            }
        }

        public var activeProvider: String
        public var providers: Providers

        public init(activeProvider: String = "perplexity", providers: Providers = Providers()) {
            self.activeProvider = activeProvider
            self.providers = providers
        }
    }

    public struct Proxy: Codable, Sendable {
        public var enabled: Bool
        public var type: String
        public var host: String
        public var port: Int
        public var username: String
        public var password: String

        public init(enabled: Bool = false, type: String = "socks5", host: String = "", port: Int = 1080, username: String = "", password: String = "") {
            self.enabled = enabled
            self.type = type
            self.host = host
            self.port = port
            self.username = username
            self.password = password
        }

        private enum CodingKeys: String, CodingKey {
            case enabled, type, host, port, username, password
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? "socks5"
            host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
            port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 1080
            username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
            password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        }
    }

    public struct Visor: Codable, Sendable {
        public struct Scheduler: Codable, Sendable {
            public var enabled: Bool
            public var intervalSeconds: Int
            public var jitterSeconds: Int

            public init(enabled: Bool = true, intervalSeconds: Int = 300, jitterSeconds: Int = 60) {
                self.enabled = enabled
                self.intervalSeconds = intervalSeconds
                self.jitterSeconds = jitterSeconds
            }
        }

        public var scheduler: Scheduler
        public var tickIntervalSeconds: Int
        public var workerTimeoutSeconds: Int
        public var branchTimeoutSeconds: Int
        public var idleThresholdSeconds: Int
        public var mergeEnabled: Bool

        public init(
            scheduler: Scheduler = Scheduler(),
            tickIntervalSeconds: Int = 30,
            workerTimeoutSeconds: Int = 600,
            branchTimeoutSeconds: Int = 60,
            idleThresholdSeconds: Int = 1800,
            mergeEnabled: Bool = false
        ) {
            self.scheduler = scheduler
            self.tickIntervalSeconds = tickIntervalSeconds
            self.workerTimeoutSeconds = workerTimeoutSeconds
            self.branchTimeoutSeconds = branchTimeoutSeconds
            self.idleThresholdSeconds = idleThresholdSeconds
            self.mergeEnabled = mergeEnabled
        }

        private enum CodingKeys: String, CodingKey {
            case scheduler, tickIntervalSeconds, workerTimeoutSeconds, branchTimeoutSeconds, idleThresholdSeconds, mergeEnabled
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            scheduler = try container.decodeIfPresent(Scheduler.self, forKey: .scheduler) ?? Scheduler()
            tickIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .tickIntervalSeconds) ?? 30
            workerTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .workerTimeoutSeconds) ?? 600
            branchTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .branchTimeoutSeconds) ?? 60
            idleThresholdSeconds = try container.decodeIfPresent(Int.self, forKey: .idleThresholdSeconds) ?? 1800
            mergeEnabled = try container.decodeIfPresent(Bool.self, forKey: .mergeEnabled) ?? false
        }
    }

    public struct GitSync: Codable, Sendable {
        public struct Schedule: Codable, Sendable {
            public var frequency: String
            public var time: String

            public init(frequency: String = "daily", time: String = "18:00") {
                self.frequency = frequency
                self.time = time
            }
        }

        public var enabled: Bool
        public var authToken: String
        public var repository: String
        public var branch: String
        public var schedule: Schedule
        public var conflictStrategy: String

        public init(enabled: Bool = false, authToken: String = "", repository: String = "", branch: String = "main", schedule: Schedule = Schedule(), conflictStrategy: String = "remote_wins") {
            self.enabled = enabled
            self.authToken = authToken
            self.repository = repository
            self.branch = branch
            self.schedule = schedule
            self.conflictStrategy = conflictStrategy
        }

        private enum CodingKeys: String, CodingKey {
            case enabled, authToken, repository, branch, schedule, conflictStrategy
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            authToken = try container.decodeIfPresent(String.self, forKey: .authToken) ?? ""
            repository = try container.decodeIfPresent(String.self, forKey: .repository) ?? ""
            branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? "main"
            schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule) ?? Schedule()
            conflictStrategy = try container.decodeIfPresent(String.self, forKey: .conflictStrategy) ?? "remote_wins"
        }
    }

    public struct ACP: Codable, Sendable {
        public var enabled: Bool
        public var targets: [ACPTarget]

        public init(enabled: Bool = false, targets: [ACPTarget] = []) {
            self.enabled = enabled
            self.targets = targets
        }

        private enum CodingKeys: String, CodingKey {
            case enabled, targets
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            targets = try container.decodeIfPresent([ACPTarget].self, forKey: .targets) ?? []
        }
    }

    public struct ACPTarget: Codable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var command: String
        public var enabled: Bool

        public init(id: String, title: String, command: String, enabled: Bool = true) {
            self.id = id
            self.title = title
            self.command = command
            self.enabled = enabled
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, command, enabled
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? id
            command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    public var listen: Listen
    public var workspace: Workspace
    public var auth: Auth
    public var onboarding: Onboarding
    public var models: [ModelConfig]
    public var memory: Memory
    public var nodes: [String]
    public var plugins: [PluginConfig]
    public var channels: ChannelConfig
    public var searchTools: SearchTools
    public var proxy: Proxy
    public var visor: Visor
    public var gitSync: GitSync
    public var acp: ACP
    public var sqlitePath: String

    public init(
        listen: Listen = Listen(),
        workspace: Workspace = Workspace(),
        auth: Auth = Auth(),
        onboarding: Onboarding = Onboarding(),
        models: [ModelConfig] = [],
        memory: Memory = Memory(),
        nodes: [String] = ["local"],
        plugins: [PluginConfig] = [],
        channels: ChannelConfig = ChannelConfig(),
        searchTools: SearchTools = SearchTools(),
        proxy: Proxy = Proxy(),
        visor: Visor = Visor(),
        gitSync: GitSync = GitSync(),
        acp: ACP = ACP(),
        sqlitePath: String = "memory/core.sqlite"
    ) {
        self.listen = listen
        self.workspace = workspace
        self.auth = auth
        self.onboarding = onboarding
        self.models = models
        self.memory = memory
        self.nodes = nodes
        self.plugins = plugins
        self.channels = channels
        self.searchTools = searchTools
        self.proxy = proxy
        self.visor = visor
        self.gitSync = gitSync
        self.acp = acp
        self.sqlitePath = sqlitePath
    }

    private enum CodingKeys: String, CodingKey {
        case listen, workspace, auth, onboarding, models, memory, nodes, plugins, channels, searchTools, proxy, visor, gitSync, acp, sqlitePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        listen = try container.decode(Listen.self, forKey: .listen)
        workspace = try container.decodeIfPresent(Workspace.self, forKey: .workspace) ?? Workspace()
        auth = try container.decode(Auth.self, forKey: .auth)
        onboarding = try container.decodeIfPresent(Onboarding.self, forKey: .onboarding) ?? Onboarding()
        models = try container.decodeIfPresent([ModelConfig].self, forKey: .models) ?? []
        memory = try container.decode(Memory.self, forKey: .memory)
        nodes = try container.decodeIfPresent([String].self, forKey: .nodes) ?? []
        plugins = try container.decodeIfPresent([PluginConfig].self, forKey: .plugins) ?? []
        channels = try container.decodeIfPresent(ChannelConfig.self, forKey: .channels) ?? ChannelConfig()
        searchTools = try container.decodeIfPresent(SearchTools.self, forKey: .searchTools) ?? SearchTools()
        proxy = try container.decodeIfPresent(Proxy.self, forKey: .proxy) ?? Proxy()
        visor = try container.decodeIfPresent(Visor.self, forKey: .visor) ?? Visor()
        gitSync = try container.decodeIfPresent(GitSync.self, forKey: .gitSync) ?? GitSync()
        acp = try container.decodeIfPresent(ACP.self, forKey: .acp) ?? ACP()
        sqlitePath = try container.decodeIfPresent(String.self, forKey: .sqlitePath) ?? "memory/core.sqlite"
    }
}
