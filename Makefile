.PHONY: build debug run clean metallib app

APP_NAME := VibingSpeech
APP_BUNDLE := $(APP_NAME).app
APP_DIR := $(APP_BUNDLE)/Contents
METALLIB_SCRIPT := scripts/build_mlx_metallib.sh
ICON_SRC := Resources/icon/icon.icns

build:
	swift build -c release
	@./$(METALLIB_SCRIPT) release

debug:
	swift build
	@./$(METALLIB_SCRIPT) debug

run: build
	.build/release/$(APP_NAME)

app: build
	@echo "Creating $(APP_BUNDLE)..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_DIR)/MacOS
	@mkdir -p $(APP_DIR)/Resources
	@cp .build/release/$(APP_NAME) $(APP_DIR)/MacOS/$(APP_NAME)
	@cp .build/release/mlx.metallib $(APP_DIR)/MacOS/mlx.metallib
	@if [ -f "$(ICON_SRC)" ]; then \
		cp "$(ICON_SRC)" $(APP_DIR)/Resources/icon.icns; \
		echo "  Copied app icon"; \
	else \
		echo "  Warning: $(ICON_SRC) not found, skipping app icon"; \
	fi
	@/usr/libexec/PlistBuddy -c "Add :CFBundleName string $(APP_NAME)" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $(APP_NAME)" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.shuichi.$(APP_NAME)" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1.0.0" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0.0" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $(APP_NAME)" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 15.0" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string icon" $(APP_DIR)/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string VibingSpeech needs microphone access for voice transcription." $(APP_DIR)/Info.plist
	@echo "Created $(APP_BUNDLE)"
	@echo ""
	@echo "To run:  open $(APP_BUNDLE)"
	@echo "To install: cp -r $(APP_BUNDLE) /Applications/"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

metallib:
	@./$(METALLIB_SCRIPT) release
