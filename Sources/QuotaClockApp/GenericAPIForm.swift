import SwiftUI
import QuotaCore

struct GenericAPIForm: View {
    @ObservedObject var model: SnapshotController
    var onAdded: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var apiModel = ""
    private func t(_ value: String) -> String { AppText.value(value, model.preferences.language) }
    private var config: GenericAPIConfiguration { .init(name: name, baseURL: baseURL, model: apiModel) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Add API Provider")).font(.title2.weight(.semibold))
            Text(t("Only requests made through QuotaClock are counted. Requests from other apps and account quotas are not available here."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow { Text(t("Provider Name")); TextField(t("Provider Name"), text: $name) }
                GridRow { Text(t("Protocol")); Text("Responses").foregroundStyle(.secondary) }
                GridRow { Text(t("Base URL")); TextField("https://api.example.com/v1", text: $baseURL) }
                GridRow { Text(t("API Key")); SecureField(t("API Key"), text: $apiKey) }
                GridRow { Text(t("Model")); TextField(t("Model"), text: $apiModel) }
            }.textFieldStyle(.roundedBorder)
            Text(t("Validation sends a tiny fixed request and may incur a small API charge. Automatic refresh sends no model requests."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let feedback = model.apiFeedback { Text(t(feedback)).font(.caption).textSelection(.enabled) }
            HStack {
                Button(t("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.validatingAPI)
                Spacer()
                if model.validatingAPI { ProgressView().controlSize(.small) }
                Button(t(model.validatingAPI ? "Validating…" : "Validate & Add")) {
                    let pending = config
                    Task {
                        if await model.validateAndAdd(pending, key: apiKey) {
                            apiKey = ""; onAdded(pending.providerID); dismiss()
                        }
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(model.validatingAPI || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (try? config.endpoint()) == nil)
            }
        }.padding(24).frame(width: 460).font(.system(size: 13))
            .interactiveDismissDisabled(model.validatingAPI)
            .onDisappear { apiKey = "" }
    }
}
