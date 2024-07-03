#[vertex]
#version 460

#include "types.glsl"

layout(binding = 0, std430) in vec4 position;

// layout(set = 0, binding = 1, std430) restrict buffer Misc {
//   mat4x4 projection;
// } MISC;

// layout(location = 0) out vec2 uv_vary;

void main() {
  gl_Position = vec4(position.xyz, 1.0);
}

// ===== //

#[fragment]
#version 460

#include "types.glsl"

layout(location = 0) out vec3 frag_color;

void main() {
  frag_color = vec3(1.0, 1.0, 0.0);
}
