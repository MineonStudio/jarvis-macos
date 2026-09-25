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

                    JarvisMascotShape()
                        .fill(
                            app.activeColorScheme == .dark ? .white : Color.jarvisAccent,
                            style: FillStyle(eoFill: true)
                        )
                        .frame(width: diameter, height: diameter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Jarvis 机器人")
                }
                .padding(40)
            }
        )
    }
}
