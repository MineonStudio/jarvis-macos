import SwiftUI

struct JarvisHomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    EmptyView()
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    EmptyView()
                }
            },
            content: {
                GeometryReader { geometry in
                    let diameter = min(max(geometry.size.width * 0.42, 320), 480)
                    let isSystemDark = app.activeColorScheme == .dark

                    Group {
                        if let image = JarvisDockIconController.shared.previewImage(
                            for: app.appIconAppearance,
                            isSystemDark: isSystemDark
                        ) {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .accessibilityLabel("Jarvis 机器人")
                        } else {
                            JarvisOrbMark(diameter: diameter * 0.72)
                        }
                    }
                    .frame(width: diameter, height: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(40)
            }
        )
    }
}
