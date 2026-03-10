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
            header
                .padding()

            // Top-level tab picker: Snap | Sidekick
            Picker("", selection: $topTab) {
                Text("Snap").tag(0)
                Text("Sidekick").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            displayPicker
                .padding(.horizontal)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 16) {
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
                .padding()
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
                Button("Undo Snap") {
                    windowManager.undoSnap()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .onAppear {
            windowManager.refreshSnapDisplays()
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

    // MARK: - Window Picker Carousel (Always Visible in Snap tab)

    private var windowPickerCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedPIDs.isEmpty ? "Select apps for Smart Mode:" : "\(selectedPIDs.count) App\(selectedPIDs.count == 1 ? "" : "s") Selected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if !selectedPIDs.isEmpty {
                    Button("Clear") {
                        selectedPIDs.removeAll()
                        heroIndex = 0
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
                
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        VStack(spacing: 4) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 36, height: 36)
                            }
                            
                            Text(app.localizedName ?? "App")
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .frame(width: 48)
                        }
                        .padding(5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPIDs.contains(app.processIdentifier) ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedPIDs.contains(app.processIdentifier) ? Color.accentColor : Color.clear, lineWidth: 2)
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
                .padding(.horizontal, 2)
            }
            .frame(height: 70)
        }
    }

    // MARK: - State 2: Smart Layouts (2+ apps selected)

    private var smartLayoutsSection: some View {
        let selectedApps = runningApps.filter { selectedPIDs.contains($0.processIdentifier) }
        let count = selectedApps.count
        let screenCount = NSScreen.screens.count
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Smart Layouts")
                .font(.headline)
            
            Text("\(count) apps selected — choose a layout:")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 1. Even Grid
            smartButton(
                emoji: "🪟",
                title: "Even Grid",
                subtitle: evenGridDescription(for: count),
                tint: Color.accentColor
            ) {
                windowManager.snapEvenGrid(apps: selectedApps, preferredDisplayID: selectedDisplayID)
                selectedPIDs.removeAll()
            }

            // 2. Main + Stack with Hero Picker
            VStack(alignment: .leading, spacing: 8) {
                smartButton(
                    emoji: "📚",
                    title: "Main + Stack",
                    subtitle: "\(selectedApps[safe: heroIndex]?.localizedName ?? "First app") gets 70%, \(count - 1) stacked in 30%",
                    tint: Color.orange
                ) {
                    // Reorder so the hero is first
                    var reordered = selectedApps
                    if heroIndex > 0 && heroIndex < reordered.count {
                        let hero = reordered.remove(at: heroIndex)
                        reordered.insert(hero, at: 0)
                    }
                    windowManager.snapMainPlusStack(apps: reordered, preferredDisplayID: selectedDisplayID)
                    selectedPIDs.removeAll()
                    heroIndex = 0
                }
                
                // Hero picker inline
                HStack(spacing: 4) {
                    Text("Hero:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    ForEach(Array(selectedApps.enumerated()), id: \.element.processIdentifier) { idx, app in
                        Button {
                            heroIndex = idx
                        } label: {
                            HStack(spacing: 3) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                Text(app.localizedName ?? "App")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(heroIndex == idx ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(heroIndex == idx ? Color.orange : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 8)
            }

            // 3. Distribute to Screens (only if multi-monitor)
            if screenCount >= 2 {
                smartButton(
                    emoji: "🖥️",
                    title: "Distribute to \(screenCount) Screens",
                    subtitle: "Spreads apps evenly across all connected monitors",
                    tint: Color.indigo
                ) {
                    windowManager.distributeToScreens(apps: selectedApps)
                    selectedPIDs.removeAll()
                }
            }
            
            // 4. Swap shortcut when exactly 2 selected
            if count == 2 {
                smartButton(
                    emoji: "🔄",
                    title: "Swap Positions",
                    subtitle: "Teleport these two windows to each other's position",
                    tint: Color.purple
                ) {
                    windowManager.swapApps(appA: selectedApps[0], appB: selectedApps[1])
                    selectedPIDs.removeAll()
                }
            }
        }
    }
    
    private func smartButton(emoji: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
    
    private func evenGridDescription(for count: Int) -> String {
        switch count {
        case 2: return "Left Half / Right Half"
        case 3: return "Three equal vertical slices"
        case 4: return "2×2 grid"
        default: return "\(count) equal columns"
        }
    }

    // MARK: - State 1: Single Window Grid

    private var basicGridsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $basicSubTab) {
                Text("Halves").tag(0)
                Text("Thirds").tag(1)
                Text("2x2").tag(2)
                Text("3x3").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)

            switch basicSubTab {
            case 0:
                halfGrid
            case 1:
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        snapButton(title: "Left 1/3", columns: 3, rows: 1, column: 0, rowFromTop: 0)
                        snapButton(title: "Center 1/3", columns: 3, rows: 1, column: 1, rowFromTop: 0)
                        snapButton(title: "Right 1/3", columns: 3, rows: 1, column: 2, rowFromTop: 0)
                    }
                    HStack(spacing: 8) {
                        snapButton(title: "Left 2/3", columns: 3, rows: 1, customSpan: (0, 2))
                        snapButton(title: "Right 2/3", columns: 3, rows: 1, customSpan: (1, 2))
                    }
                }
            case 2:
                grid2x2
            case 3:
                grid3x3
            default:
                EmptyView()
            }
            
            Spacer()
        }
    }

    // MARK: - Sidekick Tab (Separate)

    private var sidekickTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Main & Sidekick")
                .font(.headline)
            
            Text("The frontmost window becomes the Sidekick (30%). The window behind it expands into the remaining 70%.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 8) {
                Button("Sidekick Left") {
                    windowManager.snapSidekick(direction: .left, preferredDisplayID: selectedDisplayID)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Sidekick Right") {
                    windowManager.snapSidekick(direction: .right, preferredDisplayID: selectedDisplayID)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            Spacer()
        }
    }

    // MARK: - Header & Display Picker

    private var header: some View {
        HStack {
            Text("Window Snap")
                .font(.headline)
            Spacer()
            Button("Global Swap") {
                windowManager.swapTopTwoWindows()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            
            Button("Refresh") {
                windowManager.refreshSnapDisplays()
                refreshApps()
                if selectedDisplay != "auto",
                   !windowManager.snapDisplays.contains(where: { "\($0.id)" == selectedDisplay }) {
                    selectedDisplay = "auto"
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var displayPicker: some View {
        Picker("Target Display", selection: $selectedDisplay) {
            Text("Auto (Display Under Cursor)").tag("auto")
            ForEach(windowManager.snapDisplays) { display in
                Text(display.name).tag("\(display.id)")
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Single-Window Grid Helpers

    private var halfGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                snapButton(title: "Left 1/2", columns: 2, rows: 1, column: 0, rowFromTop: 0)
                snapButton(title: "Right 1/2", columns: 2, rows: 1, column: 1, rowFromTop: 0)
            }
            HStack(spacing: 8) {
                snapButton(title: "Top 1/2", columns: 1, rows: 2, column: 0, rowFromTop: 0)
                snapButton(title: "Bottom 1/2", columns: 1, rows: 2, column: 0, rowFromTop: 1)
            }
        }
    }

    private var grid2x2: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                snapButton(title: "Top Left", columns: 2, rows: 2, column: 0, rowFromTop: 0)
                snapButton(title: "Top Right", columns: 2, rows: 2, column: 1, rowFromTop: 0)
            }
            HStack(spacing: 8) {
                snapButton(title: "Bottom Left", columns: 2, rows: 2, column: 0, rowFromTop: 1)
                snapButton(title: "Bottom Right", columns: 2, rows: 2, column: 1, rowFromTop: 1)
            }
        }
    }

    private var grid3x3: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { column in
                        snapButton(
                            title: "\(row + 1)-\(column + 1)",
                            columns: 3,
                            rows: 3,
                            column: column,
                            rowFromTop: row
                        )
                    }
                }
            }
        }
    }

    // MARK: - Snap Button (Single Window Only)

    private func snapButton(title: String, columns: Int, rows: Int, column: Int, rowFromTop: Int) -> some View {
        Button(title) {
            windowManager.snapWindowToGrid(
                columns: columns,
                rows: rows,
                column: column,
                rowFromTop: rowFromTop,
                preferredDisplayID: selectedDisplayID
            )
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func snapButton(title: String, columns: Int, rows: Int, customSpan: (startColumn: Int, columnCount: Int)) -> some View {
        Button(title) {
            windowManager.snapWindowCustomSpan(
                columns: columns,
                rows: rows,
                startColumn: customSpan.startColumn,
                columnCount: customSpan.columnCount,
                preferredDisplayID: selectedDisplayID
            )
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private var selectedDisplayID: CGDirectDisplayID? {
        if selectedDisplay == "auto" {
            return nil
        }

        guard let parsed = UInt32(selectedDisplay) else {
            return nil
        }

        return CGDirectDisplayID(parsed)
    }
}

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
