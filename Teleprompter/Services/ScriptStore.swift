import PDFKit
import Compression
import Foundation
import UIKit

enum ScriptStoreError: LocalizedError {
    case emptyClipboard
    case emptyFile
    case unreadableText
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "В буфере обмена нет текста. Скопируйте сценарий и попробуйте ещё раз."
        case .emptyFile:
            return "Выбранный файл пуст."
        case .unreadableText:
            return "Не удалось распознать кодировку файла. Сохраните его в UTF-8 или UTF-16 с расширением .txt."
        case .fileTooLarge:
            return "Файл слишком большой. Максимальный размер текстового сценария — 20 МБ."
        }
    }
}

@MainActor
final class ScriptStore: ObservableObject {
    @Published private(set) var scripts: [PrompterScript] = []
    @Published var errorMessage: String?

    private let fileURL: URL
    private let defaults: UserDefaults
    private let seededKey = "scripts.seeded.v1"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("Teleprompter/scripts.json", isDirectory: false)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    func script(id: UUID) -> PrompterScript? {
        scripts.first { $0.id == id }
    }

    @discardableResult
    func add(_ script: PrompterScript) -> PrompterScript {
        scripts.append(script)
        sort()
        persist()
        return script
    }

    func update(_ script: PrompterScript) {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        guard scripts[index] != script else { return }
        var updated = script
        updated.updatedAt = .now
        scripts[index] = updated
        sort()
        persist()
    }

    func delete(id: UUID) {
        scripts.removeAll { $0.id == id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { scripts[$0].id }
        scripts.removeAll { ids.contains($0.id) }
        persist()
    }

    @discardableResult
    func duplicate(id: UUID) -> PrompterScript? {
        guard let original = script(id: id) else { return nil }
        let copy = PrompterScript(
            title: original.displayTitle + " — копия",
            text: original.text
        )
        return add(copy)
    }

    @discardableResult
    func createFromClipboard() throws -> PrompterScript {
        guard let rawText = UIPasteboard.general.string else {
            throw ScriptStoreError.emptyClipboard
        }
        let cleaned = Self.cleanImportedText(rawText)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScriptStoreError.emptyClipboard
        }
        return add(PrompterScript(title: "Из буфера обмена", text: cleaned))
    }

    @discardableResult
    func importText(from url: URL) throws -> PrompterScript {
        let hasScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let rawTitle = url.deletingPathExtension().lastPathComponent
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Импортированный сценарий" : rawTitle
        let cleaned = try Self.extractDocumentTextV2(from: url)

        let script = PrompterScript(title: title, text: cleaned)
        return add(script)
    }

    func exportTemporaryFile(for script: PrompterScript) -> URL? {
        let safeName = script.displayTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).txt")
        do {
            try script.text.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    private static func cleanImportedText(_ raw: String) -> String {
        var result = raw
        if result.hasPrefix("\u{FEFF}") {
            result.removeFirst()
        }
        return result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func load() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                scripts = try decoder.decode([PrompterScript].self, from: data)
                sort()
            } else if !defaults.bool(forKey: seededKey) {
                scripts = [.sample]
                defaults.set(true, forKey: seededKey)
                persist()
            }
        } catch {
            errorMessage = "Не удалось открыть библиотеку: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(scripts)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            errorMessage = "Не удалось сохранить сценарии: \(error.localizedDescription)"
        }
    }

    private func sort() {
        scripts.sort { $0.updatedAt > $1.updatedAt }
    }
}

