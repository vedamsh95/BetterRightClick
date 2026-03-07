import AppKit

@MainActor
final class AppSwitcherService: ObservableObject {
    @Published private(set) var runningApps: [NSRunningApplication] = []

    func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                app.bundleIdentifier != Bundle.main.bundleIdentifier
            }
            .sorted { lhs, rhs in
                (lhs.localizedName ?? "") < (rhs.localizedName ?? "")
            }
    }
}
