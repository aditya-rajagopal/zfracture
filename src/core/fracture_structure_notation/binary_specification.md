# VERSION 0.1

## FSD Header:
Header size including the asset specific header

+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|                                                                       |                                   | 
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|                 TIME STAMP OF CREATION                                |   F    |   R    |   S    |   D    |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+

+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|                 |                            ASSET VERSION            |      SIZE       |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|               TYPE ID             |MJOR|  MINOR     |        PATCH    |                 |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+

- 8 bytes are the 64 bit timestamp at which the fsd file was created. This is used to check if this file needs to be regenerated
- 4 bytes are the magic that determines if the binary being read is FSD file.
- 4 byte type ID is a unique identifier that ensures we are reading the right format of data for the fsd being defined
- 4 bytes of version
- 2 byte size defining the number of bytes the rest of the structure contains.

NOTE: The timestamp will not be included in final packed data

```zig
const FSDHeader = align(1) struct {
    time_stamp: u64,
    magic: [4]u8,
    type: u32,
	version: packed struct(u32) {
        major: u4,
        minor: u12,
        patch: u16,
    },
    size: u16,
};
```
