import SwiftUI
import QuotaCore

struct ProviderEngineSettingsView: View {
    let definition: ProviderEngineDefinition
    let saved: () -> Void
    @State private var settings = ProviderEngineSettings()
    @State private var feedback: String?
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CodexBar 数据引擎 · 仅在启用此服务后读取。先完成对应工具登录，或填写此服务的凭证。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("数据源", selection: $settings.source) {
                ForEach(definition.sources, id: \.self) { Text($0.uppercased()).tag($0) }
            }
            SecureField("API Key / Access Token（如需要）", text: $settings.apiKey)
            SecureField("Cookie Header（如需要）", text: $settings.cookieHeader)
            Toggle("允许为此服务读取浏览器登录状态", isOn: $settings.automaticCookies)
            DisclosureGroup("区域与服务配置") {
                TextField("Region", text: $settings.region)
                TextField("Endpoint / Enterprise Host", text: $settings.enterpriseHost)
                TextField("Workspace / Project / Deployment ID", text: $settings.workspaceID)
            }
            HStack {
                Button("保存并刷新") {
                    do { try ProviderEngineConfiguration.save(settings, provider: definition.id); feedback = "已保存"; saved() }
                    catch { feedback = "配置保存失败，请检查数据源和文件权限。" }
                }.disabled(!loaded)
                Link("接入说明", destination: URL(string: "https://github.com/steipete/CodexBar/blob/\(ProviderEngineCatalog.revision)/docs/providers.md")!)
            }
            Text("凭证存于本机 QuotaClock 专属配置文件（仅当前用户可读写），不会写入小组件快照。浏览器读取默认关闭。")
                .font(.caption2).foregroundStyle(.secondary)
            if let feedback { Text(feedback).font(.caption) }
        }.textFieldStyle(.roundedBorder).task {
            do { settings = try ProviderEngineConfiguration.load(definition.id); loaded = true }
            catch { feedback = "现有配置无法读取；为保护原配置，暂不覆盖。" }
        }
    }
}
