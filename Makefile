.PHONY: build debug run clean metallib

METALLIB_SCRIPT := scripts/build_mlx_metallib.sh

build:
	swift build -c release
	@./$(METALLIB_SCRIPT) release

debug:
	swift build
	@./$(METALLIB_SCRIPT) debug

run: build
	.build/release/VibingSpeech

clean:
	swift package clean

metallib:
	@./$(METALLIB_SCRIPT) release
