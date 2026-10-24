.NOTPARALLEL:

export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

PROJECT := MagPulse.xcodeproj
SCHEME  := MagPulse
DEST    := platform=macOS,arch=arm64
IDENTITY := Developer ID Application: Reff LLC (YVRAA57U55)
DEVELOPMENT_TEAM := YVRAA57U55
INSTALL_APP := build/install/Build/Products/Release/MagPulse.app

.PHONY: gen build test run clean install dmg release

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug build

run: build
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $$2; exit}')/MagPulse.app; \
	pkill -x MagPulse || true; \
	open "$$APP"

clean:
	rm -rf build DerivedData $(PROJECT)

install: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Release -derivedDataPath build/install \
		-clonedSourcePackagesDirPath build/SourcePackages \
		CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual \
		DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) ENABLE_HARDENED_RUNTIME=YES build -quiet
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" \
		"$(INSTALL_APP)/Contents/Frameworks/Sparkle.framework" || true
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" "$(INSTALL_APP)"
	pkill -x MagPulse || true
	rm -rf /Applications/MagPulse.app
	ditto "$(INSTALL_APP)" /Applications/MagPulse.app
	rm -rf build/install
	open /Applications/MagPulse.app

dmg:
	Scripts/release.sh --dmg-only

release:
	Scripts/release.sh
