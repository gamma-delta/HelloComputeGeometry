#[compute]
#version 460

#include "types.glsl"

// https://ktstephano.github.io/rendering/opengl/ssbos
// https://stackoverflow.com/questions/69497498/updating-vertices-from-compute-shader
// https://github.com/erickweil/GodotTests/blob/main/ProceduralGeometry/procedural_geometry.glsl

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) readonly restrict buffer DataIn {
  Triangle tris[];
} DATA_IN;
layout(set = 0, binding = 1, rgba32f) uniform restrict writeonly image2D IMAGE_OUT;

layout(push_constant, std430) uniform Params {
  uint out_tex_width;
  uint out_tex_height;
  float time;
  float _scratch;
} PARAMS;

#define WRITE_VEC4(IDX, V) { \
    imageStore(IMAGE_OUT, ivec2(IDX % PARAMS.out_tex_width, IDX / PARAMS.out_tex_width), V); \
    IDX += 4;}
#define WRITE_VERTEX(IDX, VERT) { \
    WRITE_VEC4(IDX, VERT.position); \
    WRITE_VEC4(IDX, VERT.normal); \
    WRITE_VEC4(IDX, vec4(VERT.uv, VERT._scratch)); }

void writeTriangle(uint index, Triangle tri) {
  uint floatIdx = SIZEOF_TRIANGLE * index;

  WRITE_VERTEX(floatIdx, tri.verts[0]);
  WRITE_VERTEX(floatIdx, tri.verts[1]);
  WRITE_VERTEX(floatIdx, tri.verts[2]);
}

vec3 getNormalFromTriangle(vec3 a, vec3 b, vec3 c) {
    return normalize(cross(b - a, c - a));
}

void main() {
  if (gl_GlobalInvocationID.x >= gl_WorkGroupSize.x * gl_NumWorkGroups.x) return;

  Triangle tri = DATA_IN.tris[gl_GlobalInvocationID.x];
  for (int i = 0; i < 3; i++) {
    tri.verts[i].position += vec4(0.0, 1.0, 0.0, 0.0) * cos(PARAMS.time);
    tri.verts[i].normal = cos(PARAMS.time) > 0.0 ? vec4(1.0, 0.0, 0.0, 1.0) : vec4(0.0, 1.0, 1.0, 1.0);
  }
  writeTriangle(gl_GlobalInvocationID.x, tri);

  /*
  for (uint i = 0; i < 9; i++) {
    uint idx = i + 9 * gl_GlobalInvocationID.x;
    vec4 col = vec4(1.0, cos(PARAMS.time) * 0.5 + 0.5, 0.0, 1.0);
    WRITE_VEC4(idx, col);
  }
  */
}

#undef WRITE_VEC4

/*
  TODO:
  Spatial shaders have a VERTEX_ID uniform.
  Manually invoke the render system to draw vertices from the buffer that ALREADY EXISTS
  on the GPU.
  Possibly pass an empty list of vertices
*/
