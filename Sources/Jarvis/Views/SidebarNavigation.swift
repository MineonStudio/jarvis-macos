import SwiftUI

struct JarvisSidebarNavigation<
    Item: Identifiable & Hashable,
    SecondaryItem: Identifiable & Hashable
>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let icon: (Item) -> String
    let secondaryParent: Item
    let secondaryItems: [SecondaryItem]
    @Binding var secondarySelection: SecondaryItem
    let secondaryTitle: (SecondaryItem) -> String
    let secondaryIcon: (SecondaryItem) -> String
    let footerTitle: String?
    let footerIcon: String?
    let footerIsSelected: Bool
    let footerAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sidebarSelectionAnimation

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        icon: @escaping (Item) -> String,
        secondaryParent: Item,
        secondaryItems: [SecondaryItem],
        secondarySelection: Binding<SecondaryItem>,
        secondaryTitle: @escaping (SecondaryItem) -> String,
        secondaryIcon: @escaping (SecondaryItem) -> String,
        footerTitle: String? = nil,
        footerIcon: String? = nil,
        footerIsSelected: Bool = false,
        footerAction: (() -> Void)? = nil
    ) {
        self.items = items
        _selection = selection
        self.title = title
        self.icon = icon
        self.secondaryParent = secondaryParent
        self.secondaryItems = secondaryItems
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
            Text("JARVIS")
                .font(JarvisTypography.pageTitle)
                .tracking(2.4)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
                .padding(.bottom, 12)

            VStack(spacing: 4) {
                ForEach(items) { item in
                    primaryRow(item)

                    if item == secondaryParent, selection == secondaryParent {
                        secondaryMenu
                    }
                }
            }
            .padding(.horizontal, JarvisMetrics.sidebarContentPadding)
            .padding(.top, JarvisMetrics.sidebarContentPadding)
            .animation(
                JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                value: selection
            )

            Spacer(minLength: 0)

            if let footerTitle, let footerIcon, let footerAction {
                Divider()
                    .padding(.horizontal, JarvisMetrics.sidebarContentPadding)

                Button {
                    withAnimation(
                        JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion)
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
                        if footerIsSelected {
                            Capsule()
                                .fill(JarvisMotion.selectionPillTint)
                                .matchedGeometryEffect(
                                    id: "sidebar-selection",
                                    in: sidebarSelectionAnimation
                                )
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(footerIsSelected ? Color.white : Color.secondary)
                .padding(JarvisMetrics.sidebarContentPadding)
                .help(footerTitle)
                .accessibilityAddTraits(footerIsSelected ? .isSelected : [])
                .animation(
                    JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                    value: footerIsSelected
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func primaryRow(_ item: Item) -> some View {
        let isSelected = selection == item
        let hasSelectedSecondary = item == secondaryParent && selection == secondaryParent
        let foregroundColor: Color = if isSelected, !hasSelectedSecondary {
            .white
        } else if hasSelectedSecondary {
            .primary
        } else {
            .secondary
        }

        return Button {
            withAnimation(
                JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion)
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
                if isSelected, !hasSelectedSecondary {
                    Capsule()
                        .fill(JarvisMotion.selectionPillTint)
                        .matchedGeometryEffect(
                            id: "sidebar-selection",
                            in: sidebarSelectionAnimation
                        )
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: selection
        )
        .help(title(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var secondaryMenu: some View {
        VStack(spacing: 3) {
            ForEach(secondaryItems) { item in
                let isSelected = secondarySelection == item

                Button {
                    withAnimation(
                        JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion)
                    ) {
                        secondarySelection = item
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: secondaryIcon(item))
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
                        if isSelected {
                            Capsule()
                                .fill(JarvisMotion.selectionPillTint)
                                .matchedGeometryEffect(
                                    id: "sidebar-selection",
                                    in: sidebarSelectionAnimation
                                )
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(secondaryTitle(item))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.leading, 20)
        .padding(.top, 1)
        .padding(.bottom, 2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
