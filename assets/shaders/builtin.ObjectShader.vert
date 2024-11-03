#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(location = 0) in vec3 in_position;

layout(set = 0, binding = 0) uniform global_uniform_buffer_object {
    mat4 view_projection;
} global_ubo;

layout(push_constant) uniform push_constant{
    // Only guaranteed to have 128 bytes
    mat4 model; // 64 bytes
} u_push_constant;

layout(location = 0) out vec3 out_position;

void main() {
    vec4 pos = global_ubo.view_projection * u_push_constant.model * vec4(in_position, 1.0);
    gl_Position = pos;
    out_position = in_position;
}
