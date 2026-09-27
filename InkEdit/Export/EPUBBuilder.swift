import Foundation

struct EPUBBuilder {
    private let htmlRenderer = MarkdownHTMLRenderer()
    private let archiveWriter = ZIPArchiveWriter()

    func build(_ publication: PublicationDocument) throws -> Data {
        let chapterEntries = try publication.chapters.enumerated().map { index, chapter in
            try Task.checkCancellation()
            let filename = String(format: "chapter-%03d.xhtml", index + 1)
            return ZIPArchiveEntry(
                path: "EPUB/text/\(filename)",
                data: data(chapterDocument(chapter, publication: publication))
            )
        }
        let resourceEntries = publication.resources.map { resource in
            ZIPArchiveEntry(path: "EPUB/\(resource.archivePath)", data: resource.data)
        }
        var entries =
            [
                ZIPArchiveEntry(path: "mimetype", data: data("application/epub+zip")),
                ZIPArchiveEntry(path: "META-INF/container.xml", data: data(containerXML)),
                ZIPArchiveEntry(path: "EPUB/style.css", data: data(htmlRenderer.styleSheet(for: .light))),
                ZIPArchiveEntry(path: "EPUB/nav.xhtml", data: data(navigationDocument(publication))),
                ZIPArchiveEntry(path: "EPUB/package.opf", data: data(packageDocument(publication))),
            ] + chapterEntries + resourceEntries
        if let cover = publication.coverPNG {
            entries.append(ZIPArchiveEntry(path: "EPUB/images/cover.png", data: cover))
            entries.append(ZIPArchiveEntry(path: "EPUB/cover.xhtml", data: data(coverDocument)))
        }
        return try archiveWriter.archive(entries: entries, date: publication.modifiedAt)
    }

    private func chapterDocument(_ chapter: PublicationChapter, publication: PublicationDocument) -> String {
        let markdown = removingUnpackagedImages(
            from: replacingResourceReferences(in: chapter.markdown, resources: publication.resources)
        )
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" lang="\(xml(publication.language))" xml:lang="\(xml(publication.language))">
              <head>
                <meta charset="utf-8" />
                <title>\(xml(chapter.title))</title>
                <link rel="stylesheet" type="text/css" href="../style.css" />
              </head>
              <body><main><h1>\(xml(chapter.title))</h1>\(htmlRenderer.renderBody(markdown))</main></body>
            </html>
            """
    }

    private func navigationDocument(_ publication: PublicationDocument) -> String {
        let coverLink = publication.coverPNG == nil ? "" : "<li><a href=\"cover.xhtml\">封面</a></li>"
        let items =
            coverLink
            + publication.chapters.enumerated().map { index, chapter in
                let filename = String(format: "chapter-%03d.xhtml", index + 1)
                return "<li><a href=\"text/\(filename)\">\(xml(chapter.title))</a></li>"
            }.joined()
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(xml(publication.language))">
              <head><meta charset="utf-8" /><title>目录</title></head>
              <body><nav epub:type="toc" id="toc"><h1>目录</h1><ol>\(items)</ol></nav></body>
            </html>
            """
    }

    private func packageDocument(_ publication: PublicationDocument) -> String {
        let chapterManifest = publication.chapters.enumerated().map { index, _ in
            let number = String(format: "%03d", index + 1)
            return
                "<item id=\"chapter-\(number)\" href=\"text/chapter-\(number).xhtml\" media-type=\"application/xhtml+xml\" />"
        }.joined()
        let resourceManifest = publication.resources.enumerated().map { index, resource in
            "<item id=\"resource-\(index + 1)\" href=\"\(xml(resource.archivePath))\" media-type=\"\(xml(resource.mediaType))\" />"
        }.joined()
        let spine = publication.chapters.indices.map { index in
            "<itemref idref=\"chapter-\(String(format: "%03d", index + 1))\" />"
        }.joined()
        let modified = ISO8601DateFormatter().string(from: publication.modifiedAt)
        let creator = publication.author.isEmpty ? "InkEdit 作者" : publication.author
        let coverManifest =
            publication.coverPNG == nil
            ? ""
            : """
            <item id="cover-image" href="images/cover.png" media-type="image/png" properties="cover-image" />
            <item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml" />
            """
        let coverSpine = publication.coverPNG == nil ? "" : "<itemref idref=\"cover-page\" />"
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="\(xml(publication.language))">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="book-id">urn:uuid:\(publication.id.uuidString.lowercased())</dc:identifier>
                <dc:title>\(xml(publication.title))</dc:title>
                <dc:creator>\(xml(creator))</dc:creator>
                <dc:language>\(xml(publication.language))</dc:language>
                <dc:description>\(xml(publication.summary))</dc:description>
                <meta property="dcterms:modified">\(xml(modified))</meta>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />
                <item id="style" href="style.css" media-type="text/css" />
                \(coverManifest)\(chapterManifest)\(resourceManifest)
              </manifest>
              <spine>\(coverSpine)\(spine)</spine>
            </package>
            """
    }

    private var coverDocument: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>封面</title></head>
          <body style="margin:0;text-align:center"><section epub:type="cover">
            <img src="images/cover.png" alt="封面" style="max-width:100%;max-height:100vh" />
          </section></body>
        </html>
        """
    }

    private var containerXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml" /></rootfiles>
        </container>
        """
    }

    private func replacingResourceReferences(
        in markdown: String,
        resources: [PublicationResource]
    ) -> String {
        resources.reduce(markdown) { result, resource in
            result.replacingOccurrences(
                of: "](\(resource.sourceReference))",
                with: "](../\(resource.archivePath))"
            )
        }
    }

    private func removingUnpackagedImages(from markdown: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"!\[([^]]*)\]\(([^)]+)\)"#) else {
            return markdown
        }
        var result = markdown
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        for match in expression.matches(in: markdown, range: range).reversed() {
            guard
                let fullRange = Range(match.range, in: result),
                let altRange = Range(match.range(at: 1), in: result),
                let referenceRange = Range(match.range(at: 2), in: result)
            else { continue }
            let reference = String(result[referenceRange])
            guard !reference.hasPrefix("../images/") else { continue }
            let altText = String(result[altRange])
            result.replaceSubrange(fullRange, with: altText)
        }
        return result
    }

    private func xml(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}
