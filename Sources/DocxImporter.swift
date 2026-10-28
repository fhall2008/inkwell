import UIKit

/// Converts a Word (.docx) file into a PDF so it can be imported like any other PDF.
/// Handles text with bold, italic, underline, size and colour, headings, alignment, simple lists,
/// tables and PNG/JPEG/GIF pictures. Headers, footers, text wrapping around pictures and
/// styles defined only in the document's style sheet are not reproduced.
enum DocxImporter {
    enum DocxError: Error { case unreadable }

    @MainActor
    static func pdfData(from url: URL) throws -> Data {
        let zip = try ZipReader(data: Data(contentsOf: url))
        guard let documentXML = zip.read("word/document.xml") else { throw DocxError.unreadable }

        var rels: [String: String] = [:]
        if let relData = zip.read("word/_rels/document.xml.rels") {
            let relParser = RelsParser()
            let parser = XMLParser(data: relData)
            parser.delegate = relParser
            parser.parse()
            rels = relParser.map
        }
        let relMap = rels

        let builder = HTMLBuilder { rid in
            guard let target = relMap[rid] else { return nil }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
            guard let data = zip.read(path) else { return nil }
            let ext = (path as NSString).pathExtension.lowercased()
            let mimes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif"]
            guard let mime = mimes[ext] else { return nil }
            return "data:\(mime);base64,\(data.base64EncodedString())"
        }
        let parser = XMLParser(data: documentXML)
        parser.delegate = builder
        guard parser.parse() else { throw DocxError.unreadable }
        return render(html: builder.document)
    }

    /// Lays the HTML out onto A4 pages with 54 pt margins.
    @MainActor
    private static func render(html: String) -> Data {
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let printable = paper.insetBy(dx: 54, dy: 54)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        let bounds = UIGraphicsGetPDFContextBounds()
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: bounds)
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
}

// MARK: - document.xml to HTML

private final class HTMLBuilder: NSObject, XMLParserDelegate {
    private let imageForRID: (String) -> String?
    private var html = ""

    private var para = ""
    private var paraStyle = ""
    private var jc = ""
    private var isList = false

    private var runText = ""
    private var bold = false
    private var italic = false
    private var underline = false
    private var size: Double?
    private var color: String?
    private var inText = false

    private var extentWidth: Double?
    private var fallbackDepth = 0

    init(imageForRID: @escaping (String) -> String?) { self.imageForRID = imageForRID }

    var document: String {
        "<html><body style=\"font-family:-apple-system,Helvetica,Arial;font-size:11pt;line-height:1.25\">\(html)</body></html>"
    }

    private func isOn(_ a: [String: String]) -> Bool {
        let v = a["w:val"]?.lowercased()
        return v != "0" && v != "false" && v != "off"
    }

