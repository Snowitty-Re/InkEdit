import Foundation

enum ZIPArchiveError: LocalizedError, Equatable {
    case invalidPath(String)
    case archiveTooLarge
    case invalidArchive
    case unsupportedCompression
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path): "ZIP 条目路径不安全：\(path)"
        case .archiveTooLarge: "导出内容超过当前 ZIP 写入器支持的 4 GB 限制。"
        case .invalidArchive: "云端项目快照不是有效的 ZIP 文件。"
        case .unsupportedCompression: "云端项目快照使用了不支持的压缩方式。"
        case .checksumMismatch(let path): "云端项目快照校验失败：\(path)"
        }
    }
}

struct ZIPArchiveEntry: Sendable {
    var path: String
    var data: Data
}

struct ZIPArchiveWriter {
    func archive(entries: [ZIPArchiveEntry], date: Date = .now) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        let timestamp = dosTimestamp(date)

        for entry in entries {
            try Task.checkCancellation()
            try validate(path: entry.path)
            guard
                let name = entry.path.data(using: .utf8),
                name.count <= Int(UInt16.max),
                entry.data.count <= Int(UInt32.max),
                archive.count <= Int(UInt32.max)
            else { throw ZIPArchiveError.archiveTooLarge }

            let checksum = try CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let localOffset = UInt32(archive.count)

            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(timestamp.time)
            archive.appendLittleEndian(timestamp.date)
            archive.appendLittleEndian(checksum)
            archive.appendLittleEndian(size)
            archive.appendLittleEndian(size)
            archive.appendLittleEndian(UInt16(name.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(name)
            archive.append(entry.data)

            centralDirectory.appendLittleEndian(UInt32(0x0201_4B50))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(0x0800))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(timestamp.time)
            centralDirectory.appendLittleEndian(timestamp.date)
            centralDirectory.appendLittleEndian(checksum)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(UInt16(name.count))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt32(0))
            centralDirectory.appendLittleEndian(localOffset)
            centralDirectory.append(name)
        }

        guard
            entries.count <= Int(UInt16.max),
            centralDirectory.count <= Int(UInt32.max),
            archive.count <= Int(UInt32.max)
        else { throw ZIPArchiveError.archiveTooLarge }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt32(centralDirectory.count))
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private func validate(path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard
            !path.isEmpty,
            !path.hasPrefix("/"),
            !path.contains("\\"),
            !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { throw ZIPArchiveError.invalidPath(path) }
    }

    private func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, components.year ?? 1980))
        let month = max(1, min(12, components.month ?? 1))
        let day = max(1, min(31, components.day ?? 1))
        let hour = max(0, min(23, components.hour ?? 0))
        let minute = max(0, min(59, components.minute ?? 0))
        let second = max(0, min(59, components.second ?? 0))
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
}

struct ZIPArchiveReader {
    func entries(in archive: Data) throws -> [ZIPArchiveEntry] {
        var offset = 0
        var entries: [ZIPArchiveEntry] = []
        while offset + 4 <= archive.count {
            let signature: UInt32 = try archive.littleEndian(at: offset)
            guard signature == 0x0403_4B50 else {
                if signature == 0x0201_4B50 || signature == 0x0605_4B50 { break }
                throw ZIPArchiveError.invalidArchive
            }
            guard offset + 30 <= archive.count else { throw ZIPArchiveError.invalidArchive }
            let flags: UInt16 = try archive.littleEndian(at: offset + 6)
            let compression: UInt16 = try archive.littleEndian(at: offset + 8)
            let checksum: UInt32 = try archive.littleEndian(at: offset + 14)
            let compressedSize: UInt32 = try archive.littleEndian(at: offset + 18)
            let uncompressedSize: UInt32 = try archive.littleEndian(at: offset + 22)
            let nameLength: UInt16 = try archive.littleEndian(at: offset + 26)
            let extraLength: UInt16 = try archive.littleEndian(at: offset + 28)
            guard flags & 0x0008 == 0, compression == 0 else {
                throw ZIPArchiveError.unsupportedCompression
            }
            guard compressedSize == uncompressedSize else { throw ZIPArchiveError.invalidArchive }

            let nameStart = offset + 30
            let dataStart = nameStart + Int(nameLength) + Int(extraLength)
            let dataEnd = dataStart + Int(compressedSize)
            guard dataEnd <= archive.count else { throw ZIPArchiveError.invalidArchive }
            let nameData = archive.subdata(in: nameStart..<(nameStart + Int(nameLength)))
            guard let path = String(data: nameData, encoding: .utf8) else { throw ZIPArchiveError.invalidArchive }
            try validate(path: path)
            let data = archive.subdata(in: dataStart..<dataEnd)
            guard try CRC32.checksum(data) == checksum else { throw ZIPArchiveError.checksumMismatch(path) }
            entries.append(ZIPArchiveEntry(path: path, data: data))
            offset = dataEnd
        }
        guard !entries.isEmpty else { throw ZIPArchiveError.invalidArchive }
        return entries
    }

    private func validate(path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard
            !path.isEmpty,
            !path.hasPrefix("/"),
            !path.contains("\\"),
            !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { throw ZIPArchiveError.invalidPath(path) }
    }
}

private enum CRC32 {
    static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) throws -> UInt32 {
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var crc = UInt32.max
            for index in bytes.indices {
                if index.isMultiple(of: 65_536) { try Task.checkCancellation() }
                crc = (crc >> 8) ^ table[Int((crc ^ UInt32(bytes[index])) & 0xFF)]
            }
            return crc ^ UInt32.max
        }
    }
}

extension Data {
    fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    fileprivate func littleEndian<T: FixedWidthInteger>(at offset: Int) throws -> T {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else {
            throw ZIPArchiveError.invalidArchive
        }
        var value: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + MemoryLayout<T>.size))
        }
        return T(littleEndian: value)
    }
}
