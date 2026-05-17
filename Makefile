APP_NAME := Hopbar
BUNDLE := dist/$(APP_NAME).app
DMG := dist/$(APP_NAME)-0.1.0-preview.dmg
EXECUTABLE := .build/release/Hopbar

.PHONY: build app dmg package test verify clean

build: app

app:
	Scripts/package_app.sh

dmg: app
	Scripts/create_dmg.sh

package: dmg

test:
	swift test

verify:
	codesign --verify --deep --strict --verbose=2 "$(BUNDLE)"
	hdiutil verify "$(DMG)"

clean:
	swift package clean
	rm -rf dist .build/release-package .build/dmg-root
