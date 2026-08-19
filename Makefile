# Zig windows build is broken with ReleaseSafe. Seems like a fix is already
# in master but not in 0.16. Let's use Debug builds until 0.17 drops.
# https://codeberg.org/ziglang/translate-c/issues/327
# ZIG_BUILD := zig build -Doptimize=ReleaseSafe -Dcpu=x86_64_v3
ZIG_BUILD := zig build -Doptimize=Debug -Dcpu=x86_64_v3
UNIX_OPTS := -fsys=sdl3 -fsys=freetype -fsys=accesskit

DIST_WIN_DIR := dist/zorts-win64
DIST_LINUX_DIR := dist/zorts-linux64

default:
	$(ZIG_BUILD) $(UNIX_OPTS)

linux:
	$(ZIG_BUILD) $(UNIX_OPTS)
	mkdir -p $(DIST_LINUX_DIR)
	mv zig-out/bin/zorts $(DIST_LINUX_DIR)/
	cp -r web propaganda LICENSE README.md $(DIST_LINUX_DIR)/
	cp players.sample.csv $(DIST_LINUX_DIR)/players.csv
	cd $(DIST_LINUX_DIR) && zip -r ../zorts-linux.zip .
	rm -r "$(DIST_LINUX_DIR)"

windows:
	$(ZIG_BUILD) -Dtarget=x86_64-windows
	mkdir -p $(DIST_WIN_DIR)
	mv zig-out/bin/zorts.exe $(DIST_WIN_DIR)/
	mv zig-out/bin/zorts.pdb $(DIST_WIN_DIR)/
	cp -r web propaganda LICENSE README.md $(DIST_WIN_DIR)/
	cp players.sample.csv $(DIST_WIN_DIR)/players.csv
	cd $(DIST_WIN_DIR) && zip -r ../zorts-windows.zip .
	rm -r "$(DIST_WIN_DIR)"

clean:
	rm -rf dist zig-out
	rm -f state.json state-applied.json

run:
	zig build run $(UNIX_OPTS)

watch:
	find . -name '*.zig' | entr -rc make run
