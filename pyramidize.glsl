#[compute]
#version 460

// https://ktstephano.github.io/rendering/opengl/ssbos

struct Vertex {
  // https://stackoverflow.com/questions/38172696/should-i-ever-use-a-vec3-inside-of-a-uniform-buffer-or-shader-storage-buffer-o/38172697#38172697
  // https://ktstephano.github.io/rendering/opengl/prog_vtx_pulling
  vec4 position;
  vec2 uv;
  // SUPER IMPORTANT: YOU NEED THIS.
  // I am wasting a little bit of space like this, but w/e
  vec2 _scratch;
};

struct Triangle {
  vec4 normal;
  Vertex verts[3];
};

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) readonly restrict buffer DataIn {
  Triangle tris[];
} DATA_IN;
layout(set = 0, binding = 1, std430) writeonly restrict buffer DataOut {
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
