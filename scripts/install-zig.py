#!/usr/bin/env python3
"""
Usage: ./scripts/install-zig.py 0.17.0

This script downloads a given zig release from a random community mirror,
verifies against zig's pubkey, then extract everything to ./zig.
Intended for CI use only.
See: https://ziglang.org/download/community-mirrors/

Dependencies:
    python3
    curl
    minisign
    tar
"""

import os
import random
import re
import shlex
import shutil
import subprocess
import sys


def run(*cmd, **kwargs):
    print(" ".join(shlex.quote(arg) for arg in cmd))
    return subprocess.run(cmd, check=True, shell=False, **kwargs)


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

mirrors = MIRRORS.split()
random.shuffle(mirrors)
version = sys.argv[1]
tarball_name = f"zig-x86_64-linux-{version}.tar.xz"

for mirror_url in mirrors:
    print("Using mirror", mirror_url)
    url = f"{mirror_url}/{tarball_name}?source={SOURCE}"
    try:
        # Download
        run("curl", "-LO", url)
        run("curl", "-LO", f"{mirror_url}/{tarball_name}.minisig?source={SOURCE}")

        # Verify
        run("minisign", "-Vm", tarball_name, "-P", PUBKEY)
        matched = None
        with open(f"{tarball_name}.minisig", "r") as file:
            sig = file.read()
        for line in sig.splitlines():
            matched = re.match(
                r"^trusted comment: timestamp:\d+\s+file:([^\s]+)\s+hashed$", line
            )
            if matched:
                break
        if not matched or matched.group(1) != tarball_name:
            print(
                f"Tarball name ({tarball_name}) doesn't match trusted comment.\n"
                "Skipped mirror."
            )
            continue
        print("Tarball name matches trusted commend.")

        # Extract
        run("tar", "-xf", tarball_name)
        extracted_dir = tarball_name[: -len(".tar.xz")]
        shutil.rmtree("zig-bin", ignore_errors=True)
        os.rename(extracted_dir, "zig-bin")
        break

    except Exception as err:  # noqa
        print(f"Error: {err}. Skipped mirror.")
        continue
