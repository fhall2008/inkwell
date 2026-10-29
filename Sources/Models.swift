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

enum NoteKind: String, Codable {
    case note, notebook, whiteboard
}

/// Standard paper sizes. Sizes are portrait, in points at 96 dpi (the unit every page is drawn in).
enum PaperPreset: String, CaseIterable, Identifiable {
    case a4, a5, a6, b5, letter, legal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a4: "A4"
        case .a5: "A5"
        case .a6: "A6"
        case .b5: "B5"
        case .letter: "US Letter"
        case .legal: "US Legal"
        }
    }

    var detail: String {
        switch self {
        case .a4: "210 × 297 mm"
        case .a5: "148 × 210 mm"
        case .a6: "105 × 148 mm"
        case .b5: "176 × 250 mm"
        case .letter: "8.5 × 11 in"
        case .legal: "8.5 × 14 in"
        }
    }

    var size: CGSize {
        switch self {
        case .a4: CGSize(width: 794, height: 1123)
        case .a5: CGSize(width: 559, height: 794)
        case .a6: CGSize(width: 397, height: 559)
        case .b5: CGSize(width: 665, height: 945)
        case .letter: CGSize(width: 816, height: 1056)
        case .legal: CGSize(width: 816, height: 1344)
        }
    }

    func size(landscape: Bool) -> CGSize {
        landscape ? CGSize(width: size.height, height: size.width) : size
    }
}

/// Sizes for whiteboards, in points. They are big so there is room to spread out, and are zoomed to fit.
enum WhiteboardSize: String, CaseIterable, Identifiable {
    case small, medium, large, huge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .huge: "Huge"
        }
    }

    var size: CGSize {
        switch self {
        case .small: CGSize(width: 2000, height: 1500)
        case .medium: CGSize(width: 3000, height: 2000)
        case .large: CGSize(width: 4000, height: 3000)
        case .huge: CGSize(width: 6000, height: 4000)
        }
    }
}

/// Paper and cover colours offered when making a notebook or whiteboard.
enum PaperColours {
    static let paper: [(name: String, hex: String)] = [
        ("White", "#FFFFFF"), ("Cream", "#FBF6E9"), ("Light blue", "#EEF4FF"),
        ("Light grey", "#F2F2F2"), ("Soft yellow", "#FFF9D6"),
    ]
    static let cover: [(name: String, hex: String)] = [
        ("Blue", "#2F5BEA"), ("Clay", "#D97757"), ("Green", "#4FB286"),
        ("Purple", "#8E44AD"), ("Red", "#C0392B"), ("Charcoal", "#1B2430"),
    ]
}

struct Note: Identifiable, Codable {
    var id = UUID()
    var title = "Untitled note"
    var folderID: UUID?
    var template: TemplateKind = .ruled
    var pages: [NotePage] = [NotePage()]
    var modified = Date()
    var kind: NoteKind = .note
    /// Page size in points. Every page of a note is the same size (A4 portrait unless set otherwise).
    var pageWidth: Double = 794
    var pageHeight: Double = 1123
    /// Notebook cover colour, shown on the library card.
    var coverHex: String?
    var paperHex: String = "#FFFFFF"
    var pageNumbers = false

    var pageSize: CGSize { CGSize(width: pageWidth, height: pageHeight) }
    var isWhiteboard: Bool { kind == .whiteboard }

    /// Every image file this note depends on.
    var imageFiles: Set<String> {
        Set(pages.flatMap { page in page.images.map(\.file) + [page.background].compactMap { $0 } })
    }
}

extension Note {
    /// Tolerant decoding so notes saved before notebooks and whiteboards existed still open.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled note"
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        template = try c.decodeIfPresent(TemplateKind.self, forKey: .template) ?? .ruled
        pages = try c.decodeIfPresent([NotePage].self, forKey: .pages) ?? [NotePage()]
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
        kind = try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .note
        pageWidth = try c.decodeIfPresent(Double.self, forKey: .pageWidth) ?? 794
        pageHeight = try c.decodeIfPresent(Double.self, forKey: .pageHeight) ?? 1123
        coverHex = try c.decodeIfPresent(String.self, forKey: .coverHex)
        paperHex = try c.decodeIfPresent(String.self, forKey: .paperHex) ?? "#FFFFFF"
        pageNumbers = try c.decodeIfPresent(Bool.self, forKey: .pageNumbers) ?? false
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
