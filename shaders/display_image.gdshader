shader_type spatial;

uniform sampler2D data_in : source_color;

vec4 read_vec4(inout int idx) {
  ivec2 sz = textureSize(data_in, 0);
  vec4 v = texelFetch(data_in, ivec2(idx % sz.x, idx / sz.x), 0);
  idx += 1;
  return v;
}

void vertex() {
  int cursor = VERTEX_ID * 3;
  VERTEX = read_vec4(cursor).xyz;
  NORMAL = read_vec4(cursor).xyz;
  vec4 uv_and_scratch = read_vec4(cursor);
  UV = uv_and_scratch.xy;
}

void fragment() {
  ALBEDO = vec3(0.0, 1.0, 0.0);
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
