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
