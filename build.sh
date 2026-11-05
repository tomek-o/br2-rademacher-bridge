#!/bin/sh
# Build the bridge image with the Buildroot copy vendored in ./buildroot.
# Usage: ./build.sh [extra make args]      Result: $OUT/images/sdcard.img
# Downloads (sources) and build output go outside the repository:
#   BR2_DL_DIR (default ../build/dl)  and  OUT (default ../build/out)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../build/out}
export BR2_DL_DIR=${BR2_DL_DIR:-$HERE/../build/dl}
mkdir -p "$BR2_DL_DIR"
make -C "$HERE/buildroot" BR2_EXTERNAL="$HERE" O="$OUT" rdm_bridge_defconfig
make -C "$OUT" "$@"
echo "Image: $OUT/images/sdcard.img"
