shader_type spatial;
render_mode unshaded, cull_front;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	ALBEDO = vec3(clamp(NORMAL, 0.0, 1.0));
	ALPHA = .3;
	// Called for every pixel the material is visible on.
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
