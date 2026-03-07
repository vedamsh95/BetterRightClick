import Cocoa
import ApplicationServices

let systemWide = AXUIElementCreateSystemWide()

// Try mouse position
let loc = NSEvent.mouseLocation
print("Mouse: \(loc)")
var hit: AXUIElement?
let result = AXUIElementCopyElementAtPosition(systemWide, Float(loc.x), Float(loc.y), &hit)

if result == .success, let hitElement = hit {
    var selectedTextRef: CFTypeRef?
    let textResult = AXUIElementCopyAttributeValue(hitElement, kAXSelectedTextAttribute as CFString, &selectedTextRef)
    print("Under mouse selected text: \(String(describing: selectedTextRef))")
}
