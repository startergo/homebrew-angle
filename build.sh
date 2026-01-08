#!/bin/bash
set -ex  # Exit on error, print each command before executing

# Tell git to not look for .git directory in parent directories
# This prevents "fatal: not a git repository" errors when building from tarball
export GIT_CEILING_DIRECTORIES=$(pwd)

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

if ! command -v python3 &> /dev/null; then
  echo "Error: 'python3' not found"
  exit 1
fi

if ! command -v ninja &> /dev/null; then
  echo "Error: 'ninja' not found"
  exit 1
fi

if ! command -v gn &> /dev/null; then
  echo "Error: 'gn' not found. Install with: brew install startergo/gn/gn"
  exit 1
fi

# Store paths to system tools before adding depot_tools to PATH
SYSTEM_GN=$(command -v gn)

# Find ninja binary directly from known installation paths
# This avoids the Homebrew shims that cause fork issues
SYSTEM_NINJA=""
for ninja_path in /opt/homebrew/Cellar/ninja/*/bin/ninja /opt/homebrew/bin/ninja /usr/local/bin/ninja /opt/local/bin/ninja; do
  if [ -x "$ninja_path" ]; then
    SYSTEM_NINJA="$ninja_path"
    break
  fi
done

if [ -z "$SYSTEM_NINJA" ]; then
  echo "ERROR: ninja not found in any known location" >&2
  exit 1
fi
echo "Found ninja at: $SYSTEM_NINJA" >&2

#
# get depot tools
#

export PATH="$(cd "$(dirname "$0")" && pwd)/depot_tools:$PATH"

if [ ! -d depot_tools ]; then
  git clone --depth=1 --no-tags --single-branch https://chromium.googlesource.com/chromium/tools/depot_tools.git || exit 1
fi

#
# clone angle source
# Use git -C syntax (MacPorts-style) to avoid directory issues
#

# ANGLE will fetch from main branch (MacPorts-style)
if [ ! -d angle/.git ]; then
  # Create angle directory and initialize git repo
  mkdir -p angle || exit 1
  git -C angle init || exit 1
  git -C angle remote add origin https://chromium.googlesource.com/angle/angle || exit 1
fi

# Fetch from main branch and checkout FETCH_HEAD (MacPorts-style)
# Retry on network failures (up to 3 times)
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if git -C angle fetch origin main; then
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Git fetch failed, retrying ($RETRY_COUNT/$MAX_RETRIES)..."
    sleep 2
  else
    echo "Error: Failed to fetch ANGLE after $MAX_RETRIES attempts" >&2
    exit 1
  fi
done
git -C angle checkout --force FETCH_HEAD || exit 1

# Apply ANGLE bug fix patches
PATCH_DIR="$(dirname "$0")/patches"

# Create a log file that survives even if output is suppressed
PATCH_LOG="/tmp/angle-patch-status.txt"
echo "=== ANGLE PATCH APPLICATION LOG ===" > "$PATCH_LOG"
echo "Looking for patches in: $PATCH_DIR" >> "$PATCH_LOG"

echo "========================================" >&2
echo "=== Looking for patches in: $PATCH_DIR ===" >&2
if [ -d "$PATCH_DIR" ]; then
  echo "=== Patches directory FOUND ===" >&2
  echo "Patches directory FOUND" >> "$PATCH_LOG"
  ls -la "$PATCH_DIR/" >&2
  ls -la "$PATCH_DIR/" >> "$PATCH_LOG"
else
  echo "=== Patches directory NOT FOUND ===" >&2
  echo "Patches directory NOT FOUND" >> "$PATCH_LOG"
fi

if [ -f "$PATCH_DIR/angle-changes-main.patch" ]; then
  echo "=== PATCH FILE FOUND! Applying... ===" >&2
  echo "PATCH FILE FOUND! Applying..." >> "$PATCH_LOG"
  echo "=== Patch file: $PATCH_DIR/angle-changes-main.patch ===" >&2
  if git -C angle apply --check ../patches/angle-changes-main.patch 2>/dev/null; then
    git -C angle apply ../patches/angle-changes-main.patch || {
      echo "=== ERROR: Failed to apply patches ===" >&2
      echo "ERROR: Failed to apply patches" >> "$PATCH_LOG"
      exit 1
    }
    echo "=== PATCHES APPLIED SUCCESSFULLY ===" >&2
    echo "PATCHES APPLIED SUCCESSFULLY" >> "$PATCH_LOG"
    # Show what was patched
    echo "=== Files patched: ===" >&2
    git -C angle diff --stat >&2
    git -C angle diff --stat >> "$PATCH_LOG"
  else
    echo "=== WARNING: Patch does not apply cleanly ===" >&2
    echo "WARNING: Patch does not apply cleanly" >> "$PATCH_LOG"
    echo "=== Continuing without patches ===" >&2
  fi
else
  echo "=== NO PATCH FILE FOUND - skipping ===" >&2
  echo "NO PATCH FILE FOUND - skipping" >> "$PATCH_LOG"
fi
echo "========================================" >&2
echo "=== PATCH LOG: $PATCH_LOG ===" >&2

# Now cd into angle for the rest of the build
cd angle

# Patch commit_id.py to not use git commands (we're building from tarball)
if [ -f src/commit_id.py ]; then
  cp src/commit_id.py src/commit_id.py.bak
  perl -i -pe 's/return _RunGitCommand\(\)/return None/g' src/commit_id.py || true
fi

# Skip bootstrap.py - it calls gclient sync which hangs on VK-GL-CTS/SwiftShader
# We manually download dependencies below instead
# python3 scripts/bootstrap.py || exit 1

# =============================================================================
# Manual dependency download (MacPorts-style approach)
# This avoids VK-GL-CTS and SwiftShader that cause gclient sync to hang
# =============================================================================

echo "=== Downloading Chromium build files ===" >&2
if [ ! -d build/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/build.git build || exit 1
fi

# Patch compiler config to remove warning flags not supported by Xcode clang
echo "=== Patching compiler config for Xcode clang compatibility ===" >&2
COMPILER_BUILD_GN="build/config/compiler/BUILD.gn"
TOOLCHAIN_GNI="build/toolchain/apple/toolchain.gni"

if [ -f "$COMPILER_BUILD_GN" ]; then
  cp "$COMPILER_BUILD_GN" "$COMPILER_BUILD_GN.bak"
  # Remove warning flags not supported by Xcode clang
  sed -i.bak '/"-Wno-nontrivial-memcall"/d' "$COMPILER_BUILD_GN" || true
  sed -i.bak '/"-Wno-uninitialized-const-pointer"/d' "$COMPILER_BUILD_GN" || true
  sed -i.bak '/"-Wno-maybe-uninitialized"/d' "$COMPILER_BUILD_GN" || true
  sed -i.bak '/"-Wno-packed-not-aligned"/d' "$COMPILER_BUILD_GN" || true
  sed -i.bak '/"-Wno-class-memaccess"/d' "$COMPILER_BUILD_GN" || true
  # Disable implicit-fallthrough warnings (third-party code has issues)
  sed -i.bak '/"-Wimplicit-fallthrough",/d' "$COMPILER_BUILD_GN" || true
  # Remove clang plugin configs (require Chromium hermetic toolchain)
  # These add -Xclang -add-plugin -Xclang find-bad-constructs and raw-ptr-plugin flags
  perl -i -pe 's|"\.\./rust/toolchain:rust_clang_plugins",|# "../rust/toolchain:rust_clang_plugins",|' "$COMPILER_BUILD_GN" || true
fi

# Patch toolchain config to use system clang directly (MacPorts-style)
if [ -f "$TOOLCHAIN_GNI" ]; then
  cp "$TOOLCHAIN_GNI" "$TOOLCHAIN_GNI.bak"
  # Comment out prefix and compiler_prefix variables
  sed -i.bak '/^    prefix = rebase_path/s|^|# |' "$TOOLCHAIN_GNI" || true
  sed -i.bak '/^    compiler_prefix = /s|^|# |' "$TOOLCHAIN_GNI" || true
  sed -i.bak '/^      compiler_prefix = /s|^|# |' "$TOOLCHAIN_GNI" || true
  # Use clang/clang++ directly instead of ${prefix}clang
  sed -i.bak 's|_cc = "${prefix}clang"|_cc = "clang"|' "$TOOLCHAIN_GNI"
  sed -i.bak 's|_cxx = "${prefix}clang++"|_cxx = "clang++"|' "$TOOLCHAIN_GNI"
  sed -i.bak 's|cc = compiler_prefix + _cc|cc = _cc|' "$TOOLCHAIN_GNI"
  sed -i.bak 's|cxx = compiler_prefix + _cxx|cxx = _cxx|' "$TOOLCHAIN_GNI"
  sed -i.bak 's|ld = _cxx|ld = cxx|' "$TOOLCHAIN_GNI"
  # Use system tools directly
  sed -i.bak 's|ar = "${prefix}llvm-ar"|ar = "ar"|' "$TOOLCHAIN_GNI"
  sed -i.bak 's|nm = "${prefix}llvm-nm"|nm = "nm"|' "$TOOLCHAIN_GNI"
  sed -i.bak 's|otool = "${prefix}llvm-otool"|otool = "otool"|' "$TOOLCHAIN_GNI"
  sed -i.bak 's|_strippath = "${prefix}llvm-strip"|_strippath = "strip"|' "$TOOLCHAIN_GNI"
  sed -i.bak 's|_installnametoolpath = "${prefix}llvm-install-name-tool"|_installnametoolpath = "install_name_tool"|' "$TOOLCHAIN_GNI"
  # Replace dsymutil rebase_path with direct path
  python3 -c $'\nimport re\nwith open("'"$TOOLCHAIN_GNI"'", '"'"'r'"'"') as f:\n    content = f.read()\ncontent = re.sub(\n    r'"'"'rebase_path\\("//tools/clang/dsymutil/bin/dsymutil",\\s+root_build_dir\\)'"'"',\n    '"'"'"dsymutil"'"'"',\n    content\n)\nwith open("'"$TOOLCHAIN_GNI"'", '"'"'w'"'"') as f:\n    f.write(content)\n' 2>/dev/null || true

  echo "=== Toolchain config patched ===" >&2
fi

echo "=== Downloading Chromium buildtools ===" >&2
if [ ! -d buildtools/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/buildtools.git buildtools || exit 1
fi

# Install system gn into buildtools (ANGLE expects it there)
# Must do this AFTER cloning buildtools to avoid conflicts
mkdir -p buildtools/mac/gn
cp "$SYSTEM_GN" buildtools/mac/gn/gn || exit 1
echo "=== Using gn: $(buildtools/mac/gn/gn --version) ===" >&2

# Install system ninja into buildtools (avoid Homebrew shim issues)
mkdir -p buildtools/mac/ninja
if [ -z "$SYSTEM_NINJA" ]; then
  echo "ERROR: SYSTEM_NINJA is empty - ninja not found in PATH" >&2
  echo "Current PATH: $PATH" >&2
  exit 1
fi
if [ ! -f "$SYSTEM_NINJA" ]; then
  echo "ERROR: SYSTEM_NINJA path doesn't exist: $SYSTEM_NINJA" >&2
  exit 1
fi
cp "$SYSTEM_NINJA" buildtools/mac/ninja/ninja || exit 1
if [ ! -x buildtools/mac/ninja/ninja ]; then
  echo "ERROR: Copied ninja is not executable: buildtools/mac/ninja/ninja" >&2
  exit 1
fi
echo "=== Using ninja: $(buildtools/mac/ninja/ninja --version) ===" >&2

echo "=== Downloading Chromium testing files ===" >&2
if [ ! -d testing/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/testing.git testing || exit 1
  # Comment out rust_static_library import
  sed -i.bak 's|^import("//build/rust/rust_static_library.gni")|#import("//build/rust/rust_static_library.gni")|' testing/test.gni || true
fi

echo "=== Downloading Vulkan headers ===" >&2
if [ ! -d third_party/vulkan-headers/src/.git ]; then
  mkdir -p third_party/vulkan-headers
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/KhronosGroup/Vulkan-Headers.git third_party/vulkan-headers/src || exit 1
fi

echo "=== Downloading SPIRV headers ===" >&2
if [ ! -d third_party/spirv-headers/src/.git ]; then
  mkdir -p third_party/spirv-headers
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/KhronosGroup/SPIRV-Headers.git third_party/spirv-headers/src || exit 1
fi

echo "=== Downloading SPIRV tools ===" >&2
if [ ! -d third_party/spirv-tools/src/.git ]; then
  mkdir -p third_party/spirv-tools
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/KhronosGroup/SPIRV-Tools.git third_party/spirv-tools/src || exit 1
fi

echo "=== Downloading glslang ===" >&2
if [ ! -d third_party/glslang/src/.git ]; then
  mkdir -p third_party/glslang
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/KhronosGroup/glslang.git third_party/glslang/src || exit 1
fi

echo "=== Downloading astc-encoder ===" >&2
if [ ! -d third_party/astc-encoder/src/Source ]; then
  mkdir -p third_party/astc-encoder
  git clone --depth=1 https://github.com/ARM-software/astc-encoder.git third_party/astc-encoder/src || exit 1
fi

echo "=== Downloading vulkan-loader ===" >&2
if [ ! -d third_party/vulkan-loader/src/.git ]; then
  mkdir -p third_party/vulkan-loader
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/KhronosGroup/Vulkan-Loader.git third_party/vulkan-loader/src || exit 1
  # Patch to remove vk_sdk_platform.h include (not needed, file was from SwiftShader)
  sed -i.bak 's|#include "vulkan/vk_sdk_platform.h"|// #include "vulkan/vk_sdk_platform.h"|' third_party/vulkan-loader/src/loader/vk_loader_platform.h || true
  # Disable VK_ENABLE_BETA_EXTENSIONS - video extension types don't exist in current Vulkan-Headers
  sed -i.bak '/"VK_ENABLE_BETA_EXTENSIONS",/d' third_party/vulkan-loader/src/BUILD.gn || true
fi

echo "=== Downloading vulkan-tools ===" >&2
if [ ! -d third_party/vulkan-tools/src/.git ]; then
  mkdir -p third_party/vulkan-tools
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/KhronosGroup/Vulkan-Tools.git third_party/vulkan-tools/src || exit 1
fi

echo "=== Downloading vulkan-utility-libraries ===" >&2
if [ ! -d third_party/vulkan-utility-libraries/src/.git ]; then
  mkdir -p third_party/vulkan-utility-libraries
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/KhronosGroup/Vulkan-Utility-Libraries.git third_party/vulkan-utility-libraries/src || exit 1
  # Disable VK_ENABLE_BETA_EXTENSIONS - video extension types don't exist in current Vulkan-Headers
  sed -i.bak '/"VK_ENABLE_BETA_EXTENSIONS"]/d' third_party/vulkan-utility-libraries/src/BUILD.gn || true
fi

echo "=== Downloading lunarg-vulkantools ===" >&2
if [ ! -d third_party/lunarg-vulkantools/src/.git ]; then
  mkdir -p third_party/lunarg-vulkantools
  # Try chromium-mirror URL first, fallback to github
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/LunarG/VulkanTools third_party/lunarg-vulkantools/src 2>/dev/null || \
  git clone --depth=1 https://github.com/LunarG/VulkanTools.git third_party/lunarg-vulkantools/src || true
fi

echo "=== Downloading vulkan-memory-allocator ===" >&2
if [ ! -d third_party/vulkan_memory_allocator/.git ]; then
  git clone https://chromium.googlesource.com/external/github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator.git third_party/vulkan_memory_allocator || exit 1
fi
# Get the VMA commit that ANGLE expects (from DEPS file)
VMA_COMMIT=$(curl -s "https://chromium.googlesource.com/angle/angle/+/refs/heads/main/DEPS?format=TEXT" | base64 -d | grep -A1 "vulkan_memory_allocator" | grep -o "@[a-f0-9]\{40\}" | cut -c2-)
if [ -z "$VMA_COMMIT" ]; then
  echo "Warning: Could not fetch VMA commit from ANGLE DEPS, using current HEAD"
else
  echo "Checking out VMA commit: $VMA_COMMIT"
  git -C third_party/vulkan_memory_allocator checkout "$VMA_COMMIT" || exit 1
fi

echo "=== Downloading googletest ===" >&2
if [ ! -d third_party/googletest/src/.git ]; then
  mkdir -p third_party/googletest
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/google/googletest.git third_party/googletest/src || exit 1
fi

echo "=== Downloading jsoncpp ===" >&2
if [ ! -d third_party/jsoncpp/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/third_party/jsoncpp.git third_party/jsoncpp || exit 1
fi

echo "=== Downloading zlib ===" >&2
if [ ! -d third_party/zlib/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/third_party/zlib.git third_party/zlib || exit 1
fi

echo "=== Downloading abseil-cpp ===" >&2
if [ ! -d third_party/abseil-cpp/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/third_party/abseil-cpp.git third_party/abseil-cpp || exit 1
fi

echo "=== Downloading YASM ===" >&2
if [ ! -d third_party/yasm/source/.git ]; then
  mkdir -p third_party/yasm
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/third_party/yasm.git third_party/yasm/source || exit 1
fi

echo "=== Downloading libpng ===" >&2
if [ ! -d third_party/libpng/src/.git ]; then
  mkdir -p third_party/libpng
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/third_party/libpng.git third_party/libpng/src || exit 1
fi

echo "=== Downloading libjpeg_turbo ===" >&2
if [ ! -d third_party/libjpeg_turbo/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/deps/libjpeg_turbo third_party/libjpeg_turbo || exit 1
fi

echo "=== Downloading re2 ===" >&2
if [ ! -d third_party/re2/src/.git ]; then
  mkdir -p third_party/re2
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/google/re2.git third_party/re2/src || exit 1
fi

echo "=== Downloading ICU ===" >&2
if [ ! -d third_party/icu/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/deps/icu.git third_party/icu || exit 1
fi

echo "=== Downloading harfbuzz ===" >&2
if [ ! -d third_party/harfbuzz-ng/harfbuzz/src/.git ]; then
  mkdir -p third_party/harfbuzz-ng/harfbuzz
  git clone --depth=1 https://chromium.googlesource.com/external/github.com/harfbuzz/harfbuzz.git third_party/harfbuzz-ng/harfbuzz/src || exit 1
fi

echo "=== Downloading freetype ===" >&2
if [ ! -d third_party/freetype/src/.git ]; then
  mkdir -p third_party/freetype
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/third_party/freetype.git third_party/freetype/src || exit 1
fi

echo "=== Downloading Chromium tools/clang ===" >&2
# The build system needs tools/clang/scripts/update.py for version checking
if [ ! -d tools/clang/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/tools/clang.git tools/clang || exit 1
fi

echo "=== Downloading Chromium tools/rust ===" >&2
# The build system needs tools/rust/update_rust.py for version checking
if [ ! -d tools/rust/.git ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/src/tools/rust.git tools/rust || exit 1
fi

echo "=== Setting up llvm-build for macOS ===" >&2
# Use system LLVM from Xcode, create minimal structure to satisfy build config
mkdir -p third_party/llvm-build/Release+Asserts
CLANG_REVISION=$(grep -oE "CLANG_REVISION = '[^']+'" tools/clang/scripts/update.py | cut -d"'" -f2)
CLANG_SUB_REVISION=$(grep -oE "CLANG_SUB_REVISION = [0-9]+" tools/clang/scripts/update.py | awk '{print $3}')
echo "${CLANG_REVISION}-${CLANG_SUB_REVISION}" > third_party/llvm-build/Release+Asserts/cr_build_revision || exit 1
echo "=== Using clang revision: ${CLANG_REVISION}-${CLANG_SUB_REVISION} ===" >&2

# Create stub clang runtime library (build references libclang_rt.osx.a)
mkdir -p third_party/llvm-build/Release+Asserts/lib/clang/22/lib/darwin
echo "=== Creating stub clang runtime library ===" >&2
cat > /tmp/stub_clang_rt.c << 'EOF'
void __clang_runtime_init(void) {}
EOF
# Use Xcode clang for compilation, Homebrew llvm-ar for archiving
xcrun clang -c /tmp/stub_clang_rt.c -o /tmp/stub_clang_rt.o || clang -c /tmp/stub_clang_rt.c -o /tmp/stub_clang_rt.o
/opt/homebrew/opt/llvm/bin/llvm-ar rcs third_party/llvm-build/Release+Asserts/lib/clang/22/lib/darwin/libclang_rt.osx.a /tmp/stub_clang_rt.o 2>/dev/null || \
libtool -static -o third_party/llvm-build/Release+Asserts/lib/clang/22/lib/darwin/libclang_rt.osx.a /tmp/stub_clang_rt.o
rm -f /tmp/stub_clang_rt.c /tmp/stub_clang_rt.o

# Set up build tools: Xcode clang for compiling, Homebrew LLVM for other tools
mkdir -p third_party/llvm-build/Release+Asserts/bin
echo "=== Setting up build tools ===" >&2
# IMPORTANT: Use wrapper scripts for clang/clang++ NOT symlinks!
# Symlinking breaks clang's ability to find its resource directory (stdarg.h, etc.)
# Also filter out Chromium clang plugin flags (require hermetic toolchain plugins)
cat > third_party/llvm-build/Release+Asserts/bin/clang <<'EOF'
#!/bin/sh
# Filter out clang plugin flags - they require Chromium's hermetic toolchain
args=""
skip_next=false
for arg in "$@"; do
  if [ "$skip_next" = true ]; then
    # This arg was preceded by -Xclang, check if it's plugin-related
    case "$arg" in
      -add-plugin|-plugin-arg-*|find-bad-constructs|raw-ptr-plugin|check-stack-allocated|check-raw-ptr-to-stack-allocated|disable-check-raw-ptr-to-stack-allocated-error|raw-ptr-exclude-path=*)
        # Skip this arg too
        skip_next=false
        continue
        ;;
      *)
        # Not plugin-related, keep the -Xclang and this arg
        args="$args -Xclang $arg"
        skip_next=false
        ;;
    esac
  else
    case "$arg" in
      -Xclang)
        skip_next=true
        ;;
      *)
        args="$args $arg"
        ;;
    esac
  fi
done
exec "$(xcrun -f clang)" $args
EOF
cat > third_party/llvm-build/Release+Asserts/bin/clang++ <<'EOF'
#!/bin/sh
# Filter out clang plugin flags - they require Chromium's hermetic toolchain
args=""
skip_next=false
for arg in "$@"; do
  if [ "$skip_next" = true ]; then
    # This arg was preceded by -Xclang, check if it's plugin-related
    case "$arg" in
      -add-plugin|-plugin-arg-*|find-bad-constructs|raw-ptr-plugin|check-stack-allocated|check-raw-ptr-to-stack-allocated|disable-check-raw-ptr-to-stack-allocated-error|raw-ptr-exclude-path=*)
        # Skip this arg too
        skip_next=false
        continue
        ;;
      *)
        # Not plugin-related, keep the -Xclang and this arg
        args="$args -Xclang $arg"
        skip_next=false
        ;;
    esac
  else
    case "$arg" in
      -Xclang)
        skip_next=true
        ;;
      *)
        args="$args $arg"
        ;;
    esac
  fi
done
exec "$(xcrun -f clang++)" $args
EOF
chmod +x third_party/llvm-build/Release+Asserts/bin/clang third_party/llvm-build/Release+Asserts/bin/clang++
# Use symlinks for Homebrew LLVM tools (ar, nm, strip, etc.)
ln -sf /opt/homebrew/opt/llvm/bin/llvm-ar third_party/llvm-build/Release+Asserts/bin/llvm-ar || true
ln -sf /opt/homebrew/opt/llvm/bin/llvm-nm third_party/llvm-build/Release+Asserts/bin/llvm-nm || true
ln -sf /opt/homebrew/opt/llvm/bin/llvm-ranlib third_party/llvm-build/Release+Asserts/bin/llvm-ranlib || true
ln -sf /opt/homebrew/opt/llvm/bin/llvm-strip third_party/llvm-build/Release+Asserts/bin/llvm-strip || true
# For compatibility, also create 'ar', 'nm', 'strip', 'ranlib' symlinks
ln -sf /opt/homebrew/opt/llvm/bin/llvm-ar third_party/llvm-build/Release+Asserts/bin/ar || true
ln -sf /opt/homebrew/opt/llvm/bin/llvm-nm third_party/llvm-build/Release+Asserts/bin/nm || true
ln -sf /opt/homebrew/opt/llvm/bin/llvm-strip third_party/llvm-build/Release+Asserts/bin/strip || true
ln -sf /opt/homebrew/opt/llvm/bin/llvm-ranlib third_party/llvm-build/Release+Asserts/bin/ranlib || true
ln -sf "$(command -v xcrun)" third_party/llvm-build/Release+Asserts/bin/xcrun || true

echo "=== Setting up rust-toolchain for macOS ===" >&2
RUST_REVISION=$(grep -oE "RUST_REVISION = '[^']+'" tools/rust/update_rust.py | cut -d"'" -f2)
RUST_SUB_REVISION=$(grep "RUST_SUB_REVISION = " tools/rust/update_rust.py | sed 's/.*RUST_SUB_REVISION = \([0-9]*\).*/\1/')
# gn parses VERSION to match "*-hash-subrev-*" pattern
mkdir -p third_party/rust-toolchain
echo "rustc x ( ${RUST_REVISION}-${RUST_SUB_REVISION}- y )" > third_party/rust-toolchain/VERSION || exit 1
echo "=== Using rust revision: ${RUST_REVISION}-${RUST_SUB_REVISION} ===" >&2

