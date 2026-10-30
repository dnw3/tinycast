import Foundation

enum CommandID: String, CaseIterable, Sendable {
    /// The palette's chat keeps the id it shipped with, so its hotkeys and fallback still reach it.
    case quickAI = "command:ai-chat"
    case aiChat = "command:ai-chat-window"
    case captureScreenshot = "command:capture-screenshot"
    case captureFullscreen = "command:capture-fullscreen"
    case captureScrollingScreenshot = "command:capture-scrolling-screenshot"
    case captureRecording = "command:capture-recording"
    case captureText = "command:capture-text"
    case captureAndTranslate = "command:capture-and-translate"
    case editClipboardImage = "command:edit-clipboard-image"
    case pinClipboardImage = "command:pin-clipboard-image"
    case captureHistory = "command:capture-history"
    case fixGrammar = "command:fix-grammar"
    case rewrite = "command:rewrite"
    case translate = "command:translate"
    case summarize = "command:summarize"
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case pasteSequentially = "command:paste-sequentially"
    case toggleClipboardRecording = "command:toggle-clipboard-recording"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case cleanUpDisk = "command:clean-up-disk"
    case quickClean = "command:quick-clean"
    case analyzeDiskUsage = "command:analyze-disk-usage"
    case rebuildThumbnails = "command:rebuild-thumbnail-cache"
    case restartDock = "command:restart-dock"
    case openProxy = "command:open-proxy"
    case proxyNodes = "command:proxy-nodes"
    case proxyRoutes = "command:proxy-routes"
    case proxyStrategies = "command:proxy-strategies"
    case addProxyRule = "command:add-proxy-rule"
    case connectProxy = "command:connect-proxy"
    case disconnectProxy = "command:disconnect-proxy"
    case testProxyNodes = "command:test-proxy-nodes"
    case updateProxySubscriptions = "command:update-proxy-subscriptions"
    case proxyRuleMode = "command:proxy-rule-mode"
    case proxyGlobalMode = "command:proxy-global-mode"
    case proxyDirectMode = "command:proxy-direct-mode"
    case searchMenuItems = "command:search-menu-items"
    case switchWindows = "command:switch-windows"
    case switchWindowsBackwards = "command:switch-windows-backwards"
    case openCamera = "command:open-camera"
    case openInBrowser = "command:open-in-browser"
    case runShellCommand = "command:run-shell-command"
    case createCustomCommand = "command:create-custom-command"
    case searchCustomCommands = "command:search-custom-commands"
    case define = "command:define"
    case joinNextMeeting = "command:join-next-meeting"
    case mySchedule = "command:my-schedule"
    case createEvent = "command:create-event"
    case copyMeetingLink = "command:copy-meeting-link"
    case openInCalendar = "command:open-in-calendar"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createWindowLayout = "command:create-window-layout"
    case captureWindowLayout = "command:capture-window-layout"
    case switchRoom = "command:switch-room"
    case createRoom = "command:create-room"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case checkForUpdates = "command:check-for-updates"
    case settings = "command:settings"
    case about = "command:about"
    case support = "command:support"
    case quit = "command:quit"

    static let defaultCompactBarCommands: [CommandID] = [
        .clipboardHistory, .searchEmoji, .searchFiles, .searchQuicklinks
    ]

    static let compactBarOptions: [CommandID] =
        defaultCompactBarCommands + [
            .searchSnippets, .showNotes, .mySchedule, .quickAI
        ] + forkCompactBarOptions

    /// Kept apart from upstream's list so a sync touches only the line that appends it.
    static let forkCompactBarOptions: [CommandID] = [
        .captureScreenshot, .translate, .proxyNodes, .cleanUpDisk, .aiChat
    ]

    static let compactBarLimit = 4

    static func validCompactBarCommands(_ commands: [CommandID]) -> Bool {
        commands.count <= compactBarLimit && Set(commands).count == commands.count
            && commands.allSatisfy(compactBarOptions.contains)
    }

    static func compactBarCommands(from identifiers: [String]) -> [CommandID]? {
        let commands = identifiers.compactMap(CommandID.init(rawValue:))
        guard commands.count == identifiers.count, validCompactBarCommands(commands) else { return nil }
        return commands
    }

    var name: String { nameResource.resolved() }

    var englishName: String { nameResource.key }

