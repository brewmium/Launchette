import Cocoa

// MARK: - App entry

struct AppEntry {
	let name: String
	let bundleName: String
	let path: String
	let bundleIdentifier: String?
	let version: String
	let icon: NSImage
	var isRunning: Bool
	let isCustom: Bool

	var displayPath: String {
		let parent = (path as NSString).deletingLastPathComponent
		let home = NSHomeDirectory()
		if parent.hasPrefix(home) {
			let rest = String(parent.dropFirst(home.count))
			if rest.isEmpty { return "Home" }
			return String(rest.dropFirst()) // strip leading /
		}
		return parent
	}

	func launch() {
		NSWorkspace.shared.open(URL(fileURLWithPath: path))
	}
}

// MARK: - App index

class AppIndex {
	private var apps: [AppEntry] = []
	private var customAppPaths: Set<String> = []
	private var usageCounts: [String: Int] = [:]
	private var hiddenPaths: Set<String> = []
	private let customAppsURL: URL
	private let usageURL: URL
	private let hiddenURL: URL

	init() {
		let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		let dir = appSupport.appendingPathComponent("Launchette")
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		customAppsURL = dir.appendingPathComponent("custom_apps.json")
		usageURL = dir.appendingPathComponent("usage_cache.json")
		hiddenURL = dir.appendingPathComponent("hidden_apps.json")
		loadCustomApps()
		loadUsage()
		loadHidden()
	}

	// MARK: Scanning

