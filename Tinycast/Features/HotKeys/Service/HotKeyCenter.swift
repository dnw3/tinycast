import AppKit
import Carbon.HIToolbox

@MainActor
private func hotKeyCarbonEventHandler(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let error = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard error == noErr else { return error }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    let kind = GetEventKind(event)
    let flagsRaw = CopyEventCGEvent(event)?.takeRetainedValue().flags.rawValue ?? 0
    return center.handle(hotKeyID, kind: kind, flagsRaw: flagsRaw)
}

/// The Carbon layer only; which shortcuts exist is `HotKeyManager`'s business.
@MainActor
final class HotKeyCenter {
    private struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: (UInt64) -> Void
        let onKeyUp: (() -> Void)?
        let carbonID: UInt32
        var ref: EventHotKeyRef?
    }

    private var entries: [String: Entry] = [:]
    private var idToKey: [UInt32: String] = [:]
    private var nextCarbonID: UInt32 = 0
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x5459_4354  // FourCC "TYCT"
    private static let eventTypes = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
    ]
    /// The app's open menus: while one tracks, AppKit holds hot keys and the main queue back.
    private var trackingMenus: [NSMenu] = []
    private var menuObserver: MenuTrackingObserver?
    private var menuPump: Timer?
    /// Set by a delivered hot key whose action still needs the open menu, as a capture does.
    private var holdsMenus = false

    /// While true every hotkey is soft-unregistered, so a recorder can capture combos.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for key in entries.keys {
                if isPaused { deactivate(key) } else { activate(key) }
            }
        }
    }

    /// Registers `shortcut` under `id`, dropping any previous one so no combo leaks.
    func register(
        id: String, shortcut: KeyShortcut, onKeyDown: @escaping (UInt64) -> Void,
        onKeyUp: (() -> Void)? = nil
    ) {
        unregister(id: id)
        nextCarbonID += 1
        entries[id] = Entry(
            shortcut: shortcut, onKeyDown: onKeyDown, onKeyUp: onKeyUp,
            carbonID: nextCarbonID, ref: nil)
        idToKey[nextCarbonID] = id
        if !isPaused { activate(id) }
    }

    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if let ref = entry.ref { UnregisterEventHotKey(ref) }
        idToKey.removeValue(forKey: entry.carbonID)
    }

    private func activate(_ id: String) {
        guard var entry = entries[id], entry.ref == nil else { return }
        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let error = RegisterEventHotKey(
            UInt32(entry.shortcut.carbonKeyCode),
            UInt32(entry.shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: entry.carbonID),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        // Another app may own the combo; the binding stays visible but doesn't fire.
        guard error == noErr, let ref else {
            NSLog("Tinycast: could not register hotkey for %@ (OSStatus %d)", id, error)
            return
        }
        entry.ref = ref
        entries[id] = entry
    }

    private func deactivate(_ id: String) {
        guard var entry = entries[id], let ref = entry.ref else { return }
        UnregisterEventHotKey(ref)
        entry.ref = nil
        entries[id] = entry
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil, let dispatcher = GetEventDispatcherTarget() else { return }
        var eventTypes = Self.eventTypes
        menuObserver = MenuTrackingObserver(
            began: { [weak self] in self?.menuBegan($0) }, ended: { [weak self] in self?.menuEnded($0) })
        InstallEventHandler(
            dispatcher,
            { @MainActor call, event, userData in
                hotKeyCarbonEventHandler(call, event: event, userData: userData)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    /// Keeps the menu a hot key was pressed over open until the returned call, from any thread.
    func holdTrackingMenus() -> (@Sendable () -> Void)? {
        guard !trackingMenus.isEmpty else { return nil }
        holdsMenus = true
        return { [weak self] in
            // A tracking menu runs the main run loop's common modes but never the main queue.
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                MainActor.assumeIsolated { self?.endMenuTracking() }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    private func menuBegan(_ menu: NSMenu) {
        trackingMenus.append(menu)
        guard menuPump == nil else { return }
        let pump = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliverQueuedHotKeys() }
        }
        RunLoop.main.add(pump, forMode: .common)
        menuPump = pump
    }

    private func menuEnded(_ menu: NSMenu) {
        trackingMenus.removeAll { $0 === menu }
        guard trackingMenus.isEmpty else { return }
        menuPump?.invalidate()
        menuPump = nil
        holdsMenus = false
    }

    /// Hot keys pressed over an open menu, which AppKit queues until it closes, delivered at once.
    private func deliverQueuedHotKeys() {
        var types = Self.eventTypes
        let queue = GetMainEventQueue()
        var delivered = false
        while let event = AcquireFirstMatchingEventInQueue(
            queue, types.count, &types, OptionBits(kEventQueueOptionsNone))
        {
            RemoveEventFromQueue(queue, event)
            SendEventToEventTarget(event, GetEventDispatcherTarget())
            ReleaseEvent(event)
            delivered = true
        }
        // Whatever the hot key opened needs the events the menu holds, unless its action kept it.
        if delivered, !holdsMenus { endMenuTracking() }
    }

    private func endMenuTracking() {
        for menu in trackingMenus { menu.cancelTrackingWithoutAnimation() }
    }

    fileprivate func handle(_ hotKeyID: EventHotKeyID, kind: UInt32, flagsRaw: UInt64) -> OSStatus {
        guard
            hotKeyID.signature == signature,
            let key = idToKey[hotKeyID.id],
            let entry = entries[key]
        else { return OSStatus(eventNotHandledErr) }
        if kind == kEventHotKeyPressed {
            entry.onKeyDown(flagsRaw)
        } else if kind == kEventHotKeyReleased {
            guard let onKeyUp = entry.onKeyUp else { return OSStatus(eventNotHandledErr) }
            onKeyUp()
        } else {
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}

/// Hears menus begin and end tracking as AppKit posts it, which a queued block would only after.
@MainActor
private final class MenuTrackingObserver: NSObject {
    private let began: (NSMenu) -> Void
    private let ended: (NSMenu) -> Void

    init(began: @escaping (NSMenu) -> Void, ended: @escaping (NSMenu) -> Void) {
        self.began = began
        self.ended = ended
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(menuBegan(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(
            self, selector: #selector(menuEnded(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
    }

    @objc private func menuBegan(_ notification: Notification) {
        if let menu = notification.object as? NSMenu { began(menu) }
    }

    @objc private func menuEnded(_ notification: Notification) {
        if let menu = notification.object as? NSMenu { ended(menu) }
    }
}