echo "=== Creating gclient_args.gni ===" >&2
mkdir -p build/config
cat > build/config/gclient_args.gni << 'EOF'
# Generated for ANGLE standalone build
declare_args() {
  checkout_angle_internal = false
  checkout_angle_mesa = false
  checkout_angle_restricted_traces = false
  generate_location_tags = false
  checkout_android = false
  checkout_android_native_support = false
  checkout_google_benchmark = false
  checkout_openxr = false
  checkout_telemetry_dependencies = false
}
EOF

echo "=== Creating .gclient for compatibility ===" >&2
cat > .gclient << 'EOF'
solutions = [
  {
    "name": ".",
    "url": "https://chromium.googlesource.com/angle/angle",
  },
]
EOF

# Create fake .gclient_entries to silence warnings
echo "=== Creating .gclient_entries for compatibility ===" >&2
cat > .gclient_entries << 'EOF'
entries = {
  ".": {
    "url": "https://chromium.googlesource.com/angle/angle",
    "scm": "git",
  },
}
EOF

# =============================================================================
# Inject Homebrew bottle config for @rpath install_name
# This ensures bottles work on any macOS system with proper dylib loading
# =============================================================================

echo "=== Injecting @rpath install_name config into BUILD.gn ===" >&2

# Create temp file with GN config blocks
cat > /tmp/angle_build_config.txt << 'EOF'
config("homebrew_bottle_config_libEGL") {
  if (is_mac) {
    ldflags = [ "-Wl,-install_name,@rpath/libEGL.dylib" ]
  }
}
config("homebrew_bottle_config_libGLESv2") {
  if (is_mac) {
    ldflags = [ "-Wl,-install_name,@rpath/libGLESv2.dylib" ]
  }
}
config("homebrew_bottle_config_libGLESv1_CM") {
  if (is_mac) {
    ldflags = [ "-Wl,-install_name,@rpath/libGLESv1_CM.dylib" ]
  }
}
EOF