// BEGIN_DOC_EXTRACTOR_V2
fileprivate extension ScriptStore {
    static func extractDocumentTextV2(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let extractedText: String

        switch ext {
        case "pdf":
            extractedText = try extractPDFTextV2(from: url)
        case "docx":
            let data = try Data(contentsOf: url)
            extractedText = try extractDOCXTextV2(from: data)
        case "rtf", "rtfd":
            let data = try Data(contentsOf: url)
            extractedText = try extractRichTextV2(from: data)
        case "doc":
            let data = try Data(contentsOf: url)
            extractedText = try extractLegacyDocTextV2(from: data)
        default:
            let data = try Data(contentsOf: url)
            extractedText = try decodePlainTextV2(from: data)
        }

        let cleaned = extractedText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            throw NSError(
                domain: "ScriptStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Файл пуст или не содержит читаемого текста."]
            )
        }
        return cleaned
    }

    static func extractPDFTextV2(from url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
            throw NSError(domain: "ScriptStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать PDF-файл."])
        }
        var pages: [String] = []
        for index in 0..<pdf.pageCount {
            if let pageText = pdf.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pageText.isEmpty {
                pages.append(pageText)
            }
        }
        return pages.joined(separator: "\n\n")
    }

    static func extractRichTextV2(from data: Data) throws -> String {
        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        return try decodePlainTextV2(from: data)
    }

    static func extractLegacyDocTextV2(from data: Data) throws -> String {
        if let rtf = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ), !rtf.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rtf.string
        }
        if let html = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ), !html.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return html.string
        }
        if data.count >= 4, data[0] == 0x50, data[1] == 0x4B {
            if let docx = try? extractDOCXTextV2(from: data), !docx.isEmpty {
                return docx
            }
        }
        let binaryText = extractReadableUnicodeRunFromBinaryDocV2(data)
        if !binaryText.isEmpty {
            return binaryText
        }
        return try decodePlainTextV2(from: data)
    }

    static func extractReadableUnicodeRunFromBinaryDocV2(_ data: Data) -> String {
        var chunks: [String] = []
        var currentScalars: [UnicodeScalar] = []
        let bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count {
            let code = UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
            let isRussianOrAscii = (code >= 0x0400 && code <= 0x045F) ||
                                   (code >= 0x0020 && code <= 0x007E) ||
                                   code == 0x000A || code == 0x000D || code == 0x0009
            if isRussianOrAscii, let scalar = UnicodeScalar(code) {
                currentScalars.append(scalar)
            } else {
                if currentScalars.count >= 12 {
                    let str = String(String.UnicodeScalarView(currentScalars))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if str.count >= 12 {
                        chunks.append(str)
                    }
                }
                currentScalars.removeAll(keepingCapacity: true)
            }
            i += 2
        }
        if currentScalars.count >= 12 {
            chunks.append(String(String.UnicodeScalarView(currentScalars)))
        }
        return chunks.joined(separator: "\n")
    }

    static func decodePlainTextV2(from data: Data) throws -> String {
        if data.count >= 4, data[0] == 0x50, data[1] == 0x4B,
           let docx = try? extractDOCXTextV2(from: data), !docx.isEmpty {
            return docx
        }

        if data.count >= 2 {
            if data[0] == 0xFF && data[1] == 0xFE,
               let text = String(data: data, encoding: .utf16LittleEndian) {
                return text
            }
            if data[0] == 0xFE && data[1] == 0xFF,
               let text = String(data: data, encoding: .utf16BigEndian) {
                return text
            }
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        if let cp1251 = String(data: data, encoding: .windowsCP1251) {
            return cp1251
        }

        let koi8Encoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)
        )
        if let koi8 = String(data: data, encoding: String.Encoding(rawValue: koi8Encoding)) {
            return koi8
        }

        if let latin = String(data: data, encoding: .isoLatin1) {
            return latin
        }

        throw NSError(domain: "ScriptStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Не удалось определить кодировку файла."])
    }

    static func extractDOCXTextV2(from archiveData: Data) throws -> String {
        guard let xmlData = extractFileFromZipV2(archiveData: archiveData, targetPath: "word/document.xml"),
              let xml = String(data: xmlData, encoding: .utf8) else {
            throw NSError(domain: "ScriptStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать документ Word (.docx)."])
        }

        var text = xml
        text = text.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "<w:br/>", with: "\n")
        text = text.replacingOccurrences(of: "<w:br />", with: "\n")
        text = text.replacingOccurrences(of: "<w:cr/>", with: "\n")
        text = text.replacingOccurrences(of: "<w:tab/>", with: "\t")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return text
    }

    static func extractFileFromZipV2(archiveData: Data, targetPath: String) -> Data? {
        let bytes = [UInt8](archiveData)
        let count = bytes.count
        guard count >= 22 else { return nil }

        func readUInt16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func readUInt32(_ offset: Int) -> Int {
            Int(UInt32(bytes[offset]) |
                (UInt32(bytes[offset + 1]) << 8) |
                (UInt32(bytes[offset + 2]) << 16) |
                (UInt32(bytes[offset + 3]) << 24))
        }

        var eocdOffset = -1
        let minSearch = max(0, count - 65557)
        for i in stride(from: count - 22, through: minSearch, by: -1) {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0 else { return nil }

        let totalEntries = Int(readUInt16(eocdOffset + 10))
        var cdOffset = readUInt32(eocdOffset + 16)

        for _ in 0..<totalEntries {
            guard cdOffset + 46 <= count,
                  bytes[cdOffset] == 0x50, bytes[cdOffset + 1] == 0x4B,
                  bytes[cdOffset + 2] == 0x01, bytes[cdOffset + 3] == 0x02 else { break }

            let compressionMethod = readUInt16(cdOffset + 10)
            let compressedSize = readUInt32(cdOffset + 20)
            let uncompressedSize = readUInt32(cdOffset + 24)
            let nameLen = Int(readUInt16(cdOffset + 28))
            let extraLen = Int(readUInt16(cdOffset + 30))
            let commentLen = Int(readUInt16(cdOffset + 32))
            let localHeaderOffset = readUInt32(cdOffset + 42)

            let nameStart = cdOffset + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= count else { break }

            let entryName = String(bytes: bytes[nameStart..<nameEnd], encoding: .utf8) ?? ""
            if entryName == targetPath {
                guard localHeaderOffset + 30 <= count else { return nil }
                let localNameLen = Int(readUInt16(localHeaderOffset + 26))
                let localExtraLen = Int(readUInt16(localHeaderOffset + 28))
                let dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen
                let dataEnd = dataStart + compressedSize
                guard dataEnd <= count else { return nil }

                let slice = Data(bytes[dataStart..<dataEnd])
                if compressionMethod == 0 {
                    return slice
                } else if compressionMethod == 8 {
                    let dstCapacity = max(uncompressedSize + 1024, compressedSize * 6, 65536)
                    var dstBuffer = [UInt8](repeating: 0, count: dstCapacity)
                    let decodedSize = slice.withUnsafeBytes { srcPtr -> Int in
                        guard let baseAddress = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                        return compression_decode_buffer(
                            &dstBuffer,
                            dstCapacity,
                            baseAddress,
                            slice.count,
                            nil,
                            COMPRESSION_ZLIB
                        )
                    }
                    guard decodedSize > 0 else { return nil }
                    return Data(dstBuffer.prefix(decodedSize))
                }
            }
            cdOffset = nameEnd + extraLen + commentLen
        }
        return nil
    }
}
// END_DOC_EXTRACTOR_V2
