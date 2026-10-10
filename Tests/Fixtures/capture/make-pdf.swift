import CoreGraphics
import CoreText
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Provide the output PDF path") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
var page = CGRect(x: 0, y: 0, width: 600, height: 800)
guard let context = CGContext(url as CFURL, mediaBox: &page,
    [kCGPDFContextTitle: "Tinycast PDF Capture QA"] as CFDictionary) else { fatalError("Cannot create PDF") }
let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)
func text(_ value: String, x: Double, y: Double) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value,
        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, context)
}
for pageNumber in 0..<20 {
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(page)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    text("Tinycast PDF QA - Page \(pageNumber + 1)", x: 24, y: 766)
    for row in 0..<25 {
        let number = pageNumber * 25 + row + 1
        let label = String(format: "PDF ROW %03d  Content %03d  Check %05d", number, number, number * 7919 % 65521)
        text(label, x: 24, y: Double(724 - row * 27))
    }
    context.endPDFPage()
}
context.closePDF()
