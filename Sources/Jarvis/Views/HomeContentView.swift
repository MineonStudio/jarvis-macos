import SwiftUI

struct JarvisHomeView: View {
    let pointerTracker: JarvisHomePointerTracker

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
                    let mascotFrame = geometry.frame(in: .named(ContentView.homePointerCoordinateSpace))
                    let pointerDirection = pointerTracker.location.map { location in
                        CGSize(
                            width: min(max((location.x - mascotFrame.midX) / (geometry.size.width * 0.5), -1), 1),
                            height: min(max((location.y - mascotFrame.midY) / (geometry.size.height * 0.5), -1), 1)
                        )
                    }

                    JarvisMascotView(diameter: diameter, pointerDirection: pointerDirection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(40)
            }
        )
    }
}
