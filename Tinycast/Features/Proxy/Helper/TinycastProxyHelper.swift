import Foundation
import os

/// The root LaunchDaemon that runs the TUN core; `--install` and `--restore-dns` serve the scripts.
@main
enum TinycastProxyHelper {
    private static let logger = Logger(subsystem: "com.tinycast", category: "ProxyHelper")

    @MainActor
    static func main() {
        guard geteuid() == 0, let path = executablePath(),
            let layout = ProxyHelperLayout(executablePath: path)
        else { exit(64) }
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case nil:
            serve(layout)
        case "--install":
            guard arguments.count == 2, let uid = UInt32(arguments[1]) else { exit(64) }
            run { try ProxyHelperSetup.install(layout, uid: uid) }
        case "--restore-dns":
            run { try ProxyHelperSetup.restoreDNS(layout) }
        default:
            exit(64)
        }
    }

    private static func run(_ step: () throws -> Void) -> Never {
        do {
            try step()
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func serve(_ layout: ProxyHelperLayout) -> Never {
        let grant = FileManager.default.contents(atPath: layout.grant).flatMap {
            try? JSONDecoder().decode(ProxyHelperGrant.self, from: $0)
        }
        guard let grant, grant.isValid, grant.appIdentifier == layout.appIdentifier else {
            logger.error("No valid grant; the helper accepts no clients until it is installed again")
            try? ProxyHelperSetup.restoreDNS(layout)
            exit(0)
        }
        let supervisor = ProxyHelperSupervisor(
            layout: layout, grant: grant, dns: ProxySystemDNSService(), boot: bootSession())
        let listener = ProxyHelperListener(grant: grant, supervisor: supervisor) { exit(0) }
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler {
            Task { @MainActor in
                await supervisor.shutDown()
                exit(0)
            }
        }
        termination.resume()
        supervisor.enqueue { await $0.resumeAfterLaunch() }
        listener.listen(on: NSXPCListener(machServiceName: layout.label), requiring: grant.appRequirement)
        withExtendedLifetime((listener, termination)) { dispatchMain() }
    }

    /// The kernel's answer, not `argv[0]`, which whoever runs the binary chooses.
    private static func executablePath() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    private static func bootSession() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "" }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}
