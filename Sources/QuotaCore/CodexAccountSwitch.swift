import Foundation
import Darwin

public enum CodexSwitchError: Error, LocalizedError, Sendable {
    case fileStorageRequired, unsafePath, signInFirst, loginChanged, recoveryRequired, workspaceMismatch
    public var errorDescription: String? {
        switch self {
        case .fileStorageRequired: "Account switching requires Codex file-based login storage."
        case .unsafePath: "The Codex login path is not a regular local file. No login was changed."
        case .signInFirst: "Sign in to this account before switching to it."
        case .loginChanged: "The Codex login changed during switching. Try again."
        case .recoveryRequired: "Account switch recovery is pending. Unlock Keychain and reopen QuotaClock."
        case .workspaceMismatch: "This account does not match the workspace required by Codex settings."
        }
    }
}

/// Only the private Keychain contains the transaction's credentials. The marker
/// on disk contains no account details; it prevents readers using a partial handoff.
struct CodexSwitchTransaction {
    let root: URL
    let active: CodexActiveLogin
    let vault: any AccountCredentialVault
    var checkpoint: @Sendable (Stage) throws -> Void = { _ in }
    enum Stage { case prepared, vaultsSaved, activeWritten, registryWritten }
    struct SavedCredential: Codable { var id: UUID; var data: Data? }
    struct Journal: Codable {
        var home: String
        var targetID: UUID
        var previousAuth: Data?
        var targetAuth: Data
        var before: [ProviderAccount]
        var after: [ProviderAccount]
        var previousVault: [SavedCredential]
        var nextVault: [SavedCredential]
        var completed = false
    }
    static let journalID = UUID(uuidString: "5700A2B3-17A1-4DCC-9BC7-20DD329D0B02")!
    private var marker: URL { root.appendingPathComponent("switch.pending") }
    private var registry: URL { root.appendingPathComponent("accounts.json") }
    private var authURL: URL { active.home.appendingPathComponent("auth.json") }
    var isPending: Bool { FileManager.default.fileExists(atPath: marker.path) }

