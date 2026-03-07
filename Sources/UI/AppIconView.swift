import AppKit
import SwiftUI

struct AppIconView: NSViewRepresentable {
    let app: NSRunningApplication

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = app.icon
    }
}
