# zfracture
A 3D Game engine in Zig for learning and also for making my own game.

<img src="https://github.com/aditya-rajagopal/zfracture/blob/master/fracture_logo/fracture_logo_small.png" alt="Fracture Engine" width="256" height="256"/>

Currently only supports windows as a platform. More to be added in the future.

This language is built in [zig](https://ziglang.org/download) and it needs to be downloaded to compile the project.

```
make debug
```

You can then use wasd to move around in the world and view the texture from different angles.

<img src="https://github.com/aditya-rajagopal/zfracture/blob/master/fracture_logo/screenshot.png" alt="Fracture Engine" width="480" height="270"/>

## Architecture

The game is built as a dll and the engine is the actual runtime. The game is loaded dynamically at runtime allowing the game
to be modified and recompiled wile running. The engine will watch the game dll and reload it. All memory is owned by the engine and all game state is owned by the engine allowing reloading to be quick. The game must be stateless.

Making using of zig comptime allows many features to be implemented in interesting ways:
- Scoped logging that allows creating of arbitrary loggers that will write to both files and the terminal using 1 backend.
- In debug builds all allocations are scoped and tracked by type of allocation but this is stripped in release builds.
- Allows static dispatch of math functions based on types rather than dynamic dispatches that woudl be common in a class based language
- A renderer that could be swapped at runtime. Currenlty only vulkan is implemented but OpenGL and DirectX will in the future.

## Interesting things

- Implemented a really fast png parser: [png.zig](https://github.com/aditya-rajagopal/zfracture/blob/master/src/core/image/png.zig)
- Fracture Sturcture Definition: A custom definition language that the engine will read during runtime in debug mode and allows changing parameters fo some variables while the program is running. In Relase builds it will load binary versions for speed and strip functinality to modify.
- SIMD math library
- Event system to signal and register callbacks.
- Vulkan renderer abstracted into a renderer agnostic API.

The following is the list of features that the engine has and is planned. More will be added as time goes on.

## Features TODO:
- [ ] Fracture Structure Definiton
    - [x] Basic parser
    - [ ] Optimize parser
        - [ ] Add support for structures
        - [ ] Add support of enum literals
- [ ] Create a looped reload system. That will make replay easy. 
    - [ ] Save inputs
    - [ ] Save delta times
    - [ ] Save resource states
        - [ ] Create the ability to seralise and deserialise structs. Try and disallow nested pointers
- [x] Test if the game can be loaded as a DLL in debug and statically linked in release
    - [x] Game builds as a DLL in debug builds and is loaded dynamically
    - [x] Everything is statically linked in release builds
- [ ] logging
    - [x] Create basic logging functionality
    - [x] Make logs coloured based on log level
    - [x] Move logging to the core library 
    - [x] Can we have 1 logger that just has different scopes so they share the buffered writer. Rather than having
          multiple buffered writers. This way we can also have more scopes than the two.
    - [ ] Fix all the missing debug asserts removed when log was moved to core
    - [ ] Change the log function to also optionally write to a log file in addition to console
    - [ ] Seperate log thread? job?
        - [ ] Could this be done by having a logger that has a memory arena and adds data to a buffer and every second dumps the data into the log and reset the arena. After max logs are written there is no allocations.
- [ ] Memory System
    - [x] Create a tracking allocator that resolves to a normal allocator in release
    - [x] Add allocators to the context passed to the game. One GPA and one FrameArena
    - [x] Move memory into core
    - [x] Remove merge enums from memory and let the game handle it's own memory
    - [ ] Should the FrameArena be replaced by a FixedBufferAllocator (i.e a bump allocator) - YES
        - [ ] A linear allocator
    - [ ] Create a custom allocator for Fracture that allows larger virtual space allocations for expanding allocations
- [ ] windows platform layer
    - [x] Create a window
    - [x] Handles events and dispatch to the event system
    - [ ] Support multiple windows
    - [ ] Support controllers
- [ ] Event system
    - [x] Basic event handling and types
    - [x] Move event system into core as type
    - [x] Move event state into Engine
    - [x] We need additional context for the listener and sender since most game functions are stateless
    - [ ] Maybe the game can have it's own event handler and can be called by the event system instead of having to connect directly
    - [ ] Check if we need SoA or AoS for the event data.
    - [ ] Make sure that when the DLL is reloaded the event listerers are still valid
    - [ ] Do we need the static versions of some of the functions
    - [ ] Create multiple lists for handling frame future events and timed events
        - [ ] Create an EventData pool for the deffered events storage
    - [ ] Does the event system need the idea of layers so that certain handlers get first shot at handling events
    - [ ] Do permanent events need a seperate structure?
    - [ ] Priority queue for deferred events?
- [ ] Input system
    - [x] Initial input system implementation
    - [x] API for platform layer to dispatch input events 
    - [ ] Support controllers
    - [ ] Should I save the number of transitions that happen within a frame
    - [ ] Remove reference to event system here. The platform/application should handle firing events. Or pass the engine.
    - [ ] Think of using a bit set for the keys instead of an array
    - [ ] Are the comptime versions of the functions necessary
    - [ ] Should there be the rest of the messages be parsed for key and mouse events whne firing events
- [ ] Signal System
    - [ ] Decide if there is a need for signal plug and socket system.
- [ ] SIMD Math Library
    - [x] Basic vec
    - [x] Basic matrix
    - [x] Basic Affine
    - [x] Basic Quaternions
    - [ ] Docstrings
    - [ ] Benchmarks
    - [ ] Tests
    - [ ] Shapes
        - [x] Rectangle
        - [ ] Circle
        - [ ] Triangle
        - [ ] Point
        - [ ] Line
- [ ] Containers
    - [ ] StaticArrayList: Partially implemented
    - [ ] Array backed linked list?
    - [ ] Array backed memory pool?
    - [ ] Create a static multiarrayList
- [ ] Instrumentation
- [ ] Renderer
    - [ ] Unify all errors into a small set that are allowed to crash the program. Everything else needs to be handled
    - [ ] Create renderer settings on the engine/app side rather than hard coded settings
    - [ ] Create image pools and modify image.zig to use offsets
    - [ ] Deal with possibility of more than 1 queues for graphics
        - [ ] Should the graphics queue have more than 1 queue
    - [ ] Should 0,0 be top left or bottom left. It is bottom left in OpenGL
    - [ ] Change command buffers to be array list rather than allocated every time teh swapchain is recreated
    - [ ] implement custom allocator for deubg builds
    - [ ] Allow choosing different graphics Backends.
    - [ ] geometry generation (2d and 3d, e.g. cube, cylinder, etc.)
    - [ ] advanced Materials
    - [ ] PBR Lighting model
    - [ ] batch rendering (2d and 3d)
    - [ ] instanced rendering
    - [ ] Per-scene vertex/index buffers
    - [ ] Queue-up of data uploads during scene load:
      - Notes/ steps involved: 
        - Setup a queue in the scene to hold pending mesh data.
        - For each mesh:
          - Make sure mesh is invalidated so it doesn't attempt to render. 
          - Assign a unique id for it and add it to the queue
          - Load it from disk (multithreaded, currently done but needs some changes). Save off id, size, data, offsets, etc.
          - Reserve space in buffer freelist but _don't_ upload to GPU. Save the offset in the queue as well.
          - NOTE: that this could be used to figure out how large the buffer needs to be.
        - Repeat this for all meshes.
        - In one swoop, upload all vertex and index data to GPU at once, perhaps on a separate (transfer) queue to avoid frame drops.
          - Probably the easiest way is a single vkCmdCopyBuffer call with multiple regions (1 per object), to a STAGING buffer.
          - Once this completes, perform a copy from staging to the appropriate vertex/index buffer at the beginning of the next available frame.
        - After the above completes (may need to setup a fence), validate meshes all at once, enabling rendering.
    - [ ] shadow maps
      - [ ] PCF
      - [ ] cascading shadow maps
      - [ ] Adjustable Directional Light properties
        - [ ] max shadow distance/fade (200/25)
        - [ ] cascade split multiplier (0.91)
        - [ ] shadow mode (soft/hard shadows/none)
      - [ ] Percentage Closer Soft Shadows (PCSS)
      - [ ] Point light shadows
    - [ ] texture mipmapping
    - [ ] Specular maps (NOTE: removed in favour of PBR)
    - [ ] Normal maps 
    - [ ] Phong Lighting model (NOTE: removed in favour of PBR)
    - [ ] Multiple/configurable renderpass support.
    - [ ] Rendergraph
      - [ ] Linear processing
      - [ ] Rendergraph Pass Dependencies/auto-resolution
      - [ ] Multithreading/waiting/signaling
      - [ ] Forward rendering specialized rendergraph
      - [ ] Deferred rendering specialized rendergraph
      - [ ] Forward+ rendering specialized rendergraph
    - [ ] Forward rendering 
    - [ ] Deferred rendering 
    - [ ] Forward+ rendering
    - [ ] Compute Shader support (frontend)
- [ ] Jobs System
- [x] Move types into core
- [x] Application and platform should be part of entry point
- [ ] Does the data in the engine structure need to be pointers or is it okay to have them flat in the structure.
- [ ] Audio System (front-end)
- [ ] Physics System (front-end)
- [ ] networking
- [ ] profiling
- [ ] timeline system
- [ ] skeletal animation system
- [ ] skybox
- [ ] skysphere (i.e dynamic day/night cycles)
- [ ] water plane
- [ ] Raycasting
- [ ] Object picking 
  - [ ] Pixel-perfect picking 
  - [ ] Raycast picking
- [ ] Gizmo (in-world object manipulation)
- [ ] Viewports
- [ ] terrain
  - [ ] binary format
  - [ ] heightmap-based
  - [ ] pixel picking
  - [ ] raycast picking 
  - [ ] chunking/culling
  - [ ] LOD
    - [ ] Blending between LOD levels (geometry skirts vs gap-filling, etc.)
  - [ ] tessellation
  - [ ] holes
  - [ ] collision
- [ ] volumes 
  - [ ] visibility/occlusion
  - [ ] triggers 
  - [ ] physics volumes 
  - [ ] weather
- [ ] Multi-window applications

## Standardized UI:
- [ ] Standard UI system
- [ ] Layering
- [ ] UI file format
- [ ] Load/Save UIs
- [ ] UI Editor (as a plugin to the editor)
- [ ] control focus (tab order?)
- [ ] docking
- [ ] drag and drop support
- [ ] UI Controls (one of the few engine-level areas that uses OOP):
  * [ ] Base control - all controls come from this
  * [ ] panel
  * [ ] image box
  * [ ] viewport control (world/scenes will be switched to use these as render targets)
  * [ ] rich text control (system text w/ multicolour, bold/italic, etc. and bitmap text with multicolour only)
  * [ ] button
  * [ ] checkbox
  * [ ] radio buttons
  * [ ] tabs
  * [ ] windows/modals (complete with resize, min/max/restore, open/close, etc.)
  * [ ] resizable multi-panels
  * [ ] scrollbar
  * [ ] scroll container
  * [ ] textbox/textarea
  * [ ] In-game debug console

## Editor: mosaic
- [ ] Editor application and 'runtime' executable
  - [ ] World editor
  - [ ] UI editor
  - [ ] editor logic library (dll/.so) hot reload
- [ ] Move .obj, .mtl import logic to editor (output to binary format).
- [ ] Move texture import logic to editor (output to binary format).
- [ ] DDS/KTX texture format imports
- [ ] FBX model imports 

## Level Generator: tessel
- [ ] Level Generation tool made using Fracture to generate proc generated levels
  - [ ] It can be a module that is loaded into the editor
  - [ ] Takes in 3D/2D tiles and allows rules to generate levels
  - [ ] Produces a binary format file that can be loaded up with the game engine to populate scenes.

## Other items:
- [ ] Auto-Generated API documentation
- [ ] Documentation
- [ ] Continuous Integration

