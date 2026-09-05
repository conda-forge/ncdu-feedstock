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
    # an option, Zig 0.14 doesn't support LLD for Mach-O). We don't need the
    # reexport ourselves, since pkg-config already puts -ltinfow on the link
    # line and the built binary loads libtinfow directly, so neutralize that
    # one load command by flipping its type to a plain LC_LOAD_DYLIB.
    # Only the throwaway build prefix is touched: rattler-build packages
    # newly created paths, so this modified dylib is never shipped.
    shopt -s nullglob
    ncursesw_dylibs=("${PREFIX}"/lib/libncursesw.[0-9]*.dylib)
    shopt -u nullglob
    if [[ ${#ncursesw_dylibs[@]} -eq 0 ]]; then
        echo "error: no libncursesw.<soversion>.dylib found in ${PREFIX}/lib" >&2
        exit 1
    fi
    /usr/bin/python3 - "${ncursesw_dylibs[@]}" <<'PYEOF'
import struct
import sys

for path in sys.argv[1:]:
    with open(path, "rb") as f:
        data = bytearray(f.read())

    if struct.unpack_from("<I", data, 0)[0] != 0xfeedfacf:
        print(f"{path}: not a 64-bit Mach-O file, skipping")
        continue

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

# The glibc minor in each -Dtarget triple must match c_stdlib_version for that
# platform (see recipe/conda_build_config.yaml), so the __glibc bound declared
# by the stdlib run-export is the one the binary was actually built against.
case "${target_platform}" in
    linux-64 )
        zig build --prefix "${PREFIX}" -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu.2.17 -Dcpu=core2
        ;;
    linux-aarch64 )
        zig build --prefix "${PREFIX}" -Doptimize=ReleaseFast -Dtarget=aarch64-linux-gnu.2.28 -Dcpu=generic
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
