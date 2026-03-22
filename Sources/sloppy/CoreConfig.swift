import Foundation

public struct CoreConfig: Codable, Sendable {
    public static let defaultConfigFileName = "sloppy.json"
    public static var defaultConfigPath: String {
        defaultConfigPath(currentDirectory: FileManager.default.currentDirectoryPath)
    }
    public static let defaultWorkspaceName = ".sloppy"
    public static let defaultWorkspaceBasePath = "."
    public static let defaultSQLiteFileName = "memory/core.sqlite"

    public struct ModelConfig: Codable, Sendable, Equatable {
        public var title: String
        public var apiKey: String
        public var apiUrl: String
        public var model: String

        public init(title: String, apiKey: String, apiUrl: String, model: String) {
            self.title = title
            self.apiKey = apiKey
            self.apiUrl = apiUrl
            self.model = model
        }
    }

    public struct PluginConfig: Codable, Sendable, Equatable {
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

    public struct Listen: Codable, Sendable {
        public var host: String
        public var port: Int

        public init(host: String, port: Int) {
            self.host = host
            self.port = port
        }
    }

    public struct Workspace: Codable, Sendable {
        public var name: String
        public var basePath: String

        public init(
            name: String = CoreConfig.defaultWorkspaceName,
            basePath: String = CoreConfig.defaultWorkspaceBasePath
        ) {
            self.name = name
            self.basePath = basePath
        }
    }

    public struct Memory: Codable, Sendable, Equatable {
        public struct Provider: Codable, Sendable, Equatable {
            public enum Mode: String, Codable, Sendable, Equatable {
                case local
                case http
                case mcp

                public init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    let rawValue = try container.decode(String.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()

                    switch rawValue {
                    case "local", "builtin", "embedded":
                        self = .local
                    case "http", "remote", "remote_http", "remote-http":
                        self = .http
                    case "mcp", "remote_mcp", "remote-mcp":
                        self = .mcp
                    default:
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "Unsupported memory provider mode: \(rawValue)"
                        )
                    }
                }

                public func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    try container.encode(rawValue)
                }
            }

            public var mode: Mode
            public var endpoint: String?
            public var mcpServer: String?
            public var timeoutMs: Int
            public var apiKeyEnv: String?

            public init(
                mode: Mode = .local,
                endpoint: String? = nil,
                mcpServer: String? = nil,
                timeoutMs: Int = 2_500,
                apiKeyEnv: String? = nil
            ) {
                self.mode = mode
                self.endpoint = endpoint
                self.mcpServer = mcpServer
                self.timeoutMs = timeoutMs
                self.apiKeyEnv = apiKeyEnv
            }
        }

        public struct Retrieval: Codable, Sendable, Equatable {
            public var topK: Int
            public var semanticWeight: Double
            public var keywordWeight: Double
            public var graphWeight: Double

            public init(
                topK: Int = 8,
                semanticWeight: Double = 0.55,
                keywordWeight: Double = 0.35,
                graphWeight: Double = 0.10
            ) {
                self.topK = topK
                self.semanticWeight = semanticWeight
                self.keywordWeight = keywordWeight
                self.graphWeight = graphWeight
            }
        }

        public struct Retention: Codable, Sendable, Equatable {
            public var episodicDays: Int
            public var todoCompletedDays: Int
            public var bulletinDays: Int

            public init(
                episodicDays: Int = 90,
                todoCompletedDays: Int = 30,
                bulletinDays: Int = 180
            ) {
                self.episodicDays = episodicDays
                self.todoCompletedDays = todoCompletedDays
                self.bulletinDays = bulletinDays
            }
        }

        public struct Embedding: Codable, Sendable, Equatable {
            /// Whether local embedding is enabled. When false, EmbeddingService is not created.
            public var enabled: Bool
            /// Model identifier for the embeddings endpoint (e.g. "text-embedding-3-small").
            public var model: String
            /// Output vector dimensionality.
            public var dimensions: Int
            /// Full URL to the embeddings endpoint. Nil = derive from configured model providers.
            public var endpoint: String?
            /// Name of the environment variable holding the API key. Nil = fall back to OPENAI_API_KEY.
            public var apiKeyEnv: String?

