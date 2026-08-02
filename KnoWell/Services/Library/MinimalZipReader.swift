import Foundation
import zlib

enum MinimalZipReader {
    struct Entry {
        let name: String
        let data: Data
    }

    static func entries(in archive: Data) -> [Entry] {
        guard let eocdOffset = findEndOfCentralDirectory(in: archive) else { return [] }

        let totalEntries = Int(readUInt16(from: archive, at: eocdOffset + 10))
        let centralSize = Int(readUInt32(from: archive, at: eocdOffset + 12))
        let centralOffset = Int(readUInt32(from: archive, at: eocdOffset + 16))
        guard centralOffset >= 0, centralOffset + centralSize <= archive.count else { return [] }

        var result: [Entry] = []
        var offset = centralOffset

        for _ in 0..<totalEntries {
            guard offset + 46 <= archive.count else { break }
            guard readUInt32(from: archive, at: offset) == 0x0201_4b50 else { break }

            let compressionMethod = readUInt16(from: archive, at: offset + 10)
            let compressedSize = Int(readUInt32(from: archive, at: offset + 20))
            let uncompressedSize = Int(readUInt32(from: archive, at: offset + 24))
            let fileNameLength = Int(readUInt16(from: archive, at: offset + 28))
            let extraLength = Int(readUInt16(from: archive, at: offset + 30))
            let commentLength = Int(readUInt16(from: archive, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(from: archive, at: offset + 42))

            let nameStart = offset + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= archive.count else { break }
            let nameData = archive[nameStart..<nameEnd]
            guard let name = String(data: nameData, encoding: .utf8) else { break }

            if let fileData = readLocalFile(
                at: localHeaderOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: compressionMethod,
                in: archive
            ) {
                result.append(Entry(name: name, data: fileData))
            }

            offset = nameEnd + extraLength + commentLength
        }

        return result
    }

    static func data(forEntryNamed name: String, in archive: Data) -> Data? {
        entries(in: archive).first { $0.name == name }?.data
    }

    static func firstEntry(where predicate: (String) -> Bool, in archive: Data) -> Entry? {
        entries(in: archive).first { predicate($0.name) }
    }

    private static func readLocalFile(
        at offset: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        compressionMethod: UInt16,
        in archive: Data
    ) -> Data? {
        guard offset >= 0, offset + 30 <= archive.count else { return nil }
        guard readUInt32(from: archive, at: offset) == 0x0403_4b50 else { return nil }

        let fileNameLength = Int(readUInt16(from: archive, at: offset + 26))
        let extraLength = Int(readUInt16(from: archive, at: offset + 28))
        let dataStart = offset + 30 + fileNameLength + extraLength
        let dataEnd = dataStart + compressedSize
        guard dataEnd <= archive.count else { return nil }

        let compressed = archive[dataStart..<dataEnd]
        return decompressEntry(Data(compressed), method: compressionMethod, uncompressedSize: uncompressedSize)
    }

    private static func decompressEntry(_ data: Data, method: UInt16, uncompressedSize: Int) -> Data? {
        switch method {
        case 0:
            return data
        case 8:
            return inflateDeflate(data, expectedSize: uncompressedSize)
        default:
            return nil
        }
    }

    private static func inflateDeflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        var initStatus: Int32 = Z_DATA_ERROR
        data.withUnsafeBytes { rawInput in
            guard let base = rawInput.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        output.reserveCapacity(max(expectedSize, data.count * 2))

        let bufferSize = 32_768
        let buffer = UnsafeMutablePointer<Bytef>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var status = Z_OK
        repeat {
            stream.next_out = buffer
            stream.avail_out = uInt(bufferSize)
            status = inflate(&stream, Z_NO_FLUSH)
            guard status == Z_OK || status == Z_STREAM_END else { return nil }

            let produced = bufferSize - Int(stream.avail_out)
            if produced > 0 {
                output.append(buffer, count: produced)
            }
        } while status != Z_STREAM_END

        if expectedSize > 0, output.count != expectedSize, !output.isEmpty {
            return output
        }

        return output.isEmpty ? nil : output
    }

    private static func findEndOfCentralDirectory(in archive: Data) -> Int? {
        let minEOCDSize = 22
        let searchStart = max(0, archive.count - minEOCDSize - 65_535)
        for offset in stride(from: archive.count - minEOCDSize, through: searchStart, by: -1) {
            guard readUInt32(from: archive, at: offset) == 0x0605_4b50 else { continue }
            let commentLength = Int(readUInt16(from: archive, at: offset + 20))
            let recordEnd = offset + minEOCDSize + commentLength
            guard recordEnd == archive.count else { continue }
            return offset
        }
        return nil
    }

    private static func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset])
            | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
