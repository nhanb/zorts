#!/usr/bin/env python3
import sys

"""
Usage: ./scripts/install-zig.py 0.17.0

This script downloads a given zig release from a random community mirror,
verifies against zig's pubkey, then extract everything to ./zig.
Intended for CI use only.
See: https://ziglang.org/download/community-mirrors/
"""

import random
import subprocess


def run(*args, **kwargs):
    return subprocess.run(args, check=True, shell=False, **kwargs)


SOURCE = "nhanb-install-zig"
PUBKEY = "RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"
MIRRORS = """\
https://pkg.hexops.org/zig
https://zigmirror.hryx.net/zig
https://zig.linus.dev/zig
https://zig.squirl.dev
https://zig.mirror.mschae23.de/zig
https://ziglang.freetls.fastly.net
https://zig.tilok.dev
https://zig-mirror.tsimnet.eu/zig
https://zig.karearl.com/zig
https://pkg.earth/zig
https://fs.liujiacai.net/zigbuilds
https://zigmirror.com
https://zig.chainsafe.dev
https://zig.savalione.com
https://zig.bcr.ist
https://zig.vortan.dev/zig
https://pkg.alexrp.com/zig"""

MIRRORS = "https://ziglang.freetls.fastly.net"

mirrors = MIRRORS.split()
random.shuffle(mirrors)
version = sys.argv[1]
tarball_name = f"zig-x86_64-linux-{version}.tar.xz"

for mirror_url in mirrors:
    url = f"{mirror_url}/{tarball_name}?source={SOURCE}"
    print("Downloading from", url)
    try:
        run("curl", "-LO", url)
        run("curl", "-LO", f"{mirror_url}/{tarball_name}.minisig?source={SOURCE}")
        run("minisign", "-Vm", tarball_name, "-P", PUBKEY)
        # TODO: verify file name against trusted comment?

    except Exception as err:  # noqa
        print(f"download error: {err}")
        continue
