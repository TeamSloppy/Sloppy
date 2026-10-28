import Foundation

/// A small, uncompressed ZIP writer for the viewer's three export files. No external process is needed on iOS.
enum ChatImageArchive {
    static func make(original: Data, originalExtension: String, annotated: Data, notes: Data) -> Data {
        // Entry names are fixed; user filenames can never introduce archive paths.
        let ext = originalExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let entries = [("original.\(ext.isEmpty ? "image" : ext)", original), ("annotated.png", annotated), ("annotations.json", notes)]
        var archive = Data()
        var directory = Data()
        for (name, data) in entries {
            let filename = Data(name.utf8)
            let offset = UInt32(archive.count)
            let size = UInt32(data.count)
            let checksum = crc32(data)
            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20)); archive.appendLE(UInt16(0x0800)); archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0x0021)) // 1980-01-01
            archive.appendLE(checksum); archive.appendLE(size); archive.appendLE(size)
            archive.appendLE(UInt16(filename.count)); archive.appendLE(UInt16(0))
            archive.append(filename); archive.append(data)

            directory.appendLE(UInt32(0x02014b50))
            directory.appendLE(UInt16(20)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(0x0800))
            directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0x0021))
            directory.appendLE(checksum); directory.appendLE(size); directory.appendLE(size)
            directory.appendLE(UInt16(filename.count)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt32(0))
            directory.appendLE(offset); directory.append(filename)
        }
        let offset = UInt32(archive.count)
        archive.append(directory)
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count)); archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(directory.count)); archive.appendLE(offset); archive.appendLE(UInt16(0))
        return archive
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320 }
        return crc
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)] }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        for offset in 0..<MemoryLayout<T>.size { append(UInt8(truncatingIfNeeded: value >> (offset * 8))) }
    }
}
