import XCTest
@testable import Launchette

final class MathEvaluatorTests: XCTestCase {
	private let evaluator = MathEvaluator()

	func testRequiresEqualsPrefix() {
		XCTAssertNil(evaluator.evaluate("2+2"))
		XCTAssertNil(evaluator.evaluate("sqrt(9)"))
		XCTAssertNil(evaluator.evaluate("20"))
	}

	func testEvaluatesWithPrefix() {
		XCTAssertEqual(evaluator.evaluate("=2+2"), "4")
		XCTAssertEqual(evaluator.evaluate("= 100 / 4"), "25")
		XCTAssertEqual(evaluator.evaluate("=sqrt(9)"), "3")
	}

	func testConstantsWorkWithoutOperators() {
		XCTAssertEqual(evaluator.evaluate("=pi"), "3.1415926536")
	}

	func testXAsMultiply() {
		XCTAssertEqual(evaluator.evaluate("=3 x 4"), "12")
	}

	func testCaretAsPower() {
		XCTAssertEqual(evaluator.evaluate("=2^10"), "1,024")
	}

	func testBareEqualsIsNil() {
		XCTAssertNil(evaluator.evaluate("="))
		XCTAssertNil(evaluator.evaluate("=  "))
	}

	func testGroupingSeparator() {
		XCTAssertEqual(evaluator.evaluate("=1000*1000"), "1,000,000")
	}
}
