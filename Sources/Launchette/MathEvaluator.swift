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

	func evaluate(_ input: String) -> String? {
		let s = input.trimmingCharacters(in: .whitespaces)
		guard !s.isEmpty else { return nil }

		// Must contain at least one digit
		guard s.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }

		// Must have an operator, parens, 'x' as multiply, or known function
		let ops = CharacterSet(charactersIn: "+-*/%^()")
		let hasXMultiply = s.range(of: "(?<=[0-9)])\\s*x\\s*(?=[0-9(])", options: .regularExpression) != nil
		let hasOp = s.rangeOfCharacter(from: ops) != nil || hasXMultiply
		let funcs = ["sqrt", "cbrt", "abs", "sin", "cos", "tan", "log", "pow", "round", "floor", "ceil", "min", "max"]
		let hasFunc = funcs.contains(where: { s.lowercased().contains($0) })
		guard hasOp || hasFunc else { return nil }

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
