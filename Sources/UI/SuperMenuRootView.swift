import SwiftUI

struct SuperMenuRootView: View {
    private enum MenuTab: String, CaseIterable, Identifiable {
        case actions = "Actions"
        case switcher = "Switcher"

        var id: String { rawValue }
    }

    @ObservedObject var windowManager: MenuWindowManager
    @State private var selectedTab: MenuTab = .actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Menu", selection: $selectedTab) {
                ForEach(MenuTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedTab {
                case .actions:
                    ActionsTab(windowManager: windowManager)
                case .switcher:
                    SwitcherTab(windowManager: windowManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}
