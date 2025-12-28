#!/bin/bash
set -e

#
# build architecture
#

ARCH=""
case "$1" in
  x64|x86_64)
    ARCH="x64"
    ;;
  arm64|aarch64)
    ARCH="arm64"
    ;;
  "")
    # Detect host architecture
    HOST_ARCH=$(uname -m)
    case "$HOST_ARCH" in
      x86_64)
        ARCH="x64"
        ;;
      arm64|aarch64)
        ARCH="arm64"
        ;;
      *)
        echo "Error: Unknown host architecture '$HOST_ARCH'"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Error: Unknown target '$1' architecture"
    exit 1
    ;;
esac

#
# dependencies
#

if ! command -v git &> /dev/null; then
  echo "Error: 'git' not found"
  exit 1
fi

#
# get depot tools
#

export PATH="$(cd "$(dirname "$0")" && pwd)/depot_tools:$PATH"

if [ ! -d depot_tools ]; then
  git clone --depth=1 --no-tags --single-branch https://chromium.googlesource.com/chromium/tools/depot_tools.git || exit 1
fi

#
# clone angle source
#

if [ -z "$ANGLE_COMMIT" ]; then
  ANGLE_COMMIT=$(git ls-remote https://chromium.googlesource.com/angle/angle HEAD | awk '{ print $1 }')
fi

if [ ! -d angle ]; then
  mkdir angle
  cd angle
  git init || exit 1
  git remote add origin https://chromium.googlesource.com/angle/angle || exit 1
  cd ..
fi

cd angle

if [ -d build ]; then
  cd build
  git reset --hard HEAD
  cd ..
fi

git fetch origin "$ANGLE_COMMIT" || exit 1
git checkout --force FETCH_HEAD || exit 1

python3 scripts/bootstrap.py || exit 1

# Remove unnecessary dependencies from DEPS file (minimal set)
python3 ../clean_deps.py || exit 1

# Create fake rust-toolchain to satisfy build (before gclient sync)
mkdir -p third_party/rust-toolchain
echo 'rustc 0.0.0 (00000000 0000-00-00)' > third_party/rust-toolchain/VERSION

gclient sync -f -D -R || exit 1

# Comment out rust_static_library import (we don't use Rust in ANGLE builds)
sed -i.bak 's|^import("//build/rust/rust_static_library.gni")|#import("//build/rust/rust_static_library.gni")|' testing/test.gni || true

cd ..

#
# build angle
#

cd angle

# Use ARCH directly - ANGLE's angle.gni only accepts x64 and arm64 as target_cpu values
gn gen out/"$ARCH" --args="target_cpu=\"$ARCH\" angle_build_all=false is_debug=false angle_has_frame_capture=false angle_enable_gl=false angle_enable_vulkan=true angle_enable_wgpu=false angle_enable_metal=true angle_enable_null=false angle_enable_abseil=false use_siso=false install_prefix=\"../angle-$ARCH\" ldflags=[\"-headerpad_max_install_names\"]" || exit 1
autoninja --offline -C out/"$ARCH" libEGL libGLESv2 libGLESv1_CM install_angle || exit 1

cd ..

#
# prepare output folder
#

OUTPUT_DIR="angle/out/angle-$ARCH"
FINAL_DIR="angle-$ARCH"

# Copy to final location
rm -rf "$FINAL_DIR"
cp -R "$OUTPUT_DIR" "$FINAL_DIR"

# Fix pkgconfig prefix to use final location (relative path for portability)
sed -i.bak "s|^prefix=.*|prefix=/usr/local|" "$FINAL_DIR"/lib/pkgconfig/*.pc
rm -f "$FINAL_DIR"/lib/pkgconfig/*.pc.bak

echo "$ANGLE_COMMIT" > "$FINAL_DIR"/commit.txt

# Copy additional SDK headers for third-party dependencies
# Vulkan headers
cp -R angle/third_party/vulkan-headers/src/include/vulkan "$FINAL_DIR"/include/ 2>/dev/null || true
cp -R angle/third_party/vulkan-headers/src/include/vk_video "$FINAL_DIR"/include/ 2>/dev/null || true
# SPIRV headers
cp -R angle/third_party/spirv-headers/src/include/spirv "$FINAL_DIR"/include/ 2>/dev/null || true

# Remove unnecessary files
find "$FINAL_DIR"/include -name "*.clang-format" -delete 2>/dev/null || true
find "$FINAL_DIR"/include -name "*.md" -delete 2>/dev/null || true

#
# Done!
#

if [ -n "$GITHUB_WORKFLOW" ]; then
  #
  # GitHub actions stuff
  #

  zip -9 -r "angle-$ARCH-${BUILD_DATE}.zip" "$FINAL_DIR" || exit 1
fi
