import SwiftUI

struct SnapTab: View {
    @ObservedObject var windowManager: MenuWindowManager

    @State private var selectedDisplay: String = "auto"

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                header
                displayPicker

                Text("Halves")
                    .font(.caption)
                    .fontWeight(.semibold)
                halfGrid

                Text("2x2 Grid")
                    .font(.caption)
                    .fontWeight(.semibold)
                grid2x2

                Text("3x3 Grid")
                    .font(.caption)
                    .fontWeight(.semibold)
                grid3x3

                Text("Uses Accessibility API to move and resize the window under your cursor. Coordinates are based on each display's visible frame (menu bar + dock excluded).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if !windowManager.statusMessage.isEmpty {
                        Text(windowManager.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Undo Snap") {
                        windowManager.undoSnap()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
        }
        .onAppear {
            windowManager.refreshSnapDisplays()
            if selectedDisplay != "auto",
               !windowManager.snapDisplays.contains(where: { "\($0.id)" == selectedDisplay }) {
                selectedDisplay = "auto"
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Window Snap")
                .font(.headline)
            Spacer()
            Button("Refresh Displays") {
                windowManager.refreshSnapDisplays()
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
