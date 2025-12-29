class Angle < Formula
  desc "Almost Native Graphics Layer Engine (OpenGL ES implementation for macOS)"
  homepage "https://chromium.googlesource.com/angle/angle"
  url "https://github.com/startergo/build-angle/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "9facfb7c61650dd4f534519b2f7fd09c98e6eaae4d5aae3ed74604c0aaa6733c"
  license "BSD-2-Clause"

  head "https://chromium.googlesource.com/angle/angle",
       using: :git

  bottle do
    root_url "https://github.com/startergo/homebrew-angle/releases/download/v1.0.0"
  end

  def install
    system "./build.sh", Hardware::CPU.arm? ? "arm64" : "x64"

    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    angle_dir = "angle-#{arch}"

    # Pre-expand dylib headers when building bottles
    # ANGLE builds with short install_name (@rpath/libX.dylib)
    # Homebrew bottle rewrites to @@HOMEBREW_PREFIX@@/opt/angle/lib/libX.dylib
    # This requires significant header space that must be pre-allocated
    if build.bottle?
      ohai "Pre-expanding dylib headers for bottle creation"

      long_id = "#{HOMEBREW_PREFIX}/Cellar/angle/999.999.999/lib/#{'X' * 50}.dylib"
      prefix = "#{HOMEBREW_PREFIX}/Cellar/angle/#{version}/lib"

      Dir["#{angle_dir}/lib/*.dylib"].each do |dylib|
        basename = File.basename(dylib)

        # First expand to max length to force header allocation
        system "install_name_tool", "-id", long_id, dylib
        # Then set to actual path
        system "install_name_tool", "-id", "#{prefix}/#{basename}", dylib

        # Expand inter-dylib dependencies
        Dir["#{angle_dir}/lib/*.dylib"].each do |other|
          other_basename = File.basename(other)
          system "install_name_tool", "-change",
                 "@rpath/#{other_basename}",
                 "#{prefix}/#{other_basename}",
                 dylib
          system "install_name_tool", "-change",
                 "./#{other_basename}",
                 "#{prefix}/#{other_basename}",
                 dylib
        end
      end
    end

    lib.install Dir["#{angle_dir}/lib/*.dylib"]
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
