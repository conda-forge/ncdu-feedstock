#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if [[ "${target_platform}" == linux-* ]]; then
    # Zig 0.14's linker cannot resolve the "-ltinfow" reference that ncurses'
    # libncursesw.so dev symlink embeds as a GNU ld linker script
    # (INPUT(libncursesw.so.6 -ltinfow)); it fails with "unable to find
    # library -ltinfow" even though the file is right there. Replace it with
    # a plain symlink to the real versioned library so zig links it directly.
    ncursesw_so="${PREFIX}/lib/libncursesw.so"
    if [[ -f "${ncursesw_so}" ]] && [[ "$(head -c4 "${ncursesw_so}")" != $'\x7fELF' ]]; then
        real_lib=$(grep -oE 'libncursesw\.so\.[0-9]+(\.[0-9]+)*' "${ncursesw_so}" | head -n1)
        ln -sf "${real_lib}" "${ncursesw_so}"
    fi
fi

if [[ "${target_platform}" == osx-* ]]; then
    # Zig 0.14's self-hosted Mach-O linker crashes ("terminated
    # unexpectedly", no diagnostic) when linking against ncurses'
    # libncursesw dylib, which re-exports libtinfow's symbols via
    # LC_REEXPORT_DYLIB (confirmed via otool -L; using LLD instead is not
    # an option, Zig 0.14 doesn't support LLD for Mach-O). We don't need
    # the reexport ourselves since we link tinfow explicitly too, so
    # neutralize it in our own build-time copy of the dylib by flipping
    # that one load command's type to a plain LC_LOAD_DYLIB.
    /usr/bin/python3 - "${PREFIX}/lib/libncursesw.6.dylib" <<'PYEOF'
import struct
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    data = bytearray(f.read())

if struct.unpack_from("<I", data, 0)[0] != 0xfeedfacf:
    sys.exit(f"{path}: not a 64-bit Mach-O file, skipping")

ncmds = struct.unpack_from("<I", data, 16)[0]
LC_REEXPORT_DYLIB = 0x1f | 0x80000000
LC_LOAD_DYLIB = 0xc
off = 32
patched = 0
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from("<II", data, off)
    if cmd == LC_REEXPORT_DYLIB:
        struct.pack_into("<I", data, off, LC_LOAD_DYLIB)
        patched += 1
    off += cmdsize

if patched:
    with open(path, "wb") as f:
        f.write(data)
print(f"{path}: neutralized {patched} LC_REEXPORT_DYLIB command(s)")
PYEOF
fi

case "${target_platform}" in
    linux-64 )
        zig build --prefix "${PREFIX}" -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu.2.17 -Dcpu=core2
        ;;
    linux-aarch64 )
        zig build --prefix "${PREFIX}" -Doptimize=ReleaseFast -Dtarget=aarch64-linux-gnu.2.17 -Dcpu=generic
        ;;
    osx-64 )
        zig build --prefix "${PREFIX}" -Dpie=true -Doptimize=ReleaseFast -Dtarget=x86_64-macos.${MACOSX_DEPLOYMENT_TARGET} -Dcpu=core2
        ;;
    osx-arm64 )
        zig build --prefix "${PREFIX}" -Dpie=true -Doptimize=ReleaseFast -Dtarget=aarch64-macos.${MACOSX_DEPLOYMENT_TARGET} -Dcpu=apple_m1
        ;;
esac

mkdir -p "${PREFIX}/share/man/man1"
install -m 644 ncdu.1 "${PREFIX}/share/man/man1/ncdu.1"
