//
// This source file is part of swift-parsers, an open source project by Wayfair
//
// Copyright (c) 2019 Wayfair, LLC.
// Licensed under the 2-Clause BSD License
//
// See LICENSE.md for license information
//

@testable import Parsers
import Prelude
import XCTest

class ParserTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    func testCharacterParserSucceeds() {
        let parser = characterThat { $0 == "X" }
        assertSucceeds(parser, forInput: "Xyz") { tuple in
            XCTAssertEqual("X", tuple.0)
            XCTAssertEqual("yz", tuple.1)
        }
    }

    func testCharacterParserFails() {
        let parser = characterThat { $0 == "X" }
        XCTAssertThrowsError(
            try parser.run("QQQQQQ")
        )
    }

    func testStringParserSucceeds() {
        let parser = string("Xy")
        assertSucceeds(parser, forInput: "Xyzzz") { tuple in
            XCTAssertEqual("Xy", tuple.0)
            XCTAssertEqual("zzz", tuple.1)
        }
    }

    func testStringParserFails() {
        let parser = string("Xy")
        XCTAssertThrowsError(
            try parser.run("abababa")
        )
    }

    func testNoneOfParserSucceeds() {
        let parser = noneOf("Xy")
        assertSucceeds(parser, forInput: "abc") { tuple in
            XCTAssertEqual("a", tuple.0)
            XCTAssertEqual("bc", tuple.1)
        }
    }

    func testNoneOfParserFails() {
        let parser = noneOf("Xy")
        XCTAssertThrowsError(
            try parser.run("Xy")
        )
    }

    func testOneOfParserSucceeds() {
        let parser = oneOf("abc")
        assertSucceeds(parser, forInput: "babababcaxbacx") { tuple in
            XCTAssertEqual("b", tuple.0)
            XCTAssertEqual("abababcaxbacx", tuple.1)
        }
    }

    func testOneOfParserFails() {
        let parser = oneOf("abc")
        XCTAssertThrowsError(
            try parser.run("Xyz")
        )
    }

    func testOneOfParsingManySucceeds() {
        let parser = oneOf("abc").zeroOrMore
        assertSucceeds(parser, forInput: "babababcaxbacx") { tuple in
            XCTAssertEqual(["b", "a", "b", "a", "b", "a", "b", "c", "a"], tuple.0)
            XCTAssertEqual("xbacx", tuple.1)
        }
    }

    func testSymbolParserSucceeds() {
        assertSucceeds(stringIgnoringTrailingWhitespace("foo"), forInput: "foo bar baz!") { tuple in
            XCTAssertEqual("foo", tuple.0)
            XCTAssertEqual("bar baz!", tuple.1)
        }
        assertSucceeds(stringIgnoringTrailingWhitespace("foo"), forInput: "foobar baz!") { tuple in
            XCTAssertEqual("foo", tuple.0)
            XCTAssertEqual("bar baz!", tuple.1)
        }
    }

    func testSymbolParserFails() {
        XCTAssertThrowsError(
            try stringIgnoringTrailingWhitespace("foo").run("qux qqqq hello")
        )
    }

    func testDoubleParserSucceeds() {
        assertSucceeds(double, forInput: "0.123XYZ") { tuple in
            XCTAssertEqual(0.123, tuple.0)
            XCTAssertEqual("XYZ", tuple.1)
        }
    }

    func testDoubleParserFails() {
        XCTAssertThrowsError(
            try double.run("foobar")
        )
    }

    func testDoubleParserFailsWithoutConsumingInput() {
        // make sure that the `double` parser fails without consuming input: although `“..00”` are characters that could make up a `Double`, the `Double` initializer will fail them. We need to make sure that when it fails (ie. the second step of the `flatMap`), the characters are not consumed from the stream
        assertSucceeds(double.fallback(99) *> string("..00"), forInput: "..00qq") { tuple in
            XCTAssertEqual("..00", tuple.0)
            XCTAssertEqual("qq", tuple.1)
        }
    }

    func testWhitespaceParserSucceeds() {
        assertSucceeds(whitespace, forInput: " ldihfsdlkg") { tuple in
            XCTAssertEqual(" ", tuple.0)
            XCTAssertEqual("ldihfsdlkg", tuple.1)
        }
    }

    func testWhitespaceParserFails() {
        XCTAssertThrowsError(
            try whitespace.run("kjdhglsj")
        )
    }

    func testParserBetween() {
        let parser = string("foo").between(string("["), string("]"))
        assertSucceeds(parser, forInput: "[foo] xyz!") { tuple in
            XCTAssertEqual("foo", tuple.0)
            XCTAssertEqual(" xyz!", tuple.1)
        }
    }

    func testParserChoice() {
        let parser = string("peter") <|> string("pete")
        assertSucceeds(parser, forInput: "pete hello there") { tuple in
            XCTAssertEqual("pete", tuple.0)
            XCTAssertEqual(" hello there", tuple.1)
        }
    }

    func testParserOption() {
        assertSucceeds(string("peter").fallback("something else"), forInput: "yadda yadda yadda") { tuple in
            XCTAssertEqual("something else", tuple.0)
            XCTAssertEqual("yadda yadda yadda", tuple.1)
        }
    }

    func testParserRepeatedPassesWhenExpected() {
        let parser = string("blob").repeated(4)
        assertSucceeds(parser, forInput: "blobblobblobblob foo") { tuple in
            XCTAssertEqual(["blob", "blob", "blob", "blob"], tuple.0)
            XCTAssertEqual(" foo", tuple.1)
        }
    }

    func testParserRepeatedFailsWhenExpected() {
        let parser = string("blob").repeated(4)
        assertFails(parser, forInput: "blobblobblob foo") { error in
            let actualResult = ["blob", "blob", "blob"]
            XCTAssertEqual((error as? ParseError)?.message, "Did not consume 4 items, consumed 3: \(actualResult),  foo")
        }
    }
}

func assertSucceeds<A>(
    _ parser: StringParser<A>,
    forInput input: String,
    file: StaticString = #file,
    line: UInt = #line,
    outputWas callback: ((A, String)) -> Void = { _ in }) {
    do {
        let output = try parser.run(input)
        callback(output)
    } catch {
        XCTFail("failed parsing: \(input) with error: \(error)", file: file, line: line)
    }
}

func assertFails<A>(
    _ parser: StringParser<A>,
    forInput input: String,
    file: StaticString = #file,
    line: UInt = #line,
    errorWas callback: (Error) -> Void = { _ in }) {
    do {
        let output = try parser.run(input)
        XCTFail("Did not fail parsing as expected for: \(input), got: \(output)", file: file, line: line)
    } catch {
        callback(error)
    }
}
