import AppKit
import QuotaCore

extension SnapshotController {
    var connectedSources: [String] {
        let known = accounts.map(\.sourceID) + ProviderCatalog.providers.map(\.id).filter { $0 != "codex" && enabled($0) } + customAPIs.map(\.providerID)
        var result: [String] = []
        for id in (platform.connectionOrder ?? []) + known where known.contains(id) && !result.contains(id) { result.append(id) }
        return result
    }
    var displaySources: [String] { connectedSources.filter { enabled($0) } }
    /// Upgrade existing connections once. Linking only reads the active Codex session.
    func enableAccountConnections() async throws {
        guard !platform.codexMultiAccount else { return }
        let saved = try await codexAccounts.accounts()
        var next = platform
        if next.enabledProducts.contains("codex.subscription"), let identity = await codexAccounts.currentIdentity() {
            let current: ProviderAccount
            if let existing = saved.first(where: { $0.identityKey == identity }) { current = existing }
            else {
                let names = ["Main", "Personal", "Current", "Default"]
                let name = names.first { candidate in !saved.contains { $0.signature.lowercased() == candidate.lowercased() } } ?? "Codex"
                current = try await codexAccounts.linkCurrent(signature: name)
            }
            next.enabledProducts.insert(current.productID)
            next.display[current.sourceID] = next.display["codex"]
            next.menuOrder = next.menuOrder.map { $0 == "codex" ? current.sourceID : $0 }
            next.saverOrder = next.saverOrder.map { $0 == "codex" ? current.sourceID : $0 }
        }
        next.codexMultiAccount = true
        try next.save(); platform = next
    }
    func initializeDisplayOrdering() throws {
        guard platform.providerDisplay == nil else { return }
        var next = platform
        next.connectionOrder = connectedSources
        next.providerDisplay = ProviderDisplayConfiguration()
        try next.save(); platform = next
    }
    var heroProviderIDs: [String] {
        var result: [String] = []
        for source in connectedSources {
            let family = accounts.first { $0.sourceID == source }?.providerID ?? source
            if !result.contains(family) { result.append(family) }
        }
        return result
    }
    var selectedHeroProviderID: String {
        let saved = displayConfiguration.heroProviderID
        return heroProviderIDs.first { $0 == saved } ?? heroProviderIDs.first ?? ""
    }
    var displayConfiguration: ProviderDisplayConfiguration { platform.providerDisplay ?? .init() }
    func cancelAddingProvider(_ id: String) {
        if id == "codex", let task = signInTask {
            cancelCodexSignIn()
            Task {
                await task.value
                // A login already committed to storage wins this race; never remove it.
                providerSetup.cancelAdding(id)
            }
        } else if !signingIn {
            providerSetup.cancelAdding(id)
        }
    }
    func observeCurrentCodexAccount() async {
        guard platform.codexMultiAccount, coordinator != nil, switchingAccountID == nil else { return }
        let identity = await codexAccounts.currentIdentity()
        guard identity != currentCodexIdentity else { return }
        await reloadAccounts()
        if let current = accounts.first(where: { $0.identityKey == currentCodexIdentity }), platform.isProductEnabled(current.productID) {
            refreshProduct(current.productID)
        }
    }
    func reloadAccounts() async {
        guard !onboardingPreview else { return }
        if let pending = accountReloadTask {
            await pending.value
            // A login/removal may have completed while the previous read was in flight.
            await reloadAccounts()
            return
        }
        let task = Task {
            defer { accountReloadTask = nil }
            await readAndRegisterAccounts()
        }
        accountReloadTask = task
        await task.value
    }
    private func readAndRegisterAccounts() async {
        do {
            let loaded = try await codexAccounts.accounts()
            let identity = await codexAccounts.currentIdentity()
            let revision = await codexAccounts.currentCredentialRevision()
            let changed = loaded != accounts || currentCodexIdentity != identity || currentCodexCredentialRevision != revision
            for old in accounts where !loaded.contains(where: { $0.id == old.id }) { await coordinator?.unregister(old.productID) }
            let changedAccounts: [any ProductAdapter] = loaded.filter { !accounts.contains($0) || currentCodexIdentity != identity ||
                (($0.connection == .currentSession || $0.credentialsHandedToCodex == true) && currentCodexCredentialRevision != revision)
            }.map { CodexAccountAdapter(account: $0, currentIdentity: identity, store: codexAccounts) }
            await coordinator?.register(changedAccounts)
            accounts = loaded; currentCodexIdentity = identity
            currentCodexCredentialRevision = revision
            // Publish the new identity immediately, even if quota refresh is slow or in backoff.
            if changed, let coordinator { show(try await coordinator.configure(platform)) }
        } catch { accountFeedback = accountMessage(error) }
    }
    func accountAdded(_ account: ProviderAccount, isNew: Bool) async throws {
        await reloadAccounts()
        guard accounts.contains(where: { $0.id == account.id }) else { throw AccountError.storage }
        var setup = providerSetup
        let order = setup.connected(providerID: account.providerID, sourceID: account.sourceID,
                                    isNew: isNew, order: connectedSources)
        var next = platform
        next.enabledProducts.insert(account.productID)
        next.reorderConnections(order, available: connectedSources)
        if !next.menuOrder.contains(account.sourceID) { next.menuOrder.append(account.sourceID) }
        if !next.saverOrder.contains(account.sourceID) { next.saverOrder.append(account.sourceID) }
        try next.save(); platform = next
        providerSetup = setup
        accountFeedback = nil
        if let coordinator { show(try await coordinator.configure(next)) }
        refreshProduct(account.productID)
    }
    func linkCodex(signature: String) {
        guard !onboardingPreview else { return }
        guard !signingIn, switchingAccountID == nil else { return }
        signingIn = true; accountFeedback = nil
        providerSetup.beginConnection()
        Task {
            defer { signingIn = false }
            do { try await accountAdded(codexAccounts.linkCurrent(signature: signature), isNew: true) }
            catch { accountFeedback = accountMessage(error) }
        }
    }
    func signInCodex(signature: String, replacing account: ProviderAccount? = nil) {
        guard !onboardingPreview else { return }
        guard !signingIn, switchingAccountID == nil else { return }
        signingIn = true; accountFeedback = nil; signInPrompt = nil
        providerSetup.beginConnection()
        let isNew = account == nil
        let requestID = UUID(); signInRequestID = requestID
        signInTask = Task {
            defer { signingIn = false; signInPrompt = nil; signInTask = nil; signInRequestID = nil }
            do {
                let account = try await codexAccounts.signIn(signature: signature, replacing: account?.id) { prompt in
                    Task { @MainActor in
                        guard self.signInRequestID == requestID else { return }
                        self.signInPrompt = prompt
                        if !NSWorkspace.shared.open(prompt.url) {
                            self.accountFeedback = "Could not open your browser. Copy the sign-in link and open it in a browser on this Mac."
                        }
                    }
                }
                try await accountAdded(account, isNew: isNew)
            } catch is CancellationError { accountFeedback = nil }
            catch { accountFeedback = accountMessage(error) }
        }
    }
    func cancelCodexSignIn() {
        signInRequestID = nil
        signInTask?.cancel()
    }
    func reorderConnections(_ order: [String]) {
        var next = platform
        next.reorderConnections(order, available: connectedSources)
        savePlatform(next)
    }
    func renameAccount(_ account: ProviderAccount, signature: String) {
        guard !onboardingPreview else { return }
        Task {
            do {
                try await codexAccounts.rename(account.id, signature: signature)
                await reloadAccounts()
                if let coordinator { show(try await coordinator.configure(platform)) }
                accountFeedback = nil
            } catch { accountFeedback = accountMessage(error) }
        }
    }
    func removeAccount(_ account: ProviderAccount) {
        guard !onboardingPreview else { return }
        Task {
            do {
                // The store refuses removal while its token is being rotated.
                try await codexAccounts.remove(account.id)
                await coordinator?.unregister(account.productID)
                var next = platform; next.enabledProducts.remove(account.productID); next.display[account.sourceID] = nil
                next.menuOrder.removeAll { $0 == account.sourceID }; next.saverOrder.removeAll { $0 == account.sourceID }
                try next.save(); platform = next
                await reloadAccounts()
                if let coordinator {
                    if let updated = try? await coordinator.configure(next) { show(updated) }
                }
                accountFeedback = nil
            } catch { accountFeedback = accountMessage(error) }
        }
    }
    func accountMessage(_ error: Error) -> String {
        (error as? CodexSwitchError)?.errorDescription ?? (error as? CodexDesktopSwitchError)?.errorDescription ??
        (error as? AccountError)?.errorDescription ?? (error as? ProviderFetchError)?.errorDescription ?? "Could not access secure account storage."
    }

