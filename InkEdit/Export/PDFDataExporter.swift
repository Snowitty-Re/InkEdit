import AppKit
import WebKit

enum PDFExportError: LocalizedError {
    case navigationFailed(String)
    case printingFailed

    var errorDescription: String? {
        switch self {
        case .navigationFailed(let reason): "无法排版 PDF：\(reason)"
        case .printingFailed: "PDF 打印排版失败。"
        }
    }
}

@MainActor
final class PDFDataExporter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Data, Error>?
    private var webView: WKWebView?

    func render(html: String, baseURL: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200), configuration: configuration)
            self.webView = webView
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkEdit-\(UUID().uuidString).pdf")
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
        guard operation.run(), let pdf = try? Data(contentsOf: temporaryURL) else {
            finish(.failure(PDFExportError.printingFailed))
            return
        }
        try? FileManager.default.removeItem(at: temporaryURL)
        finish(.success(pdf))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(.failure(PDFExportError.navigationFailed(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        finish(.failure(PDFExportError.navigationFailed(error.localizedDescription)))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }
}
