import SwiftUI

/// What is on this device, how large it is, and what the server has that is newer.
struct DownloadsView: View {
    @Environment(ContentRepository.self) private var repository
    @Environment(AccountModel.self) private var account
    @AppStorage(ReadingKeys.wifiOnly) private var wifiOnly = false

    @State private var checking = false
    @State private var message: String?
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                        if checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(checking)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Toggle("Download on Wi-Fi only", isOn: $wifiOnly)
            } footer: {
                Text("Every course ships inside the app, so reading works with no network. A server adds newer versions of a course without an app update; set its address in Profile.")
            }

            Section("Courses") {
                ForEach(repository.availableCourses) { course in
                    DownloadRow(course: course, wifiOnly: wifiOnly) { text in message = text }
                }
            }

            if !repository.downloads.isEmpty {
                Section {
                    Button("Delete all downloads", role: .destructive) { confirmDeleteAll = true }
                } footer: {
                    Text(downloadedText)
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all downloaded courses?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete downloads", role: .destructive) { repository.deleteAllDownloads() }
        }
    }

    private var downloadedText: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(repository.downloadedBytes), countStyle: .file)
        return size + " downloaded. Deleting a download returns the course to the version in the app. Progress, notes and highlights are kept."
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do {
            let changed = try await repository.checkForUpdates(using: account.client)
            if changed.isEmpty {
                message = "Every course is up to date."
            } else if changed.count == 1 {
                message = "1 course has a newer version."
            } else {
                message = "\(changed.count) courses have a newer version."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct DownloadRow: View {
    let course: CourseSummary
    let wifiOnly: Bool
    let report: (String) -> Void

    @Environment(ContentRepository.self) private var repository
    @Environment(AccountModel.self) private var account

    var body: some View {
        let info = repository.installed(course.id)
        let hasUpdate = repository.updatesAvailable.contains(course.id)
        HStack(spacing: 12) {
            Image(systemName: course.icon).foregroundStyle(course.tintColor).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.title)
                Text(detail(info)).font(.caption).foregroundStyle(.secondary)
                if hasUpdate && info.source != .missing {
                    Text("Update available").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            Spacer()
            if repository.downloading.contains(course.id) {
                ProgressView()
            } else if hasUpdate || info.source == .missing {
                Button {
                    Task { await download() }
                } label: {
                    Image(systemName: "arrow.down.circle").font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Download or update " + course.title))
            }
        }
        .swipeActions(edge: .trailing) {
            if info.source == .downloaded {
                Button("Delete", role: .destructive) { repository.deleteDownload(course.id) }
            }
        }
    }

    private func detail(_ info: InstalledCourse) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(info.bytes), countStyle: .file)
        let version = String((info.version ?? "").prefix(8))
        switch info.source {
        case .bundled:
            return "In the app · \(size) · version \(version)"
        case .downloaded:
            let day = info.date?.formatted(date: .abbreviated, time: .omitted) ?? ""
            return "Downloaded \(day) · \(size) · version \(version)"
        case .missing:
            return "Not on this device"
        }
    }

    private func download() async {
        do {
            try await repository.download(course.id, using: account.client, wifiOnly: wifiOnly)
            report("\(course.title) is up to date.")
        } catch {
            report(error.localizedDescription)
        }
    }
}
