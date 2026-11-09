import Foundation

/// Where the Asana token comes from, in order: Keychain, `ASANA_PAT` in the environment, a token file.
/// Keychain failures (locked keychain over SSH, denied prompt) fall through to the next source.
public enum TokenSource {
    public static let environmentKey = "ASANA_PAT"

    public static func resolve(keychain: () throws -> String?, environment: [String: String], tokenFile: String?) throws -> String? {
        if let stored = try? keychain(), let token = nonEmpty(stored) { return token }
        if let token = nonEmpty(environment[environmentKey]) { return token }
        if let tokenFile {
            let path = (tokenFile as NSString).expandingTildeInPath
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            return nonEmpty(contents)
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