    private var nameResource: LocalizedStringResource {
        switch self {
        case .quickAI: return "Quick AI"
        case .captureScreenshot: return "Capture Screenshot"
        case .captureFullscreen: return "Capture Full Screen"
        case .captureScrollingScreenshot: return "Capture Scrolling Screenshot"
        case .captureRecording: return "Record Screen"
        case .captureText: return "Capture Text"
        case .captureAndTranslate: return "Capture & Translate"
        case .editClipboardImage: return "Edit Clipboard Image"
        case .pinClipboardImage: return "Pin Clipboard Image"
        case .captureHistory: return "Capture History"
        case .aiChat: return "AI Chat"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.titleResource
        case .rewrite: return BuiltInQuickAction.rewrite.titleResource
        case .translate: return "Translate"
        case .summarize: return BuiltInQuickAction.summarize.titleResource
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .pasteSequentially: return "Paste Sequentially"
        case .toggleClipboardRecording: return "Pause or Resume Clipboard History"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .cleanUpDisk: return "Clean Up Disk"
        case .quickClean: return "Quick Clean"
        case .analyzeDiskUsage: return "Disk Usage"
        case .rebuildThumbnails: return "Rebuild Thumbnail Cache"
        case .restartDock: return "Restart Dock"
        case .openProxy: return "Open Proxy Window"
        case .proxyNodes: return "Choose Proxy Node"
        case .proxyRoutes: return "Proxy Routes"
        case .proxyStrategies: return "Proxy Strategies"
        case .addProxyRule: return "Add Proxy Rule"
        case .connectProxy: return "Connect Proxy"
        case .disconnectProxy: return "Disconnect Proxy"
        case .testProxyNodes: return "Test Proxy Nodes"
        case .updateProxySubscriptions: return "Update Proxy Subscriptions"
        case .proxyRuleMode: return "Proxy Rule Mode"
        case .proxyGlobalMode: return "Proxy Global Mode"
        case .proxyDirectMode: return "Proxy Direct Mode"
        case .searchMenuItems: return "Search Menu Bar Items"
        case .switchWindows: return "Switch Windows"
        case .switchWindowsBackwards: return "Switch Windows Backwards"
        case .openCamera: return "Open Camera"
        case .openInBrowser: return "Open in Browser"
        case .runShellCommand: return "Run Shell Command"
        case .createCustomCommand: return "Create Custom Command"
        case .searchCustomCommands: return "Search Custom Commands"
        case .define: return "Define Word"
        case .joinNextMeeting: return "Join Next Meeting"
        case .mySchedule: return "My Schedule"
        case .createEvent: return "Create Event"
        case .copyMeetingLink: return "Copy Meeting Link"
        case .openInCalendar: return "Open in Calendar"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createWindowLayout: return "Create Window Layout"
        case .captureWindowLayout: return "Create Layout from Current Windows"
        case .switchRoom: return "Switch Room"
        case .createRoom: return "Create Room"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .importFromRaycast: return "Import from Raycast"
        case .checkForUpdates: return "Check for Updates"
        case .settings: return "Tinycast Settings"
        case .about: return "About Tinycast"
        case .support: return "Support Tinycast"
        case .quit: return "Quit Tinycast"
        }
    }

    var alternateTitles: [String] {
        switch self {
        case .captureScreenshot: ["截图", "区域截图", "截屏", "Screenshot"]
        case .captureFullscreen: ["全屏截图", "屏幕截图", "Full Screen Capture"]
        case .captureScrollingScreenshot: ["长截图", "滚动截图", "长图", "Scroll Capture"]
        case .captureRecording: ["录屏", "屏幕录制", "Screen Recording"]
        case .captureText: ["截图取字", "取字", "OCR"]
        case .captureAndTranslate: ["截图翻译", "屏幕翻译"]
        case .editClipboardImage: ["编辑剪贴板图片", "编辑图片"]
        case .pinClipboardImage: ["贴图", "固定截图"]
        case .captureHistory: ["截图历史", "截屏历史"]
        case .cleanUpDisk: ["清理磁盘", "磁盘清理", "清理缓存", "Free Up Space", "Clear Cache"]
        case .quickClean: ["快速清理", "一键清理"]
        case .analyzeDiskUsage: ["磁盘空间分析", "空间占用", "磁盘占用", "Storage"]
        case .rebuildThumbnails: ["重建缩略图缓存", "Quick Look"]
        case .restartDock: ["重启程序坞", "Dock"]
        case .toggleClipboardRecording: ["暂停剪贴板记录", "恢复剪贴板记录"]
        case .openProxy: ["代理窗口", "代理面板", "Proxy Window", "Proxy Dashboard"]
        case .proxyNodes: ["选择节点", "切换节点", "节点", "Switch Node"]
        case .proxyRoutes: ["分流", "分流规则", "Routing"]
        case .proxyStrategies: ["策略", "策略组", "Proxy Groups"]
        case .addProxyRule: ["添加分流规则", "添加规则", "Add Rule"]
        case .connectProxy: ["开启代理", "打开代理", "连接 VPN", "VPN", "Proxy On"]
        case .disconnectProxy: ["关闭代理", "断开 VPN", "VPN", "Proxy Off"]
        case .testProxyNodes: ["节点测速", "测速", "延迟测试", "Speed Test"]
        case .updateProxySubscriptions: ["更新订阅", "刷新订阅", "Refresh Subscriptions"]
        case .proxyRuleMode: ["规则模式", "分流模式", "Rule Mode"]
        case .proxyGlobalMode: ["全局模式", "全局代理", "Global Mode"]
        case .proxyDirectMode: ["直连模式", "暂停代理", "Direct Mode"]
        default: []
        }
    }

