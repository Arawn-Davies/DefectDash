import XCTest
@testable import DefectDashTUI

final class TextLayoutTests: XCTestCase {
    func testTruncate() {
        XCTAssertEqual(TextLayout.truncate("hello", width: 5), "hello")
        XCTAssertEqual(TextLayout.truncate("hello world", width: 5), "hell…")
        XCTAssertEqual(TextLayout.truncate("hi", width: 5), "hi")
        XCTAssertEqual(TextLayout.truncate("hello", width: 0), "")
        XCTAssertEqual(TextLayout.truncate("hello", width: 1), "…")
    }

    func testPad() {
        XCTAssertEqual(TextLayout.pad("ab", width: 4), "ab  ")
        XCTAssertEqual(TextLayout.pad("abcdef", width: 4), "abc…")
    }

    func testWrapParagraph() {
        let lines = TextLayout.wrap("the quick brown fox jumps over the lazy dog", width: 10)
        XCTAssertEqual(lines, ["the quick", "brown fox", "jumps over", "the lazy", "dog"])
        XCTAssertTrue(lines.allSatisfy { $0.count <= 10 })
    }

    func testWrapHardBreaksLongWordsAndKeepsBlankLines() {
        XCTAssertEqual(TextLayout.wrap("abcdefghijkl", width: 5), ["abcde", "fghij", "kl"])
        XCTAssertEqual(TextLayout.wrap("a\n\nb", width: 5), ["a", "", "b"])
        XCTAssertEqual(TextLayout.wrap("", width: 5), [""])
    }
}

final class ScreenTests: XCTestCase {
    func testPutClipsAtEdges() {
        let screen = Screen(cols: 6, rows: 2)
        screen.put(x: 4, y: 0, "hello", style: .plain)
        screen.put(x: -2, y: 1, "world", style: .plain)
        screen.put(x: 0, y: 5, "off", style: .plain)
        XCTAssertEqual(screen.line(0), "    he")
        XCTAssertEqual(screen.line(1), "rld   ")
    }

    func testRenderContainsTextAndSGR() {
        let screen = Screen(cols: 4, rows: 1)
        screen.put(x: 0, y: 0, "ab", style: Style(fg: .red, bold: true))
        let out = screen.render(palette: .ansi16)
        XCTAssertTrue(out.contains("ab"), out)
        XCTAssertTrue(out.contains("\u{1B}[1m") || out.contains(";1m") || out.contains("1;"), out)
        XCTAssertTrue(out.contains("\u{1B}[0m"), out)
    }
}
