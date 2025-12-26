# Documentation: https://docs.brew.sh/Formula-Cookbook
#                https://rubydoc.brew.sh/Formula
class Angle < Formula
  desc "Almost Native Graphics Layer Engine (OpenGL ES implementation for macOS)"
  homepage "https://chromium.googlesource.com/angle/angle"
  # For local testing with file:// URL:
  # url "file:///Users/macbookpro/build-angle/build-angle-1.0.0.tar.gz"
  # For production with GitHub release:
  url "https://github.com/startergo/build-angle/archive/refs/tags/v1.0.0.tar.gz"
  version "1.0.0"
  sha256 :no_check
  license "BSD-2-Clause"

  bottle do
    root_url "https://github.com/startergo/homebrew-angle/releases/download/v#{version}"
    sha256 cellar: :any_skip_relocation, arm64_sonoma: "9434db2be6d2a607e223b88d7e89c9ee1e3a5cfb2e539eddd510b2b0e8d990af"
  end

  depends_on "gn" => :build
  depends_on "ninja" => :build
  depends_on "python@3.12" => :build

  # ANGLE has no stable releases, track HEAD
  head "https://chromium.googlesource.com/angle/angle",
       using: :git

  def install
    # Use the project's build script
    system "./build.sh", Hardware::CPU.arm? ? "arm64" : "x64"

    # Install the built libraries
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    angle_dir = "angle-#{arch}"

    # Install libraries
    lib.install Dir["#{angle_dir}/lib/*.dylib"]

    # Install headers
    include.install Dir["#{angle_dir}/include/*"]

    # Install pkgconfig files
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
