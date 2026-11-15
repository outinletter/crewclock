import SwiftUI
import PhotosUI
import PDFKit
import Vision
import CoreImage
import UniformTypeIdentifiers

@MainActor @Observable
final class ImportCoordinator {
    struct Review {
        var flights: [ParsedFlight]
        var duties: [Duty]
    }
    enum Sheet: Identifiable {
        case text, manual, review(Review)
        var id: String {
            switch self {
            case .text: return "text"
            case .manual: return "manual"
            case .review: return "review"
            }
        }
    }
    var showMenu = false
    var showFiles = false
    var showPhotos = false
    var sheet: Sheet?
    var photo: PhotosPickerItem?
    var working = false
}

struct AddRosterToolbar: ToolbarContent {
    @Environment(ImportCoordinator.self) private var importer
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { importer.showMenu = true } label: { Label("Add Roster", systemImage: "plus") }
        }
    }
}

struct RosterImportModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(ImportCoordinator.self) private var importer

    private static let fileTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText]
        for ext in ["ics", "ical"] { if let t = UTType(filenameExtension: ext) { types.append(t) } }
        return types
    }()

    func body(content: Content) -> some View {
        @Bindable var importer = importer
        content
            .confirmationDialog("Add flight", isPresented: $importer.showMenu, titleVisibility: .visible) {
                Button("Import PDF / ICS calendar") { importer.showFiles = true }
                Button("Import roster image") { importer.showPhotos = true }
                Button("Paste schedule text") { importer.sheet = .text }
                Button("Enter flight manually") { importer.sheet = .manual }
            } message: {
                Text("Files and images are read on this device only. Review before saving.")
            }
            .fileImporter(isPresented: $importer.showFiles, allowedContentTypes: Self.fileTypes) { result in
                guard case .success(let url) = result else { return }
                load { try await RosterOCR.text(fromFile: url) }
            }
            .photosPicker(isPresented: $importer.showPhotos, selection: $importer.photo, matching: .images)
            .onChange(of: importer.photo) { _, item in
                guard let item else { return }
                importer.photo = nil
                load {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        throw AppError("Unable to read the selected image.")
                    }
                    return try await RosterOCR.text(from: image)
                }
            }
            .sheet(item: $importer.sheet) { sheet in
                switch sheet {
                case .text:
                    TextRosterSheet { text in process(text) }
                case .manual:
                    FlightEditorSheet(existing: nil, home: store.home)
                case .review(let review):
                    ReviewSheet(review: review)
                }
            }
            .overlay {
                if importer.working {
                    ProgressView("Reading roster…").padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
    }

    private func load(_ read: @escaping () async throws -> String) {
        importer.working = true
        Task {
            do {
                let text = try await read()
                importer.working = false
                process(text)
            } catch {
                importer.working = false
                store.notice = error.localizedDescription
            }
        }
    }

    private func process(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let duties = store.parser.nonFlightDays(text)
        do {
            var flights: [ParsedFlight] = []
            do {
                flights = try store.parser.parse(text)
            } catch let error as AppError where !duties.isEmpty && error.message.hasPrefix("No dated flights") {
                flights = []
            }
            importer.sheet = .review(.init(flights: flights, duties: duties))
        } catch {
            importer.sheet = nil
            store.notice = error.localizedDescription
        }
    }
}

struct TextRosterSheet: View {
    let onPreview: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 180).autocorrectionDisabled()
                } header: {
                    Text("Roster text")
                } footer: {
                    Text("Paste ICS, or text copied from a full monthly roster (include month/year and date headings). For calendar images, Import roster image preserves date columns more reliably.\nFlight lines: 2026-11-02 KE955 ICN IST 13:55\nOptional arrival: 2026-11-02 20:05. All times are airport-local.")
                }
            }
            .navigationTitle("Paste roster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Preview") { onPreview(text) } }
            }
        }
    }
}

