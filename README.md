# Pong Game
This project is written in Zig 0.15.2 using Vulkan (1.0 feature set) as the graphics API and GLSL as the shader language.

## Notable Features
- Game modes:
  - Player vs. Player
  - Player vs. AI
  - AI vs. AI
- Physicalized particle system using compute shaders
- Dynamic sound effects based on ball velocity

## Controls
**Left player**
- W: move up
- S: move down
- A: toggle AI mode (OFF | INACCURATE | ACCURATE)

**Right player**
- ⬆: move up
- ⬇: move down
- ➡: toggle AI mode (OFF | INACCURATE | ACCURATE)

## Installation
This project uses static libraries whose used files are embedded within the project file structure.<br>
The only system-level dependency is the Vulkan driver.
The Vulkan SDK is required only when running the debug build (as it uses validation layers), or if you wish to compile the shaders via the project's build system.<br>
Only Linux and Windows platforms are supported, and only x86_64 architecture has been tested.<br>
Cross-compilation from Windows to Linux for the debug build is not supported by this project's build system.

Download or clone the project's source code and compile it using one of the following Zig 0.15.2 build options:
  ```
  // Compiled shaders (.spv) are included in "src/shaders" directory, so the Vulkan SDK is not required.
  //  Otherwise, you can use one of these commands to compile the shaders (example shown uses the debug build mode).
  zig build -Donly-shaders
  zig build -Dwith-shaders

  // Implicit current architecture
  zig build // Debug
  zig build --release=fast
  zig build --release=small
  zig build --release=safe

  // Explicit Windows x86_64 architecture
  zig build -Dtarget=x86_64-windows-gnu // Debug
  zig build -Dtarget=x86_64-windows-gnu --release=fast
  zig build -Dtarget=x86_64-windows-gnu --release=small
  zig build -Dtarget=x86_64-windows-gnu --release=safe

  // Explicit Linux x86_64 architecture
  zig build -Dtarget=x86_64-linux-gnu // Debug
  zig build -Dtarget=x86_64-linux-gnu --release=fast
  zig build -Dtarget=x86_64-linux-gnu --release=small
  zig build -Dtarget=x86_64-linux-gnu --release=safe
  ```

After the compilation, run the binary for your platform:
- **Linux:** `zig-out/bin/vulkan-pong`
- **Windows:** `zig-out/bin/vulkan-pong.exe`
