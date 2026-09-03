import AppKit
import SwiftUI

struct EntertainmentView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showsDownloadManager = false

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    JarvisToolbarGroupedPicker(
                        items: EntertainmentPlatform.allCases,
                        selection: selectedPlatform,
                        title: { $0.title },
                        icon: { platform, _ in
                            EntertainmentPlatformIcon(platform: platform)
                        }
                    )
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    JarvisWebPlatformActionCluster(
                        controller: currentController,
                        showsDownloadManager: $showsDownloadManager,
                        activeDownloadCount: app.entertainmentVideoDownloads.activeCount,
                        downloadHelp: "视频下载"
                    ) {
                        EntertainmentVideoDownloadView(
                            manager: app.entertainmentVideoDownloads,
                            initialURL: currentController.currentURL
                        )
                        .frame(width: 360, height: 420)
                    }
                }
            },
            content: {
                JarvisWebPlatformBrowserPage(controller: currentController)
                    .id(app.selectedEntertainmentPlatform)
            }
        )
        .onAppear {
            app.resumeSelectedEntertainmentMedia()
        }
        .onDisappear {
            app.suspendSelectedEntertainmentMedia()
        }
    }

    private var selectedPlatform: Binding<EntertainmentPlatform> {
        Binding(
            get: { app.selectedEntertainmentPlatform },
            set: { app.selectEntertainmentPlatform($0) }
        )
    }

    private var currentController: JarvisWebPlatformController {
        app.entertainmentController(for: app.selectedEntertainmentPlatform)
    }
}

struct EntertainmentPlatformIcon: View {
    let platform: EntertainmentPlatform

    var body: some View {
        Group {
            if let image = Self.image(for: platform) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: platform.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private static func image(for platform: EntertainmentPlatform) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: platform.iconResourceName,
            withExtension: platform.iconResourceExtension,
            subdirectory: "EntertainmentIcons"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        return image
    }
}
