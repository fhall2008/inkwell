import SwiftUI

enum Theme {
    static let accent = Color(red: 0.184, green: 0.357, blue: 0.918)
    static let paper = Color(red: 0.965, green: 0.957, blue: 0.937)
    static let sidebar = Color(red: 0.925, green: 0.910, blue: 0.875)
    static let ink = Color(red: 0.106, green: 0.141, blue: 0.188)
    static let hairline = Color(red: 0.851, green: 0.831, blue: 0.780)
}

struct Folder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

struct PlacedImage: Identifiable, Codable, Hashable {
    var id = UUID()
    var file: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ObjectKind: String, Codable, CaseIterable, Identifiable {
    case text, line, arrow, rectangle, ellipse, triangle, star, sticky, checklist, table, stamp

    var id: String { rawValue }
    static let shapes: [ObjectKind] = [.line, .arrow, .rectangle, .ellipse, .triangle, .star]

    var title: String {
        switch self {
        case .text: "Text box"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Circle"
        case .triangle: "Triangle"
        case .star: "Star"
        case .sticky: "Sticky note"
        case .checklist: "Checklist"
        case .table: "Table"
        case .stamp: "Stamp"
        }
    }

    var icon: String {
        switch self {
        case .text: "textformat"
        case .line: "minus"
        case .arrow: "arrow.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .star: "star"
        case .sticky: "note.text"
        case .checklist: "checklist"
        case .table: "tablecells"
        case .stamp: "seal"
        }
    }
}

enum TextDesign: String, Codable, CaseIterable, Identifiable {
    case sans, serif, rounded, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sans: "Sans"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .mono: "Mono"
        }
    }
}

enum ListStyle: String, Codable, CaseIterable, Identifiable {
    case none, bullet, numbered
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "No list"
        case .bullet: "Bullets"
        case .numbered: "Numbered"
        }
    }
}

struct CheckItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text = ""
    var done = false
}

/// Anything you can place on a page above the template: text, shapes, sticky notes, checklists, tables, stamps.
struct PageObject: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: ObjectKind
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var colorHex = "#1B2430"      // stroke and text colour
    var fillHex: String?          // shape fill, sticky colour
    var lineWidth = 3.0
    var text = ""                 // text box, sticky note, stamp
    var fontSize = 18.0
    var design = TextDesign.sans
    var bold = false
    var italic = false
    var list = ListStyle.none
    var items: [CheckItem] = []   // checklist
    var cells: [[String]] = []    // table

    static func make(_ kind: ObjectKind, text: String = "") -> PageObject {
        var o = PageObject(kind: kind, x: 80, y: 160, width: 220, height: 120)
        switch kind {
        case .text:
            o.width = 400; o.height = 40; o.text = text
        case .line, .arrow:
            o.width = 240; o.height = 30
        case .rectangle, .ellipse:
            break
        case .triangle:
            o.width = 180; o.height = 150
        case .star:
            o.width = 160; o.height = 160; o.fillHex = "#FFD84D"
        case .sticky:
            o.width = 220; o.height = 180; o.fillHex = "#FFE98A"; o.fontSize = 17; o.text = text
        case .checklist:
            o.width = 320; o.items = [CheckItem(), CheckItem(), CheckItem()]
        case .table:
            o.width = 420; o.fontSize = 16
            o.cells = Array(repeating: Array(repeating: "", count: 3), count: 3)
        case .stamp:
            o.width = 240; o.height = 60; o.text = text.isEmpty ? "APPROVED" : text
            o.colorHex = "#C0392B"; o.fontSize = 26; o.bold = true
        }
        return o
    }

    /// Readable text for exports; nil if the object carries none.
    var plainText: String? {
        switch kind {
        case .text, .sticky, .stamp:
            return text.isEmpty ? nil : text
        case .checklist:
            let lines = items.filter { !$0.text.isEmpty }.map { ($0.done ? "[x] " : "[ ] ") + $0.text }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        case .table:
            let rows = cells.map { $0.joined(separator: "\t") }
            return rows.allSatisfy { $0.replacingOccurrences(of: "\t", with: "").isEmpty } ? nil : rows.joined(separator: "\n")
        default:
            return nil
        }
    }
}

struct NotePage: Identifiable, Codable {
    var id = UUID()
    var drawing = Data()
    var images: [PlacedImage] = []
    var objects: [PageObject] = []
    /// Image file shown in place of the template, e.g. an imported PDF page.
    var background: String?

    init() {}

    // Tolerant decoding so notes saved by earlier versions still open.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        drawing = try c.decodeIfPresent(Data.self, forKey: .drawing) ?? Data()
        images = try c.decodeIfPresent([PlacedImage].self, forKey: .images) ?? []
        objects = try c.decodeIfPresent([PageObject].self, forKey: .objects) ?? []
        background = try c.decodeIfPresent(String.self, forKey: .background)
    }
}

struct Note: Identifiable, Codable {
    var id = UUID()
    var title = "Untitled note"
    var folderID: UUID?
    var template: TemplateKind = .ruled
    var pages: [NotePage] = [NotePage()]
    var modified = Date()

    /// Every image file this note depends on.
    var imageFiles: Set<String> {
        Set(pages.flatMap { page in page.images.map(\.file) + [page.background].compactMap { $0 } })
    }
}

/// A page the user saved as a reusable template (background style plus its ink).
struct CustomTemplate: Identifiable, Codable {
    var id = UUID()
    var name: String
    var base: TemplateKind
    var drawing: Data
}

struct NoteBackup: Codable {
    var note: Note
    var images: [String: Data]
}