    var sfSymbol: String {
        switch self {
        case .quickAI: return "sparkles"
        case .aiChat: return "bubble.left.and.bubble.right"
        case .captureScreenshot: return "viewfinder"
        case .captureFullscreen: return "rectangle.dashed"
        case .captureScrollingScreenshot: return "rectangle.portrait.and.arrow.forward"
        case .captureRecording: return "record.circle"
        case .captureText: return "text.viewfinder"
        case .captureAndTranslate: return "translate"
        case .editClipboardImage: return "pencil"
        case .pinClipboardImage: return "pin"
        case .captureHistory: return "photo.on.rectangle"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.symbol
        case .rewrite: return BuiltInQuickAction.rewrite.symbol
        case .translate: return "translate"
        case .summarize: return BuiltInQuickAction.summarize.symbol
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pasteSequentially: return "list.bullet.clipboard"
        case .toggleClipboardRecording: return "pause.circle"
        case .searchEmoji: return "face.smiling"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .cleanUpDisk: return "externaldrive.badge.minus"
        case .quickClean: return "wand.and.rays"
        case .analyzeDiskUsage: return "chart.bar.doc.horizontal"
        case .rebuildThumbnails: return "photo.stack"
        case .restartDock: return "dock.rectangle"
        case .openProxy: return "macwindow"
        case .proxyNodes: return "network"
        case .proxyRoutes: return "arrow.triangle.branch"
        case .proxyStrategies: return "square.stack.3d.up"
        case .addProxyRule: return "text.badge.plus"
        case .connectProxy: return "network"
        case .disconnectProxy: return "network.slash"
        case .testProxyNodes: return "speedometer"
        case .updateProxySubscriptions: return "arrow.triangle.2.circlepath"
        case .proxyRuleMode: return "arrow.triangle.branch"
        case .proxyGlobalMode: return "globe"
        case .proxyDirectMode: return "arrow.right"
        case .searchMenuItems: return "menubar.rectangle"
        case .switchWindows, .switchWindowsBackwards: return "macwindow.on.rectangle"
        case .openCamera: return "camera"
        case .openInBrowser: return "globe"
        case .runShellCommand: return "terminal"
        case .createCustomCommand: return "terminal"
        case .searchCustomCommands: return "terminal"
        case .define: return "book.closed"
        case .joinNextMeeting: return "video.fill"
        case .mySchedule: return "calendar"
        case .createEvent: return "calendar.badge.plus"
        case .copyMeetingLink: return "link"
        case .openInCalendar: return "calendar.badge.clock"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createWindowLayout: return "plus.rectangle.on.rectangle"
        case .captureWindowLayout: return "macwindow.badge.plus"
        case .switchRoom: return "door.left.hand.open"
        case .createRoom: return "rectangle.stack.badge.plus"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .searchSnippets: return "curlybraces"
        case .createSnippet: return "plus.rectangle.on.rectangle"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .checkForUpdates: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .support: return "heart"
        case .quit: return "power"
        }
    }

    /// Exhaustive, so a fifth shipped action cannot reach the launcher without a row here.
    init(_ action: BuiltInQuickAction) {
        switch action {
        case .fixGrammar: self = .fixGrammar
        case .rewrite: self = .rewrite
        case .summarize: self = .summarize
        }
    }

    var builtInQuickAction: BuiltInQuickAction? {
        switch self {
        case .fixGrammar: return .fixGrammar
        case .rewrite: return .rewrite
        case .summarize: return .summarize
        default: return nil
        }
    }

    /// Queries this command wins until the user opens a rival more.
    var boostedTerms: Set<String> {
        switch self {
        case .quickAI: ["ai"]
        case .aiChat: ["chat"]
        default: []
        }
    }

    /// Suggested, highest first, until the user's own habits fill the section.
    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .searchFiles: 70
        case .mySchedule: 60
        case .searchEmoji: 50
        case .createQuicklink, .createSnippet: 30
        default: nil
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser || self == .runShellCommand
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
