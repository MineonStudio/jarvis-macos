import SwiftUI

struct JarvisSidebarNavigation<Item: Identifiable & Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let icon: (Item) -> String
    let footerTitle: String?
    let footerIcon: String?
    let footerIsSelected: Bool
    let footerAction: (() -> Void)?

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        icon: @escaping (Item) -> String,
        footerTitle: String? = nil,
        footerIcon: String? = nil,
        footerIsSelected: Bool = false,
        footerAction: (() -> Void)? = nil
    ) {
        self.items = items
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
            List(items, selection: listSelection) { item in
                Label {
                    Text(title(item))
                        .font(.system(size: 13))
                } icon: {
                    Image(systemName: icon(item))
                        .font(.system(size: 13))
                }
                .tag(item.id)
                .help(title(item))
            }
            .listStyle(.sidebar)

            if let footerTitle, let footerIcon, let footerAction {
                Divider()
                    .padding(.horizontal, JarvisMetrics.sidebarContentPadding)

                Button(action: footerAction) {
                    Label {
                        Text(footerTitle)
                            .font(.system(size: 13))
                    } icon: {
                        Image(systemName: footerIcon)
                            .font(.system(size: 13))
                    }
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(
                        footerIsSelected ? Color.accentColor.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(footerIsSelected ? Color.accentColor : Color.primary)
                .padding(JarvisMetrics.sidebarContentPadding)
                .help(footerTitle)
                .accessibilityAddTraits(footerIsSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var listSelection: Binding<Item.ID?> {
        Binding(
            get: {
                items.contains(selection) ? selection.id : nil
            },
            set: { selectedID in
                guard let selectedID,
                      let item = items.first(where: { $0.id == selectedID })
                else {
                    return
                }
                selection = item
            }
        )
    }
}
