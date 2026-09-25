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
                    let diameter = min(max(geometry.size.width * 0.42, 320), 480)

                    JarvisMascotView(diameter: diameter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(40)
            }
        )
    }
}
