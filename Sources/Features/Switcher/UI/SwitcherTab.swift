import SwiftUI

struct SwitcherTab: View {
    @ObservedObject var windowManager: MenuWindowManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Running Apps")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    windowManager.switcher.refreshApps()
                }
            }

            List(windowManager.runningApps, id: \.processIdentifier) { app in
                Button {
                    windowManager.switcher.focusApp(app)
                } label: {
                    HStack(spacing: 10) {
                        AppIconView(app: app)
                            .frame(width: 18, height: 18)
                        Text(app.localizedName ?? "Unknown")
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
