# Example 
```
@def material 0.0.1
@name: [16]u8 = "test_material"
@diffuse_colour: vec4s = [ 1.0, 1.0, 1.0, 1.0 ]
@diffuse_map: Texture = "cobblestone1"
```

# Specification
@def <definition_type> <major: u4>.<minor: u12>.<patch: u16>
@<field>: <type> = <data>
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

### <major: u4>.<minor: u12>.<patch: u16>
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
* []<base_type>: Array of base types. The size is inferred from the data and must be less than the expected type from 
the data. If the expected type from the defitition_type is itself a slice this data will be allocated with the allocator.
* [N]<base_type>: Array of N elements of base_type. If the elements are less than N in the data then it will pad with default
values. N must be less than expected size in the definition_type. It will be allocated if destination field is a slice.

#### Custom Types:
* Texture: <string path relative to base_asset_path>. It is just a typedef of []u8. Just better to read. Might have different
handling than strings

## Data

* Integers: 123151, -1123124123, 100_000.
* Floating: 1.11231245.
* arrays: {}
* structs: .{}
* enum literal: .<identifier>