    func switchCodexAccount(_ account: ProviderAccount) {
        guard !onboardingPreview, !signingIn, switchingAccountID == nil,
              account.switchOption(currentIdentity: currentCodexIdentity).canSwitch else { return }
        switchingAccountID = account.id
        accountFeedback = nil; accountSwitchFeedback = nil; accountSwitchStage = "Checking account…"
        let expectedIdentity = currentCodexIdentity
        Task {
            // Release switching state before quota work below. Do not defer this
            // cleanup across reloadAccounts: a later user switch may already start.
            let desktop = CodexDesktopSwitch(progress: { [weak controller = self] stage in controller?.accountSwitchStage = stage })
            var switched = false
            do {
                _ = try desktop.preflight()
                let before = Set(accounts.map(\.id))
                let saved = try await codexAccounts.switchAccount(to: account.id, expectedCurrentIdentity: expectedIdentity) {
                    try await desktop.stop()
                    await MainActor.run { self.accountSwitchStage = "Saving login…" }
                }
                switched = true
                guard await codexAccounts.currentIdentity() == account.identityKey else { throw CodexSwitchError.loginChanged }
                accounts = saved; currentCodexIdentity = account.identityKey
                var next = platform
                for newAccount in saved where !before.contains(newAccount.id) {
                    next.enabledProducts.insert(newAccount.productID)
                    next.connectionOrder = (next.connectionOrder ?? []) + [newAccount.sourceID]
                }
                try next.save(); platform = next
                // Publish identity before reopening Desktop. Assigning currentCodexIdentity
                // above makes the ordinary change detector miss this update, so explicitly
                // replace every adapter's account marker in one coordinator turn.
                if let coordinator {
                    await coordinator.register(saved.map { CodexAccountAdapter(account: $0, currentIdentity: account.identityKey, store: codexAccounts) })
                    if let updated = try? await coordinator.configure(next) { show(updated) }
                    // Quota I/O overlaps Desktop launch, and each result republishes Widgets.
                    Task {
                        await coordinator.refresh(productID: account.productID) { value in
                            await MainActor.run { self.show(value) }
                        }
                    }
                }
                // Reopen immediately after the credential transaction, before any quota work.
                try await desktop.reopen(launchIfClosed: true)
                accountFeedback = "Codex login switched."
                accountSwitchFeedback = accountFeedback
            } catch {
                let failure = accountMessage(error)
                if let switchError = error as? CodexSwitchError, case .recoveryRequired = switchError {
                    // Do not restart a credential writer while recovery owns the journal.
                    accountFeedback = failure
                } else if !switched {
                    accountSwitchStage = "Restoring Codex…"
                    do {
                        try await desktop.reopen(launchIfClosed: false)
                        accountFeedback = failure
                    } catch {
                        accountFeedback = "Switch did not complete. Open Codex manually and check the signed-in account."
                    }
                } else {
                    accountFeedback = "The login was switched. Open Codex manually to continue."
                }
                accountSwitchFeedback = accountFeedback
            }
            switchingAccountID = nil; accountSwitchStage = nil
            await reloadAccounts()
            Task { await refreshAll() }
        }
    }
}
