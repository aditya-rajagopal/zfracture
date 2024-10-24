debug: game
	zig build -freference-trace && .\zig-out\bin\game.exe

game:
	zig build game -freference-trace  --summary all

check:
	zig build check

test:
	zig build test --summary new -freference-trace

build_debug: game
	zig build -freference-trace

# release needs to pass tests first
build_release: test
	zig build -Doptimize=ReleaseSafe

release:
	zig build -Doptimize=ReleaseSafe && .\zig-out\bin\game.exe

# distribution needs to pass tests first
build_dist: test
	zig build -Doptimize=ReleaseFast

dist: test
	zig build -Doptimize=ReleaseFast && .\zig-out\bin\game.exe

build_docs:
	zig build docs

docs:
	zig build docs && .\zig-out\docs\index.html

all: test game build_debug build_release build_dist build_docs

uninstall:
	zig build uninstall
