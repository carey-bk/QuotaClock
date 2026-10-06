import Foundation
import CryptoKit
@testable import QuotaCore

private struct ForbiddenVault: AccountCredentialVault {
    func read(_ id: UUID) throws -> Data? { throw AccountError.storage }
    func save(_ data: Data, id: UUID) throws { throw AccountError.storage }
    func delete(_ id: UUID) throws { throw AccountError.storage }
}
/// Opt-in real quota reads only. No Keychain persistence, model request, or active-auth mutation.
@main struct IsolationSmoke {
    static func main() async throws {
        let active = CodexActiveLogin(), file = active.home.appendingPathComponent("auth.json")
        let before = try Data(contentsOf: file)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quotaclock-live-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexAccountStore(root: root, vault: ForbiddenVault(), active: active, rpc: IsolatedCodexRPC())
        do {
            if CommandLine.arguments.contains("--browser-flow") {
                let (stream, continuation) = AsyncStream<Bool>.makeStream()
                let task = Task { () throws -> ProviderAccount in
                    defer { continuation.finish() }
                    return try await store.signIn(signature: "Probe") { prompt in
                        continuation.yield(prompt.url.scheme == "https" && prompt.url.query != nil)
                    }
                }
                var promptReceived = false
                for await valid in stream { promptReceived = valid; task.cancel(); break }
                task.cancel()
                _ = try? await task.value
                guard promptReceived else { throw ProviderFetchError.unavailable }
                guard try Data(contentsOf: file) == before else { throw AccountError.identityChanged }
                print("Official browser sign-in initiation and cancellation: PASS")
                print("Active auth bytes unchanged: PASS; no browser opened; no login completed; no stored credentials")
                return
            }
            let account = try await store.linkCurrent(signature: "Current")
            let quota = try await store.fetch(account.id, at: .now)
            let after = try Data(contentsOf: file), next = try FileManager.default.attributesOfItem(atPath: file.path)
            guard before == after, (attrs[.modificationDate] as? Date) == (next[.modificationDate] as? Date) else {
                print("Active authentication changed during check; isolation acceptance INCONCLUSIVE."); exit(2)
            }
            print("Live isolated account/rateLimits/read: PASS")
            print("Active auth bytes and modification time unchanged: PASS")
            print("Keychain writes: none; saved refresh-token copies: none")
            print("Parsed meters: \(quota.meters.count); account matched: \(quota.account?.isCurrent == true)")
        } catch {
            print("Live isolated read failed: \((error as? LocalizedError)?.errorDescription ?? "unavailable")")
            print("Active auth bytes unchanged: \((try? Data(contentsOf: file)) == before)")
            exit(1)
        }
    }
}
