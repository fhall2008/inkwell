import UIKit
import Vision

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, docx, png, txt, rtf, backup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .docx: "Word document"
        case .png: "Images"
        case .txt: "Plain text"
        case .rtf: "Rich text"
        case .backup: "Inkwell backup"
        }
    }

    var detail: String {
        switch self {
        case .pdf: "Pages exactly as written. Best for sharing."
        case .docx: "Each page as a picture, plus recognised handwriting as editable text."
        case .png: "One PNG per page (zipped if more than one)."
        case .txt: "Recognised handwriting as plain text."
        case .rtf: "Recognised handwriting. Opens in Pages and TextEdit."
        case .backup: "Editable copy to move between devices."
        }
    }

    var badge: String {
        switch self {
        case .pdf: "PDF"
        case .docx: "DOCX"
        case .png: "PNG"
        case .txt: "TXT"
        case .rtf: "RTF"
        case .backup: "INK"
        }
    }

    var badgeColor: UIColor {
        switch self {
        case .pdf: UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1)
        case .docx: UIColor(red: 0.17, green: 0.34, blue: 0.60, alpha: 1)
        case .png: UIColor(red: 0.23, green: 0.49, blue: 0.37, alpha: 1)
        case .txt: UIColor(red: 0.36, green: 0.40, blue: 0.45, alpha: 1)
        case .rtf: UIColor(red: 0.54, green: 0.35, blue: 0.62, alpha: 1)
        case .backup: UIColor(red: 0.11, green: 0.14, blue: 0.19, alpha: 1)
        }
    }
}

enum ExportError: LocalizedError {
    case failed
    var errorDescription: String? { "The export could not be created." }
}

