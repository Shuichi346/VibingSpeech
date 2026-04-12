.PHONY: build debug run clean

build:
	swift build -c release
	@echo "Note: If you see \"Failed to load the default metallib\" error, run: xcodebuild -downloadComponent MetalToolchain"

debug:
	swift build

run: build
	.build/release/VibingSpeech

clean:
	swift package clean
