import Foundation

/// The helper's XPC interface; a reply's `Data` is an encoded `ProxyHelperFailure`, nil on success.
@objc(TinycastProxyHelperXPC)
protocol ProxyHelperXPC {
    /// The interface version the helper speaks; any other one means it needs reinstalling.
    func handshake(reply: @escaping @Sendable (Int) -> Void)
    /// An encoded `ProxyHelperStatus`.
    func status(reply: @escaping @Sendable (Data) -> Void)
    /// Reads `file` to its end; `signed` also requires Tinycast's signature, for the core it ships.
    func installCore(
        _ file: FileHandle, sha256: String, signed: Bool, reply: @escaping @Sendable (Data?) -> Void)
    func writeFile(_ name: String, contents: Data, reply: @escaping @Sendable (Data?) -> Void)
    func removeFile(_ name: String, reply: @escaping @Sendable (Data?) -> Void)
    /// Starts the core on `config`, or has a running one reload it.
    func start(
        _ config: Data, placeholderDNS: Bool, outlivesClient: Bool, reply: @escaping @Sendable (Data?) -> Void
    )
    func stop(reply: @escaping @Sendable () -> Void)
    /// A fresh connection to the core's controller socket, which only root can open.
    func openController(reply: @escaping @Sendable (FileHandle?, Data?) -> Void)
}

/// What the helper tells Tinycast without being asked.
@objc(TinycastProxyHelperClientXPC)
protocol ProxyHelperClientXPC {
    /// An encoded `ProxyHelperStatus`.
    func helperStatusDidChange(_ status: Data)
}

enum ProxyHelperWire {
    /// Raise it with any change to the helper: only a different version asks the user to reinstall.
    static let version = 1

    static func helperInterface() -> NSXPCInterface { NSXPCInterface(with: ProxyHelperXPC.self) }
    static func clientInterface() -> NSXPCInterface { NSXPCInterface(with: ProxyHelperClientXPC.self) }
}
