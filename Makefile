build_debug:
	zig build -freference-trace

build_game:
	zig build game

debug: build_debug build_game
	raddbg --project:.\testbed_.rdbg --auto_run --quit_after_success

run:
	zig build run

build_docs:
	zig build docs

docs:
	zig build docs && python -m http.server 8000 -d .\zig-out\docs\
