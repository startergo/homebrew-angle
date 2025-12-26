# homebrew-angle

Homebrew tap for [ANGLE](https://chromium.googlesource.com/angle/angle) - Almost Native Graphics Layer Engine.

## What is ANGLE?

ANGLE translates OpenGL ES API calls to native GPU APIs on Windows, macOS, and Linux. On macOS, it translates to Metal, providing a performant OpenGL ES implementation.

## Installation

```bash
# Tap the repository
brew tap startergo/angle

# Install ANGLE
brew install startergo/angle/angle
```

## Usage

### Compile and link with pkg-config

```bash
# Compile
gcc -o myapp myapp.c $(pkg-config --cflags --libs egl glesv2)

# Or for CMake
find_package(PkgConfig REQUIRED)
pkg_check_modules(ANGLE REQUIRED egl glesv2)
include_directories(${ANGLE_INCLUDE_DIRS})
target_link_libraries(myapp ${ANGLE_LIBRARIES})
```

### Manual compile flags

```bash
# Include paths
-I$(brew --prefix angle)/include/EGL
-I$(brew --prefix angle)/include/GLES2
-I$(brew --prefix angle)/include/GLES3
-I$(brew --prefix angle)/include/KHR

# Library paths
-L$(brew --prefix angle)/lib

# Libraries
-lEGL -lGLESv2 -lGLESv1_CM
```

## What's Included

- **Shared libraries**: `libEGL.dylib`, `libGLESv2.dylib`, `libGLESv1_CM.dylib`
- **Headers**: EGL, GLES2, GLES3, GLES3, KHR, platform-specific headers
- **Vulkan headers**: For compatibility with applications that reference them
- **SPIRV headers**: For shader compatibility
- **pkg-config files**: `egl.pc`, `glesv2.pc`, `glesv1_cm.pc`

## Build Configuration

This build is configured for **Metal-only** on macOS with these optimizations:
- Vulkan backend disabled
- OpenGL backend disabled
- WebGL/GPU backends disabled
- Minimal dependencies (73+ dependencies removed)
- Metal renderer enabled

## License

BSD-2-Clause

## Upstream

- [ANGLE Project](https://chromium.googlesource.com/angle/angle)
- [Build scripts](https://github.com/startergo/build-angle)
