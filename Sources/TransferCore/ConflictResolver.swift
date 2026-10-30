import Foundation

public enum ConflictChoice: Sendable { case replace, keepBoth, skip }

public enum ConflictResolver {
    /// "photo.jpg" -> "photo (2).jpg", skipping names already taken.
    public static func keepBothName(_ name: String, taken: Set<String>) -> String {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            if !taken.contains(candidate) { return candidate }
            n += 1
        }
    }
}
