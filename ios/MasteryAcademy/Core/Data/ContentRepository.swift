import Foundation
import Observation

/// Loads the catalog and courses. Bundled content always works offline; a newer copy downloaded from the
/// server (Caches/content) is preferred when its version matches the catalog.
@MainActor
@Observable
final class ContentRepository {
    private(set) var catalog: [CourseSummary] = []
    private(set) var loadError: String?
    private var courses: [String: Course] = [:]
    private var loading: [String: Task<Course, Error>] = [:]

    /// Courses with a newer version on the server, filled by `checkForUpdates`.
    private(set) var updatesAvailable: Set<String> = []
    private(set) var downloading: Set<String> = []
    private(set) var downloads: [String: DownloadRecord] = [:]
    private var remoteSummaries: [String: CourseSummary] = [:]

    private let bundle: Bundle
    private let cacheDirectory: URL

    init(bundle: Bundle = .main, cacheDirectory: URL? = nil) {
        self.bundle = bundle
        self.cacheDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("content", isDirectory: true)
        loadCatalog()
        loadDownloads()
    }

    var availableCourses: [CourseSummary] { catalog.filter { $0.isAvailable } }

    func summary(_ id: String) -> CourseSummary? { catalog.first { $0.id == id } }

    /// Groups in first-appearance order, available courses first inside each group.
    var groups: [(name: String, courses: [CourseSummary])] {
        var order: [String] = []
        var byGroup: [String: [CourseSummary]] = [:]
        for course in catalog {
            if byGroup[course.group] == nil { order.append(course.group) }
            byGroup[course.group, default: []].append(course)
        }
        return order.map { name in
            let list = byGroup[name] ?? []
            return (name, list.filter { $0.isAvailable } + list.filter { !$0.isAvailable })
        }
    }

    private func loadCatalog() {
        let cached = cacheDirectory.appendingPathComponent("catalog.json")
        let candidates = [cached, bundle.url(forResource: "catalog", withExtension: "json")].compactMap { $0 }
        for url in candidates {
            if let data = try? Data(contentsOf: url), let decoded = try? JSONCoding.decoder().decode(Catalog.self, from: data) {
                catalog = decoded.courses
                loadError = nil
                return
            }
        }
        loadError = "The course catalog is missing from the app."
    }

    /// Decodes off the main actor; concurrent callers share one load.
    func course(_ id: String) async throws -> Course {
        if let course = courses[id] { return course }
        if let running = loading[id] { return try await running.value }
        let expected = summary(id)?.version
        let cached = cacheDirectory.appendingPathComponent("course-\(id).json")
        let bundled = bundle.url(forResource: "course-\(id)", withExtension: "json")
        let task = Task.detached(priority: .userInitiated) { () throws -> Course in
            let decoder = JSONCoding.decoder()
            if let data = try? Data(contentsOf: cached), let course = try? decoder.decode(Course.self, from: data), course.version == expected {
                return course
            }
            guard let bundled else { throw ContentError.notInstalled }
            return try decoder.decode(Course.self, from: Data(contentsOf: bundled))
        }
        loading[id] = task
        defer { loading[id] = nil }
        let course = try await task.value
        courses[id] = course
        return course
    }

    func webPageURL(for summary: CourseSummary) -> URL? {
        guard let name = summary.web else { return nil }
        return bundle.url(forResource: name, withExtension: "html")
    }

    /// Asks the server for the catalog and downloads any course whose version differs from what is installed.
    /// Returns the ids that were updated. Content is validated by decoding before it replaces the cache.
    func refresh(using client: APIClient) async throws -> [String] {
        let remote: Catalog = try await client.send(.listCourses)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        var updated: [String] = []
        for summary in remote.courses where summary.isAvailable {
            let installed = try? await course(summary.id)
            if installed?.version == summary.version { continue }
            let data = try await client.sendRaw(.getCourse(courseId: summary.id))
            let envelope = try JSONCoding.decoder().decode(DataEnvelope<Course>.self, from: data)
            guard envelope.data.version == summary.version else { continue }
            // Store the course object itself, not the envelope, so the loader reads one shape.
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let inner = object["data"] {
                try JSONSerialization.data(withJSONObject: inner).write(to: cacheDirectory.appendingPathComponent("course-\(summary.id).json"), options: .atomic)
                courses[summary.id] = envelope.data
                updated.append(summary.id)
            }
        }
        try JSONCoding.encoder().encode(remote).write(to: cacheDirectory.appendingPathComponent("catalog.json"), options: .atomic)
        catalog = remote.courses
        return updated
    }
}

enum ContentError: LocalizedError {
    case notInstalled
    case notOnServer
    case waitingForWiFi

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "This course is not installed yet."
        case .notOnServer: return "The server does not have this course."
        case .waitingForWiFi: return "Downloads are set to Wi-Fi only. Connect to Wi-Fi or change the setting."
        }
    }
}

