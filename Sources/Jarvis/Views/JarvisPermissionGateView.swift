import AppKit
import SwiftUI

struct JarvisPermissionGateOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.16))
                .ignoresSafeArea()
                .contentShape(Rectangle())

            JarvisPermissionGateView(onDismiss: onDismiss)
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
        }
        .onAppear {
            app.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissionStatus()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("先让我帮得上忙")
    }
}

struct JarvisPermissionGateView: View {
    @Environment(AppModel.self) private var app
    let onDismiss: () -> Void

    private var remainingCount: Int {
        JarvisRequiredPermission.allCases.count { !app.isRequiredPermissionGranted($0) }
    }

    private var invitationLine: String {
        switch remainingCount {
        case 0: "都好了，我们开始。"
        case 1: "就差这一步了。"
        default: "打开这些，我们就开始。"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 12) {
                JarvisOrbMark(diameter: 58)

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭权限提示")
                .help("稍后在设置中处理权限")
            }

            VStack(spacing: 7) {
                Text("先让我帮得上忙")
                    .font(JarvisTypography.pageTitle)
                    .multilineTextAlignment(.center)
                Text(invitationLine)
                    .font(JarvisTypography.secondary)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
                Text("可以先关闭，之后在设置中继续开启")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                ForEach(Array(JarvisRequiredPermission.allCases.enumerated()), id: \.element.id) { index, permission in
                    permissionRow(permission)
                    if index < JarvisRequiredPermission.allCases.count - 1 {
                        Divider()
                            .opacity(0.45)
                            .padding(.leading, 50)
                    }
                }
            }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(width: 400)
        .jarvisGlass(cornerRadius: 24, interactive: false)
        .shadow(color: Color.black.opacity(0.16), radius: 32, y: 14)
    }

    private func permissionRow(_ permission: JarvisRequiredPermission) -> some View {
        let isGranted = app.isRequiredPermissionGranted(permission)
        return HStack(spacing: 12) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isGranted ? Color.green : Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    (isGranted ? Color.green : Color.accentColor).opacity(0.12),
                    in: Circle()
                )

            Text(permission.title)
                .font(JarvisTypography.bodyEmphasis)
                .foregroundStyle(isGranted ? Color.jarvisTextSecondary : Color.primary)

            Spacer(minLength: 8)

            if isGranted {
                Text("已就绪")
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(permission.title)已就绪")
            } else {
                Button("允许") {
                    app.requestRequiredPermission(permission)
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .controlSize(.small)
                .accessibilityLabel("允许\(permission.title)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .animation(JarvisMotion.selection, value: isGranted)
    }
}
