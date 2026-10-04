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
    @ObservationIgnored private var needsSave = false
    @ObservationIgnored private var editRevision = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var editorIsBusy = false
    @ObservationIgnored private var saveGeneration = 0
    private let autosaveIdleDuration: Duration
    private let autosaveClock: any AutosaveClock
    private let chapterWriteQueue = DispatchQueue(label: "InkEdit.chapter-writes", qos: .utility)

    init(
        project: OpenBookProject,
        repository: BookRepository = BookRepository(),
        annotationRepository: AnnotationRepository = AnnotationRepository(),
        autosaveIdleDuration: Duration = .seconds(5),
        autosaveClock: any AutosaveClock = ContinuousAutosaveClock()
    ) {
        rootURL = project.rootURL
        self.project = project.metadata
        self.repository = repository
        self.annotationRepository = annotationRepository
        self.autosaveIdleDuration = autosaveIdleDuration
        self.autosaveClock = autosaveClock
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
        // Do not replace an existing editor buffer when SwiftUI presents the view again.
        if selectedChapterID == nil { loadChapter(project.chapters.first) }
        do {
            annotationDocument = try annotationRepository.load(in: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectChapter(id: UUID) {
        guard id != selectedChapterID, let chapter = chapters.first(where: { $0.id == id }) else { return }
        guard flushCurrentChapter() else { return }
        loadChapter(chapter)
    }

    func updateText(_ text: String) {
        guard selectedChapter != nil, chapterText != text else { return }
        chapterText = text
        needsSave = true
        editRevision += 1
        saveState = .unsaved
        scheduleSave()
    }

    func recordEditorActivity(isBusy: Bool, chapterID: UUID) {
        guard chapterID == selectedChapterID else { return }
        editorIsBusy = isBusy
        scheduleSave()
    }

    func addChapter(title: String) {
        guard flushCurrentChapter() else { return }
        do {
            project = try repository.addChapter(title: title, to: project, in: rootURL)
            loadChapter(project.chapters.last)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func flushCurrentChapter() -> Bool {
        cancelScheduledSave()
        guard needsSave else { return true }
        guard let chapter = selectedChapter else { return false }
        do {
            // Wait for any already-started autosave before writing the newest version.
            // Cancelling a task alone cannot stop an atomic file write in progress.
            try chapterWriteQueue.sync {
                try repository.writeChapter(chapterText, chapter: chapter, in: rootURL)
            }
            needsSave = false
            saveState = .saved(.now)
            return true
        } catch {
            saveState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func applyProjectDetails(_ updated: BookProject) {
        guard updated.id == project.id else { return }
        project = updated
    }

    func reloadAfterExternalChange() {
        cancelScheduledSave()
        do {
            let updated = try repository.loadProject(at: rootURL)
            let chapter = updated.chapters.first { $0.id == selectedChapterID } ?? updated.chapters.first
            let content = try chapter.map { try repository.readChapter($0, in: rootURL) } ?? ""
            let annotations = try annotationRepository.load(in: rootURL)
            // Publish a coherent snapshot only after every read succeeds.
            project = updated
            applyLoadedChapter(chapter, content: content)
            annotationDocument = annotations
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

    private func loadChapter(_ chapter: BookOutlineNode?) {
        do {
            let content = try chapter.map { try repository.readChapter($0, in: rootURL) } ?? ""
            applyLoadedChapter(chapter, content: content)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyLoadedChapter(_ chapter: BookOutlineNode?, content: String) {
        cancelScheduledSave()
        editorIsBusy = false
        selectedChapterID = chapter?.id
        chapterText = content
        needsSave = false
        saveState = .saved(.now)
    }

    private func cancelScheduledSave() {
        saveTask?.cancel()
        saveTask = nil
        saveGeneration += 1
    }

    private func scheduleSave() {
        cancelScheduledSave()
        guard
            !editorIsBusy, needsSave,
            let chapter = selectedChapter,
            let relativePath = chapter.relativePath,
            let destinationURL = try? repository.safeURL(for: relativePath, in: rootURL)
        else { return }
        let content = chapterText
        let revision = editRevision
        let generation = saveGeneration
        let clock = autosaveClock
        let deadline = clock.now + autosaveIdleDuration
        saveTask = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
                guard let self, !Task.isCancelled, generation == self.saveGeneration, !self.editorIsBusy else {
                    return
                }
                self.saveState = .saving
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.chapterWriteQueue.async {
                        do {
                            try AtomicFileWriter.write(content, to: destinationURL)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                guard
                    !Task.isCancelled, generation == self.saveGeneration,
                    chapter.id == self.selectedChapterID, revision == self.editRevision
                else { return }
                self.needsSave = false
                self.saveState = .saved(.now)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, generation == self.saveGeneration else { return }
                self.saveState = .failed(error.localizedDescription)
                self.errorMessage = error.localizedDescription
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
