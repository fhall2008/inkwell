import Foundation
import PencilKit
import UIKit

// The shared note format. See docs/SYNC-FORMAT.md; the web portal reads and writes the same shapes.

struct WireStroke: Codable, Equatable {
    var ink: String          // "pen" | "pencil" | "highlighter"
    var color: String        // "#RRGGBB"
    var opacity: Double?
    var inkType: String?     // the original PencilKit ink, kept so the iPad can restore it
    var points: [[Double]]   // [x, y, width]
}

struct WireImage: Codable {
    var id: String
    var file: String         // image object id, "img-..."
    var mime: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

private struct LossyObject: Decodable {
    let value: PageObject?
    init(from decoder: Decoder) throws { value = try? PageObject(from: decoder) }
}

struct WirePage: Codable {
    var id: String
    var background: String?
    var strokes: [WireStroke]
    var images: [WireImage]
    var objects: [PageObject]
    /// The iPad's own drawing data. Used instead of the strokes when nothing else has edited them, so
    /// pressure, tilt and ink details survive a round trip.
    var pk: String?

    init(id: String, background: String?, strokes: [WireStroke], images: [WireImage], objects: [PageObject], pk: String?) {
        self.id = id
        self.background = background
        self.strokes = strokes
        self.images = images
        self.objects = objects
        self.pk = pk
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        background = try c.decodeIfPresent(String.self, forKey: .background)
        strokes = try c.decodeIfPresent([WireStroke].self, forKey: .strokes) ?? []
        images = try c.decodeIfPresent([WireImage].self, forKey: .images) ?? []
        // Objects this app doesn't know (from a newer web version) are skipped rather than failing the whole note.
        objects = (try c.decodeIfPresent([LossyObject].self, forKey: .objects) ?? []).compactMap(\.value)
        pk = try c.decodeIfPresent(String.self, forKey: .pk)
    }
}

struct WireNote: Codable {
    var v = 1
    var id: String
    var title: String
    var folderId: String?
    var template: String
    var modified: Double     // milliseconds since 1970
    var pages: [WirePage]
}

struct WireFolder: Codable {
    var id: String
    var name: String
}

struct WireFolders: Codable {
    var v = 1
    var folders: [WireFolder]
}

enum SyncMapper {
    // MARK: Picture ids

    /// Local files are "<uuid>.jpg"; on the server the same picture is the object "img-<uuid>".
    static func imageID(forFile file: String) -> String {
        "img-" + (file as NSString).deletingPathExtension
    }

    static func file(forImageID id: String) -> String {
        (id.hasPrefix("img-") ? String(id.dropFirst(4)) : id) + ".jpg"
    }

    static func imageIDs(in wire: WireNote) -> Set<String> {
        var ids = Set<String>()
        for page in wire.pages {
            if let bg = page.background { ids.insert(bg) }
            for image in page.images { ids.insert(image.file) }
        }
        return ids
    }

    // MARK: Note to shared format

    static func wire(from note: Note) -> WireNote {
        WireNote(
            id: note.id.uuidString,
            title: note.title,
            folderId: note.folderID?.uuidString,
            template: note.template.rawValue,
            modified: note.modified.timeIntervalSince1970 * 1000,
            pages: note.pages.map(wirePage)
        )
    }

    private static func wirePage(_ page: NotePage) -> WirePage {
        let drawing = (try? PKDrawing(data: page.drawing)) ?? PKDrawing()
        return WirePage(
            id: page.id.uuidString,
            background: page.background.map(imageID(forFile:)),
            strokes: strokes(from: drawing),
            images: page.images.map {
                WireImage(id: $0.id.uuidString, file: imageID(forFile: $0.file), mime: "image/jpeg",
                          x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            },
            objects: page.objects,
            pk: drawing.strokes.isEmpty ? nil : page.drawing.base64EncodedString()
        )
    }

    // MARK: Shared format to note

    static func note(from wire: WireNote) -> Note? {
        guard let id = UUID(uuidString: wire.id) else { return nil }
        var pages = wire.pages.map(notePage)
        if pages.isEmpty { pages = [NotePage()] }
        return Note(
            id: id,
            title: wire.title,
            folderID: wire.folderId.flatMap { UUID(uuidString: $0) },
            template: TemplateKind(rawValue: wire.template) ?? .ruled,
            pages: pages,
            modified: Date(timeIntervalSince1970: wire.modified / 1000)
        )
    }

    private static func notePage(_ wire: WirePage) -> NotePage {
        var page = NotePage()
        page.id = UUID(uuidString: wire.id) ?? UUID()
        page.background = wire.background.map(file(forImageID:))
        page.images = wire.images.map {
            PlacedImage(id: UUID(uuidString: $0.id) ?? UUID(), file: file(forImageID: $0.file),
                        x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        page.objects = wire.objects

        if let pk = wire.pk, let data = Data(base64Encoded: pk), let native = try? PKDrawing(data: data),
           strokes(from: native) == wire.strokes {
            page.drawing = data   // nothing has changed the strokes since the iPad wrote them
        } else if !wire.strokes.isEmpty {
            page.drawing = drawing(from: wire.strokes).dataRepresentation()
        }
        return page
    }

    // MARK: Ink

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    static func strokes(from drawing: PKDrawing) -> [WireStroke] {
        let light = UITraitCollection(userInterfaceStyle: .light)
        return drawing.strokes.map { stroke in
            let t = stroke.transform
            let scale = Double((t.a * t.a + t.b * t.b).squareRoot())
            let type = stroke.ink.inkType
            let kind: String
            var opacity: Double?
            switch type {
            case .marker: kind = "highlighter"; opacity = 0.35
            case .pencil: kind = "pencil"
            default: kind = "pen"
            }
            let points = stroke.path.interpolatedPoints(by: .distance(3)).map { p -> [Double] in
                let at = p.location.applying(t)
                return [round1(Double(at.x)), round1(Double(at.y)), round1(max(0.5, Double(p.size.width) * scale))]
            }
            return WireStroke(
                ink: kind,
                color: stroke.ink.color.resolvedColor(with: light).hexString,
                opacity: opacity,
                inkType: type.rawValue,
                points: points
            )
        }
    }

    static func drawing(from strokes: [WireStroke]) -> PKDrawing {
        var out: [PKStroke] = []
        for s in strokes where !s.points.isEmpty {
            let type = s.inkType.flatMap { PKInk.InkType(rawValue: $0) }
                ?? (s.ink == "highlighter" ? .marker : (s.ink == "pencil" ? .pencil : .pen))
            var points: [PKStrokePoint] = s.points.enumerated().compactMap { index, p in
                guard p.count >= 3 else { return nil }
                return PKStrokePoint(
                    location: CGPoint(x: p[0], y: p[1]),
                    timeOffset: TimeInterval(index) * 0.01,
                    size: CGSize(width: p[2], height: p[2]),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                )
            }
            if points.count == 1, let only = points.first {
                points.append(PKStrokePoint(location: only.location, timeOffset: 0.01, size: only.size,
                                            opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
            }
            guard !points.isEmpty else { continue }
            let path = PKStrokePath(controlPoints: points, creationDate: Date())
            out.append(PKStroke(ink: PKInk(type, color: UIColor(hex: s.color)), path: path))
        }
        return PKDrawing(strokes: out)
    }
}
