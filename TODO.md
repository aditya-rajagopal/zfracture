# Things needed in the Fracture Engine

## Engine general:
- [ ] logging
    - [x] Create basic logging functionality
    - [x] Make logs coloured based on log level
    - [ ] Change the log function to also optionally write to a log file in addition to console
    - [ ] Seperate log thread? job?
        - [ ] Could this be done by having a logger that has a memory arena and adds data to a buffer and every second dumps the data into the log and reset the arena. After max logs are written there is no allocations.
- [ ] Memory System
    - [x] Create a tracking allocator that resolves to a normal allocator in release
    - [x] Add allocators to the context passed to the game. One GPA and one FrameArena
    - [ ] Create a custom allocator for Fracture that allows larger virtual space allocations for expanding allocations
- [ ] windows platform layer
    - [x] Create a window
    - [ ] Support multiple windows
    - [ ] Handles events and dispatch to the event system
- [ ] Event system
- [ ] Input system
- [ ] SIMD Math Library
- [ ] Containers
    - [ ] StaticArrayList
    - [ ] Array backed linked list?
    - [ ] Array backed memory pool?
- [ ] Instrumentation
- [ ] Renderer
- [ ] Jobs System
