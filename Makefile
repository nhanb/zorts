ZIG_BUILD := zig build -Doptimize=ReleaseSafe -Dcpu=x86_64_v3
UNIX_OPTS := -fsys=sdl3 -fsys=freetype -fsys=accesskit

default:
	$(ZIG_BUILD) $(UNIX_OPTS)

linux:
	$(ZIG_BUILD) $(UNIX_OPTS) -Dtarget=x86_64-linux

windows:
	$(ZIG_BUILD) -Dtarget=x86_64-windows

run:
	zig build run $(UNIX_OPTS)

watch:
	find . -name '*.zig' | entr -rc make run