struct ReviewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let review: ImportCoordinator.Review
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(review.flights.count) flights · \(review.duties.count) non-flight entries. Matching dated routes will be updated; other existing flights are retained. Confirm airport-local times before scheduling.")
                        .font(.footnote)
                }
                Section("Flights") {
                    ForEach(review.flights) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(store.importChange(f)) · \(Fmt.ymd(f.departure, zone: store.zone(f.from))) \(f.number) \(f.from) → \(f.to)")
                                .font(.subheadline.weight(.semibold))
                            if let old = try? store.matchingFlight(f) {
                                Text("Before: " + store.timesText(from: old.from, to: old.to, departure: old.departure, arrival: old.arrival))
                                    .font(.caption).foregroundStyle(Color.ccMuted)
                            }
                            Text("After: " + store.timesText(from: f.from, to: f.to, departure: f.departure, arrival: f.arrival))
                                .font(.caption).foregroundStyle(Color.ccMuted)
                        }
                    }
                }
                if !review.duties.isEmpty {
                    Section("Non-flight days") {
                        ForEach(review.duties) { d in
                            LabeledContent(d.date) { Text("\(d.category) · \(d.label)") }.font(.footnote)
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Review roster changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        saving = true
                        Task {
                            do {
                                try await store.importFlights(review.flights, duties: review.duties)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}

enum RosterOCR {
    static func text(from image: UIImage) async throws -> String {
        // Render orientation before OCR so camera and rotated screenshots share coordinates.
        let factor = min(1, 4096 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = normalized.cgImage else { throw AppError("Unable to read the selected image.") }
        return try await Task.detached(priority: .userInitiated) { try recognizeCalendar(cg) }.value
    }

    static func text(fromFile url: URL) async throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 5_000_000 else { throw AppError("Choose a roster smaller than 5 MB.") }
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(data: data), pdf.pageCount > 0, pdf.pageCount <= 12 else {
                throw AppError("Choose a PDF with 1–12 pages.")
            }
            var images: [CGImage] = []
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let thumb = page.thumbnail(of: CGSize(width: 2400, height: 2400 * bounds.height / bounds.width), for: .mediaBox)
                if let cg = thumb.cgImage { images.append(cg) }
            }
            return try await Task.detached(priority: .userInitiated) {
                let pages = try images.map { try recognizeCalendar($0) }
                let months = Set(pages.compactMap { $0.components(separatedBy: "\n").first })
                guard months.count == 1, !pages.isEmpty else {
                    throw AppError("Import one monthly roster at a time. Each PDF page must contain a complete monthly calendar.")
                }
                return pages.joined(separator: "\n")
            }.value
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw AppError("Use a UTF-8 calendar or text file.")
        }
        return text
    }

    /// Geometry preserves calendar cells; plain OCR reading order can mix adjacent dates.
    nonisolated static func recognizeCalendar(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, observation.boundingBox)
        }
        let monthPattern = #"(?i)^(January|February|March|April|May|June|July|August|September|October|November|December)\s+20[0-9]{2}$"#
        guard let title = lines.first(where: { $0.0.range(of: monthPattern, options: .regularExpression) != nil })?.0 else {
            throw AppError("Month and year were not recognized. Choose a full, clear monthly roster image.")
        }
        let dayPattern = #"(?i)^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+[0-9]{1,2}$"#
        let anchors = lines.filter { $0.0.range(of: dayPattern, options: .regularExpression) != nil }
        guard anchors.count >= 28 else { throw AppError("Calendar dates are incomplete. Choose the full monthly roster.") }
        func day(_ text: String) -> Int { Int(text.split(separator: " ").last ?? "") ?? 0 }
        var output = [title]
        let ordered = anchors.sorted { day($0.0) < day($1.0) }
        let xs = anchors.map { $0.1.minX }.sorted()
        let left = xs[0] - 0.008
        let columnWidth = (xs[xs.count - 1] - xs[0]) / 6
        let context = CIContext(options: [.cacheIntermediates: false])
        let width = CGFloat(image.width), height = CGFloat(image.height)
        for anchor in ordered {
            let column = ((anchor.1.minX - left) / columnWidth).rounded(.down)
            let nextRow = anchors.filter { $0.1.midY < anchor.1.midY - 0.04 }.map { $0.1.midY }.max() ?? 0
            let top = anchor.1.midY - 0.006
            let bottom = nextRow + 0.015
            let x = max(0, left + column * columnWidth)
            let rect = CGRect(x: x * width, y: (1 - top) * height,
                              width: min(columnWidth, 1 - x) * width,
                              height: max(0.001, top - bottom) * height).integral
            guard let cropped = image.cropping(to: rect) else { continue }
            let scaled = CIImage(cgImage: cropped).transformed(by: CGAffineTransform(scaleX: 3, y: 3))
            let enlarged = context.createCGImage(scaled, from: scaled.extent) ?? cropped
            let cellRequest = VNRecognizeTextRequest()
            cellRequest.recognitionLevel = .accurate
            cellRequest.recognitionLanguages = ["en-US"]
            cellRequest.usesLanguageCorrection = false
            cellRequest.customWords = ["KE", "DH", "ICN", "IST", "PRG", "DFW", "DPS", "HKT", "GMP"]
            try VNImageRequestHandler(cgImage: enlarged).perform([cellRequest])
            let cell = (cellRequest.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            output.append(anchor.0)
            output.append(contentsOf: cell.compactMap { $0.topCandidates(1).first?.string })
        }
        return output.joined(separator: "\n")
    }
}
