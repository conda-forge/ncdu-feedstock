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
    # The published conda-forge ncurses package records its "upward" link to
    # libtinfow via an absolute, un-rewritten build-time placeholder path
    # (LC_LOAD_UPWARD_DYLIB) instead of @rpath/libtinfow.*.dylib like its own
    # LC_ID_DYLIB entry. Zig's Mach-O linker appears to crash rather than
    # cleanly error when it can't resolve that reference (matches the
    # ncurses-tinfow linker issue worked around above for Linux). Print the
    # load commands for visibility and repoint any non-@rpath libtinfow
    # reference so zig resolves it directly within our own prefix.
    ncursesw_dylib="${PREFIX}/lib/libncursesw.6.dylib"
    if [[ -f "${ncursesw_dylib}" ]]; then
        echo "libncursesw.6.dylib load commands:"
        "${OTOOL}" -L "${ncursesw_dylib}" || true
        bad_ref=$("${OTOOL}" -L "${ncursesw_dylib}" | awk '/libtinfow/{print $1}' | grep -v '^@rpath/' || true)
        if [[ -n "${bad_ref}" ]]; then
            echo "Repointing broken libtinfow reference: ${bad_ref} -> @rpath/libtinfow.6.dylib"
            "${INSTALL_NAME_TOOL}" -change "${bad_ref}" "@rpath/libtinfow.6.dylib" "${ncursesw_dylib}"
        fi
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
