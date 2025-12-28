#!/bin/bash
set -e

ARCH=arm64
BUILD_DIR="/Users/macbookpro/build-angle"
VERSION="1.0.0"

echo "=== Step 1: Build ANGLE if not already built ==="
cd "$BUILD_DIR"
if [ ! -d "angle-$ARCH" ]; then
  echo "ANGLE not built yet. Running build.sh..."
  ./build.sh $ARCH
else
  echo "ANGLE already built in angle-$ARCH"
fi

echo ""
echo "=== Step 2: Set up tap directory ==="
cd "$BUILD_DIR/homebrew-angle"

TAP_DIR="$(brew --repository)/Library/Taps/startergo/homebrew-angle"
mkdir -p "$TAP_DIR/Formula"

# Initialize tap as a git repository (required by Homebrew)
if [ ! -d "$TAP_DIR/.git" ]; then
  echo "Initializing tap as git repository..."
  cd "$TAP_DIR"
  git init
  git checkout -b master
  echo "# homebrew-angle tap" > README.md
  git add README.md
  git commit -m "Initial commit"
  cd "$BUILD_DIR/homebrew-angle"
fi

# Create tap formula that installs from pre-built angle-arm64 directory
# This matches what's actually on disk and avoids build dependencies
cat > "$TAP_DIR/Formula/angle.rb" <<'EOF'
# Documentation: https://docs.brew.sh/Formula-Cookbook
#                https://rubydoc.brew.sh/Formula
class Angle < Formula
  desc "Almost Native Graphics Layer Engine (OpenGL ES implementation for macOS)"
  homepage "https://chromium.googlesource.com/angle/angle"
  version "1.0.0"
  url "https://github.com/startergo/build-angle/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "9facfb7c61650dd4f534519b2f7fd09c98e6eaae4d5aae3ed74604c0aaa6733c"
  license "BSD-2-Clause"

  bottle do
    root_url "https://github.com/startergo/homebrew-angle/releases/download/v1.0.0"
  end

  # ANGLE has no stable releases, track HEAD
  head "https://chromium.googlesource.com/angle/angle",
       using: :git

  def install
    # Use pre-built ANGLE from build directory
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    angle_dir = "/Users/macbookpro/build-angle/angle-#{arch}"

    # Verify pre-built directory exists
    if !Dir.exist?(angle_dir)
      odie "Pre-built ANGLE directory not found: #{angle_dir}\nPlease build first with: cd /Users/macbookpro/build-angle && ./build.sh #{arch}"
    end

    # Install from the pre-built directory
    lib.install Dir["#{angle_dir}/lib/*.dylib"]
    include.install Dir["#{angle_dir}/include/*"]
    (lib/"pkgconfig").install Dir["#{angle_dir}/lib/pkgconfig/*.pc"]

    # Fix pkgconfig prefix to point to Homebrew prefix
    inreplace Dir[lib/"pkgconfig/*.pc"] do |s|
      s.gsub!(/^prefix=.*$/, "prefix=#{HOMEBREW_PREFIX}")
    end
  end

  test do
    system "pkg-config", "--exists", "egl"
    system "pkg-config", "--exists", "glesv2"
    system "pkg-config", "--exists", "glesv1_cm"

    # Test that libraries are linkable
    test_c = <<~EOS
      #include <EGL/egl.h>
      #include <GLES2/gl2.h>
      int main() {
        EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        return 0;
      }
    EOS

    (testpath/"test.c").write test_c
    system ENV.cc, "test.c",
           "-I#{include}/EGL",
           "-I#{include}/GLES2",
           "-L#{lib}",
           "-lEGL",
           "-lGLESv2",
           "-o", "test"
    system "./test"
  end
end
EOF

# Pre-create homebrew/core and homebrew/cask taps to prevent auto-cloning
CORE_TAP_DIR="$(brew --repository)/Library/Taps/homebrew/homebrew-core"
if [ ! -d "$CORE_TAP_DIR" ]; then
  echo "Creating placeholder for homebrew/core tap to prevent auto-cloning..."
  mkdir -p "$CORE_TAP_DIR"
  echo "# Placeholder to prevent auto-cloning" > "$CORE_TAP_DIR/.gitkeep"
fi

CASK_TAP_DIR="$(brew --repository)/Library/Taps/homebrew/homebrew-cask"
if [ ! -d "$CASK_TAP_DIR" ]; then
  echo "Creating placeholder for homebrew/cask tap to prevent auto-cloning..."
  mkdir -p "$CASK_TAP_DIR"
  echo "# Placeholder to prevent auto-cloning" > "$CASK_TAP_DIR/.gitkeep"
fi

echo ""
echo "=== Step 3: Create a fake source directory to satisfy Homebrew ==="
cd "$BUILD_DIR"
FAKE_SOURCE_DIR="$BUILD_DIR/homebrew-angle-angle-source"
rm -rf "$FAKE_SOURCE_DIR"
mkdir -p "$FAKE_SOURCE_DIR"

