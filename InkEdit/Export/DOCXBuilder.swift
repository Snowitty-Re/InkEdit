import Foundation
import ImageIO

struct DOCXBuilder {
    private let archiveWriter = ZIPArchiveWriter()

    func build(_ publication: PublicationDocument) throws -> Data {
        var entries = [
            ZIPArchiveEntry(path: "[Content_Types].xml", data: data(contentTypes)),
            ZIPArchiveEntry(path: "_rels/.rels", data: data(packageRelationships)),
            ZIPArchiveEntry(path: "docProps/core.xml", data: data(coreProperties(publication))),
            ZIPArchiveEntry(path: "word/document.xml", data: data(try documentXML(publication))),
            ZIPArchiveEntry(path: "word/styles.xml", data: data(stylesXML)),
            ZIPArchiveEntry(path: "word/_rels/document.xml.rels", data: data(documentRelationships(publication))),
        ]
        if let cover = publication.coverPNG {
            entries.append(ZIPArchiveEntry(path: "word/media/cover.png", data: cover))
        }
        return try archiveWriter.archive(entries: entries, date: publication.modifiedAt)
    }

    private func documentXML(_ publication: PublicationDocument) throws -> String {
        var paragraphs = [paragraph(publication.title, style: "Title")]
        if let cover = publication.coverPNG {
            paragraphs.insert(try coverParagraph(cover), at: 0)
            paragraphs[1] = paragraph(publication.title, style: "Title", pageBreakBefore: true)
        }
        if !publication.author.isEmpty {
            paragraphs.append(paragraph(publication.author, style: "Subtitle"))
        }
        if !publication.summary.isEmpty {
            paragraphs.append(paragraph(publication.summary))
        }
        for chapter in publication.chapters {
            try Task.checkCancellation()
            paragraphs.append(paragraph(chapter.title, style: "Heading1", pageBreakBefore: true))
            paragraphs.append(contentsOf: try markdownParagraphs(chapter.markdown))
        }
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
              xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
              <w:body>
                \(paragraphs.joined(separator: "\n"))
                <w:sectPr>
                  <w:pgSz w:w="11906" w:h="16838" />
                  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0" />
                </w:sectPr>
              </w:body>
            </w:document>
            """
    }

    private func coverParagraph(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double,
            width > 0, height > 0
        else { throw BookDetailsError.invalidImage }
        // Fit within A4 content margins, retaining the cover's aspect ratio.
        let scale = min(5_700_000 / width, 8_000_000 / height)
        let cx = Int(width * scale)
        let cy = Int(height * scale)
        return """
            <w:p><w:pPr><w:jc w:val="center" /></w:pPr><w:r><w:drawing>
              <wp:inline distT="0" distB="0" distL="0" distR="0">
                <wp:extent cx="\(cx)" cy="\(cy)" /><wp:docPr id="1" name="封面" />
                <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                  <pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="cover.png" /><pic:cNvPicPr /></pic:nvPicPr>
                    <pic:blipFill><a:blip r:embed="rIdCover" /><a:stretch><a:fillRect /></a:stretch></pic:blipFill>
                    <pic:spPr><a:xfrm><a:off x="0" y="0" /><a:ext cx="\(cx)" cy="\(cy)" /></a:xfrm>
                      <a:prstGeom prst="rect"><a:avLst /></a:prstGeom></pic:spPr>
                  </pic:pic>
                </a:graphicData></a:graphic>
              </wp:inline>
            </w:drawing></w:r></w:p>
            """
    }

    private func markdownParagraphs(_ markdown: String) throws -> [String] {
        try markdown.components(separatedBy: .newlines).map { source in
            try Task.checkCancellation()
            let trimmed = source.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "<w:p />" }
            let hashes = trimmed.prefix { $0 == "#" }
            if (1...6).contains(hashes.count), trimmed.dropFirst(hashes.count).first == " " {
                let text = String(trimmed.dropFirst(hashes.count + 1))
                return paragraph(plainText(text), style: hashes.count == 1 ? "Heading1" : "Heading2")
            }
            if trimmed.hasPrefix(">") {
                return paragraph(plainText(String(trimmed.dropFirst())), style: "Quote")
            }
            return paragraph(plainText(trimmed))
        }
    }

    private func paragraph(
        _ text: String,
        style: String? = nil,
        pageBreakBefore: Bool = false
    ) -> String {
        let styleXML = style.map { "<w:pStyle w:val=\"\($0)\" />" } ?? ""
        let breakXML = pageBreakBefore ? "<w:pageBreakBefore />" : ""
        return """
            <w:p>
              <w:pPr>\(styleXML)\(breakXML)</w:pPr>
              <w:r><w:rPr><w:lang w:val="zh-CN" w:eastAsia="zh-CN" /></w:rPr><w:t xml:space="preserve">\(xml(text))</w:t></w:r>
            </w:p>
            """
    }

    private func plainText(_ markdown: String) -> String {
        var result = markdown
        for pattern in [#"!\[([^]]*)\]\([^)]+\)"#, #"\[([^]]+)\]\([^)]+\)"#, #"[*_`~]"#] {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: pattern.hasPrefix("!") ? "$1" : (pattern.hasPrefix("\\[") ? "$1" : "")
            )
        }
        return result
    }

    private func coreProperties(_ publication: PublicationDocument) -> String {
        let modified = ISO8601DateFormatter().string(from: publication.modifiedAt)
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
              <dc:title>\(xml(publication.title))</dc:title>
              <dc:creator>\(xml(publication.author))</dc:creator>
              <dc:language>\(xml(publication.language))</dc:language>
              <dcterms:modified xsi:type="dcterms:W3CDTF">\(xml(modified))</dcterms:modified>
            </cp:coreProperties>
            """
    }

    private var contentTypes: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
          <Default Extension="xml" ContentType="application/xml" />
          <Default Extension="png" ContentType="image/png" />
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml" />
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml" />
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml" />
        </Types>
        """
    }

    private var packageRelationships: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml" />
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml" />
        </Relationships>
        """
    }

    private func documentRelationships(_ publication: PublicationDocument) -> String {
        let cover =
            publication.coverPNG == nil
            ? ""
            : """
            <Relationship Id="rIdCover" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/cover.png" />
            """
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml" />
              \(cover)
            </Relationships>
            """
    }

    private var stylesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" /><w:sz w:val="24" /><w:lang w:val="zh-CN" w:eastAsia="zh-CN" /></w:rPr></w:rPrDefault></w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal" /><w:pPr><w:spacing w:after="180" w:line="420" w:lineRule="auto" /></w:pPr></w:style>
          <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title" /><w:basedOn w:val="Normal" /><w:rPr><w:b /><w:sz w:val="40" /><w:szCs w:val="40" /></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle" /><w:basedOn w:val="Normal" /><w:rPr><w:color w:val="666666" /><w:sz w:val="24" /></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1" /><w:basedOn w:val="Normal" /><w:next w:val="Normal" /><w:rPr><w:b /><w:sz w:val="34" /></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2" /><w:basedOn w:val="Normal" /><w:next w:val="Normal" /><w:rPr><w:b /><w:sz w:val="28" /></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote" /><w:basedOn w:val="Normal" /><w:pPr><w:ind w:left="720" /></w:pPr><w:rPr><w:i /><w:color w:val="666666" /></w:rPr></w:style>
        </w:styles>
        """
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
