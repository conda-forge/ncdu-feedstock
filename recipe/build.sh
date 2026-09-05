#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if [[ "${target_platform}" == linux-* ]]; then
    # ncurses splits terminfo out into libtinfow, and ships libncursesw.so as
    # a GNU ld linker script (INPUT(libncursesw.so.6 -ltinfow)) rather than a
    # symlink, so that a bare -lncursesw still resolves terminfo symbols
    # (DT_NEEDED alone does not, with --no-copy-dt-needed-entries).
    #
    # Zig cannot consume that. It either fails to parse the script as ELF
    # ("failed to parse shared library: UnexpectedEndOfFile") or, where LLD
    # does parse it, cannot resolve the nested -l ("ld.lld: unable to find
    # library -ltinfow"). This is a known, still-open upstream bug, reported
    # against ncdu itself while packaging it for Fedora:
    #   https://github.com/ziglang/zig/issues/23849
    #
    # Replace the script with a plain symlink to the real library. Nothing is
    # lost: ncursesw.pc puts -ltinfow on the link line regardless, which is
    # where the binary's libtinfow dependency actually comes from. Still
    # required on 0.15.2 (verified by building with this block removed); drop
    # it once the zig issue is fixed.
    ncursesw_so="${PREFIX}/lib/libncursesw.so"
    if [[ -f "${ncursesw_so}" ]] && [[ "$(head -c4 "${ncursesw_so}")" != $'\x7fELF' ]]; then
        real_lib=$(grep -oE 'libncursesw\.so\.[0-9]+(\.[0-9]+)*' "${ncursesw_so}" | head -n1)
        ln -sf "${real_lib}" "${ncursesw_so}"
    fi
fi

if [[ "${target_platform}" == osx-* ]]; then
    # The Mach-O face of the same ncurses terminfo split as above: with no
    # linker-script format, libncursesw.6.dylib instead re-exports libtinfow's
    # symbols (LC_REEXPORT_DYLIB, confirmed via otool -L) so that a bare
    # -lncursesw stays sufficient.
    #
    # Zig's self-hosted Mach-O linker crashes on that re-export ("terminated
    # unexpectedly", no diagnostic). Forcing LLD instead was not an option on
    # 0.14, which had dropped LLD for Mach-O.
    #
    # We do not need the re-export ourselves: pkg-config puts -ltinfow on the
    # link line regardless, and the built binary loads libtinfow directly. So
    # flip that one load command to a plain LC_LOAD_DYLIB. Only the throwaway
    # build prefix is touched -- rattler-build packages newly created paths,
    # so the modified dylib is never shipped.
    #
    # Diagnosed against zig 0.14 and NOT re-verified since the move to 0.15.2;
    # it may now be unnecessary, but dropping it needs a macOS CI run to
    # confirm. Harmless if redundant.
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

# The glibc minor in each -Dtarget triple is the floor the binary actually has,
# and must stay in step with c_stdlib_version, which is what stdlib("c")'s
# run-export turns into the package's __glibc bound.
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
