import Foundation

/// 最小 ZIP 写入器（Store 方式，无压缩），用于生成 .apkg。
struct MinimalZipWriter {
    private struct Entry {
        let name: String
        let data: Data
    }

    private var entries: [Entry] = []

    mutating func addEntry(name: String, data: Data) {
        entries.append(Entry(name: name, data: data))
    }

    func build() -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let localOffset = UInt32(archive.count)
            archive.append(makeLocalFileHeader(name: entry.name, data: entry.data))
            archive.append(entry.data)
            centralDirectory.append(
                makeCentralDirectoryHeader(name: entry.name, data: entry.data, localOffset: localOffset)
            )
        }

        let centralOffset = UInt32(archive.count)
        let centralSize = UInt32(centralDirectory.count)
        archive.append(centralDirectory)
        archive.append(
            makeEndOfCentralDirectory(
                entryCount: UInt16(entries.count),
                centralSize: centralSize,
                centralOffset: centralOffset
            )
        )
        return archive
    }

    private func makeLocalFileHeader(name: String, data: Data) -> Data {
        var header = Data()
        header.appendUInt32(0x0403_4b50)
        header.appendUInt16(20) // version needed
        header.appendUInt16(0) // flags
        header.appendUInt16(0) // compression: store
        header.appendUInt16(0) // mod time
        header.appendUInt16(0) // mod date
        header.appendUInt32(crc32(data))
        header.appendUInt32(UInt32(data.count))
        header.appendUInt32(UInt32(data.count))
        let nameData = Data(name.utf8)
        header.appendUInt16(UInt16(nameData.count))
        header.appendUInt16(0) // extra length
        header.append(nameData)
        return header
    }

    private func makeCentralDirectoryHeader(name: String, data: Data, localOffset: UInt32) -> Data {
        var header = Data()
        header.appendUInt32(0x0201_4b50)
        header.appendUInt16(20) // version made by
        header.appendUInt16(20) // version needed
        header.appendUInt16(0)
        header.appendUInt16(0)
        header.appendUInt16(0)
        header.appendUInt16(0)
        header.appendUInt32(crc32(data))
        header.appendUInt32(UInt32(data.count))
        header.appendUInt32(UInt32(data.count))
        let nameData = Data(name.utf8)
        header.appendUInt16(UInt16(nameData.count))
        header.appendUInt16(0)
        header.appendUInt16(0)
        header.appendUInt16(0)
        header.appendUInt16(0)
        header.appendUInt32(0)
        header.appendUInt32(localOffset)
        header.append(nameData)
        return header
    }

    private func makeEndOfCentralDirectory(entryCount: UInt16, centralSize: UInt32, centralOffset: UInt32) -> Data {
        var header = Data()
        header.appendUInt32(0x0605_4b50)
        header.appendUInt16(0)
        header.appendUInt16(0)
        header.appendUInt16(entryCount)
        header.appendUInt16(entryCount)
        header.appendUInt32(centralSize)
        header.appendUInt32(centralOffset)
        header.appendUInt16(0)
        return header
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: MemoryLayout<UInt32>.size))
    }
}
