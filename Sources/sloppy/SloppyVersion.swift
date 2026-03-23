import Foundation

enum SloppyVersion {
    private static let devPlaceholder = "__SLOPPY_APP_VERSION__"

    static let current: String = {
        guard
            let url = Bundle.module.url(forResource: "sloppy-version", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let core = json["sloppy-core"] as? [String: Any],
            let version = core["version"] as? String
        else {
            return devPlaceholder
        }
        return version
    }()

    static let isReleaseBuild: Bool = current != devPlaceholder

    /// Returns true if `candidate` is a newer semver than `current`.
    /// Compares dot-separated integer segments; missing segments treated as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { v in
            v.split(separator: ".").compactMap { Int($0) }
        }
        let a = parse(candidate)
        let b = parse(current)
        let length = max(a.count, b.count)
        for i in 0..<length {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }
}
