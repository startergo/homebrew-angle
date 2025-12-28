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
