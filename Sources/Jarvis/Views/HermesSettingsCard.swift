import SwiftUI

struct HermesSettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var showingUninstallOptions = false
    @State private var showingUninstallConfirmation = false
    @State private var pendingUninstallMode: HermesUninstallMode?

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCardHeader(title: "Hermes", systemImage: "terminal")

                HStack(alignment: .top, spacing: 12) {
                    statusIndicator

                    VStack(alignment: .leading, spacing: 5) {
                        Text(statusTitle)
                            .font(JarvisTypography.bodyEmphasis)
                        Text(statusMessage)
                            .font(JarvisTypography.secondary)
                            .foregroundStyle(Color.jarvisTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    action
                }

                if let errorMessage = app.hermesUninstallErrorMessage {
                    Text(errorMessage)
                        .font(JarvisTypography.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            app.refreshHermesStatus()
        }
        .confirmationDialog(
            "选择卸载方式",
            isPresented: $showingUninstallOptions,
            titleVisibility: .visible
        ) {
            Button(HermesUninstallMode.standard.choiceTitle) {
                selectUninstallMode(.standard)
            }
            Button(HermesUninstallMode.complete.choiceTitle, role: .destructive) {
                selectUninstallMode(.complete)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "普通卸载：\(HermesUninstallMode.standard.choiceDescription)\n\n"
                    + "完全卸载：\(HermesUninstallMode.complete.choiceDescription)"
            )
        }
        .confirmationDialog(
            pendingUninstallMode?.confirmationTitle ?? "确认卸载 Hermes？",
            isPresented: $showingUninstallConfirmation,
            titleVisibility: .visible
        ) {
            if let pendingUninstallMode {
                Button(pendingUninstallMode.actionTitle, role: .destructive) {
                    app.uninstallHermes(mode: pendingUninstallMode)
                    self.pendingUninstallMode = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingUninstallMode = nil
            }
        } message: {
            Text(pendingUninstallMode?.confirmationMessage ?? "")
        }
    }

    private var statusIndicator: some View {
        Circle()
            .fill(app.hermesIsInstalled ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 8, height: 8)
            .padding(.top, 6)
    }

    private var statusTitle: String {
        if app.hermesUninstallIsBusy {
            return "正在卸载 Hermes…"
        }
        if !app.hermesIsInstalled {
            return "尚未安装"
        }
        return app.hermesProfileReady ? "已安装 · JARVIS Profile 已就绪" : "已安装 · 尚未完成 JARVIS 设置"
    }

    private var statusMessage: String {
        if app.hermesIsInstalled {
            return "Hermes CLI 负责在本机执行 JARVIS 任务。"
        }
        return "可在对话页一键部署 Hermes。"
    }

    @ViewBuilder
    private var action: some View {
        if app.hermesUninstallIsBusy {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 78, minHeight: 28)
        } else if app.hermesIsInstalled {
            Button("卸载 Hermes", role: .destructive) {
                showingUninstallOptions = true
            }
            .buttonStyle(JarvisToolbarButtonStyle(tint: .red))
            .disabled(app.hermesIsBusy || app.hermesChatIsSending)
            .help(disabledActionHelp)
        } else {
            Button("去对话部署") {
                app.selectedSection = .conversation
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }

    private var disabledActionHelp: String {
        if app.hermesIsBusy {
            return "Hermes 部署进行中，完成后才能卸载"
        }
        if app.hermesChatIsSending {
            return "当前对话结束后才能卸载 Hermes"
        }
        return "卸载 Hermes"
    }

    private func selectUninstallMode(_ mode: HermesUninstallMode) {
        pendingUninstallMode = mode
        DispatchQueue.main.async {
            showingUninstallConfirmation = true
        }
    }
}
