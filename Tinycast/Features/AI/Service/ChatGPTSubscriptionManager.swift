import Foundation
import Observation

/// Owns the app-server, reusing the account already configured in the user's Codex installation.
@MainActor
@Observable
final class ChatGPTSubscriptionManager {
    /// Long enough to span a conversation; a relaunch costs a second, a resident server ~20 MB.
    private static let idleShutdown: Duration = .seconds(600)

    private let client: CodexAppServerClient
    let turns: CodexTurnRunner
    /// An agent's helper keeps its shell tool, so a plain chat never runs on one that has it.
    private let agentClient: CodexAppServerClient
    let agentTurns: CodexTurnRunner
    /// Forwarded to the app-server's launch; a change takes effect at its next start.
    @ObservationIgnored var launchSettings: () -> InstalledAILaunch {
        get { client.launchSettings }
        set {
            client.launchSettings = newValue
            agentClient.launchSettings = newValue
        }
    }

    private(set) var phase = ChatGPTSubscription.Phase.idle
    private(set) var access: ChatGPTSubscription.Access?
    private(set) var models: [ChatGPTSubscription.Model] = []
    private(set) var rateLimits: ChatGPTSubscription.RateLimits?
    /// Copied from the client at each check: the client is not observed, and Settings shows this.
    private(set) var executable: URL?

    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var agentIdleTask: Task<Void, Never>?

    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        let root = supportDirectory.appending(path: "InstalledAI/Codex", directoryHint: .isDirectory)
        let workspace = root.appending(path: "Workspace", directoryHint: .isDirectory)
        client = CodexAppServerClient(workspace: workspace)
        turns = CodexTurnRunner(client: client)
        agentClient = CodexAppServerClient(workspace: workspace, runsCommands: true)
        agentTurns = CodexTurnRunner(client: agentClient, runsAgents: true)
        turns.connect = { [weak self] servers in
            guard let self else { throw CancellationError() }
            try await self.ensureConnected(toolServers: servers)
            return self.models
        }
        turns.onTurnEnded = { [weak self] in self?.turnDidEnd() }
        client.onNotification = { [weak self] method, params in
            self?.handleNotification(method: method, params: params)
        }
        client.onExit = { [weak self] message in
            self?.forget()
            self?.phase = .failed(message)
        }
        agentTurns.connect = { [weak self] servers in
            guard let self else { throw CancellationError() }
            try await self.ensureAgentConnected(toolServers: servers)
            return self.models
        }
        agentTurns.onTurnEnded = { [weak self] in self?.agentTurnDidEnd() }
        agentClient.onNotification = { [weak self] method, params in
            guard let self else { return }
            if method == "account/updated" {
                self.handleNotification(method: method, params: params)
            } else {
                self.agentTurns.handle(method: method, params: params)
            }
        }
        agentClient.onExit = { [weak self] _ in self?.agentTurns.reset() }
    }

    var account: ChatGPTSubscription.Account? {
        if case .account(let account) = access { account } else { nil }
    }

    var isConnected: Bool { access != nil && phase == .connected }

    @discardableResult
    func refresh() -> Task<Void, Never> {
        // A check is under way the moment it is asked for, so `.idle` can mean nobody asked.
        if phase == .idle { phase = .starting }
        return runOperation { [weak self] in await self?.refreshNow() }
    }

    func currentRefreshTask() -> Task<Void, Never> { operationTask ?? Task {} }

    /// Releases process, timers and state alike; `.idle` lets the next visit check again.
    func stop() {
        operationTask?.cancel()
        // Interrupting a live turn re-arms idle shutdown, so forgetting must precede the cancel.
        forget()
        phase = .idle
        idleTask?.cancel()
        agentIdleTask?.cancel()
        client.stop()
        agentClient.stop()
    }

    /// A helper launched with a server no longer offered stops now, not ten idle minutes later.
    func dropWithdrawnServers(keeping offered: Set<String>) {
        let withdrawn = { (helper: CodexAppServerClient) in
            helper.toolServers.contains(where: { !offered.contains($0.handle) })
        }
        if !turns.isActive, withdrawn(client) {
            idleTask?.cancel()
            turns.reset()
            client.stop()
        }
        if !agentTurns.isActive, withdrawn(agentClient) {
            agentIdleTask?.cancel()
            agentTurns.reset()
            agentClient.stop()
        }
    }

    /// What a turn needs before it starts: a running server and confirmed access.
    private func ensureConnected(toolServers: [AIToolServer]) async throws {
        idleTask?.cancel()
        // A changed list relaunches, since it is fixed at exec; access outlives the process.
        try await client.start(toolServers: toolServers)
        guard access == nil else { return }
        guard try await verifyAccess(on: client) else {
            throw AIProviderError.unavailable(
                String(localized: "Sign in with `codex login`, then check Codex again."))
        }
    }

    private func ensureAgentConnected(toolServers: [AIToolServer]) async throws {
        agentIdleTask?.cancel()
        try await agentClient.start(toolServers: toolServers)
        guard access == nil else { return }
        guard try await verifyAccess(on: agentClient) else {
            throw AIProviderError.unavailable(
                String(localized: "Sign in with `codex login`, then check Codex again."))
        }
    }

    private func turnDidEnd() {
        Task { [weak self] in
            guard let self else { return }
            await self.loadRateLimits(on: self.client)
        }
        scheduleIdleShutdown()
    }

    private func agentTurnDidEnd() {
        Task { [weak self] in
            guard let self else { return }
            await self.loadRateLimits(on: self.agentClient)
        }
        agentIdleTask?.cancel()
        agentIdleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleShutdown)
            guard !Task.isCancelled, let self, !self.agentTurns.isActive else { return }
            self.agentTurns.reset()
            self.agentClient.stop()
        }
    }

    @discardableResult
    private func runOperation(
        _ operation: @escaping @MainActor () async -> Void
    )
        -> Task<Void, Never>
    {
        operationTask?.cancel()
        let task = Task { await operation() }
        operationTask = task
        return task
    }

    private func refreshNow() async {
        phase = .starting
        do {
            try await client.startForCheck()
            executable = client.executable
            guard try await verifyAccess(on: client) else { return }
            scheduleIdleShutdown()
        } catch {
            apply(error)
        }
    }

    /// A check and a turn reach the same verdict, so neither leaves a signed-out server running.
    private func verifyAccess(on helper: CodexAppServerClient) async throws -> Bool {
        guard try await restoreAccess(on: helper) else {
            phase = .signedOut
            helper.stop()
            return false
        }
        phase = .connected
        await loadModelsAndLimits(on: helper)
        return true
    }

    /// The server stays resident only while it is being used; a stopped one restarts on demand.
    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleShutdown)
            guard !Task.isCancelled, let self, !self.turns.isActive else { return }
            self.turns.reset()
            self.client.stop()
        }
    }

    private func loadModelsAndLimits(on helper: CodexAppServerClient) async {
        do {
            let response = try await helper.request(
                method: "model/list", params: ["includeHidden": false, "limit": 100])
            models = (response["data"]?.arrayValue ?? []).compactMap { value in
                guard let raw = value.objectValue, let id = raw["model"]?.stringValue else {
                    return nil
                }
                let rawEfforts = raw["supportedReasoningEfforts"]?.arrayValue ?? []
                let efforts = rawEfforts.compactMap { effort -> ChatGPTSubscription.Effort? in
                    guard let raw = effort.objectValue,
                        let id = raw["reasoningEffort"]?.stringValue
                    else { return nil }
                    return ChatGPTSubscription.Effort(
                        id: id, detail: raw["description"]?.stringValue)
                }
                return ChatGPTSubscription.Model(
                    id: id,
                    name: raw["displayName"]?.stringValue ?? id,
                    efforts: efforts,
                    defaultEffort: raw["defaultReasoningEffort"]?.stringValue,
                    isDefault: raw["isDefault"]?.boolValue ?? false)
            }
        } catch {
            models = []
        }
        await loadRateLimits(on: helper)
    }

    private func loadRateLimits(on helper: CodexAppServerClient) async {
        do {
            let response = try await helper.request(method: "account/rateLimits/read")
            guard let limits = response["rateLimits"]?.objectValue else {
                rateLimits = nil
                return
            }
            rateLimits = ChatGPTSubscription.RateLimits(
                primary: usageWindow(limits["primary"]),
                secondary: usageWindow(limits["secondary"]))
        } catch {
            rateLimits = nil
        }
    }

    private func usageWindow(_ value: JSONValue?) -> ChatGPTSubscription.UsageWindow? {
        guard let raw = value?.objectValue, let used = raw["usedPercent"]?.intValue else {
            return nil
        }
        return ChatGPTSubscription.UsageWindow(
            usedPercent: used,
            durationMinutes: raw["windowDurationMins"]?.intValue,
            resetsAt: raw["resetsAt"]?.intValue.map {
                Date(timeIntervalSince1970: Double($0))
            })
    }

    private func restoreAccess(on helper: CodexAppServerClient) async throws -> Bool {
        let response = try await helper.request(
            method: "account/read", params: ["refreshToken": false])
        if let rawAccount = response["account"]?.objectValue {
            let type = rawAccount["type"]?.stringValue ?? "unknown"
            access = .account(
                ChatGPTSubscription.Account(
                    email: rawAccount["email"]?.stringValue,
                    plan: rawAccount["planType"]?.stringValue ?? type))
        } else if response["requiresOpenaiAuth"]?.boolValue == false {
            access = .provider
        } else {
            forget()
            return false
        }
        return true
    }

    private func handleNotification(method: String, params: [String: JSONValue]) {
        switch method {
        case "account/updated":
            runOperation { [weak self] in await self?.refreshNow() }
        default:
            turns.handle(method: method, params: params)
        }
    }

    private func forget() {
        access = nil
        models = []
        rateLimits = nil
        turns.reset()
        agentTurns.reset()
    }

    private func apply(_ error: Error) {
        // A cancelled check has no verdict: whoever cancelled it already set the state it wanted.
        guard !Task.isCancelled else { return }
        forget()
        let message = Self.userFacing(error).localizedDescription
        if let clientError = error as? CodexAppServerClient.ClientError,
            case .executableMissing = clientError
        {
            phase = .unavailable(message)
        } else {
            phase = .failed(message)
        }
    }

    static func userFacing(_ error: Error) -> Error {
        if error is AIProviderError { return error }
        let message =
            (error as? LocalizedError)?.errorDescription
            ?? String(localized: "The Codex connection failed.")
        return AIProviderError.responseFailed(message)
    }
}

struct CodexInstalledProvider: AIProvider {
    let turns: CodexTurnRunner
    let model: String
    let effort: String?
    /// Set only by chat: a quick action has nothing to call and arms no server.
    var toolServers: AIToolServerSession?
    /// Set only by an agent chat, whose `turns` is the helper that keeps a shell.
    var agent: AgentSession?

    func stream(_ request: AIRequest) -> AIProviderStream {
        turns.stream(request, model: model, effort: effort, toolServers: toolServers, agent: agent)
    }
}
