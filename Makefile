.PHONY: build test app run import-pat clean

APP = build/DefectDash.app

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

clean:
	rm -rf .build build
