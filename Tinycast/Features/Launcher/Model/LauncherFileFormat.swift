import Foundation

/// A launcher item's row as settings.json spells it: shortcut, alias and launcher visibility.
enum LauncherFileFormat {
    struct Record: Equatable, Sendable {
        var shortcut: String?
        var alias: String?
        var showInLauncher = true

        var isEmpty: Bool { shortcut == nil && alias == nil && showInLauncher }
    }

    typealias Decoded = (records: [String: Record], problems: [LocalizedStringResource])

    static func json(_ records: [(name: String, record: Record)]) -> SettingsFileJSON {
        .object(
            records.map { item in
                SettingsFileJSON.Member(
                    key: item.name,
                    value: .object([
                        "shortcut": text(item.record.shortcut),
                        "alias": text(item.record.alias),
                        "showInLauncher": .bool(item.record.showInLauncher)
                    ]))
            })
    }

    static func records(from json: SettingsFileJSON, locale: Locale = Locale(identifier: "en"), bundle: LocalizedStringResource.BundleDescription = .main, current: (String) -> Record) -> Decoded? {
        guard let members = json.members else { return nil }
        var decoded: Decoded = ([:], [])
        for member in members {
            let fields = member.value
            guard fields.members != nil else {
                decoded.records[member.key] = current(member.key)
                decoded.problems.append(LocalizedStringResource("“\(member.key)” needs an object", locale: locale, bundle: bundle))
                continue
            }
            var record = current(member.key)
            text(fields["shortcut"], field: "shortcut", of: member.key, into: &record.shortcut, &decoded, locale: locale, bundle: bundle)
            text(fields["alias"], field: "alias", of: member.key, into: &record.alias, &decoded, locale: locale, bundle: bundle)
            switch fields["showInLauncher"] {
            case nil: break
            case .bool(let shown)?: record.showInLauncher = shown
            default: decoded.problems.append(LocalizedStringResource("“\(member.key)”: “showInLauncher” needs true or false", locale: locale, bundle: bundle))
            }
            decoded.records[member.key] = record
        }
        return decoded
    }

    private static func text(_ value: String?) -> SettingsFileJSON {
        value.map(SettingsFileJSON.string) ?? .null
    }

    private static func text(
        _ json: SettingsFileJSON?, field: String, of name: String, into value: inout String?,
        _ decoded: inout Decoded, locale: Locale, bundle: LocalizedStringResource.BundleDescription
    ) {
        switch json {
        case nil: return
        case .null?: value = nil
        case .string(let text)?: value = text
        default: decoded.problems.append(LocalizedStringResource("“\(name)”: “\(field)” needs quotes, or null", locale: locale, bundle: bundle))
        }
    }
}
