class Angle < Formula
  desc "Almost Native Graphics Layer Engine (OpenGL ES implementation for macOS)"
  homepage "https://chromium.googlesource.com/angle/angle"

  bottle do
    root_url "https://github.com/startergo/homebrew-angle/releases/download/v1.0.15"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "2b41a696f450a941016adf8b157e754c3223b6032ac9b9f0aac4216e899074c7"
  end
  depends_on "startergo/gn/gn" => :build
  depends_on "ninja" => :build
  depends_on "llvm" => :build
  version "1.0.15"
  url "https://github.com/startergo/homebrew-angle/archive/refs/tags/v1.0.15.tar.gz"
  sha256 "3065be5afcf0eca4b1b2406321308fb11f755767134a3b45899058292678ed1b"
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

  def post_install
    # Restore @rpath install_names that Homebrew may have changed
    # Homebrew changes @rpath/libX.dylib to /opt/homebrew/opt/angle/lib/libX.dylib
    # We need to restore them for proper dylib loading
    Dir[lib/"*.dylib"].each do |dylib|
      current_name = Utils.popen_read("otool", "-D", dylib).strip.split("\n").last
      if current_name.include?("/opt/homebrew/opt/angle/lib/")
        basename_name = File.basename(dylib)
        system "install_name_tool", "-id", "@rpath/#{basename_name}", dylib
      end
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
