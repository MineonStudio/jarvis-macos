import AppKit
import SwiftUI

struct WallpaperSourcesSettingsCard: View {
    @Binding var enabledSourcesStorageValue: String

    private var enabledSources: [WallpaperSource] {
        WallpaperSourcePreferences.enabledSources(from: enabledSourcesStorageValue)
    }

    var body: some View {
        VStack(spacing: SettingsFormMetrics.sectionSpacing) {
            ForEach(WallpaperSource.onlineGalleryCases) { source in
                sourcePanel(source)
            }
        }
    }

    private func sourcePanel(_ source: WallpaperSource) -> some View {
        let isEnabled = enabledSources.contains(source)
        let isOnlyEnabledSource = isEnabled && enabledSources.count == 1

        return JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
                HStack(spacing: 12) {
                    sourceIcon(source)
                        .frame(width: 28, height: 28)

                    Text(source.title)
                        .font(SettingsTypography.cardTitle)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    Toggle(source.title, isOn: Binding(
                        get: { enabledSources.contains(source) },
                        set: { setEnabled($0, source: source) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(isOnlyEnabledSource)
                    .accessibilityLabel("在前台显示\(source.title)")
                }

                if source == .wallhaven {
                    WallhavenAPIKeySettingsCard()
                }
            }
        }
    }

    @ViewBuilder
    private func sourceIcon(_ source: WallpaperSource) -> some View {
        if let url = Bundle.main.url(
            forResource: iconName(for: source),
            withExtension: "png",
            subdirectory: "WallpaperSourceIcons"
        ), let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(3)
                .background(
                    Color.jarvisPanel.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: source.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.jarvisAccent)
                .frame(width: 28, height: 28)
                .background(
                    Color.jarvisAccent.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }

    private func iconName(for source: WallpaperSource) -> String {
        switch source {
        case .wallhaven: "wallhaven"
        case .qihoo: "qihoo"
        case .wikimedia, .local: source.rawValue
        }
    }

    private func setEnabled(_ isEnabled: Bool, source: WallpaperSource) {
        var sources = enabledSources
        if isEnabled {
            if !sources.contains(source) {
                sources.append(source)
            }
        } else {
            guard sources.count > 1 else { return }
            sources.removeAll { $0 == source }
        }
        enabledSourcesStorageValue = WallpaperSourcePreferences.storageValue(for: sources)
    }
}
