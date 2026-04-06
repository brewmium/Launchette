// swift-tools-version: 5.10
import PackageDescription

let package = Package(
	name: "Launchette",
	platforms: [.macOS(.v13)],
	targets: [
		.executableTarget(
			name: "Launchette",
			path: "Sources/Launchette",
			linkerSettings: [
				.linkedFramework("Carbon"),
			]
		),
	]
)