/// What is known about a downloaded copy of a course without opening the file.
struct DownloadRecord: Codable, Equatable {
    var version: String
    var bytes: Int
    var date: Date
}

enum CourseSource: Equatable {
    case bundled
    case downloaded
    case missing
}

struct InstalledCourse: Equatable {
    let source: CourseSource
    let bytes: Int
    let version: String?
    let date: Date?
}

// MARK: Downloads

extension ContentRepository {
    private var downloadsFile: URL { cacheDirectory.appendingPathComponent("downloads.json") }
    private func courseFile(_ id: String) -> URL { cacheDirectory.appendingPathComponent("course-\(id).json") }

    fileprivate func loadDownloads() {
        guard let data = try? Data(contentsOf: downloadsFile),
              let decoded = try? JSONCoding.decoder().decode([String: DownloadRecord].self, from: data) else { return }
        // A record without its file is stale (the system may clear Caches).
        downloads = decoded.filter { FileManager.default.fileExists(atPath: courseFile($0.key).path) }
    }

    private func saveDownloads() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? JSONCoding.encoder().encode(downloads).write(to: downloadsFile, options: .atomic)
    }

    private func saveCatalog() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? JSONCoding.encoder().encode(Catalog(schemaVersion: 1, courses: catalog)).write(to: cacheDirectory.appendingPathComponent("catalog.json"), options: .atomic)
    }

    private func bundledCatalog() -> [CourseSummary] {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json"), let data = try? Data(contentsOf: url),
              let decoded = try? JSONCoding.decoder().decode(Catalog.self, from: data) else { return [] }
        return decoded.courses
    }

    /// Where the course on this device comes from, and how large it is.
    func installed(_ id: String) -> InstalledCourse {
        if let record = downloads[id], record.version == summary(id)?.version {
            return InstalledCourse(source: .downloaded, bytes: record.bytes, version: record.version, date: record.date)
        }
        if let url = bundle.url(forResource: "course-\(id)", withExtension: "json") {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            return InstalledCourse(source: .bundled, bytes: size, version: summary(id)?.version, date: nil)
        }
        return InstalledCourse(source: .missing, bytes: 0, version: nil, date: nil)
    }

    var downloadedBytes: Int { downloads.values.reduce(0) { $0 + $1.bytes } }

    /// Asks the server for its catalog and records which courses differ from what is installed. Downloads nothing.
    @discardableResult
    func checkForUpdates(using client: APIClient) async throws -> Set<String> {
        let remote: Catalog = try await client.send(.listCourses)
        remoteSummaries = Dictionary(remote.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed: Set<String> = []
        for item in remote.courses where item.isAvailable {
            let local = summary(item.id)
            if local == nil || local?.version != item.version || installed(item.id).source == .missing {
                changed.insert(item.id)
            }
        }
        updatesAvailable = changed
        return changed
    }

    /// Downloads one course, checks that it decodes and matches the server's catalog, then makes it the installed copy.
    /// Progress, notes and highlights are untouched because they are keyed by lesson id.
    func download(_ id: String, using client: APIClient, wifiOnly: Bool = false) async throws {
        if downloading.contains(id) { return }
        if wifiOnly, await Connectivity.isExpensive() { throw ContentError.waitingForWiFi }
        downloading.insert(id)
        defer { downloading.remove(id) }
        if remoteSummaries[id] == nil { try await checkForUpdates(using: client) }
        guard let remote = remoteSummaries[id] else { throw ContentError.notOnServer }
        let data = try await client.sendRaw(.getCourse(courseId: id))
        let envelope = try JSONCoding.decoder().decode(DataEnvelope<Course>.self, from: data)
        guard envelope.data.version == remote.version,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let inner = object["data"] else {
            throw ContentError.notOnServer
        }
        // The course object itself is stored, not the envelope, so the loader reads one shape.
        let body = try JSONSerialization.data(withJSONObject: inner)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try body.write(to: courseFile(id), options: .atomic)
        downloads[id] = DownloadRecord(version: remote.version, bytes: body.count, date: Date())
        saveDownloads()
        courses[id] = envelope.data
        if let index = catalog.firstIndex(where: { $0.id == id }) { catalog[index] = remote } else { catalog.append(remote) }
        saveCatalog()
        updatesAvailable.remove(id)
    }

    /// Removes the downloaded copy. The course falls back to the version that ships in the app, if there is one.
    func deleteDownload(_ id: String) {
        try? FileManager.default.removeItem(at: courseFile(id))
        downloads[id] = nil
        saveDownloads()
        courses[id] = nil
        if let original = bundledCatalog().first(where: { $0.id == id }), let index = catalog.firstIndex(where: { $0.id == id }) {
            catalog[index] = original
        }
        saveCatalog()
    }

    func deleteAllDownloads() {
        for id in Array(downloads.keys) { deleteDownload(id) }
    }
}
