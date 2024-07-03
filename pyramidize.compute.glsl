#[compute]
#version 460

#include "types.glsl"

// https://ktstephano.github.io/rendering/opengl/ssbos


layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) readonly restrict buffer DataIn {
  Triangle tris[];
} DATA_IN;
layout(set = 0, binding = 1, std430) writeonly buffer DataOut {
  Triangle tris[];
} DATA_OUT;
layout(set = 0, binding = 2, std430) restrict buffer Misc {
  float time;
} MISC;

vec3 getNormalFromTriangle(vec3 a, vec3 b, vec3 c) {
    return normalize(cross(b - a, c - a));
}

void main() {
  if (gl_GlobalInvocationID.x >= gl_WorkGroupSize.x * gl_NumWorkGroups.x) return;

  Triangle tri = DATA_IN.tris[gl_GlobalInvocationID.x];
  for (int i = 0; i < 3; i++)
    tri.verts[i].position += vec4(0.0, 1.0, 0.0, 0.0) * cos(MISC.time);
  DATA_OUT.tris[gl_GlobalInvocationID.x] = tri;
}

/*
  TODO:
  Spatial shaders have a VERTEX_ID uniform.
  Manually invoke the render system to draw vertices from the buffer that ALREADY EXISTS
  on the GPU.
  Possibly pass an empty list of vertices
*/