	func scan() {
		var discovered: [String: AppEntry] = [:]

		let searchDirs = [
			"/Applications",
			"/Applications/Utilities",
			"/System/Applications",
			"/System/Applications/Utilities",
			"/System/Library/CoreServices",
			NSHomeDirectory() + "/Applications",
		]

		for dir in searchDirs {
			scanDirectory(dir, into: &discovered, depth: 2)
		}

		for path in customAppPaths {
			if discovered[path] == nil, FileManager.default.fileExists(atPath: path) {
				if let entry = makeEntry(path: path, isCustom: true) {
					discovered[path] = entry
				}
			}
		}

		apps = Array(discovered.values).sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}
		refreshRunningApps()
	}

	private func scanDirectory(_ path: String, into discovered: inout [String: AppEntry], depth: Int) {
		guard depth > 0 else { return }
		guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }

		for item in contents {
			let fullPath = (path as NSString).appendingPathComponent(item)
			if item.hasSuffix(".app") {
				if discovered[fullPath] == nil, let entry = makeEntry(path: fullPath, isCustom: false) {
					discovered[fullPath] = entry
				}
			} else {
				var isDir: ObjCBool = false
				if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
					scanDirectory(fullPath, into: &discovered, depth: depth - 1)
				}
			}
		}
	}

	private func makeEntry(path: String, isCustom: Bool) -> AppEntry? {
		let url = URL(fileURLWithPath: path)
		let displayName = url.deletingPathExtension().lastPathComponent
		let bundle = Bundle(path: path)
		// Skip background-only apps (not user-launchable)
		if bundle?.infoDictionary?["LSBackgroundOnly"] as? Bool == true { return nil }

		let bundleName = bundle?.infoDictionary?["CFBundleDisplayName"] as? String
			?? bundle?.infoDictionary?["CFBundleName"] as? String
			?? displayName
		let bundleID = bundle?.bundleIdentifier
		let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
		let icon = NSWorkspace.shared.icon(forFile: path)
		icon.size = NSSize(width: 48, height: 48)

		return AppEntry(
			name: displayName,
			bundleName: bundleName,
			path: path,
			bundleIdentifier: bundleID,
			version: version,
			icon: icon,
			isRunning: false,
			isCustom: isCustom
		)
	}

	// MARK: Running apps

	func refreshRunningApps() {
		let runningPaths = Set(
			NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
		)
		for i in apps.indices {
			apps[i].isRunning = runningPaths.contains(apps[i].path)
		}
	}

	// MARK: Search

	func search(query: String) -> [AppEntry] {
		let q = query.lowercased()
		var matches: [(entry: AppEntry, score: Int)] = []

		for app in apps {
			guard !hiddenPaths.contains(app.path) else { continue }

			let name = app.name.lowercased()
			let alias = app.bundleName.lowercased()
			var score = 0

			if name == q || alias == q {
				score = 100
			} else if name.hasPrefix(q) || alias.hasPrefix(q) {
				score = 80
			} else if name.contains(q) || alias.contains(q) {
				score = 60
			} else if initialsMatch(query: q, name: name) || initialsMatch(query: q, name: alias) {
				score = 70
			} else if fuzzyMatch(query: q, target: name) || fuzzyMatch(query: q, target: alias) {
				score = 40
			} else {
				continue
			}

			if app.isRunning { score += 20 }
			let usage = min(usageCounts[app.path] ?? 0, 10)
			score += usage * 5
			matches.append((app, score))
		}

		return matches
			.sorted {
				if $0.score != $1.score { return $0.score > $1.score }
				return $0.entry.version.compare($1.entry.version, options: .numeric) == .orderedDescending
			}
			.prefix(8)
			.map { $0.entry }
	}

	private func initialsMatch(query: String, name: String) -> Bool {
		// Split on spaces, hyphens, camelCase boundaries
		var initials: [Character] = []
		let words = name.split { $0 == " " || $0 == "-" || $0 == "_" }
		for word in words {
			if let first = word.first {
				initials.append(first)
			}
			// Also grab camelCase boundaries within a word
			var prev: Character? = word.first
			for ch in word.dropFirst() {
				if ch.isUppercase && prev?.isUppercase == false {
					initials.append(ch)
				}
				prev = ch
			}
		}
		let initialsStr = String(initials).lowercased()
		return initialsStr.hasPrefix(query)
	}

	private func fuzzyMatch(query: String, target: String) -> Bool {
		var qi = query.startIndex
		var ti = target.startIndex
		while qi < query.endIndex && ti < target.endIndex {
			if query[qi] == target[ti] {
				qi = query.index(after: qi)
			}
			ti = target.index(after: ti)
		}
		return qi == query.endIndex
	}

	// MARK: Launch and record

	func launchApp(_ entry: AppEntry) {
		usageCounts[entry.path, default: 0] += 1
		saveUsage()
		entry.launch()
	}

	// MARK: Hidden apps

	func hideApp(path: String) {
		hiddenPaths.insert(path)
		saveHidden()
	}

	func unhideApp(path: String) {
		hiddenPaths.remove(path)
		saveHidden()
	}

	func getHiddenApps() -> [(name: String, path: String)] {
		hiddenPaths.compactMap { path in
			let name = apps.first(where: { $0.path == path })?.name
				?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
			return (name: name, path: path)
		}
		.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	private func loadHidden() {
		guard let data = try? Data(contentsOf: hiddenURL),
			let paths = try? JSONDecoder().decode([String].self, from: data)
		else { return }
		hiddenPaths = Set(paths)
	}

	private func saveHidden() {
		guard let data = try? JSONEncoder().encode(Array(hiddenPaths)) else { return }
		try? data.write(to: hiddenURL)
	}

	// MARK: Usage management

	func getRecentApps() -> [(name: String, path: String, count: Int)] {
		usageCounts
			.filter { $0.value > 0 }
			.compactMap { (path, count) in
				let name = apps.first(where: { $0.path == path })?.name
					?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
				return (name: name, path: path, count: count)
			}
			.sorted { $0.count > $1.count }
	}

	func clearUsage(forPath path: String) {
		usageCounts.removeValue(forKey: path)
		saveUsage()
	}

	// MARK: Usage cache

	private func loadUsage() {
		guard let data = try? Data(contentsOf: usageURL),
			let counts = try? JSONDecoder().decode([String: Int].self, from: data)
		else { return }
		usageCounts = counts
	}

	private func saveUsage() {
		guard let data = try? JSONEncoder().encode(usageCounts) else { return }
		try? data.write(to: usageURL)
	}

	// MARK: Custom apps

	func addCustomApp(path: String) {
		customAppPaths.insert(path)
		saveCustomApps()
		scan()
	}

	private func loadCustomApps() {
		guard let data = try? Data(contentsOf: customAppsURL),
			let paths = try? JSONDecoder().decode([String].self, from: data)
		else { return }
		customAppPaths = Set(paths)
	}

	private func saveCustomApps() {
		guard let data = try? JSONEncoder().encode(Array(customAppPaths)) else { return }
		try? data.write(to: customAppsURL)
	}
}
