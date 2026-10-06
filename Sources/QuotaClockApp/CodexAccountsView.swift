import SwiftUI
import AppKit
import QuotaCore

struct CodexAccountsView: View {
    @ObservedObject var model: SnapshotController
    var selectedAccountID: String?
    @State private var signature = ""
    @State private var removing: ProviderAccount?
    @State private var copiedSignInLink = false
    private func t(_ key: String) -> String { AppText.value(key, model.preferences.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedAccountID, model.providerSetup.completedSourceID == selectedAccountID,
               let account = model.accounts.first(where: { $0.sourceID == selectedAccountID }) {
                Label(t(account.connection == .currentSession ? "Account linked successfully." : "Signed in successfully."),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            if selectedAccountID == nil {
                Text(t("Monitor multiple Codex accounts independently without affecting your current Codex login."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Group {
                ForEach(model.accounts.filter { $0.sourceID == selectedAccountID }) { account in
                    CodexAccountRow(model: model, account: account, remove: { removing = account })
                }
                if selectedAccountID == nil {
                HStack {
                    Text(t("Nickname"))
                    TextField(t("Nickname"), text: $signature).textFieldStyle(.roundedBorder)
                }
                Text(t("Use 1–12 English letters for the signature.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(t("Use Current Account")) { model.linkCodex(signature: signature) }
                        .disabled(model.currentCodexIdentity == nil)
                        .help(t("Read your current Codex login without saving credentials. Monitoring stops when you sign out of or switch Codex accounts."))
                    Button(t("Add Independent Account…")) { model.signInCodex(signature: signature) }
                        .help(t("Sign in and save credentials in QuotaClock for ongoing monitoring and one-click account switching."))
                }.disabled(!ProviderAccount.validSignature(signature) || model.signingIn || model.switchingAccountID != nil)
                Text(t("Using the current account does not save credentials. QuotaClock saves credentials for independent accounts, enabling ongoing monitoring and one-click switching."))
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.signingIn {
                VStack(alignment: .leading, spacing: 8) {
                    if let prompt = model.signInPrompt {
                        Text(t("Sign in with the account you want to monitor."))
                        Text(t("Finish signing in in your browser, then return here. No device code is needed."))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Link(t("Open Sign-in Page"), destination: prompt.url)
                            Button(t(copiedSignInLink ? "Link Copied" : "Copy Sign-in Link")) {
                                NSPasteboard.general.clearContents()
                                copiedSignInLink = NSPasteboard.general.setString(prompt.url.absoluteString, forType: .string)
                            }
                        }
                    } else { ProgressView(t("Preparing sign-in…")).controlSize(.small) }
                    Button(t("Cancel")) { model.cancelCodexSignIn() }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            if let message = model.accountFeedback { Text(t(message)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .onChange(of: model.signInPrompt?.url) { _, _ in copiedSignInLink = false }
        .confirmationDialog(t("Remove this account from QuotaClock?"), isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                if let removing { Button(t("Remove"), role: .destructive) { model.removeAccount(removing) } }
            } message: { Text(t("This removes its saved monitoring credentials. Codex remains signed in.")) }
    }
}

private struct CodexAccountRow: View {
    @ObservedObject var model: SnapshotController
    let account: ProviderAccount
    var remove: () -> Void
    private func t(_ key: String) -> String { AppText.value(key, model.preferences.language) }
    private var provider: ProviderQuota? { model.snapshot?.providers.first { $0.id == account.sourceID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(t("Enabled"))
                if account.identityKey == model.currentCodexIdentity {
                    Text(t("Current Codex Login")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(t("Enabled"), isOn: Binding(get: { model.platform.enabledProducts.contains(account.productID) },
                    set: { model.setProduct(account.productID, enabled: $0) })).labelsHidden().toggleStyle(CompactSwitchStyle())
            }
            if let email = account.email { Text(email).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Text(t(account.connection == .currentSession || account.credentialsHandedToCodex == true ? "Linked to Codex" : "Independent login"))
                if let plan = provider?.planName ?? account.plan { Text("· " + plan) }
                Spacer()
                Text(t(provider?.health?.state.displayName ?? "Waiting"))
            }.font(.caption).foregroundStyle(.secondary)
            if let reason = provider?.health?.reason { Text(t(reason)).font(.caption).foregroundStyle(.secondary) }
            ProviderNicknameField(value: account.signature, language: model.preferences.language, rename: {
                model.renameAccount(account, signature: $0)
            }, actions: {
                HStack(spacing: 8) {
                    Button(t("Refresh")) { model.refreshProduct(account.productID) }
                        .disabled(!model.platform.isProductEnabled(account.productID))
                    Button(t(account.connection == .currentSession ? "Sign In" : "Sign In Again")) {
                        model.signInCodex(signature: account.signature, replacing: account)
                    }.disabled(model.signingIn)
                }.controlSize(.small).fixedSize()
            }, footer: {
                Button(t("Remove"), role: .destructive, action: remove).disabled(model.signingIn)
                    .controlSize(.small)
            })
            if model.platform.isProductEnabled(account.productID) {
                ProviderResetTimes(provider: provider, language: model.preferences.language)
                if let success = provider?.health?.lastSuccess { Text("\(t("Last success")) \(success.formatted())").font(.caption).foregroundStyle(.secondary) }
            }
            if account.identityKey == model.currentCodexIdentity {
                Label(t("Current Codex Login"), systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if account.connection == .independent && account.credentialsHandedToCodex != true {
                HStack {
                    Button(t(model.switchingAccountID == account.id ? "Switching…" : "Switch to This Account")) {
                        model.switchCodexAccount(account)
                    }.disabled(model.signingIn || model.switchingAccountID != nil)
                    Text(t(model.accountSwitchStage ?? "Automatically closes Codex, saves the current login and reopens with this account. Running tasks will be interrupted."))
                        .font(.caption).foregroundStyle(.secondary)
                }.controlSize(.small)
            } else {
                Text(t("Sign in to this account before switching to it."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.switchingAccountID != nil)
    }
}