            public init(
                enabled: Bool = false,
                model: String = "text-embedding-3-small",
                dimensions: Int = 1536,
                endpoint: String? = nil,
                apiKeyEnv: String? = nil
            ) {
                self.enabled = enabled
                self.model = model
                self.dimensions = dimensions
                self.endpoint = endpoint
                self.apiKeyEnv = apiKeyEnv
            }
        }

        public var backend: String
        public var provider: Provider
        public var retrieval: Retrieval
        public var retention: Retention
        public var embedding: Embedding

        public init(
            backend: String,
            provider: Provider = Provider(),
            retrieval: Retrieval = Retrieval(),
            retention: Retention = Retention(),
            embedding: Embedding = Embedding()
        ) {
            self.backend = backend
            self.provider = provider
            self.retrieval = retrieval
            self.retention = retention
            self.embedding = embedding
        }

        private enum CodingKeys: String, CodingKey {
            case backend
            case provider
            case retrieval
            case retention
            case embedding
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            backend = try container.decode(String.self, forKey: .backend)
            provider = try container.decodeIfPresent(Provider.self, forKey: .provider) ?? Provider()
            retrieval = try container.decodeIfPresent(Retrieval.self, forKey: .retrieval) ?? Retrieval()
            retention = try container.decodeIfPresent(Retention.self, forKey: .retention) ?? Retention()
            embedding = try container.decodeIfPresent(Embedding.self, forKey: .embedding) ?? Embedding()
        }
    }

    public struct Auth: Codable, Sendable {
        public var token: String

        public init(token: String) {
            self.token = token
        }
    }

    public struct Onboarding: Codable, Sendable, Equatable {
        public var completed: Bool

        public init(completed: Bool = false) {
            self.completed = completed
        }
    }

    public struct GitSync: Codable, Sendable, Equatable {
        public struct Schedule: Codable, Sendable, Equatable {
            public enum Frequency: String, Codable, Sendable, Equatable {
                case manual
                case daily
                case weekdays
            }

            public var frequency: Frequency
            public var time: String

            public init(
                frequency: Frequency = .daily,
                time: String = "18:00"
            ) {
                self.frequency = frequency
                self.time = time
            }
        }

        public enum ConflictStrategy: String, Codable, Sendable, Equatable {
            case remoteWins = "remote_wins"
            case localWins = "local_wins"
            case manual
        }

        public var enabled: Bool
        public var authToken: String
        public var repository: String
        public var branch: String
        public var schedule: Schedule
        public var conflictStrategy: ConflictStrategy

        public init(
            enabled: Bool = false,
            authToken: String = "",
            repository: String = "",
            branch: String = "main",
            schedule: Schedule = Schedule(),
            conflictStrategy: ConflictStrategy = .remoteWins
        ) {
            self.enabled = enabled
            self.authToken = authToken
            self.repository = repository
            self.branch = branch
            self.schedule = schedule
            self.conflictStrategy = conflictStrategy
        }

        private enum CodingKeys: String, CodingKey {
            case enabled
            case authToken
            case repository
            case branch
            case schedule
            case conflictStrategy
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            authToken = try container.decodeIfPresent(String.self, forKey: .authToken) ?? ""
            repository = try container.decodeIfPresent(String.self, forKey: .repository) ?? ""
            branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? "main"
            schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule) ?? Schedule()
            conflictStrategy = try container.decodeIfPresent(ConflictStrategy.self, forKey: .conflictStrategy) ?? .remoteWins
        }
    }

    public struct Proxy: Codable, Sendable, Equatable {
        public enum ProxyType: String, Codable, Sendable, Equatable {
            case socks5
            case http
            case https
        }

        public var enabled: Bool
        public var type: ProxyType
        public var host: String
        public var port: Int
        public var username: String
        public var password: String

        public init(
            enabled: Bool = false,
            type: ProxyType = .socks5,
            host: String = "",
            port: Int = 1080,
            username: String = "",
            password: String = ""
        ) {
            self.enabled = enabled
            self.type = type
            self.host = host
            self.port = port
            self.username = username
            self.password = password
        }

        private enum CodingKeys: String, CodingKey {
            case enabled
            case type
            case host
            case port
            case username
            case password
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            type = try container.decodeIfPresent(ProxyType.self, forKey: .type) ?? .socks5
            host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
            port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 1080
            username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
            password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        }
    }

    public struct SearchTools: Codable, Sendable, Equatable {
        public enum ProviderID: String, Codable, Sendable, Equatable {
            case brave
            case perplexity
        }

        public struct Provider: Codable, Sendable, Equatable {
            public var apiKey: String

            public init(apiKey: String = "") {
                self.apiKey = apiKey
            }
        }

        public struct Providers: Codable, Sendable, Equatable {
            public var brave: Provider
            public var perplexity: Provider

            public init(
                brave: Provider = Provider(),
                perplexity: Provider = Provider()
            ) {
                self.brave = brave
                self.perplexity = perplexity
            }

            private enum CodingKeys: String, CodingKey {
                case brave
                case perplexity
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                brave = try container.decodeIfPresent(Provider.self, forKey: .brave) ?? Provider()
                perplexity = try container.decodeIfPresent(Provider.self, forKey: .perplexity) ?? Provider()
            }
        }

        public var activeProvider: ProviderID
        public var providers: Providers

        public init(
            activeProvider: ProviderID = .perplexity,
            providers: Providers = Providers()
        ) {
            self.activeProvider = activeProvider
            self.providers = providers
        }

        private enum CodingKeys: String, CodingKey {
            case activeProvider
            case providers
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeProvider = try container.decodeIfPresent(ProviderID.self, forKey: .activeProvider) ?? .perplexity
            providers = try container.decodeIfPresent(Providers.self, forKey: .providers) ?? Providers()
        }
    }

    public struct ChannelConfig: Codable, Sendable, Equatable {
        public struct Discord: Codable, Sendable, Equatable {
            /// Discord bot token.
            public var botToken: String
            /// Maps Sloppy channelId -> Discord channel ID.
            public var channelDiscordChannelMap: [String: String]
            /// When non-empty, only these guild IDs are allowed.
            public var allowedGuildIds: [String]
            /// When non-empty, only these channel IDs are allowed.
            public var allowedChannelIds: [String]
            /// When non-empty, only these Discord user IDs are allowed.
            public var allowedUserIds: [String]

            public init(
                botToken: String,
                channelDiscordChannelMap: [String: String] = [:],
                allowedGuildIds: [String] = [],
                allowedChannelIds: [String] = [],
                allowedUserIds: [String] = []
            ) {
                self.botToken = botToken
                self.channelDiscordChannelMap = channelDiscordChannelMap
                self.allowedGuildIds = allowedGuildIds
                self.allowedChannelIds = allowedChannelIds
                self.allowedUserIds = allowedUserIds
            }
        }

        public struct Telegram: Codable, Sendable, Equatable {
            /// Telegram Bot API token.
            public var botToken: String
            /// Maps Sloppy channelId → Telegram chat_id.
            public var channelChatMap: [String: Int64]
            /// When non-empty, only these Telegram user IDs are allowed.
            public var allowedUserIds: [Int64]
            /// When non-empty, only these Telegram chat IDs are allowed.
            public var allowedChatIds: [Int64]

            public init(
                botToken: String,
                channelChatMap: [String: Int64] = [:],
                allowedUserIds: [Int64] = [],
                allowedChatIds: [Int64] = []
            ) {
                self.botToken = botToken
                self.channelChatMap = channelChatMap
                self.allowedUserIds = allowedUserIds
                self.allowedChatIds = allowedChatIds
            }
        }

        public var discord: Discord?
        public var telegram: Telegram?

        public init(
            discord: Discord? = nil,
            telegram: Telegram? = nil
        ) {
            self.discord = discord
            self.telegram = telegram
        }
    }

    public struct Visor: Codable, Sendable, Equatable {
        public struct Scheduler: Codable, Sendable, Equatable {
            public var enabled: Bool
            public var intervalSeconds: Int
            public var jitterSeconds: Int

            public init(
                enabled: Bool = true,
                intervalSeconds: Int = 300,
                jitterSeconds: Int = 60
            ) {
                self.enabled = enabled
                self.intervalSeconds = intervalSeconds
                self.jitterSeconds = jitterSeconds
            }
        }

        public var scheduler: Scheduler
        public var bootstrapBulletin: Bool
        /// Model identifier used for bulletin LLM synthesis (e.g. "openai:gpt-4o-mini").
        /// When nil, falls back to the default system model.
        public var model: String?
        /// Target word count for LLM-synthesized bulletin summary.
        public var bulletinMaxWords: Int
        /// Interval in seconds for the Visor supervision tick loop.
        public var tickIntervalSeconds: Int
        /// Seconds a worker may stay in .running/.waitingInput before it's considered hanging.
        public var workerTimeoutSeconds: Int
        /// Seconds a branch may stay alive before it's force-concluded by Visor.
        public var branchTimeoutSeconds: Int
        /// Interval in seconds between memory maintenance runs (decay + prune).
        public var maintenanceIntervalSeconds: Int
        /// Daily fractional decay applied to non-identity memory importance.
        public var decayRatePerDay: Double
        /// Memories with importance below this threshold are candidates for pruning.
        public var pruneImportanceThreshold: Double
        /// Minimum age in days before a memory can be pruned.
        public var pruneMinAgeDays: Int
        /// Number of workerFailed events in a channel within the window to trigger channel_degraded signal.
        public var channelDegradedFailureCount: Int
        /// Window in seconds for channel degradation failure counting.
        public var channelDegradedWindowSeconds: Int
        /// Seconds of inactivity before the idle signal is published.
        public var idleThresholdSeconds: Int
        /// Webhook URLs to POST signal events to when visor.signal.* events fire.
        public var webhookURLs: [String]
        /// Whether memory merge is enabled. When false, runMemoryMerge() is skipped.
        public var mergeEnabled: Bool
        /// Minimum recall score (0–1) required to consider two memories merge candidates.
        public var mergeSimilarityThreshold: Double
        /// Maximum number of merge operations performed in a single maintenance run.
        public var mergeMaxPerRun: Int

        public init(
            scheduler: Scheduler = Scheduler(),
            bootstrapBulletin: Bool = true,
            model: String? = nil,
            bulletinMaxWords: Int = 300,
            tickIntervalSeconds: Int = 30,
            workerTimeoutSeconds: Int = 600,
            branchTimeoutSeconds: Int = 60,
            maintenanceIntervalSeconds: Int = 3600,
            decayRatePerDay: Double = 0.05,
            pruneImportanceThreshold: Double = 0.1,
            pruneMinAgeDays: Int = 30,
            channelDegradedFailureCount: Int = 3,
            channelDegradedWindowSeconds: Int = 600,
            idleThresholdSeconds: Int = 1800,
            webhookURLs: [String] = [],
            mergeEnabled: Bool = false,
            mergeSimilarityThreshold: Double = 0.80,
            mergeMaxPerRun: Int = 10
        ) {
            self.scheduler = scheduler
            self.bootstrapBulletin = bootstrapBulletin
            self.model = model
            self.bulletinMaxWords = bulletinMaxWords
            self.tickIntervalSeconds = tickIntervalSeconds
            self.workerTimeoutSeconds = workerTimeoutSeconds
            self.branchTimeoutSeconds = branchTimeoutSeconds
            self.maintenanceIntervalSeconds = maintenanceIntervalSeconds
            self.decayRatePerDay = decayRatePerDay
            self.pruneImportanceThreshold = pruneImportanceThreshold
            self.pruneMinAgeDays = pruneMinAgeDays
            self.channelDegradedFailureCount = channelDegradedFailureCount
            self.channelDegradedWindowSeconds = channelDegradedWindowSeconds
            self.idleThresholdSeconds = idleThresholdSeconds
            self.webhookURLs = webhookURLs
            self.mergeEnabled = mergeEnabled
            self.mergeSimilarityThreshold = mergeSimilarityThreshold
            self.mergeMaxPerRun = mergeMaxPerRun
        }

        private enum CodingKeys: String, CodingKey {
            case scheduler
            case bootstrapBulletin
            case model
            case bulletinMaxWords
            case tickIntervalSeconds
            case workerTimeoutSeconds
            case branchTimeoutSeconds
            case maintenanceIntervalSeconds
            case decayRatePerDay
            case pruneImportanceThreshold
            case pruneMinAgeDays
            case channelDegradedFailureCount
            case channelDegradedWindowSeconds
            case idleThresholdSeconds
            case webhookURLs
            case mergeEnabled
            case mergeSimilarityThreshold
            case mergeMaxPerRun
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            scheduler = try container.decodeIfPresent(Scheduler.self, forKey: .scheduler) ?? Scheduler()
            bootstrapBulletin = try container.decodeIfPresent(Bool.self, forKey: .bootstrapBulletin) ?? true
            model = try container.decodeIfPresent(String.self, forKey: .model)
            bulletinMaxWords = try container.decodeIfPresent(Int.self, forKey: .bulletinMaxWords) ?? 300
            tickIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .tickIntervalSeconds) ?? 30
            workerTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .workerTimeoutSeconds) ?? 600
            branchTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .branchTimeoutSeconds) ?? 60
            maintenanceIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .maintenanceIntervalSeconds) ?? 3600
            decayRatePerDay = try container.decodeIfPresent(Double.self, forKey: .decayRatePerDay) ?? 0.05
            pruneImportanceThreshold = try container.decodeIfPresent(Double.self, forKey: .pruneImportanceThreshold) ?? 0.1
            pruneMinAgeDays = try container.decodeIfPresent(Int.self, forKey: .pruneMinAgeDays) ?? 30
            channelDegradedFailureCount = try container.decodeIfPresent(Int.self, forKey: .channelDegradedFailureCount) ?? 3
            channelDegradedWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .channelDegradedWindowSeconds) ?? 600
            idleThresholdSeconds = try container.decodeIfPresent(Int.self, forKey: .idleThresholdSeconds) ?? 1800
            webhookURLs = try container.decodeIfPresent([String].self, forKey: .webhookURLs) ?? []
            mergeEnabled = try container.decodeIfPresent(Bool.self, forKey: .mergeEnabled) ?? false
            mergeSimilarityThreshold = try container.decodeIfPresent(Double.self, forKey: .mergeSimilarityThreshold) ?? 0.80
            mergeMaxPerRun = try container.decodeIfPresent(Int.self, forKey: .mergeMaxPerRun) ?? 10
        }
    }

    public var listen: Listen
    public var workspace: Workspace
    public var auth: Auth
    public var onboarding: Onboarding
    public var models: [ModelConfig]
    public var memory: Memory
    public var nodes: [String]
    public var gateways: [String]
    public var plugins: [PluginConfig]
    public var channels: ChannelConfig
    public var gitSync: GitSync
    public var searchTools: SearchTools
    public var proxy: Proxy
    public var visor: Visor
    public var sqlitePath: String

    public init(
        listen: Listen,
        workspace: Workspace,
        auth: Auth,
        onboarding: Onboarding = Onboarding(),
        models: [ModelConfig],
        memory: Memory,
        nodes: [String],
        gateways: [String],
        plugins: [PluginConfig],
        channels: ChannelConfig = ChannelConfig(),
        gitSync: GitSync = GitSync(),
        searchTools: SearchTools = SearchTools(),
        proxy: Proxy = Proxy(),
        visor: Visor = Visor(),
        sqlitePath: String
    ) {
        self.listen = listen
        self.workspace = workspace
        self.auth = auth
        self.onboarding = onboarding
        self.models = models
        self.memory = memory
        self.nodes = nodes
        self.gateways = gateways
        self.plugins = plugins
        self.channels = channels
        self.gitSync = gitSync
        self.searchTools = searchTools
        self.proxy = proxy
        self.visor = visor
        self.sqlitePath = sqlitePath
    }

    public static var `default`: CoreConfig {
        CoreConfig(
            listen: .init(host: "0.0.0.0", port: 25101),
            workspace: .init(),
            auth: .init(token: "dev-token"),
            onboarding: .init(),
            models: [
                .init(
                    title: "openai-main",
                    apiKey: "",
                    apiUrl: "https://api.openai.com/v1",
                    model: "gpt-4.1-mini"
                ),
                .init(
                    title: "ollama-local",
                    apiKey: "",
                    apiUrl: "http://127.0.0.1:11434",
                    model: "qwen3"
                )
            ],
            memory: .init(backend: "sqlite-local-vectors"),
            nodes: ["local"],
            gateways: [],
            plugins: [],
            channels: .init(),
            gitSync: .init(),
            searchTools: .init(),
            proxy: .init(),
            visor: .init(),
            sqlitePath: CoreConfig.defaultSQLiteFileName
        )
    }

    public static func defaultConfigPath(
        for workspace: Workspace = Workspace(),
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String {
        let cwd = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        return Self.resolvePath(workspace.basePath, currentDirectory: cwd)
            .appendingPathComponent(workspace.name, isDirectory: true)
            .appendingPathComponent(defaultConfigFileName)
            .path
    }

    public static func load(
        from path: String? = nil,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> CoreConfig {
        let normalizedPath = path?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedPath, !normalizedPath.isEmpty {
            if let decoded = decodeConfigFile(at: normalizedPath) {
                return decoded
            }
            return .default
        }

        let resolvedPath = defaultConfigPath(currentDirectory: currentDirectory)
        if let decoded = decodeConfigFile(at: resolvedPath) {
            return decoded
        }

        return .default
    }

    private static func decodeConfigFile(at path: String) -> CoreConfig? {
        let fileURL = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(CoreConfig.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case listen
        case workspace
        case auth
        case onboarding
        case models
        case memory
        case nodes
        case gateways
        case plugins
        case channels
        case gitSync
        case searchTools
        case proxy
        case visor
        case sqlitePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        listen = try container.decode(Listen.self, forKey: .listen)
        workspace = try container.decodeIfPresent(Workspace.self, forKey: .workspace) ?? .init()
        auth = try container.decode(Auth.self, forKey: .auth)
        onboarding = try container.decodeIfPresent(Onboarding.self, forKey: .onboarding) ?? .init()
        memory = try container.decode(Memory.self, forKey: .memory)
        nodes = try container.decodeIfPresent([String].self, forKey: .nodes) ?? []
        gateways = try container.decodeIfPresent([String].self, forKey: .gateways) ?? []
        channels = try container.decodeIfPresent(ChannelConfig.self, forKey: .channels) ?? .init()
        gitSync = try container.decodeIfPresent(GitSync.self, forKey: .gitSync) ?? .init()
        searchTools = try container.decodeIfPresent(SearchTools.self, forKey: .searchTools) ?? .init()
        proxy = try container.decodeIfPresent(Proxy.self, forKey: .proxy) ?? .init()
        visor = try container.decodeIfPresent(Visor.self, forKey: .visor) ?? .init()
        sqlitePath = try container.decode(String.self, forKey: .sqlitePath)
        models = try container.decodeIfPresent([ModelConfig].self, forKey: .models) ?? []
        plugins = try container.decodeIfPresent([PluginConfig].self, forKey: .plugins) ?? []
    }

    public func resolvedWorkspaceRootURL(currentDirectory: String = FileManager.default.currentDirectoryPath) -> URL {
        let cwd = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        return Self.resolvePath(workspace.basePath, currentDirectory: cwd)
            .appendingPathComponent(workspace.name, isDirectory: true)
    }

    public func resolvedSQLiteURL(currentDirectory: String = FileManager.default.currentDirectoryPath) -> URL {
        if Self.isAbsolutePath(sqlitePath) {
            return URL(fileURLWithPath: sqlitePath)
        }

        return resolvedWorkspaceRootURL(currentDirectory: currentDirectory)
            .appendingPathComponent(sqlitePath)
    }

    private static func resolvePath(_ rawPath: String, currentDirectory: URL) -> URL {
        if let expandedHome = expandHomeShortcut(rawPath) {
            return URL(fileURLWithPath: expandedHome, isDirectory: true)
        }
        if isAbsolutePath(rawPath) {
            return URL(fileURLWithPath: rawPath, isDirectory: true)
        }
        return currentDirectory.appendingPathComponent(rawPath, isDirectory: true).standardized
    }

    private static func expandHomeShortcut(_ rawPath: String) -> String? {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if rawPath == "~" {
            return homePath
        }
        if rawPath.hasPrefix("~/") {
            let suffix = String(rawPath.dropFirst(2))
            return URL(fileURLWithPath: homePath, isDirectory: true)
                .appendingPathComponent(suffix, isDirectory: true)
                .path
        }
        if rawPath == "$HOME" {
            return homePath
        }
        if rawPath.hasPrefix("$HOME/") {
            let suffix = String(rawPath.dropFirst("$HOME/".count))
            return URL(fileURLWithPath: homePath, isDirectory: true)
                .appendingPathComponent(suffix, isDirectory: true)
                .path
        }
        return nil
    }

    private static func isAbsolutePath(_ rawPath: String) -> Bool {
        rawPath.hasPrefix("/")
    }
}
