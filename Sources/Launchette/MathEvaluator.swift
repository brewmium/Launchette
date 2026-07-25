import Foundation
import JavaScriptCore

class MathEvaluator {
	private let context: JSContext

	init() {
		context = JSContext()!
		context.evaluateScript("""
			function sqrt(x) { return Math.sqrt(x); }
			function cbrt(x) { return Math.cbrt(x); }
			function abs(x)  { return Math.abs(x); }
			function sin(x)  { return Math.sin(x); }
			function cos(x)  { return Math.cos(x); }
			function tan(x)  { return Math.tan(x); }
			function log(x)  { return Math.log(x); }
			function log2(x) { return Math.log2(x); }
			function log10(x){ return Math.log10(x); }
			function pow(x,y){ return Math.pow(x,y); }
			function round(x){ return Math.round(x); }
			function floor(x){ return Math.floor(x); }
			function ceil(x) { return Math.ceil(x); }
			function min()   { return Math.min.apply(null, arguments); }
			function max()   { return Math.max.apply(null, arguments); }
			var pi = Math.PI;
			var e  = Math.E;
			""")
	}

	// Math requires explicit intent: input must start with "=". The prefix is
	// the whole gate -- anything evaluable after it is fair game (=2+2, =pi).
	func evaluate(_ input: String) -> String? {
		var s = input.trimmingCharacters(in: .whitespaces)
		guard s.hasPrefix("=") else { return nil }
		s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
		guard !s.isEmpty else { return nil }

		// Only safe characters
		let allowed = CharacterSet.decimalDigits
			.union(CharacterSet(charactersIn: "+-*/%^(). \t,"))
			.union(.letters)
		guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

		// Replace 'x' between digits/parens with '*' (but not in func names like max, exp)
		var expr = s.replacingOccurrences(
			of: "(?<=[0-9)])\\s*x\\s*(?=[0-9(])",
			with: "*",
			options: .regularExpression
		)
		expr = expr.replacingOccurrences(of: "^", with: "**")

		guard let result = context.evaluateScript(expr),
			!result.isUndefined, !result.isNull
		else { return nil }

		let n = result.toDouble()
		guard n.isFinite else { return nil }

		let formatter = NumberFormatter()
		formatter.groupingSeparator = ","
		formatter.usesGroupingSeparator = true

		if n == Darwin.floor(n) && Swift.abs(n) < 1e15 {
			formatter.maximumFractionDigits = 0
			return formatter.string(from: NSNumber(value: n)) ?? String(format: "%.0f", n)
		}
		formatter.maximumFractionDigits = 10
		formatter.minimumFractionDigits = 0
		return formatter.string(from: NSNumber(value: n)) ?? String(format: "%g", n)
	}
}
