#ifndef TYPES
#define TYPES

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

struct Triangle {
  Vertex verts[3];
};

#endif
