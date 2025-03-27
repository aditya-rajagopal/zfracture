# Example 
```
@def material 0:0:1
@name: [16]u8 = "test_material"
@diffuse_colour: vec4s = [ 1.0, 1.0, 1.0, 1.0 ]
@diffuse_map: Texture = "cobblestone1"
```

# Specification
TODO: Add specification to be able to reference other files to load into structures

```
@def <definition_type> <major: u4>:<minor: u12>:<patch: u16>
@<field>: <type> = <data>
```
...

* @: The start of a line containing a definition must contain an @
* Every fsd file must start with a @def header declaration
* Every field must have a type assigned to it. There will be no implicit typing

## Header
Definition must be at the head of the file. And must contain all these

### def
The keyword that indicates that the rest of the line contains the defintion for this file

### <definition_type> 
This is the type of structure defined in the file
Options:
 * material

### <major: u4>:<minor: u12>:<patch: u16>
A period seperated version for the definition

## Fields

<field>: Can be any string. Should match an expected field from the <definition_type>

<type>: The type to interpret the data after the = symbol

<data>: Data to store in the field

## Types

#### Base types:
* u8, u16, u32, u64
* i8, i16, i32, i64,
* f32, f64
* bool
* vec2s, vec3s, vec4s

#### Array Types:
Array types must have a fixed shape in the destination struct. Dynamic allocation is not allowed. Set reasonable limits
for the types. This will minimize runtime allocations.

* []<base_type>: Array of base types. The size is inferred from the data and must be less than the expected type from 
the data.
* [N]<base_type>: Array of N elements of base_type. If the elements are less than N in the data then it will pad with default
values. N must be less than expected size in the definition_type.

#### Structure types:
You can have data be a structure. The type will be just called structure.
@data: Structure = .{...}

the value must start with a '.' followed by a { indicating the start of a structure. And then a new line.
Then starting from there each line is a new field in the structure until you reach a line which contains a '}'.

The structure itself is just a bunch of fsd statements in the form of 

```
@<field>: <type> = <data>
```

So a structure example will be like follows

```
@data: Structure = .{
    @nested_data: Structure = .{
        @field_1: u8 = 10
    }
}
```

#### Enum liternal

The type of Enum is used for fields that have some Enum type as the base. An enum literal is created . followed by an
identifier that starts with a alphabet. The names may not be a zig keyword.

```
@field: Enum = .some_enum_literal
```

Enums are stored as their integer counterparts when in binary.

#### Custom Types:
* Texture: <string path relative to base_asset_path>. It is just a typedef of []u8. Just better to read. Might have different
handling than strings

## Data

* Integers: 123151, -1123124123, 100_000.
* Floating: 1.11231245.
* arrays: []
* structs: {}
* enum literal: .<identifier>
