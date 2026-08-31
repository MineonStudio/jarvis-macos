import SwiftUI

struct JarvisSidebarSecondaryMenu<Parent: Hashable, Item: Identifiable & Hashable> {
    let parent: Parent
    let items: [Item]
}

struct JarvisSidebarNavigation<
    Item: Identifiable & Hashable,
    SecondaryItem: Identifiable & Hashable
>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let icon: (Item) -> String
    let secondaryMenus: [JarvisSidebarSecondaryMenu<Item, SecondaryItem>]
    @Binding var secondarySelection: SecondaryItem
    let secondaryTitle: (SecondaryItem) -> String
    let secondaryIcon: (SecondaryItem, Bool) -> AnyView
    let footerTitle: String?
    let footerIcon: String?
    let footerIsSelected: Bool
    let footerAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        icon: @escaping (Item) -> String,
        secondaryMenus: [JarvisSidebarSecondaryMenu<Item, SecondaryItem>],
        secondarySelection: Binding<SecondaryItem>,
        secondaryTitle: @escaping (SecondaryItem) -> String,
        secondaryIcon: @escaping (SecondaryItem, Bool) -> AnyView,
        footerTitle: String? = nil,
        footerIcon: String? = nil,
        footerIsSelected: Bool = false,
        footerAction: (() -> Void)? = nil
    ) {
        self.items = items
        _selection = selection
        self.title = title
        self.icon = icon
        self.secondaryMenus = secondaryMenus
        _secondarySelection = secondarySelection
        self.secondaryTitle = secondaryTitle
        self.secondaryIcon = secondaryIcon
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

            VStack(spacing: 4) {
                ForEach(items) { item in
                    primaryRow(item)

                    if let secondaryItems = secondaryItems(for: item), selection == item {
                        secondaryMenu(items: secondaryItems)
                    }
                }
            }
            .padding(.horizontal, JarvisMetrics.sidebarContentPadding)
            .padding(.top, JarvisMetrics.sidebarContentPadding)

            Spacer(minLength: 0)

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

    private func primaryRow(_ item: Item) -> some View {
        let isSelected = selection == item
        let hasSelectedSecondary = secondaryItems(for: item) != nil && selection == item
        let foregroundColor: Color = if isSelected, !hasSelectedSecondary {
            .white
        } else if hasSelectedSecondary {
            .primary
        } else {
            .secondary
        }

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
                    .opacity(isSelected && !hasSelectedSecondary ? 1 : 0)
                    .scaleEffect(isSelected && !hasSelectedSecondary ? 1 : 0.96)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(
            JarvisMotion.animation(JarvisMotion.sidebarSelection, reduceMotion: reduceMotion),
            value: isSelected && !hasSelectedSecondary
        )
        .help(title(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func secondaryMenu(items: [SecondaryItem]) -> some View {
        VStack(spacing: 3) {
            ForEach(items) { item in
                let isSelected = secondarySelection == item

                Button {
                    withAnimation(
                        JarvisMotion.animation(JarvisMotion.sidebarSelection, reduceMotion: reduceMotion)
                    ) {
                        secondarySelection = item
                    }
                } label: {
                    HStack(spacing: 7) {
                        secondaryIcon(item, isSelected)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 18, height: 18)
                        Text(secondaryTitle(item))
                            .font(
                                isSelected
                                    ? JarvisTypography.controlEmphasis
                                    : JarvisTypography.control
                            )
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
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
                .help(secondaryTitle(item))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.leading, 20)
        .padding(.top, 1)
        .padding(.bottom, 2)
        // Replace the submenu in place. Animating its insertion and removal
        // would keep the outgoing and incoming menus composited together.
        .transition(.identity)
    }

    private func secondaryItems(for parent: Item) -> [SecondaryItem]? {
        secondaryMenus.first { $0.parent == parent }?.items
    }
}
