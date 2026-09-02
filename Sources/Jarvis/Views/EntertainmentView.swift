import SwiftUI

struct EntertainmentView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showsDownloadManager = false

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: JarvisToolbarMetrics.controlSpacing) {
                        JarvisToolbarGroupedPicker(
                            items: EntertainmentPlatform.allCases,
                            selection: selectedPlatform,
                            title: { $0.title },
                            icon: { platform, isSelected in
                                Group {
                                    if platform == .x {
                                        Text("X")
                                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    } else {
                                        Image(systemName: platform.systemImage)
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            }
                        )
                        JarvisWebPlatformBrowserControls(controller: currentController)
                    }
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    JarvisWebPlatformDownloadButton(
                        controller: currentController,
                        showsDownloadManager: $showsDownloadManager,
                        emptyHint: "在娱乐页面点击文件下载后，任务会显示在这里"
                    )
                }
            },
            content: {
                JarvisWebPlatformBrowserPage(controller: currentController)
                    .id(app.selectedEntertainmentPlatform)
            }
        )
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
