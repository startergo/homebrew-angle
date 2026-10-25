class Angle < Formula
  desc "Almost Native Graphics Layer Engine (OpenGL ES implementation for macOS)"
  homepage "https://chromium.googlesource.com/angle/angle"

  bottle do
    root_url "https://github.com/startergo/homebrew-angle/releases/download/v1.0.18"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "af49dc1f227b1e638f792843affc9e7f6780eb8783fddc63ddf449ef8c6ed4f3"
  end
  depends_on "startergo/gn/gn" => :build
  depends_on "ninja" => :build
  depends_on "llvm" => :build
  version "1.0.18"
  url "https://github.com/startergo/homebrew-angle/archive/refs/tags/v1.0.18.tar.gz"
  sha256 "b7e2cb5392f4a36254ca01addcec77165ca35773e2b871ded079c45c43bae980"
  license "BSD-2-Clause"

  head "https://chromium.googlesource.com/angle/angle",
       using: :git

  def install
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    angle_dir = "angle-#{arch}"

    # build.sh handles @rpath install_name configuration internally
    # for both bottle builds and local source builds
    system "./build.sh", arch

    # Copy dylibs directly to preserve install_name set during build
    # lib.install would rewrite to keg-only path, losing the header padding
    mkdir_p lib
    system "cp", "-R", "#{angle_dir}/lib/.", lib.to_s

    include.install Dir["#{angle_dir}/include/*"]
    (lib/"pkgconfig").install Dir["#{angle_dir}/lib/pkgconfig/*.pc"]

    # Fix pkgconfig prefix to point to Homebrew prefix
    inreplace Dir[lib/"pkgconfig/*.pc"] do |s|
      s.gsub!(/^prefix=.*$/, "prefix=#{HOMEBREW_PREFIX}")
    end

    # Store commit info
    (share/"angle").install "#{angle_dir}/commit.txt"
  end

  post_install_steps do
    # Restore @rpath install names that Homebrew may have changed to
    # /opt/homebrew/opt/angle/lib/*.dylib. change_dylib_id re-signs on arm64.
    on_macos do
      change_dylib_id "lib/libEGL.dylib", "@rpath/libEGL.dylib"
      change_dylib_id "lib/libGLESv1_CM.dylib", "@rpath/libGLESv1_CM.dylib"
      change_dylib_id "lib/libGLESv2.dylib", "@rpath/libGLESv2.dylib"
    end
  end

  test do
    # Test that pkg-config files are valid
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
