#!/bin/sh
# Builds libprojectM, the MilkDrop engine behind Miniamp's MilkDrop window, from a pinned
# release and installs it into Vendor/projectM: the dynamic library the Mac app embeds and the
# C headers its OpenGL view includes. Run it again to update or rebuild the library; it needs
# git and cmake (brew install cmake). projectM is LGPL-2.1, so it stays a separate dynamic
# library that anyone can rebuild and replace.
set -eu
cd "$(dirname "$0")/../.."
VERSION="${PROJECTM_VERSION:-v4.1.8}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet --depth 1 --branch "$VERSION" --recurse-submodules --shallow-submodules \
    https://github.com/projectM-visualizer/projectm.git "$WORK/src"
cmake -S "$WORK/src" -B "$WORK/build" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF \
    -DENABLE_PLAYLIST=OFF -DENABLE_SYSTEM_PROJECTM_EVAL=OFF -DENABLE_SYSTEM_GLM=OFF \
    -DENABLE_DEBUG_POSTFIX=OFF -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0 \
    -DCMAKE_INSTALL_PREFIX="$WORK/install" >/dev/null
cmake --build "$WORK/build" --parallel "$(sysctl -n hw.ncpu)" >/dev/null
cmake --install "$WORK/build" >/dev/null

OUT=Vendor/projectM
rm -rf "$OUT/include" "$OUT/lib"
mkdir -p "$OUT/include" "$OUT/lib"
cp -R "$WORK/install/include/projectM-4" "$OUT/include/"
# One file under the name the library records as its install name, stripped of local symbols.
strip -x -o "$OUT/lib/libprojectM-4.4.dylib" "$WORK/install/lib/libprojectM-4.4.dylib"
cp "$WORK/src/COPYING" "$OUT/COPYING"
cp "$WORK/src/LICENSE.txt" "$OUT/LICENSE.txt"
# The app carries the license with the library it ships.
cp "$WORK/src/LICENSE.txt" "MinidiscMac/MilkDrop/projectM LGPL-2.1.txt"
echo "$VERSION" > "$OUT/VERSION"
echo "projectM $VERSION installed in $OUT"
