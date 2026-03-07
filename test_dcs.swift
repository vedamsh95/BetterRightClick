import Foundation
import CoreServices

let text = "apple"
if let result = DCSCopyTextDefinition(nil, text as CFString, CFRangeMake(0, text.count))?.takeRetainedValue() as String? {
    print(result)
} else {
    print("Not found")
}
