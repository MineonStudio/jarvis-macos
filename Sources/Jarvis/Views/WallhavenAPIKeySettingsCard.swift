import SwiftUI

struct WallhavenAPIKeySettingsCard: View {
    @State private var keyDraft = ""
    @State private var isConfigured = false
    @State private var isEditing = true
    @State private var message: String?
    @State private var showingDeleteConfirmation = false
    @State private var showingAPIKeyHelp = false

    private var trimmedKey: String {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Text("API Key")
                        .font(SettingsTypography.itemTitle)

                    Button {
                        showingAPIKeyHelp.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Wallhaven API Key 帮助")
                    .popover(isPresented: $showingAPIKeyHelp, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("填写后可显示 NSFW 壁纸；留空仍可正常浏览其他内容。")
                                .font(SettingsTypography.itemSubtitle)
                                .foregroundStyle(Color.jarvisTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Link("去获取", destination: URL(string: "https://wallhaven.cc/settings/account")!)
                                .font(SettingsTypography.itemSubtitle)
                        }
                        .padding(12)
                        .frame(width: 260, alignment: .leading)
                    }
                }
                .frame(width: 84, alignment: .leading)

                apiControl {
                    if isLocked {
                        Text("••••••••")
                            .font(JarvisTypography.control)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    } else {
                        SecureField(
                            isConfigured ? "输入新的 API Key" : "输入 API Key",
                            text: $keyDraft
                        )
                        .textFieldStyle(.plain)
                        .textContentType(.password)
                        .accessibilityLabel("Wallhaven API Key")
                    }
                }

                actionsRow
            }

            if let message {
                Text(message)
                    .font(SettingsTypography.itemSubtitle)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refreshStatus)
        .confirmationDialog(
            "删除 Wallhaven API 配置？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除配置", role: .destructive, action: removeKey)
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，搜索将不再包含 NSFW 壁纸。")
        }
    }

    private var isLocked: Bool {
        isConfigured && !isEditing
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            if isLocked {
                Button("编辑", action: beginEditing)
                    .buttonStyle(JarvisSecondaryButtonStyle())
                Button("删除", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
            } else {
                Button("保存", action: saveKey)
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(trimmedKey.isEmpty)

                if isConfigured {
                    Button("取消", action: cancelEditing)
                        .buttonStyle(JarvisSecondaryButtonStyle())
                }
            }
        }
        .fixedSize()
    }

    private func apiControl(
        @ViewBuilder content: () -> some View
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: SettingsFormMetrics.controlHeight, alignment: .leading)
            .padding(.horizontal, 10)
            .background(
                Color.jarvisPanel.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }

    private func refreshStatus() {
        do {
            isConfigured = try !(WallhavenAPIKeyStore.shared.read() ?? "").isEmpty
            isEditing = !isConfigured
            message = nil
        } catch {
            isConfigured = false
            isEditing = true
            message = "读取本地配置失败：\(error.localizedDescription)"
        }
    }

    private func beginEditing() {
        keyDraft = ""
        message = nil
        isEditing = true
    }

    private func cancelEditing() {
        keyDraft = ""
        message = nil
        isEditing = false
    }

    private func saveKey() {
        do {
            try WallhavenAPIKeyStore.shared.write(trimmedKey)
            keyDraft = ""
            isConfigured = true
            isEditing = false
            message = nil
        } catch {
            message = "保存配置失败：\(error.localizedDescription)"
        }
    }

    private func removeKey() {
        do {
            try WallhavenAPIKeyStore.shared.delete()
            keyDraft = ""
            isConfigured = false
            isEditing = true
            message = nil
        } catch {
            message = "删除配置失败：\(error.localizedDescription)"
        }
    }
}
