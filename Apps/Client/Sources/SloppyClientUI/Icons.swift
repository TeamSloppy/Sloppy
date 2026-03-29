import AdaEngine
import Foundation

public enum Icons {
    public static let home = loadIcon("ic_home")
    public static let star = loadIcon("ic_star")

    private static func loadIcon(_ name: String) -> Image {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            assertionFailure("Missing icon resource: \(name).png")
            return Image()
        }
        guard let image = try? Image(contentsOf: url) else {
            assertionFailure("Failed to load icon: \(name).png")
            return Image()
        }
        return image
    }
}