    private func resetRun() {
        runText = ""
        bold = false
        italic = false
        underline = false
        size = nil
        color = nil
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func flushRun() {
        guard !runText.isEmpty else { return }
        var css = ""
        if bold { css += "font-weight:bold;" }
        if italic { css += "font-style:italic;" }
        if underline { css += "text-decoration:underline;" }
        if let size { css += "font-size:\(size)pt;" }
        if let color { css += "color:#\(color);" }
        let text = escape(runText)
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\t", with: "&emsp;&emsp;")
        para += css.isEmpty ? text : "<span style=\"\(css)\">\(text)</span>"
        runText = ""
    }

    private func endParagraph() {
        let tag: String
        switch paraStyle {
        case "Title", "Heading1": tag = "h1"
        case "Heading2": tag = "h2"
        case "Heading3", "Heading4": tag = "h3"
        default: tag = "p"
        }
        var style = "margin:0 0 6pt 0;"
        switch jc {
        case "center": style += "text-align:center;"
        case "right": style += "text-align:right;"
        case "both": style += "text-align:justify;"
        default: break
        }
        let content = para.isEmpty ? "&nbsp;" : (isList ? "• " + para : para)
        html += "<\(tag) style=\"\(style)\">\(content)</\(tag)>"
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        // Word writes some content twice (a modern version and a fallback); keep the first.
        if name == "mc:Fallback" { fallbackDepth += 1 }
        guard fallbackDepth == 0 else { return }

        switch name {
        case "w:p":
            para = ""; paraStyle = ""; jc = ""; isList = false
        case "w:pStyle": paraStyle = a["w:val"] ?? ""
        case "w:jc": jc = a["w:val"] ?? ""
        case "w:numPr": isList = true
        case "w:r": resetRun()
        case "w:b": bold = isOn(a)
        case "w:i": italic = isOn(a)
        case "w:u": underline = (a["w:val"] ?? "single") != "none"
        case "w:sz": size = (Double(a["w:val"] ?? "") ?? 22) / 2
        case "w:color":
            let v = a["w:val"] ?? "auto"
            color = v == "auto" ? nil : v
        case "w:t": inText = true
        case "w:tab": runText += "\t"
        case "w:br":
            if a["w:type"] == "page" {
                flushRun()
                para += "<div style=\"page-break-after:always\"></div>"
            } else {
                runText += "\n"
            }
        case "wp:extent":
            extentWidth = (Double(a["cx"] ?? "") ?? 0) / 9525
        case "a:blip":
            if let rid = a["r:embed"], let uri = imageForRID(rid) {
                flushRun()
                let width = extentWidth.map { " width=\"\(Int(min(max($0, 20), 600)))\"" } ?? ""
                para += "<img src=\"\(uri)\"\(width)>"
            }
        case "w:tbl": html += "<table border=\"1\" cellspacing=\"0\" cellpadding=\"4\" style=\"border-collapse:collapse;width:100%\">"
        case "w:tr": html += "<tr>"
        case "w:tc": html += "<td style=\"vertical-align:top\">"
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        if name == "mc:Fallback" {
            fallbackDepth = max(0, fallbackDepth - 1)
            return
        }
        guard fallbackDepth == 0 else { return }

        switch name {
        case "w:t": inText = false
        case "w:r": flushRun()
        case "w:p": endParagraph()
        case "w:tc": html += "</td>"
        case "w:tr": html += "</tr>"
        case "w:tbl": html += "</table>"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText && fallbackDepth == 0 { runText += string }
    }
}

private final class RelsParser: NSObject, XMLParserDelegate {
    var map: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        if name == "Relationship", let id = a["Id"], let target = a["Target"] { map[id] = target }
    }
}

// MARK: - Minimal ZIP reader

struct ZipReader {
    private struct Entry {
        let offset: Int
        let compressedSize: Int
        let method: Int
    }

    private let data: Data
    private var entries: [String: Entry] = [:]

    init(data: Data) throws {
        self.data = data
        guard data.count > 22 else { throw DocxImporter.DocxError.unreadable }

        var eocd = -1
        var i = data.count - 22
        let lowest = max(0, data.count - 22 - 65535)
        while i >= lowest {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw DocxImporter.DocxError.unreadable }

        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= data.count, u32(p) == 0x02014b50 else { throw DocxImporter.DocxError.unreadable }
            let method = u16(p + 10)
            let compressed = u32(p + 20)
            let nameLen = u16(p + 28)
            let extraLen = u16(p + 30)
            let commentLen = u16(p + 32)
            let offset = u32(p + 42)
            let start = data.startIndex + p + 46
            guard start + nameLen <= data.endIndex else { throw DocxImporter.DocxError.unreadable }
            let name = String(decoding: data.subdata(in: start..<(start + nameLen)), as: UTF8.self)
            entries[name] = Entry(offset: offset, compressedSize: compressed, method: method)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    private func u16(_ o: Int) -> Int {
        Int(data[data.startIndex + o]) | Int(data[data.startIndex + o + 1]) << 8
    }

    private func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

    func read(_ name: String) -> Data? {
        guard let e = entries[name], e.offset + 30 <= data.count, u32(e.offset) == 0x04034b50 else { return nil }
        let start = e.offset + 30 + u16(e.offset + 26) + u16(e.offset + 28)
        guard start + e.compressedSize <= data.count else { return nil }
        let raw = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8: return try? (raw as NSData).decompressed(using: .zlib) as Data
        default: return nil
        }
    }
}
