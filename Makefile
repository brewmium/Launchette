.PHONY: build run clean install uninstall

APP_NAME = Launchette
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app

build:
	swift build -c release
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	cp "Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	codesign --force --sign - "$(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)"

install: build
	cp -r "$(APP_BUNDLE)" /Applications/

uninstall:
	rm -rf "/Applications/$(APP_BUNDLE)"
