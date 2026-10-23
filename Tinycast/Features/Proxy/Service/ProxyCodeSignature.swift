import CryptoKit
import Foundation
import Security

/// The signatures the TUN helper's trust rests on: Tinycast's identity, and checks against it.
enum ProxyCodeSignature {
    struct Identity: Equatable, Sendable {
        var identifier: String
        /// SHA-1 of the leaf certificate's DER bytes, as `certificate leaf = H"…"` names it.
        var leafHash: String
    }

    /// This process's signer; nil for ad-hoc or unsigned code, which no requirement can pin.
    static func current() -> Identity? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode
        else { return nil }
        return identity(of: staticCode)
    }

    static func identity(ofFileAt path: String) -> Identity? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else { return nil }
        return identity(of: staticCode)
    }

    /// Strict validation of the whole file against `requirement`, every architecture included.
    static func satisfies(fileAt path: String, requirement: String) -> Bool {
        var staticCode: SecStaticCode?
        var compiled: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode,
            SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess,
            let compiled
        else { return false }
        let flags = SecCSFlags(
            rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(staticCode, flags, compiled) == errSecSuccess
    }

    private static func identity(of staticCode: SecStaticCode) -> Identity? {
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let information = information as? [String: Any],
            let identifier = information[kSecCodeInfoIdentifier as String] as? String,
            let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first
        else { return nil }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data)
        return Identity(identifier: identifier, leafHash: digest.map { String(format: "%02x", $0) }.joined())
    }
}
