import Foundation

/// The AppleScript run with administrator privileges to install or remove the TUN helper.
enum ProxyHelperScript {
    /// Root runs only the copy it verified, as the user can replace the one in the app bundle.
    static func install(
        bundledHelper: String, layout: ProxyHelperLayout, grant: ProxyHelperGrant, prompt: String
    ) -> String? {
        guard grant.isValid, grant.appIdentifier == layout.appIdentifier else { return nil }
        let executable = quoted(layout.executable)
        let shell = [
            "set -e", "umask 022",
            "/bin/mkdir -p \(quoted(ProxyHelperLayout.toolsDirectory))",
            "copy=$(/usr/bin/mktemp \(quoted(ProxyHelperLayout.toolsDirectory + "/." + layout.label + ".XXXXXX")))",
            "trap '/bin/rm -f \"$copy\"' EXIT",
            "/bin/cp -X \(quoted(bundledHelper)) \"$copy\"",
            "/usr/sbin/chown root:wheel \"$copy\"", "/bin/chmod 755 \"$copy\"",
            "/usr/bin/codesign --verify --strict -R \(quoted("=" + grant.helperRequirement)) \"$copy\"",
            "/bin/mv -f \"$copy\" \(executable)",
            "\(executable) --install \(grant.uid)",
            "/bin/launchctl bootout system/\(layout.label) 2>/dev/null || true",
            // A job just booted out can refuse a bootstrap for a moment.
            "loaded=no",
            "for attempt in 1 2 3 4 5; do",
            "if /bin/launchctl bootstrap system \(quoted(layout.launchdPlist)); then loaded=yes; break; fi",
            "/bin/sleep 1",
            "done",
            "[ \"$loaded\" = yes ]"
        ]
        return appleScript(shell, prompt: prompt)
    }

    /// Stopping the job puts DNS back; `--restore-dns` covers a helper that was not running.
    static func uninstall(layout: ProxyHelperLayout, prompt: String) -> String {
        let executable = quoted(layout.executable)
        let shell = [
            "/bin/launchctl bootout system/\(layout.label) 2>/dev/null || true",
            "if [ -x \(executable) ]; then \(executable) --restore-dns || true; fi",
            "/bin/rm -f \(quoted(layout.launchdPlist)) \(executable)",
            "/bin/rm -rf \(quoted(layout.root))",
            "/bin/rmdir \(quoted(ProxyHelperLayout.supportDirectory)) 2>/dev/null || true"
        ]
        return appleScript(shell, prompt: prompt)
    }

    /// One shell word, whatever the text holds.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScript(_ lines: [String], prompt: String) -> String {
        "do shell script \"" + escaped(lines.joined(separator: "\n")) + "\" with prompt \"" + escaped(prompt)
            + "\" with administrator privileges"
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
