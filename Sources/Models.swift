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

struct NotePage: Identifiable, Codable {
    var id = UUID()
    var drawing = Data()
    var images: [PlacedImage] = []
}

struct Note: Identifiable, Codable {
    var id = UUID()
    var title = "Untitled note"
    var folderID: UUID?
    var template: TemplateKind = .ruled
    var pages: [NotePage] = [NotePage()]
    var modified = Date()
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
