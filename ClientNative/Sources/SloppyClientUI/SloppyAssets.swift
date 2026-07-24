import SwiftUI

#if os(macOS)
import AppKit
#endif

public enum SloppyAssets {
    public static var projectLogo: Image {
        #if os(macOS)
        if let image = Bundle.module.image(forResource: "SloppyProjectLogo") {
            return Image(nsImage: image)
        }
        if let url = Bundle.module.url(
            forResource: "so_logo",
            withExtension: "svg",
            subdirectory: "SloppyClientAssets.xcassets/SloppyProjectLogo.imageset"
        ), let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        #endif
        return Image("SloppyProjectLogo", bundle: .module)
    }
}
