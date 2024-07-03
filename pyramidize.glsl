#[vertex]
#version 460

#include "types.glsl"

layout(set = 0, binding = 0, std430) readonly buffer DataIn {
  // Vertex verts[];
  vec4 positions[];
} DATA_IN;
// layout(set = 0, binding = 1, std430) restrict buffer Misc {
//   mat4x4 projection;
// } MISC;

// layout(location = 0) out vec2 uv_vary;

void main() {
  gl_Position = vec4(DATA_IN.positions[gl_VertexIndex].xyz, 1.0);
}

// ===== //

#[fragment]
#version 460

#include "types.glsl"

layout(location = 0) out vec3 frag_color;

void main() {
  frag_color = vec3(1.0, 1.0, 0.0);
}
