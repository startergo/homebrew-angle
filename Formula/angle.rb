class Angle < Formula
  desc "Almost Native Graphics Layer Engine (OpenGL ES implementation for macOS)"
  homepage "https://chromium.googlesource.com/angle/angle"

  bottle do
    root_url "https://github.com/startergo/homebrew-angle/releases/download/v1.0.2"
    sha256 cellar: :any, arm64_sequoia: "a871f8c9450c00d8b9eaa7827db8f750ebbf62835fa9b16fa21e74b8c9f30ccd"
  end
  depends_on "startergo/gn/gn" => :build
  depends_on "ninja" => :build
  depends_on "llvm" => :build
  version "1.0.2"
  url "https://github.com/startergo/homebrew-angle/archive/refs/tags/v1.0.2.tar.gz"
  sha256 "5d1b4411f6b9fdff216dec85853972dafe52929fd04e0db682d5a31e7f8df9f4"
  license "BSD-2-Clause"

  head "https://chromium.googlesource.com/angle/angle",
       using: :git

  def install
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    angle_dir = "angle-#{arch}"

    # Inject @rpath install_name config for bottle compatibility
    # Using @rpath avoids headerpad overflow and improves portability
    angle_build_config = <<~EOS
      config("homebrew_bottle_config_libEGL") {
        if (is_mac && !is_component_build) {
          ldflags = [ "-Wl,-install_name,@rpath/libEGL.dylib" ]
        }
      }
      config("homebrew_bottle_config_libGLESv2") {
        if (is_mac && !is_component_build) {
          ldflags = [ "-Wl,-install_name,@rpath/libGLESv2.dylib" ]
        }
      }
      config("homebrew_bottle_config_libGLESv1_CM") {
        if (is_mac && !is_component_build) {
          ldflags = [ "-Wl,-install_name,@rpath/libGLESv1_CM.dylib" ]
        }
      }
    EOS

    ENV["ANGLE_BUILD_CONFIG"] = angle_build_config
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
