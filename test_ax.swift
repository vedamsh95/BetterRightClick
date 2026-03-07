import Cocoa
import ApplicationServices

let systemWide = AXUIElementCreateSystemWide()
var focusedElementRef: CFTypeRef?
let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)

if result == .success, let focusedElement = focusedElementRef {
    let element = focusedElement as! AXUIElement
    var selectedTextRef: CFTypeRef?
    let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef)
    
    if textResult == .success, let selectedText = selectedTextRef as? String {
        print("SELECTED TEXT: \(selectedText)")
    } else {
        print("No selected text found or not supported by app.")
    }
} else {
    print("Could not get focused element.")
}
