import SwiftUI

struct SnapTab: View {
    @ObservedObject var windowManager: MenuWindowManager

    @State private var selectedDisplay: String = "auto"
    @State private var selectedPIDs: Set<pid_t> = []
    @State private var runningApps: [NSRunningApplication] = []
    @State private var basicSubTab: Int = 0
    @State private var topTab: Int = 0          // 0 = Snap, 1 = Sidekick
    @State private var heroIndex: Int = 0       // Which selected app is the "hero" in Main+Stack

    var body: some View {
        VStack(spacing: 0) {
            // Compact header: all controls in one row
            HStack(spacing: 6) {
                // Snap / Sidekick toggle (compact)
                Picker("", selection: $topTab) {
                    Image(systemName: "rectangle.split.2x1").tag(0)
                    Image(systemName: "person.2.crop.square.stack").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .help(topTab == 0 ? "Snap Mode" : "Sidekick Mode")
                
                // Display picker (compact dropdown)
                Picker("", selection: $selectedDisplay) {
                    Text("Auto").tag("auto")
                    ForEach(windowManager.snapDisplays) { display in
                        Text(display.name).tag("\(display.id)")
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
                .controlSize(.small)
                
                Spacer()
                
                // Icon-only action buttons with tooltips
                Button {
                    windowManager.snap.swapApps(appA: windowManager.runningApps[0], appB: windowManager.runningApps[1])
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help("Global Swap: swap the two frontmost windows")
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    windowManager.snap.refreshSnapDisplays()
                    refreshApps()
                    if selectedDisplay != "auto",
                       !windowManager.snapDisplays.contains(where: { "\($0.id)" == selectedDisplay }) {
                        selectedDisplay = "auto"
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh displays & running apps")
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 12) {
                    if topTab == 0 {
                        windowPickerCarousel

                        Divider()

                        if selectedPIDs.count >= 2 {
                            smartLayoutsSection
                        } else {
                            basicGridsTab
                        }
                    } else {
                        sidekickTab
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }

            Divider()
            
            HStack {
                if !windowManager.statusMessage.isEmpty {
                    Text(windowManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Button("Undo") {
                    windowManager.snap.undoSnap()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .onAppear {
            windowManager.snap.refreshSnapDisplays()
            if selectedDisplay != "auto",
               !windowManager.snapDisplays.contains(where: { "\($0.id)" == selectedDisplay }) {
                selectedDisplay = "auto"
            }
            refreshApps()
        }
    }
    
    private func refreshApps() {
        self.runningApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular 
            && app.localizedName != "Better Right Click"
            && app.localizedName != "Finder"
        }
    }

    // MARK: - Window Picker Carousel

    private var windowPickerCarousel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedPIDs.isEmpty ? "Select apps:" : "\(selectedPIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !selectedPIDs.isEmpty {
                    Button("Clear") {
                        selectedPIDs.removeAll()
                        heroIndex = 0
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
                
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        VStack(spacing: 2) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 28, height: 28)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 28, height: 28)
                            }
                            
                            Text(app.localizedName ?? "")
                                .font(.system(size: 8))
                                .lineLimit(1)
                                .frame(width: 40)
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedPIDs.contains(app.processIdentifier) ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedPIDs.contains(app.processIdentifier) ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                        .onTapGesture {
                            if selectedPIDs.contains(app.processIdentifier) {
                                selectedPIDs.remove(app.processIdentifier)
                            } else {
                                selectedPIDs.insert(app.processIdentifier)
                            }
                            heroIndex = 0
                        }
                    }
                }
            }
            .frame(height: 52)
        }
    }

    // MARK: - State 2: Smart Layouts (2+ apps selected)

    private var smartLayoutsSection: some View {
        let selectedApps = runningApps.filter { selectedPIDs.contains($0.processIdentifier) }
        let count = selectedApps.count
        let screenCount = NSScreen.screens.count
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Smart Layouts")
                .font(.subheadline)
                .fontWeight(.semibold)

            // Even Grid
            smartButton(
                emoji: "🪟",
                title: "Even Grid",
                subtitle: evenGridDescription(for: count),
                tint: Color.accentColor
            ) {
                windowManager.snap.snapEvenGrid(apps: selectedApps, preferredDisplayID: selectedDisplayID)
                selectedPIDs.removeAll()
            }

            // Main + Stack with Hero Picker
            VStack(alignment: .leading, spacing: 6) {
                smartButton(
                    emoji: "📚",
                    title: "Main + Stack",
                    subtitle: "\(selectedApps[safe: heroIndex]?.localizedName ?? "First") → 70%",
                    tint: Color.orange
                ) {
                    var reordered = selectedApps
                    if heroIndex > 0 && heroIndex < reordered.count {
                        let hero = reordered.remove(at: heroIndex)
                        reordered.insert(hero, at: 0)
                    }
                    windowManager.snap.snapMainPlusStack(apps: reordered, preferredDisplayID: selectedDisplayID)
                    selectedPIDs.removeAll()
                    heroIndex = 0
                }
                
                // Compact hero picker
                HStack(spacing: 3) {
                    Text("Hero:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    ForEach(Array(selectedApps.enumerated()), id: \.element.processIdentifier) { idx, app in
                        Button {
                            heroIndex = idx
                        } label: {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .padding(2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(heroIndex == idx ? Color.orange.opacity(0.3) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(heroIndex == idx ? Color.orange : Color.clear, lineWidth: 1)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .help(app.localizedName ?? "App")
                    }
                }
                .padding(.leading, 6)
            }

            // Distribute to Screens
            if screenCount >= 2 {
                smartButton(
                    emoji: "🖥️",
                    title: "Distribute to \(screenCount) Screens",
                    subtitle: "Even spread across monitors",
                    tint: Color.indigo
                ) {
                    windowManager.snap.distributeToScreens(apps: selectedApps)
                    selectedPIDs.removeAll()
                }
            }
            
            // Swap (2 selected)
            if count == 2 {
                smartButton(
                    emoji: "🔄",
                    title: "Swap",
                    subtitle: "Teleport to each other's position",
                    tint: Color.purple
                ) {
                    windowManager.snap.swapApps(appA: selectedApps[0], appB: selectedApps[1])
                    selectedPIDs.removeAll()
                }
            }
        }
    }
    
    private func smartButton(emoji: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
    
    private func evenGridDescription(for count: Int) -> String {
        switch count {
        case 2: return "Left / Right halves"
        case 3: return "Three equal slices"
        case 4: return "2×2 grid"
        default: return "\(count) columns"
        }
    }

    // MARK: - State 1: Single Window Grid

    private var basicGridsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $basicSubTab) {
                Image(systemName: "rectangle.split.1x2").tag(0)
                Image(systemName: "rectangle.split.3x1").tag(1)
                Image(systemName: "rectangle.split.2x2").tag(2)
                Image(systemName: "rectangle.split.3x3").tag(3)
            }
            .pickerStyle(.segmented)

            switch basicSubTab {
            case 0: halfGrid
            case 1:
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        snapIconButton(icon: "rectangle.leftthird.inset.filled", help: "Left Third", columns: 3, rows: 1, column: 0, rowFromTop: 0)
                        snapIconButton(icon: "rectangle.centerthird.inset.filled", help: "Center Third", columns: 3, rows: 1, column: 1, rowFromTop: 0)
                        snapIconButton(icon: "rectangle.rightthird.inset.filled", help: "Right Third", columns: 3, rows: 1, column: 2, rowFromTop: 0)
                    }
                    HStack(spacing: 6) {
                        snapIconButton(icon: "rectangle.leadinghalf.inset.filled", help: "Left Two-Thirds", columns: 3, rows: 1, customSpan: (0, 2))
                        snapIconButton(icon: "rectangle.trailinghalf.inset.filled", help: "Right Two-Thirds", columns: 3, rows: 1, customSpan: (1, 2))
                    }
                }
            case 2: grid2x2
            case 3: grid3x3
            default: EmptyView()
            }
        }
    }

    // MARK: - Sidekick Tab

    private var sidekickTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Main & Sidekick")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("Frontmost window → 30% sidekick. Window behind it → 70% main.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 8) {
                Button {
                    windowManager.snap.snapSidekick(direction: .left, preferredDisplayID: selectedDisplayID)
                } label: {
                    Label("Left", systemImage: "sidebar.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                
                Button {
                    windowManager.snap.snapSidekick(direction: .right, preferredDisplayID: selectedDisplayID)
                } label: {
                    Label("Right", systemImage: "sidebar.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid Helpers

    private var halfGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                snapIconButton(icon: "rectangle.lefthalf.filled", help: "Left Half", columns: 2, rows: 1, column: 0, rowFromTop: 0)
                snapIconButton(icon: "rectangle.righthalf.filled", help: "Right Half", columns: 2, rows: 1, column: 1, rowFromTop: 0)
            }
            HStack(spacing: 6) {
                snapIconButton(icon: "rectangle.tophalf.filled", help: "Top Half", columns: 1, rows: 2, column: 0, rowFromTop: 0)
                snapIconButton(icon: "rectangle.bottomhalf.filled", help: "Bottom Half", columns: 1, rows: 2, column: 0, rowFromTop: 1)
            }
        }
    }

    private var grid2x2: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                snapIconButton(icon: "rectangle.inset.topleft.filled", help: "Top Left", columns: 2, rows: 2, column: 0, rowFromTop: 0)
                snapIconButton(icon: "rectangle.inset.topright.filled", help: "Top Right", columns: 2, rows: 2, column: 1, rowFromTop: 0)
            }
            HStack(spacing: 6) {
                snapIconButton(icon: "rectangle.inset.bottomleft.filled", help: "Bottom Left", columns: 2, rows: 2, column: 0, rowFromTop: 1)
                snapIconButton(icon: "rectangle.inset.bottomright.filled", help: "Bottom Right", columns: 2, rows: 2, column: 1, rowFromTop: 1)
            }
        }
    }

    private var grid3x3: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        Button {
                            windowManager.snap.snapWindowToGrid(
                                columns: 3, rows: 3,
                                column: column, rowFromTop: row,
                                preferredDisplayID: selectedDisplayID
                            )
                        } label: {
                            Image(systemName: "square.fill")
                                .font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Row \(row+1), Column \(column+1)")
                    }
                }
            }
        }
    }

    // MARK: - Snap Icon Buttons

    private func snapIconButton(icon: String, help: String, columns: Int, rows: Int, column: Int, rowFromTop: Int) -> some View {
        Button {
            windowManager.snap.snapWindowToGrid(
                columns: columns, rows: rows,
                column: column, rowFromTop: rowFromTop,
                preferredDisplayID: selectedDisplayID
            )
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }

    private func snapIconButton(icon: String, help: String, columns: Int, rows: Int, customSpan: (startColumn: Int, columnCount: Int)) -> some View {
        Button {
            windowManager.snap.snapWindowCustomSpan(
                columns: columns, rows: rows,
                startColumn: customSpan.startColumn,
                columnCount: customSpan.columnCount,
                preferredDisplayID: selectedDisplayID
            )
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }

    private var selectedDisplayID: CGDirectDisplayID? {
        if selectedDisplay == "auto" { return nil }
        guard let parsed = UInt32(selectedDisplay) else { return nil }
        return CGDirectDisplayID(parsed)
    }
}

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
