import AppKit
import ApplicationServices

// Get all CG windows
guard let rawInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    print("No window info")
    exit(1)
}

for info in rawInfo {
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    if owner == "Xcode" {
        print(info)
        
        let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
        print(" -> Window ID: \(windowID)")
        
        // C-level private API trick
        // let axApp = AXUIElementCreateApplication(info[kCGWindowOwnerPID] as! pid_t)
    }
}
