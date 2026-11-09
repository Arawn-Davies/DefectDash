.PHONY: build test app run import-pat tui run-tui install-tui dist clean

APP = build/DefectDash.app
PREFIX ?= /usr/local

build:
	swift build

test:
	swift test

app:
	scripts/build-app.sh

run: app
	open $(APP)

# Usage: make import-pat PAT_FILE=~/Asana_PAT.txt
# The app binary reads the file itself and stores the token in the Keychain; nothing is echoed.
import-pat:
	@test -n "$(PAT_FILE)" || { echo "usage: make import-pat PAT_FILE=<path>"; exit 2; }
	@test -x $(APP)/Contents/MacOS/DefectDash || { echo "run 'make app' first"; exit 2; }
	$(APP)/Contents/MacOS/DefectDash --import-pat "$(PAT_FILE)"

# Terminal UI: build/defectdash
tui:
	swift build -c release --product defectdash-tui
	mkdir -p build
	cp "$$(swift build -c release --product defectdash-tui --show-bin-path)/defectdash-tui" build/defectdash

run-tui: tui
	build/defectdash

# Usage: make install-tui [PREFIX=~/.local]
install-tui: tui
	install -d "$(PREFIX)/bin"
	install -m 755 build/defectdash "$(PREFIX)/bin/defectdash"
	@echo "installed $(PREFIX)/bin/defectdash"

# Release archive with the app and the terminal binary side by side (what the Homebrew cask installs).
# Usage: make dist VERSION=0.0.4  -> build/DefectDash-0.0.4-macos-arm64.zip
dist: app tui
	@test -n "$(VERSION)" || { echo "usage: make dist VERSION=x.y.z"; exit 2; }
	rm -rf build/dist && mkdir -p build/dist
	ditto $(APP) build/dist/DefectDash.app
	cp build/defectdash build/dist/defectdash
	codesign --force --sign - build/dist/defectdash
	rm -f build/DefectDash-$(VERSION)-macos-arm64.zip
	cd build/dist && ditto -c -k --keepParent --sequesterRsrc . ../DefectDash-$(VERSION)-macos-arm64.zip
	@shasum -a 256 build/DefectDash-$(VERSION)-macos-arm64.zip

clean:
	rm -rf .build build
