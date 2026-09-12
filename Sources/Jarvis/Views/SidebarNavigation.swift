import SwiftUI

struct JarvisSidebarNavigation<
    Item: Identifiable & Hashable
>: View {
    let topItems: [Item]
    let bottomItems: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let icon: (Item) -> String
    let footerTitle: String?
    let footerIcon: String?
    let footerIsSelected: Bool
    let footerAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        topItems: [Item],
        bottomItems: [Item] = [],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        icon: @escaping (Item) -> String,
        footerTitle: String? = nil,
        footerIcon: String? = nil,
        footerIsSelected: Bool = false,
        footerAction: (() -> Void)? = nil
    ) {
        self.topItems = topItems
        self.bottomItems = bottomItems
        _selection = selection
        self.title = title
        self.icon = icon
        self.footerTitle = footerTitle
        self.footerIcon = footerIcon
        self.footerIsSelected = footerIsSelected
        self.footerAction = footerAction
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                JarvisOrbMark(diameter: 24)

                Text("JARVIS")
                    .font(JarvisTypography.pageTitle)
                    .tracking(2.4)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 14)
            .padding(.bottom, 12)

            itemGroup(topItems)
                .padding(.horizontal, JarvisMetrics.sidebarContentPadding)
                .padding(.top, JarvisMetrics.sidebarContentPadding)

            Spacer(minLength: 0)

            if !bottomItems.isEmpty {
                itemGroup(bottomItems)
                    .padding(.horizontal, JarvisMetrics.sidebarContentPadding)
                    .padding(.bottom, 4)
            }

            if let footerTitle, let footerIcon, let footerAction {
                Divider()
                    .padding(.horizontal, JarvisMetrics.sidebarContentPadding)

                Button {
                    withAnimation(
                        JarvisMotion.animation(JarvisMotion.sidebarSelection, reduceMotion: reduceMotion)
                    ) {
                        footerAction()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: footerIcon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18, height: 18)
                        Text(footerTitle)
                            .font(footerIsSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                    }
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background {
                        Capsule()
                            .fill(JarvisMotion.selectionPillTint)
                            .opacity(footerIsSelected ? 1 : 0)
                            .scaleEffect(footerIsSelected ? 1 : 0.96)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(footerIsSelected ? Color.white : Color.secondary)
                .padding(JarvisMetrics.sidebarContentPadding)
                .help(footerTitle)
                .accessibilityAddTraits(footerIsSelected ? .isSelected : [])
                .animation(
                    JarvisMotion.animation(JarvisMotion.sidebarSelection, reduceMotion: reduceMotion),
                    value: footerIsSelected
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.jarvisBackground)
    }

    private func itemGroup(_ items: [Item]) -> some View {
        VStack(spacing: 4) {
            ForEach(items) { item in
                primaryRow(item)
            }
        }
    }

    private func primaryRow(_ item: Item) -> some View {
        let isSelected = selection == item
        let foregroundColor: Color = isSelected ? .white : .secondary

        return Button {
            withAnimation(
                JarvisMotion.animation(JarvisMotion.sidebarSelection, reduceMotion: reduceMotion)
            ) {
                selection = item
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon(item))
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18, height: 18)
                Text(title(item))
                    .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 8)
            .background {
                Capsule()
                    .fill(JarvisMotion.selectionPillTint)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.96)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(
            JarvisMotion.animation(JarvisMotion.sidebarSelection, reduceMotion: reduceMotion),
            value: isSelected
        )
        .help(title(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
