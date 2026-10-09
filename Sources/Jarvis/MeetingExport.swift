import AppKit
import CoreText
import Foundation

enum MeetingExport {
    static func pdfData(for record: MeetingRecord) -> Data {
        let text = record.markdownDocument(includeTranscript: true)
        let font = NSFont.systemFont(ofSize: 11)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black
            ]
        )
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let textRect = page.insetBy(dx: 48, dy: 48)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let data = NSMutableData()
        var mediaBox = page
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            return Data()
        }

        var location = 0
        let length = attributed.length
        while location < length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            location += max(visible.length, 1)
        }
        context.closePDF()
        return data as Data
    }
}