    func readActive() throws -> CodexCredential? {
        try validateStorage()
        return try readAuth().map(CodexCredential.init)
    }
    func validateTarget(_ credential: CodexCredential) throws { try validateStorage(target: credential) }
    private func validateStorage(target: CodexCredential? = nil) throws {
        guard active.home.standardizedFileURL == active.home.resolvingSymlinksInPath().standardizedFileURL else {
            throw CodexSwitchError.unsafePath
        }
        let configURL = active.home.appendingPathComponent("config.toml")
        guard let config = try regularData(configURL, limit: 1_048_576) else { return }
        guard let text = String(data: config, encoding: .utf8) else { throw CodexSwitchError.fileStorageRequired }
        // Accept plain or quoted TOML keys and both string quote styles. Every
        // occurrence must be compatible, including configured profile overrides.
        for (key, allowed) in [("cli_auth_credentials_store", "file"), ("forced_login_method", "chatgpt")] {
            for value in try setting(key, in: text) where value != allowed { throw CodexSwitchError.fileStorageRequired }
        }
        if let target {
            for value in try setting("forced_chatgpt_workspace_id", in: text) where value != target.accountID {
                throw CodexSwitchError.workspaceMismatch
            }
        }
    }
    private func setting(_ key: String, in text: String) throws -> [String] {
        let pattern = try NSRegularExpression(pattern: "(?m)^[ \\t]*[\"']?" + key + "[\"']?[ \\t]*=[ \\t]*([^\\r\\n]+)")
        // Do not silently miss dotted keys or inline profile tables. Switching
        // supports simple string settings only; unknown syntax fails closed.
        // Comment-only lines are harmless, including configuration examples.
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || !trimmed.contains(key) { continue }
            if let comment = trimmed.firstIndex(of: "#"), !trimmed[..<comment].contains(key) { continue }
            guard pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else {
                throw CodexSwitchError.fileStorageRequired
            }
        }
        return try pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            let raw = String(text[Range(match.range(at: 1), in: text)!])
            let quoted = try NSRegularExpression(pattern: #"^["']([^"']*)["']\s*(?:#.*)?$"#)
            guard let value = quoted.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  let range = Range(value.range(at: 1), in: raw) else { throw CodexSwitchError.fileStorageRequired }
            return String(raw[range])
        }
    }
    private func regularData(_ url: URL, limit: Int) throws -> Data? {
        var status = stat()
        if lstat(url.path, &status) != 0 {
            if errno == ENOENT { return nil }
            throw CodexSwitchError.unsafePath
        }
        guard status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1,
              status.st_uid == getuid(), status.st_size <= limit else { throw CodexSwitchError.unsafePath }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CodexSwitchError.unsafePath }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_ino == status.st_ino, opened.st_dev == status.st_dev else {
            throw CodexSwitchError.loginChanged
        }
        let data = try handle.readToEnd() ?? Data()
        guard data.count <= limit else { throw CodexSwitchError.unsafePath }
        return data
    }
    private func readAuth() throws -> Data? { try regularData(authURL, limit: 131_072) }
    private func replaceAuth(_ data: Data?, expected: Data?) throws {
        try validateStorage()
        guard try readAuth() == expected else { throw CodexSwitchError.loginChanged }
        if let data {
            try FileManager.default.createDirectory(at: active.home, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try Self.writePrivate(data, to: authURL)
        } else if expected != nil {
            guard unlink(authURL.path) == 0 else { throw CodexSwitchError.recoveryRequired }
        }
    }
    static func writePrivate(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".quotaclock-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AccountError.storage }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else { throw AccountError.storage }
        let parent = open(url.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
        if parent >= 0 { _ = fsync(parent); close(parent) }
    }
    private func apply(_ credentials: [SavedCredential], accounts: [ProviderAccount]) throws {
        for entry in credentials {
            if let data = entry.data { try vault.save(data, id: entry.id) }
            else { try vault.delete(entry.id) }
        }
        try Self.writePrivate(JSONEncoder().encode(accounts), to: registry)
    }
    private func clear() throws {
        try vault.delete(Self.journalID)
        if isPending { try FileManager.default.removeItem(at: marker) }
    }
    func recover() throws {
        guard isPending else { return }
        guard let data = try vault.read(Self.journalID) else { try clear(); return }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.home == active.home.standardizedFileURL.path else { throw CodexSwitchError.recoveryRequired }
        if journal.completed { try clear(); return }
        let current = try readActive()
        let target = try CodexCredential(journal.targetAuth)
        let previous = try journal.previousAuth.map(CodexCredential.init)
        if current?.identityKey == target.identityKey {
            // Desktop may have been opened after a crash. Preserve its newer
            // tokens; the target remains externally owned and is never rotated here.
            try apply(journal.nextVault, accounts: journal.after)
        } else if current?.identityKey == previous?.identityKey {
            try apply(journal.previousVault, accounts: journal.before)
        } else { throw CodexSwitchError.recoveryRequired }
        try clear()
    }
    func commit(to id: UUID, accounts: [ProviderAccount], expectedCurrentIdentity: String?) throws -> [ProviderAccount] {
        guard !isPending, let target = accounts.first(where: { $0.id == id }),
              target.connection == .independent, target.credentialsHandedToCodex != true,
              let targetData = try vault.read(id) else { throw CodexSwitchError.signInFirst }
        let credential = try CodexCredential(targetData)
        guard credential.identityKey == target.identityKey, credential.refreshToken?.isEmpty == false else {
            throw AccountError.identityChanged
        }
        try validateStorage(target: credential)
        let previousData = try readAuth()
        let previous = try previousData.map(CodexCredential.init)
        guard previous?.identityKey == expectedCurrentIdentity else { throw CodexSwitchError.loginChanged }
        if previous?.identityKey == credential.identityKey { return accounts }
        var after = accounts
        var previousVault = [SavedCredential(id: id, data: targetData)]
        var nextVault = previousVault
        if let previous, let previousData {
            guard previous.refreshToken?.isEmpty == false else { throw CodexSwitchError.signInFirst }
            var old: ProviderAccount
            if let existing = after.first(where: { $0.identityKey == previous.identityKey }) { old = existing }
            else {
                var name = "Previous"
                while after.contains(where: { $0.signature.lowercased() == name.lowercased() }) {
                    name = "Saved" + String(UUID().uuidString.filter(\.isLetter).prefix(7))
                }
                old = ProviderAccount(signature: name, identityKey: previous.identityKey, email: previous.email,
                                      plan: previous.plan, connection: .independent)
            }
            previousVault.append(SavedCredential(id: old.id, data: try vault.read(old.id)))
            nextVault.append(SavedCredential(id: old.id, data: previousData))
            old.connection = .independent; old.credentialsHandedToCodex = nil
            if let index = after.firstIndex(where: { $0.id == old.id }) { after[index] = old }
            else { after.append(old) }
        }
        after[after.firstIndex(where: { $0.id == id })!].credentialsHandedToCodex = true
        var journal = Journal(home: active.home.standardizedFileURL.path, targetID: id,
                              previousAuth: previousData, targetAuth: targetData, before: accounts, after: after,
                              previousVault: previousVault, nextVault: nextVault)
        try Self.writePrivate(Data("pending".utf8), to: marker)
        do {
            try vault.save(JSONEncoder().encode(journal), id: Self.journalID)
            try checkpoint(.prepared)
            for entry in nextVault { if let data = entry.data { try vault.save(data, id: entry.id) } }
            try checkpoint(.vaultsSaved)
            try replaceAuth(targetData, expected: previousData)
            try checkpoint(.activeWritten)
            try Self.writePrivate(JSONEncoder().encode(after), to: registry)
            try checkpoint(.registryWritten)
            journal.completed = true
            try vault.save(JSONEncoder().encode(journal), id: Self.journalID)
        } catch {
            do {
                let current = try readAuth()
                if current == targetData { try replaceAuth(previousData, expected: targetData) }
                else if current != previousData { throw CodexSwitchError.loginChanged }
                try apply(previousVault, accounts: accounts)
                try clear()
            } catch { throw CodexSwitchError.recoveryRequired }
            throw error
        }
        try? clear() // A committed journal can be safely cleaned on the next launch.
        return after
    }
}
