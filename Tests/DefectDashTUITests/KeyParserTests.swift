import XCTest
@testable import DefectDashTUI

final class KeyParserTests: XCTestCase {
    func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    func testArrowsAndPlainCharacters() {
        XCTAssertEqual(KeyParser.parse(bytes("\u{1B}[A\u{1B}[B\u{1B}[C\u{1B}[D")), [.up, .down, .right, .left])
        XCTAssertEqual(KeyParser.parse(bytes("jk/")), [.char("j"), .char("k"), .char("/")])
    }

    func testPageHomeEndAndEnter() {
        XCTAssertEqual(KeyParser.parse(bytes("\u{1B}[5~\u{1B}[6~")), [.pageUp, .pageDown])
        XCTAssertEqual(KeyParser.parse(bytes("\u{1B}[H\u{1B}[F\u{1B}[1~\u{1B}[4~")), [.home, .end, .home, .end])
        XCTAssertEqual(KeyParser.parse(bytes("\r\n")), [.enter, .enter])
        XCTAssertEqual(KeyParser.parse([0x7F, 0x08]), [.backspace, .backspace])
    }

    func testLoneEscapeIsEscape() {
        XCTAssertEqual(KeyParser.parse([0x1B]), [.escape])
        XCTAssertEqual(KeyParser.parse(bytes("\u{1B}j")), [.escape, .char("j")])   // ESC then a key
    }

    func testUTF8MultibyteCharacter() {
        XCTAssertEqual(KeyParser.parse(bytes("é→")), [.char("é"), .char("→")])
    }

    func testControlKeys() {
        XCTAssertEqual(KeyParser.parse([0x03]), [.ctrlC])
        XCTAssertEqual(KeyParser.parse([0x09]), [.tab])
        XCTAssertEqual(KeyParser.parse(bytes("\u{1B}[Z")), [.unknown])   // shift-tab not mapped
    }
}
