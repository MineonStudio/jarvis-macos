import SwiftUI

struct JarvisHomeView: View {
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
                    JarvisOrbView(
                        diameter: min(max(geometry.size.width * 0.42, 320), 480)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(40)
            }
        )
    }
}