enum Exporter {
    static func export(note: Note, format: ExportFormat, includeTemplate: Bool) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try build(note: note, format: format, includeTemplate: includeTemplate)
        }.value
    }

    private static func build(note: Note, format: ExportFormat, includeTemplate: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = safeName(note.title)

        switch format {
        case .pdf:
            let url = dir.appendingPathComponent("\(base).pdf")
            try pdf(note, includeTemplate).write(to: url)
            return url

        case .png:
            let pngs = note.pages.compactMap {
                PageRenderer.render(note: note, page: $0, scale: 2, includeTemplate: includeTemplate).pngData()
            }
            guard pngs.count == note.pages.count else { throw ExportError.failed }
            if pngs.count == 1 {
                let url = dir.appendingPathComponent("\(base).png")
                try pngs[0].write(to: url)
                return url
            }
            var zip = ZipWriter()
            for (i, data) in pngs.enumerated() { zip.add("\(base) page \(i + 1).png", data) }
            let url = dir.appendingPathComponent("\(base).zip")
            try zip.finish().write(to: url)
            return url

        case .txt:
            let url = dir.appendingPathComponent("\(base).txt")
            try plainText(note).write(to: url, atomically: true, encoding: .utf8)
            return url

        case .rtf:
            let url = dir.appendingPathComponent("\(base).rtf")
            try rtf(note).write(to: url, atomically: true, encoding: .utf8)
            return url

        case .docx:
            let url = dir.appendingPathComponent("\(base).docx")
            try docx(note, includeTemplate).write(to: url)
            return url

        case .backup:
            var images: [String: Data] = [:]
            for file in note.imageFiles {
                images[file] = try? Data(contentsOf: Paths.images.appendingPathComponent(file))
            }
            let url = dir.appendingPathComponent("\(base).inkwell")
            try JSONEncoder().encode(NoteBackup(note: note, images: images)).write(to: url)
            return url
        }
    }

    private static func safeName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Note" : cleaned
    }

    // MARK: PDF

    private static func pdf(_ note: Note, _ includeTemplate: Bool) -> Data {
        let a4 = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        return UIGraphicsPDFRenderer(bounds: a4).pdfData { ctx in
            for page in note.pages {
                ctx.beginPage()
                PageRenderer.render(note: note, page: page, scale: 2.5, includeTemplate: includeTemplate).draw(in: a4)
            }
        }
    }

    // MARK: Handwriting recognition

    /// Recognised text per page. Renders ink only so template lines don't confuse Vision.
    private static func pageTexts(_ note: Note) -> [String] {
        note.pages.map { page in
            let img = PageRenderer.render(note: note, page: page, scale: 2, includeTemplate: false, includeImages: false)
            let typed = page.texts.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
            guard let cg = img.cgImage else { return typed }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            let handwriting = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            return [typed, handwriting].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    private static func plainText(_ note: Note) -> String {
        let texts = pageTexts(note)
        var out = note.title + "\n\n"
        for (i, t) in texts.enumerated() {
            if texts.count > 1 { out += "--- Page \(i + 1) ---\n" }
            out += t.isEmpty ? "(no handwriting recognised)\n\n" : t + "\n\n"
        }
        return out
    }

    // MARK: RTF

    private static func rtfEscape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "{": out += "\\{"
            case "}": out += "\\}"
            case "\n": out += "\\line "
            default:
                if scalar.value < 128 { out.unicodeScalars.append(scalar) }
                else { out += "\\u\(Int16(truncatingIfNeeded: scalar.value))?" }
            }
        }
        return out
    }

    private static func rtf(_ note: Note) -> String {
        var out = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 "
        out += "{\\b\\fs40 \(rtfEscape(note.title))}\\par\\par "
        for (i, t) in pageTexts(note).enumerated() {
            out += "{\\b Page \(i + 1)}\\par \(rtfEscape(t))\\par\\par "
        }
        return out + "}"
    }

    // MARK: DOCX

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func docx(_ note: Note, _ includeTemplate: Bool) throws -> Data {
        let texts = pageTexts(note)
        // 15.9 cm wide: fits inside A4 with 2.5 cm margins. 360000 EMU per cm.
        let cx = 15.9 * 360000
        let cy = cx * Double(PageRenderer.pageSize.height / PageRenderer.pageSize.width)
        var zip = ZipWriter()
        var body = ""
        var rels = ""

        body += "<w:p><w:r><w:rPr><w:b/><w:sz w:val=\"40\"/></w:rPr><w:t>\(xmlEscape(note.title))</w:t></w:r></w:p>"

        for (i, page) in note.pages.enumerated() {
            guard let png = PageRenderer.render(note: note, page: page, scale: 1.5, includeTemplate: includeTemplate).pngData()
            else { throw ExportError.failed }
            let n = i + 1
            zip.add("word/media/page\(n).png", png)
            rels += "<Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/page\(n).png\"/>"
            body += """
            <w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(Int(cx))" cy="\(Int(cy))"/><wp:docPr id="\(n)" name="Page \(n)" descr="Handwritten page \(n)"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="\(n)" name="page\(n).png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rId\(n)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(Int(cx))" cy="\(Int(cy))"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
            """
            if !texts[i].isEmpty {
                body += "<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Recognised text, page \(n)</w:t></w:r></w:p>"
                for line in texts[i].split(separator: "\n", omittingEmptySubsequences: false) {
                    body += "<w:p><w:r><w:t xml:space=\"preserve\">\(xmlEscape(String(line)))</w:t></w:r></w:p>"
                }
            }
            if i < note.pages.count - 1 { body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" }
        }

        let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        let document = """
        \(header)<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1418" w:right="1418" w:bottom="1418" w:left="1418" w:header="709" w:footer="709" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
        zip.add("[Content_Types].xml", Data("""
        \(header)<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
        """.utf8))
        zip.add("_rels/.rels", Data("""
        \(header)<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """.utf8))
        zip.add("word/document.xml", Data(document.utf8))
        zip.add("word/_rels/document.xml.rels", Data("""
        \(header)<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
        """.utf8))
        return zip.finish()
    }
}

// MARK: - Minimal ZIP writer (stored, no compression). Enough for DOCX and multi-page PNG exports.

struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    mutating func add(_ name: String, _ data: Data) {
        let nameBytes = Data(name.utf8)
        let crc = Self.crc32(data)
        let offset = UInt32(body.count)
        let dosDate: UInt16 = (44 << 9) | (1 << 5) | 1   // 2024-01-01

        body.le32(0x04034b50); body.le16(20); body.le16(0x0800); body.le16(0)
        body.le16(0); body.le16(dosDate); body.le32(crc)
        body.le32(UInt32(data.count)); body.le32(UInt32(data.count))
        body.le16(UInt16(nameBytes.count)); body.le16(0)
        body.append(nameBytes); body.append(data)

        central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x0800); central.le16(0)
        central.le16(0); central.le16(dosDate); central.le32(crc)
        central.le32(UInt32(data.count)); central.le32(UInt32(data.count))
        central.le16(UInt16(nameBytes.count)); central.le16(0); central.le16(0)
        central.le16(0); central.le16(0); central.le32(0); central.le32(offset)
        central.append(nameBytes)
        count += 1
    }

    func finish() -> Data {
        var out = body
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x06054b50); out.le16(0); out.le16(0)
        out.le16(count); out.le16(count)
        out.le32(UInt32(central.count)); out.le32(cdOffset); out.le16(0)
        return out
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
    mutating func le32(_ v: UInt32) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}
