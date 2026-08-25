import CryptoKit
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
    private(set) var annotationDocument = AnnotationDocument()

    private let repository: BookRepository
    private let annotationRepository: AnnotationRepository
    private var savedText = ""
    private var editRevision = 0
    private var saveTask: Task<Void, Never>?

    init(
        project: OpenBookProject,
        repository: BookRepository = BookRepository(),
        annotationRepository: AnnotationRepository = AnnotationRepository()
    ) {
        rootURL = project.rootURL
        self.project = project.metadata
        self.repository = repository
        self.annotationRepository = annotationRepository
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

    var currentChapterAnnotations: [BookAnnotation] {
        guard let path = selectedChapter?.relativePath else { return [] }
        return annotationDocument.annotations
            .filter { $0.chapterRelativePath == path }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func start() {
        loadSelectedChapter()
        do {
            annotationDocument = try annotationRepository.load(in: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
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

    func reloadAfterExternalChange() {
        saveTask?.cancel()
        do {
            project = try repository.loadProject(at: rootURL)
            if !chapters.contains(where: { $0.id == selectedChapterID }) {
                selectedChapterID = chapters.first?.id
            }
            loadSelectedChapter()
            annotationDocument = try annotationRepository.load(in: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addHighlight(_ selection: ReaderSelection) {
        guard
            let chapter = selectedChapter,
            let path = chapter.relativePath,
            !selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let source = chapterText as NSString
        let selectedRange = source.range(of: selection.selectedText)
        let location = selectedRange.location == NSNotFound ? 0 : selectedRange.location
        let length = selectedRange.location == NSNotFound ? selection.selectedText.utf16.count : selectedRange.length
        let prefixStart = max(0, location - 32)
        let sourcePrefix = source.substring(with: NSRange(location: prefixStart, length: location - prefixStart))
        let suffixStart = min(source.length, location + length)
        let sourceSuffix = source.substring(
            with: NSRange(location: suffixStart, length: min(32, source.length - suffixStart))
        )
        let digest = SHA256.hash(data: Data(chapterText.utf8)).map { String(format: "%02x", $0) }.joined()
        let annotation = BookAnnotation(
            chapterRelativePath: path,
            kind: .highlight,
            selectedText: selection.selectedText,
            prefix: sourcePrefix.isEmpty ? selection.prefix : sourcePrefix,
            suffix: sourceSuffix.isEmpty ? selection.suffix : sourceSuffix,
            utf16Location: location,
            utf16Length: length,
            chapterDigest: digest
        )
        annotationDocument.annotations.append(annotation)
        saveAnnotations()
    }

    func updateNote(id: UUID, note: String) {
        guard let index = annotationDocument.annotations.firstIndex(where: { $0.id == id }) else { return }
        annotationDocument.annotations[index].note = note
        annotationDocument.annotations[index].kind = note.isEmpty ? .highlight : .note
        annotationDocument.annotations[index].modifiedAt = .now
        saveAnnotations()
    }

    func deleteAnnotation(id: UUID) {
        annotationDocument.annotations.removeAll { $0.id == id }
        saveAnnotations()
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

    private func saveAnnotations() {
        do {
            try annotationRepository.save(annotationDocument, in: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
