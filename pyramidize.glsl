#[vertex]
#version 460

#include "types.glsl"

layout(set = 0, binding = 0, std430) readonly buffer DataIn {
  Vertex verts[];
} DATA_IN;
// layout(set = 0, binding = 1, std430) restrict buffer Misc {
//   mat4x4 projection;
// } MISC;

layout(location = 0) out vec2 uv_vary;

void main() {
  Vertex vert = DATA_IN.verts[gl_VertexIndex];
  
  gl_Position = vec4(vert.position.xyz, 1.0);
  uv_vary = vert.uv;
}

// ===== //

#[fragment]
#version 460

#include "types.glsl"

layout(location = 0) in vec2 uv_vary;

layout(location = 0) out vec3 frag_color;

void main() {
  frag_color = vec3(uv_vary.x, uv_vary.y, 0.0);
}
