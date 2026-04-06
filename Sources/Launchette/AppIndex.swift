import Cocoa

// MARK: - App entry

struct AppEntry {
	let name: String
	let path: String
	let bundleIdentifier: String?
	let icon: NSImage
	var isRunning: Bool
	let isCustom: Bool

	func launch() {
		let url = URL(fileURLWithPath: path)
		let config = NSWorkspace.OpenConfiguration()
		config.activates = true
		NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
	}
}

// MARK: - App index

class AppIndex {
	private var apps: [AppEntry] = []
	private var customAppPaths: Set<String> = []
	private let customAppsURL: URL

	init() {
		let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		let dir = appSupport.appendingPathComponent("Launchette")
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		customAppsURL = dir.appendingPathComponent("custom_apps.json")
		loadCustomApps()
	}

	// MARK: Scanning

	func scan() {
		var discovered: [String: AppEntry] = [:]

		let searchDirs = [
			"/Applications",
			"/Applications/Utilities",
			"/System/Applications",
			"/System/Applications/Utilities",
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
		let fallbackName = url.deletingPathExtension().lastPathComponent
		let bundle = Bundle(path: path)
		let displayName = bundle?.infoDictionary?["CFBundleDisplayName"] as? String
			?? bundle?.infoDictionary?["CFBundleName"] as? String
			?? fallbackName
		let bundleID = bundle?.bundleIdentifier
		let icon = NSWorkspace.shared.icon(forFile: path)
		icon.size = NSSize(width: 32, height: 32)

		return AppEntry(
			name: displayName,
			path: path,
			bundleIdentifier: bundleID,
			icon: icon,
			isRunning: false,
			isCustom: isCustom
		)
	}

	// MARK: Running apps

	func refreshRunningApps() {
		let runningIDs = Set(
			NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
		)
		for i in apps.indices {
			apps[i].isRunning = apps[i].bundleIdentifier.map { runningIDs.contains($0) } ?? false
		}
	}

	// MARK: Search

	func search(query: String) -> [AppEntry] {
		let q = query.lowercased()
		var matches: [(entry: AppEntry, score: Int)] = []

		for app in apps {
			let name = app.name.lowercased()
			var score = 0

			if name == q {
				score = 100
			} else if name.hasPrefix(q) {
				score = 80
			} else if name.contains(q) {
				score = 60
			} else if fuzzyMatch(query: q, target: name) {
				score = 40
			} else {
				continue
			}

			if app.isRunning { score += 20 }
			matches.append((app, score))
		}

		return matches
			.sorted { $0.score > $1.score }
			.prefix(8)
			.map { $0.entry }
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