# Create minimal files to make it look like a downloaded tarball
echo "# ANGLE fake source" > "$FAKE_SOURCE_DIR/README.md"
echo "1.0.0" > "$FAKE_SOURCE_DIR/VERSION"

# Create a fake tarball that Homebrew will "download"
# Tar from BUILD_DIR (parent of FAKE_SOURCE_DIR)
tar czf "$FAKE_SOURCE_DIR.tar.gz" -C "$BUILD_DIR" "$(basename "$FAKE_SOURCE_DIR")"

echo ""
echo "=== Step 4: Create local formula that uses file:// URL ==="
cd "$BUILD_DIR/homebrew-angle"
cat > Formula/angle_local.rb <<'EOF'
# Documentation: https://docs.brew.sh/Formula-Cookbook
#                https://rubydoc.brew.sh/Formula
class Angle < Formula
  desc "Almost Native Graphics Layer Engine (OpenGL ES implementation for macOS)"
  homepage "https://chromium.googlesource.com/angle/angle"
  version "1.0.0"

  # Use file:// URL to skip download
  url "file:///Users/macbookpro/build-angle/homebrew-angle-angle-source.tar.gz"
  sha256 "9999999999999999999999999999999999999999999999999999999999999"
  license "BSD-2-Clause"

  bottle do
    root_url "https://github.com/startergo/homebrew-angle/releases/download/v1.0.0"
  end

  # Skip build dependencies for local testing since we use pre-built files
  # depends_on "gn" => :build
  # depends_on "ninja" => :build
  # depends_on "python@3.12" => :build

  # ANGLE has no stable releases, track HEAD
  head "https://chromium.googlesource.com/angle/angle",
       using: :git

  def install
    # Skip build - files are already in place
    # Just verify the build directory exists
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    angle_dir = "#{buildpath}/../angle-#{arch}"

    # Install from the pre-built directory
    lib.install Dir["#{angle_dir}/lib/*.dylib"]
    include.install Dir["#{angle_dir}/include/*"]
    (lib/"pkgconfig").install Dir["#{angle_dir}/lib/pkgconfig/*.pc"]

    # Fix pkgconfig prefix to point to Homebrew prefix
    inreplace Dir[lib/"pkgconfig/*.pc"] do |s|
      s.gsub!(/^prefix=.*$/, "prefix=#{HOMEBREW_PREFIX}")
    end
  end

  test do
    system "pkg-config", "--exists", "egl"
    system "pkg-config", "--exists", "glesv2"
  end
end
EOF

echo ""
echo "=== Step 5: Manually install ANGLE files to Homebrew prefix ==="
# Skip brew install to avoid tapping homebrew/core
# Instead, manually copy files to simulate installation (matching CI workflow)
cd "$BUILD_DIR"
ANGLE_DIR="$BUILD_DIR/angle-$ARCH"
HOMEBREW_PREFIX=$(brew --prefix)

# Install libraries
echo "Copying libraries to prefix..."
mkdir -p "$HOMEBREW_PREFIX/lib"
cp -R "$ANGLE_DIR/lib/"*.dylib "$HOMEBREW_PREFIX/lib/"

# Install headers
echo "Copying headers to prefix..."
mkdir -p "$HOMEBREW_PREFIX/include"
cp -R "$ANGLE_DIR/include/"* "$HOMEBREW_PREFIX/include/"

# Install pkgconfig files
echo "Copying pkgconfig files to prefix..."
mkdir -p "$HOMEBREW_PREFIX/lib/pkgconfig"
cp "$ANGLE_DIR/lib/pkgconfig/"*.pc "$HOMEBREW_PREFIX/lib/pkgconfig/"

# Fix pkgconfig prefix
echo "Fixing pkgconfig prefix..."
for pc in "$HOMEBREW_PREFIX/lib/pkgconfig/"*.pc; do
  if [ -f "$pc" ]; then
    perl -pi -e "s|^prefix=.*|prefix=$HOMEBREW_PREFIX|" "$pc"
  fi
done

echo "Files installed to $HOMEBREW_PREFIX"

echo ""
echo "=== Step 6: Create bottle directly from tap formula ==="
cd "$BUILD_DIR/homebrew-angle"
export HOMEBREW_NO_INSTALL_FROM_API=1

# Build bottle from tap directory path (NO brew install)
echo "Creating bottle..."
TAP_DIR="$(brew --repository)/Library/Taps/startergo/homebrew-angle"
brew bottle --json --force-core-tap "$TAP_DIR/Formula/angle.rb" \
  --root-url=https://github.com/startergo/homebrew-angle/releases/download/v$VERSION \
  --force

echo ""
echo "=== Done! Check for *.rb files ==="
ls -la *.rb 2>/dev/null || echo "No .rb files found"
