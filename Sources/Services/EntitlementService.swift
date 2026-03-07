import Foundation
import Security

struct EntitlementService {
    func hasEntitlement(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let raw = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else { return false }

        if CFGetTypeID(raw) == CFBooleanGetTypeID() {
            let value = unsafeBitCast(raw, to: CFBoolean.self)
            return CFBooleanGetValue(value)
        }

        return false
    }
}
