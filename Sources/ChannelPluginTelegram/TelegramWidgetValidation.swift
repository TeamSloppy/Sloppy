import Foundation
#if canImport(CWidgetZlib)
import CWidgetZlib
#endif

enum TelegramWidgetError: Error { case invalidPayload, compressionUnavailable, forbidden, unknownHandle, unavailable }

enum TelegramWidgetValidation {
    static func validateData(_ data: String) throws {
        guard data.utf8.count <= 1024, !data.contains("\0") else { throw TelegramWidgetError.invalidPayload }
    }
    static func validate(html: String, caption: String, chatData: String?) throws {
        guard !html.isEmpty, html.utf8.count <= 32768, !html.contains("\0"),
              !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              caption.utf16.count <= 1024, !caption.contains("\0") else { throw TelegramWidgetError.invalidPayload }
        if let chatData { try validateData(chatData) }
        guard try compressedSize(html) <= 4096 else { throw TelegramWidgetError.invalidPayload }
    }
    static func compressedSize(_ html: String) throws -> Int {
#if canImport(CWidgetZlib)
        let source = Array(html.utf8)
        var length = compressBound(uLong(source.count))
        var destination = [UInt8](repeating: 0, count: Int(length))
        let result = compress2(&destination, &length, source, uLong(source.count), 9)
        guard result == Z_OK else { throw TelegramWidgetError.invalidPayload }
        return Int(length)
#else
        throw TelegramWidgetError.compressionUnavailable
#endif
    }
}