# Use awk to insert config before shared_library_public_config in BUILD.gn
awk '
  /config\("shared_library_public_config"\)/ {
    while ((getline line < "/tmp/angle_build_config.txt") > 0) {
      print line
    }
    close("/tmp/angle_build_config.txt")
    print ""
  }
  { print }
' BUILD.gn > BUILD.gn.tmp && mv BUILD.gn.tmp BUILD.gn
rm -f /tmp/angle_build_config.txt
echo "Config injected into BUILD.gn" >&2

# Add each install_name config to its respective library target in BUILD.gn
for lib in EGL GLESv2 GLESv1_CM; do
  awk -v lib="$lib" '
    /angle_shared_library\("lib'"$lib"'"\)/ { in_target = 1 }
    in_target && /configs =/ && !target_modified {
      print $0
      print "    configs += [ \":homebrew_bottle_config_lib'"$lib"'\" ]"
      target_modified = 1
      next
    }
    in_target && /\}/ {
      in_target = 0
    }
    { print }
  ' BUILD.gn > BUILD.gn.tmp && mv BUILD.gn.tmp BUILD.gn
done
echo "install_name configs added to library targets in BUILD.gn" >&2

cd ..

#
# build angle
#

cd angle

# Set up clean PATH (remove Homebrew shims that cause fork issues)
CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "Homebrew/shims" | tr '\n' ':' | sed 's/:$//')
# Add llvm-build bin to PATH (contains Xcode clang + Homebrew LLVM tools)
export PATH="$(pwd)/third_party/llvm-build/Release+Asserts/bin:$(pwd)/buildtools/mac/gn:$(pwd)/buildtools/mac/ninja:$CLEAN_PATH"

