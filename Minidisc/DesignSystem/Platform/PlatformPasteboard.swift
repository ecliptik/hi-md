#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

nonisolated enum PlatformPasteboard {
    static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
