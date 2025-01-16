#!/usr/bin/env bash

set -o xtrace -o nounset -o pipefail -o errexit

unset HTTP_PROXY
unset HTTPS_PROXY

case ${target_platform} in
    linux-64 )
        zig build --prefix ${PREFIX} -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu.2.17 -Dcpu=core2;;
    linux-aarch64 )
        zig build --prefix ${PREFIX} -Doptimize=ReleaseFast -Dtarget=aarch64-linux-gnu.2.17 -Dcpu=generic;;
    osx-64 )
        zig build --prefix ${PREFIX} -Dpie=true -Doptimize=ReleaseFast -Dcpu=core2;;
    osx-arm64 )
        zig build --prefix ${PREFIX} -Dpie=true -Doptimize=ReleaseFast -Dtarget=aarch64-macos.11.0 -Dcpu=apple_m1;;
esac

mkdir -p ${PREFIX}/share/man/man1
install -m 644 ncdu.1 ${PREFIX}/share/man/man1/ncdu.1
