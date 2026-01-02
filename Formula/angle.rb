class Angle < Formula
  desc "Almost Native Graphics Layer Engine (OpenGL ES implementation for macOS)"
  homepage "https://chromium.googlesource.com/angle/angle"
  depends_on "startergo/gn/gn" => :build
  depends_on "ninja" => :build
  depends_on "llvm" => :build
  url "https://github.com/startergo/homebrew-angle/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "9b7b345ee821890ce81d6f9f8e65d5d726e0cd58c013fab2321c3fd33008d53a"
  license "BSD-2-Clause"

  bottle do
    root_url "https://github.com/startergo/homebrew-angle/releases/download/v1.0.2"
    rebuild 1
    sha256 cellar: :any, arm64_sequoia: "01b9b89ea3b135e1f09a78a112a51e26760ffc90362cd26a25ce0bd4117bfdfe"
  end

  head "https://chromium.googlesource.com/angle/angle",
       using: :git

  def install
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    angle_dir = "angle-#{arch}"

    # Install_name configs are handled by angle-homebrew-bottle.patch
    # The patch adds each config to its respective library target only

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
