import SwiftUI

struct SuperMenuRootView: View {
    private enum MenuTab: String, CaseIterable, Identifiable {
        case actions = "Actions"
        case switcher = "Switcher"
        case snap = "Snap"
        case settings = "Settings"

        var id: String { rawValue }
    }

    @ObservedObject var windowManager: MenuWindowManager
    @State private var selectedTab: MenuTab = .actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Drag handle + Pin toggle
            HStack {
                // Visual drag affordance
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                
                Spacer()
                
                Button {
                    windowManager.isPinned.toggle()
                } label: {
                    Image(systemName: windowManager.isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(windowManager.isPinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(windowManager.isPinned ? "Unpin window" : "Pin window (stays on top)")
            }
            .padding(.bottom, -4)
            
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
                case .snap:
                    SnapTab(windowManager: windowManager)
                case .settings:
                    SettingsTab(windowManager: windowManager)
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
