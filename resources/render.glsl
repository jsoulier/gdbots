#[vertex]
#version 450

// Cone geometry — bound as vertex buffer
layout(location = 0) in vec3 vertex_position;

// Boid instances — SSBO
layout(set = 0, binding = 0, std430) readonly buffer BoidBuffer {
	float boids[]; // 22 floats per boid
};

layout(push_constant, std430) uniform Params {
	mat4  view_proj;
	float cone_vertex_count;
	float boid_count;
} params;

layout(location = 0) out vec3 frag_normal;
layout(location = 1) out vec3 frag_color;

mat3 basis_from_forward(vec3 fwd) {
	fwd = normalize(fwd);
	vec3 up    = abs(fwd.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 right = normalize(cross(up, fwd));
	up         = cross(fwd, right);
	return mat3(right, fwd, up);
}

void main() {
	int b         = gl_InstanceIndex * 22;
	vec3 position = vec3(boids[b + 0], boids[b + 1], boids[b + 2]);
	vec3 forward  = vec3(boids[b + 3], boids[b + 4], boids[b + 5]);

	mat3 rot      = basis_from_forward(forward);
	vec3 world    = position + rot * vertex_position;

	gl_Position = params.view_proj * vec4(world, 1.0);
	frag_normal = normalize(rot * vec3(vertex_position.x, 0.0, vertex_position.z));
	frag_color  = vec3(fract(float(gl_InstanceIndex) * 0.618),
					   fract(float(gl_InstanceIndex) * 0.382),
					   0.8);
}

#[fragment]
#version 450

layout(location = 0) in vec3 frag_normal;
layout(location = 1) in vec3 frag_color;
layout(location = 0) out vec4 out_color;

void main() {
	vec3  light = normalize(vec3(0.5, 1.0, 0.3));
	float diff  = max(dot(normalize(frag_normal), light), 0.0);
	out_color   = vec4(frag_color * (0.2 + 0.8 * diff), 1.0);
}
