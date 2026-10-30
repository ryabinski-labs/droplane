import Foundation

public enum NameSanitizer {
    /// A colon is legal on Android but is a path separator in Finder (A-011).
    public static func forMac(_ name: String) -> String {
        name.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
    }
    /// Android rejects a few characters the Mac allows.
    public static func forPhone(_ name: String) -> String {
        var s = name
        for c in ["\\", "*", "?", "\"", "<", ">", "|"] { s = s.replacingOccurrences(of: c, with: "_") }
        return s
    }
}
