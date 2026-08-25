import Foundation
import Observation

@MainActor
@Observable
final class BookWorkspaceModel {
    enum SaveState: Equatable {
        case saved(Date)
        case saving
        case unsaved
        case failed(String)
    }

    let rootURL: URL
    private(set) var project: BookProject
    private(set) var selectedChapterID: UUID?
    private(set) var chapterText = ""
    private(set) var saveState: SaveState = .saved(.now)
    private(set) var errorMessage: String?

    private let repository: BookRepository
    private var savedText = ""
    private var editRevision = 0
    private var saveTask: Task<Void, Never>?

    init(project: OpenBookProject, repository: BookRepository = BookRepository()) {
        rootURL = project.rootURL
        self.project = project.metadata
        self.repository = repository
        selectedChapterID = project.metadata.chapters.first?.id
    }

    var chapters: [BookOutlineNode] {
        project.chapters
    }

    var selectedChapter: BookOutlineNode? {
        chapters.first { $0.id == selectedChapterID }
    }

    var statistics: WritingStatistics {
        WritingStatistics(markdown: chapterText)
    }

    func start() {
        loadSelectedChapter()
    }

    func selectChapter(id: UUID) {
        guard id != selectedChapterID else { return }
        flushCurrentChapter()
        selectedChapterID = id
        loadSelectedChapter()
    }

    func updateText(_ text: String) {
        guard chapterText != text else { return }
        chapterText = text
        editRevision += 1
        saveState = .unsaved
        scheduleSave(revision: editRevision)
    }

    func addChapter(title: String) {
        flushCurrentChapter()
        do {
            project = try repository.addChapter(title: title, to: project, in: rootURL)
            selectedChapterID = project.chapters.last?.id
            loadSelectedChapter()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func flushCurrentChapter() {
        saveTask?.cancel()
        guard chapterText != savedText, let chapter = selectedChapter else { return }
        do {
            try repository.writeChapter(chapterText, chapter: chapter, in: rootURL)
            savedText = chapterText
            saveState = .saved(.now)
        } catch {
            saveState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func loadSelectedChapter() {
        saveTask?.cancel()
        guard let chapter = selectedChapter else {
            chapterText = ""
            savedText = ""
            return
        }
        do {
            let content = try repository.readChapter(chapter, in: rootURL)
            chapterText = content
            savedText = content
            saveState = .saved(.now)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSave(revision: Int) {
        saveTask?.cancel()
        guard
            let chapter = selectedChapter,
            let relativePath = chapter.relativePath,
            let destinationURL = try? repository.safeURL(for: relativePath, in: rootURL)
        else { return }
        let content = chapterText
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.saveState = .saving
                try await Task.detached(priority: .utility) {
                    try AtomicFileWriter.write(content, to: destinationURL)
                }.value
                guard let self, revision == self.editRevision else { return }
                self.savedText = content
                self.saveState = .saved(.now)
            } catch is CancellationError {
                return
            } catch {
                self?.saveState = .failed(error.localizedDescription)
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}
