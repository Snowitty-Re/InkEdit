import AppKit
import ApplicationServices
import WebKit

enum PDFExportError: LocalizedError {
    case navigationFailed(String)
    case printingFailed
    case timedOut
    case webProcessTerminated

    var errorDescription: String? {
        switch self {
        case .navigationFailed(let reason): "无法排版 PDF：\(reason)"
        case .printingFailed: "PDF 打印排版失败。"
        case .timedOut: "PDF 生成超时，请重试或将书稿分卷导出。"
        case .webProcessTerminated: "PDF 排版进程意外退出，请重试。"
        }
    }
}

@MainActor
final class PDFDataExporter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Data, Error>?
    private var webView: WKWebView?
    private var printWindow: NSWindow?
    private var printOperation: NSPrintOperation?
    private var temporaryURL: URL?
    private var timeoutTask: Task<Void, Never>?
    // AppKit may deliver its print callback after the caller has cancelled.
    private var printingLifetime: PDFDataExporter?

    static func renderDocument(html: String, baseURL: URL) async throws -> Data {
        try await PDFDataExporter().render(html: html, baseURL: baseURL)
    }

    func render(html: String, baseURL: URL, timeout: Duration = .seconds(60)) async throws -> Data {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                let webView = WKWebView(
                    frame: NSRect(x: 0, y: 0, width: 900, height: 1200), configuration: configuration)
                self.webView = webView
                webView.navigationDelegate = self
                timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        self?.abort(with: PDFExportError.timedOut)
                    } catch {}
                }
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.abort(with: CancellationError())
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Leave WebKit's navigation callback before starting its asynchronous print job.
        Task { @MainActor [weak self] in
            self?.startPrinting()
        }
    }

    private func startPrinting() {
        guard continuation != nil, printOperation == nil, let webView else { return }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkEdit-\(UUID().uuidString).pdf")
        self.temporaryURL = temporaryURL
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595.2, height: 841.8)
        printInfo.topMargin = 54
        printInfo.bottomMargin = 54
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporaryURL

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.canSpawnSeparateThread = true
        let window = NSWindow(
            contentRect: webView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        printWindow = window
        printOperation = operation
        printingLifetime = self
        operation.runModal(
            for: window, delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc nonisolated private func printOperationDidRun(
        _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in
            defer {
                self.printOperation = nil
                self.printingLifetime = nil
                self.cleanup()
            }
            guard self.continuation != nil else { return }
            guard success, let url = self.temporaryURL, let pdf = try? Data(contentsOf: url) else {
                self.finish(.failure(PDFExportError.printingFailed))
                return
            }
            self.finish(.success(pdf))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(.failure(PDFExportError.navigationFailed(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        finish(.failure(PDFExportError.navigationFailed(error.localizedDescription)))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        abort(with: PDFExportError.webProcessTerminated)
    }

    private func abort(with error: any Error) {
        if let printOperation {
            PMSessionSetError(OpaquePointer(printOperation.printInfo.pmPrintSession()), OSStatus(kPMCancel))
        }
        finish(.failure(error))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        if printOperation == nil { cleanup() }
        continuation.resume(with: result)
    }

    private func cleanup() {
        printWindow?.contentView = nil
        printWindow?.close()
        printWindow = nil
        webView = nil
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        temporaryURL = nil
    }
}
