#[compute]
#version 460

// https://ktstephano.github.io/rendering/opengl/ssbos
// https://stackoverflow.com/questions/69497498/updating-vertices-from-compute-shader
// https://github.com/erickweil/GodotTests/blob/main/ProceduralGeometry/procedural_geometry.glsl

struct Vertex {
  // https://stackoverflow.com/questions/38172696/should-i-ever-use-a-vec3-inside-of-a-uniform-buffer-or-shader-storage-buffer-o/38172697#38172697
  // https://ktstephano.github.io/rendering/opengl/prog_vtx_pulling
  vec4 position;
  vec4 normal;
  vec2 uv;
  // SUPER IMPORTANT: YOU NEED THIS.
  // I am wasting a little bit of space like this, but w/e
  vec2 _scratch;
};

// IN FLOATS
#define SIZEOF_VERTEX ((4 + 4 + 2 + 2))

struct Triangle {
  Vertex verts[3];
};

#define SIZEOF_TRIANGLE ((3 * SIZEOF_VERTEX))

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

// yes, the readonly goes before restrict here, but writeonly goes AFTER restrict later
// beats me
layout(std430, set = 0, binding = 0) readonly restrict buffer DataIn {
  Triangle tris[];
} DATA_IN;
layout(rgba32f, set = 0, binding = 1) uniform restrict writeonly image2D IMAGE_OUT;

// it turns out, this increases over EVERY work group at once.
// not just one per workgroup
layout(std430, set = 0, binding = 2) restrict buffer CounterBuffer {
    uint COUNTER;
};

layout(push_constant, std430) uniform Params {
  uint out_tex_width;
  uint out_tex_height;
  uint max_tris_per_tri;
  
  float time;
} PARAMS;

void writeVec4(uint index, vec4 v) {
  // pixel index equals the index, handy!
  imageStore(IMAGE_OUT, 
    ivec2(index % PARAMS.out_tex_width, index / PARAMS.out_tex_width),
    v);
}
  
void writeVertex(uint index, Vertex vert) {
  writeVec4(index * 3 + 0, vert.position);
  writeVec4(index * 3 + 1, vert.normal);
  writeVec4(index * 3 + 2, vec4(vert.uv, vert._scratch));
}

void writeTriangle(Triangle tri) {
  uint wgIdx = atomicAdd(COUNTER, 1);
  // if (wgIdx > PARAMS.max_tris_per_tri) return;
  uint triIdx = wgIdx;

  writeVertex(triIdx * 3 + 0, tri.verts[0]);
  writeVertex(triIdx * 3 + 1, tri.verts[1]);
  writeVertex(triIdx * 3 + 2, tri.verts[2]);
}

// @@USER_CODE@@

void main() {
  if (gl_GlobalInvocationID.x >= gl_WorkGroupSize.x * gl_NumWorkGroups.x) return;

  Triangle tri = DATA_IN.tris[gl_GlobalInvocationID.x];

  writeTriangle(tri);
}
