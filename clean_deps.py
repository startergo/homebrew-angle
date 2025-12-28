#!/usr/bin/env python3
"""Remove unnecessary dependencies from ANGLE DEPS file."""
import sys
import re

# Dependencies to remove - keys to delete from the deps dict
DEPS_TO_REMOVE = [
    # Already excluded in previous version
    'third_party/catapult',
    'third_party/dawn',
    'third_party/llvm/src',
    # Note: Keep SwiftShader - needed by Vulkan backend for vulkan.gni
    # 'third_party/SwiftShader',
    'third_party/VK-GL-CTS/src',
    # android_* (wildcard - handled specially)
    'third_party/OpenCL-cts',
    'third_party/OpenCL-libs',
    'third_party/fuchsia-sdk',
    'third_party/libdrm',
    'third_party/wayland',
    'third_party/meson',
    'third_party/bazel',
    'third_party/siso',
    'third_party/gles1_conform',
    'third_party/glmark2',
    'third_party/perfetto',
    'third_party/ijar',
    # Note: Keep vulkan-deps, glslang, vulkan-loader for Vulkan backend
    # 'third_party/vulkan-deps',
    # 'third_party/glslang',
    # 'third_party/lunarg-vulkantools',
    'third_party/spirv-cross',
    # 'third_party/vulkan-loader',
    # 'third_party/vulkan-tools',
    # 'third_party/vulkan-utility-libraries',
    'third_party/cherry',
    'third_party/proguard',
    'third_party/jdk',
    'third_party/kotlin',
    'third_party/r8',
    'third_party/turbine',
    # Additional exclusions for Metal-only macOS build
    # Large unnecessary directories (>25M each)
    'third_party/rust-toolchain',
    'third_party/rust',
    # Note: Keep vulkan-headers, spirv-headers, OpenGL-Registry for SDK users
    'third_party/vulkan-validation-layers/src',
    'third_party/llvm-build',
    # Note: Keep libc++ - needed by build tools
    # 'third_party/libc++/src',
    # Note: Keep depot_tools - needed for gclient hooks
    # 'third_party/depot_tools',
    'third_party/abseil-cpp',
    'third_party/OpenCL-CTS/src',
    'third_party/OpenCL-Docs/src',
    'third_party/OpenCL-ICD-Loader/src',
    'third_party/clspv/src',
    'third_party/mesa/src',
    # Note: Keep EGL-Registry for SDK users
    # Note: For Vulkan backend support, keep vulkan-loader and related deps
    # Note: Keep spirv-tools/src for headers (needed by GN to parse BUILD.gn)
    # 'third_party/spirv-tools/src',
    # Note: Keep vulkan-tools/src - needed by Vulkan backend for VkICD_mock_icd
    # 'third_party/vulkan-tools/src',
    # 'third_party/vulkan_memory_allocator',
    # Python test/benchmark infrastructure
    'third_party/colorama/src',
    'third_party/jinja2',
    'third_party/markupsafe',
    'third_party/Python-Markdown',
    'third_party/six',
    'third_party/requests/src',
    # C++ runtime (using system)
    # Note: Keep libc++abi - needed by build tools
    # 'third_party/libc++abi/src',
    'third_party/libunwind/src',
    # Note: Keep llvm-libc - needed by libc++ build
    # 'third_party/llvm-libc/src',
    # Serialization/tracing (disabled with angle_has_frame_capture=false)
    'third_party/flatbuffers/src',
    'third_party/protobuf',
    # x86 assembly only
    'third_party/nasm',
    # Image libraries (not needed for Metal)
    'third_party/libpng/src',
    'third_party/libjpeg_turbo',
    # Regex library (only used by abseil/googletest)
    'third_party/re2/src',
]

def remove_deps_from_file(content):
    """Remove dependencies from DEPS file content while preserving format."""
    lines = content.split('\n')

    # Find deps = { line
    deps_start = None
    for i, line in enumerate(lines):
        if re.match(r'deps\s*=\s*{', line):
            deps_start = i
            break

    if deps_start is None:
        return None, "Error: Could not find 'deps = {' in DEPS file"

    # Track which entries to keep
    # We need to parse the deps dict structure to find top-level keys
    new_lines = []
    i = 0
    removed_count = 0
    android_removed = 0

    # Keep everything up to and including the deps = { line
    new_lines.extend(lines[:deps_start + 1])

    # Process the deps dict entries
    # Track global brace depth from the deps = { line
    # Calculate initial depth from the deps = { line
    initial_depth = lines[deps_start].count('{') - lines[deps_start].count('}')
    brace_depth = initial_depth

    i = deps_start + 1
    while i < len(lines):
        line = lines[i]

        # Update brace depth
        brace_depth += line.count('{') - line.count('}')

        # Check for hooks section
        if re.match(r'hooks\s*=\s*{', line):
            # Found hooks section, include it and everything after
            new_lines.extend(lines[i:])
            break

        # Check for closing brace of deps dict (brace depth back to initial depth)
        if brace_depth == initial_depth - 1:
            # Found the actual deps closing brace
            new_lines.append(line)
            i += 1
            # Add remaining lines (hooks, vars, etc.)
            if i < len(lines):
                new_lines.extend(lines[i:])
            break

        # Check if this is a new dependency entry (starts with a quote)
        match = re.match(r"^\s*'([^']+)':\s*(?:\{)?$", line)
        if match:
            key = match.group(1)
            # Check if we should remove this key
            should_remove = (
                key in DEPS_TO_REMOVE or
                'android_' in key or
                key.startswith('third_party/android')
            )

            if should_remove:
                removed_count += 1
                if 'android_' in key or key.startswith('third_party/android'):
                    android_removed += 1
                # Skip this entry and its value
                # Find the entry closing by looking for the comma at this brace depth
                entry_start_depth = brace_depth
                i += 1
                while i < len(lines):
                    line_brace_diff = lines[i].count('{') - lines[i].count('}')
                    brace_depth += line_brace_diff
                    # Look for }, or } at the entry's original depth (entry is closed)
                    if brace_depth == entry_start_depth - 1 and re.match(r"^\s*}(?:,\s*)?$", lines[i]):
                        i += 1  # Skip the closing line
                        break
                    i += 1
                continue

        # Keep this line
        new_lines.append(line)
        i += 1

    # Check for hooks section that might have been missed
    for j in range(i, min(i + 10, len(lines))):
        if 'hooks = {' in lines[j]:
            if lines[j - 1].strip() != '}':
                new_lines.append('\n')
            new_lines.extend(lines[j:])
            break

    return '\n'.join(new_lines), (removed_count, android_removed)

def main():
    deps_file = 'DEPS'
    import os
    if not os.path.exists(deps_file):
        print(f"Error: {deps_file} not found in current directory", file=sys.stderr)
        return 1

    with open(deps_file, 'r') as f:
        content = f.read()

    # Count original entries (keys may have { on same line)
    original_count = len(re.findall(r"^\s*'[^']+':\s*(?:\{)?$", content, re.MULTILINE))
    print(f"Original deps count: {original_count}")

    new_content, result = remove_deps_from_file(content)

    if isinstance(new_content, str):
        removed, android_removed = result
        print(f"Removed {removed} dependencies ({android_removed} android)")

        new_count = len(re.findall(r"^\s*'[^']+':\s*(?:\{)?$", new_content, re.MULTILINE))
        print(f"Remaining deps count: {new_count}")

        with open(deps_file, 'w') as f:
            f.write(new_content)

        print(f"Updated {deps_file}")
        return 0
    else:
        print(result, file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
