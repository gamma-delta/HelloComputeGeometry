shader_type spatial;

uniform sampler2D data_in : source_color;

void fragment() {
  ALBEDO = texture(data_in, UV).xyz;
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
