import SwiftUI
import QuotaCore

/// Every saved connection has the same labelled nickname and explicit rename action.
struct ProviderNicknameField<Actions: View, Footer: View>: View {
    let value: String
    let language: AppLanguage
    let allowsEmpty: Bool
    let rename: (String) -> Void
    let actions: Actions
    let footer: Footer
    @State private var draft = ""
    init(value: String, language: AppLanguage, allowsEmpty: Bool = false,
         rename: @escaping (String) -> Void,
         @ViewBuilder actions: () -> Actions = { EmptyView() },
         @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.value = value
        self.language = language
        self.allowsEmpty = allowsEmpty
        self.rename = rename
        self.actions = actions()
        self.footer = footer()
    }
    private func t(_ key: String) -> String { AppText.value(key, language) }
    private var canRename: Bool {
        draft != value && (ProviderAccount.validSignature(draft) || (allowsEmpty && draft.isEmpty))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(t("Nickname"))
                TextField(t("Nickname"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit { if canRename { rename(draft) } }
                Button { rename(draft) } label: {
                    Image(systemName: "pencil").frame(width: 20, height: 20)
                }.controlSize(.small).disabled(!canRename)
                    .help(t("Rename")).accessibilityLabel(t("Rename"))
                actions
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text(t("Use 1–12 English letters for the nickname."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                footer
            }
        }.onAppear { draft = value }
            .onChange(of: value) { _, newValue in draft = newValue }
    }
}