# Use Xcode clang for compilation (has macOS SDK patches)
# Use Homebrew LLVM for other tools
export CC=$(xcrun -f clang)
export CXX=$(xcrun -f clang++)
export AR=llvm-ar
export RANLIB=llvm-ranlib

# gn gen (target_cpu: x64 or arm64)
gn gen out/"$ARCH" --args="target_cpu=\"$ARCH\" angle_build_all=false is_debug=false angle_has_frame_capture=false angle_enable_gl=false angle_enable_vulkan=true angle_enable_swiftshader=false angle_enable_wgpu=false angle_enable_metal=true angle_enable_null=false angle_enable_abseil=false use_siso=false install_prefix=\"../angle-$ARCH\" use_system_xcode=true use_custom_libcxx=false use_lld=false" || exit 1
# Use copied ninja directly from buildtools with limited parallelism to avoid memory issues
"$(pwd)/buildtools/mac/ninja/ninja" -j 4 -C out/"$ARCH" libEGL libGLESv2 libGLESv1_CM install_angle || exit 1

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

  # Create source tarball for formula URL
  VERSION="${VERSION:-1.0.0}"
  tar -czf "angle-${VERSION}.tar.gz" "$FINAL_DIR"
  echo "Created tarball: angle-${VERSION}.tar.gz"
  # Also calculate sha256 for formula
  if command -v shasum &> /dev/null; then
    SHA256=$(shasum -a 256 "angle-${VERSION}.tar.gz" | awk '{print $1}')
    echo "SHA256: $SHA256"
    # Write to file for reliable capture (brew may suppress stdout, and GITHUB_ENV is not available in brew subprocess)
    echo "$SHA256" > /tmp/angle-source-sha256.txt
    echo "SHA256 written to /tmp/angle-source-sha256.txt"
  fi
fi
