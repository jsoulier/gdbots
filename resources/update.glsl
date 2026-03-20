#[compute]
#version 450

layout(local_size_x = 1024, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer BoidBuffer {
	// 22 floats per boid:
	// [0..2]   position
	// [3..5]   forward
	// [6..8]   velocity
	// [9..11]  acceleration
	// [12..14] avgFlockHeading
	// [15..17] avgAvoidanceHeading
	// [18..20] centreOfFlockmates
	// [21]     numPerceivedFlockmates (bit-cast int)
	float boids[];
};

layout(push_constant, std430) uniform Params {
    float num_boids;
    float view_radius;
    float avoid_radius;
    float min_speed;
    float max_speed;
    float align_weight;
    float cohesion_weight;
    float separate_weight;
    float delta_time;
    float _pad0;
    float _pad1;
    float _pad2;
} params;

const int STRIDE = 22;

vec3 boid_position(int i)  { return vec3(boids[i*STRIDE+0],  boids[i*STRIDE+1],  boids[i*STRIDE+2]);  }
vec3 boid_forward(int i)   { return vec3(boids[i*STRIDE+3],  boids[i*STRIDE+4],  boids[i*STRIDE+5]);  }
vec3 boid_velocity(int i)  { return vec3(boids[i*STRIDE+6],  boids[i*STRIDE+7],  boids[i*STRIDE+8]);  }

vec3 steer_towards(vec3 target_dir, vec3 velocity, float max_speed) {
	vec3 v = normalize(target_dir) * max_speed - velocity;
	float len = length(v);
	// clamp to max_speed as a simple force cap
	return len > max_speed ? v / len * max_speed : v;
}

void main() {
	int id = int(gl_GlobalInvocationID.x);
	if (id >= params.num_boids) return;

	vec3 pos = boid_position(id);
	vec3 fwd = boid_forward(id);
	vec3 vel = boid_velocity(id);

	// --- Perception pass ---
	vec3 flock_heading    = vec3(0.0);
	vec3 flock_centre     = vec3(0.0);
	vec3 avoidance        = vec3(0.0);
	int  num_flockmates   = 0;

	for (int b = 0; b < params.num_boids; b++) {
		if (b == id) continue;
		vec3  offset  = boid_position(b) - pos;
		float sqr_dst = dot(offset, offset);
		if (sqr_dst < params.view_radius * params.view_radius) {
			num_flockmates++;
			flock_heading += boid_forward(b);
			flock_centre  += boid_position(b);
			if (sqr_dst < params.avoid_radius * params.avoid_radius) {
				avoidance -= offset / sqr_dst;
			}
		}
	}

	// Write perception results back
	boids[id*STRIDE+12] = flock_heading.x;
	boids[id*STRIDE+13] = flock_heading.y;
	boids[id*STRIDE+14] = flock_heading.z;
	boids[id*STRIDE+15] = avoidance.x;
	boids[id*STRIDE+16] = avoidance.y;
	boids[id*STRIDE+17] = avoidance.z;
	boids[id*STRIDE+18] = flock_centre.x;
	boids[id*STRIDE+19] = flock_centre.y;
	boids[id*STRIDE+20] = flock_centre.z;
	boids[id*STRIDE+21] = intBitsToFloat(num_flockmates);

	// --- Steering ---
	vec3 acceleration = vec3(0.0);

	if (num_flockmates > 0) {
		flock_centre /= float(num_flockmates);
		vec3 offset_to_centre = flock_centre - pos;
		acceleration += steer_towards(flock_heading,    vel, params.max_speed) * params.align_weight;
		acceleration += steer_towards(offset_to_centre, vel, params.max_speed) * params.cohesion_weight;
		acceleration += steer_towards(avoidance,        vel, params.max_speed) * params.separate_weight;
	}

	// --- Integrate ---
	vel += acceleration * params.delta_time;
	float speed = length(vel);
	vec3  dir   = speed > 0.0001 ? vel / speed : fwd;
	speed       = clamp(speed, params.min_speed, params.max_speed);
	vel         = dir * speed;
	pos        += vel * params.delta_time;

	// Write back position, forward, velocity
	boids[id*STRIDE+0] = pos.x;
	boids[id*STRIDE+1] = pos.y;
	boids[id*STRIDE+2] = pos.z;
	boids[id*STRIDE+3] = dir.x;
	boids[id*STRIDE+4] = dir.y;
	boids[id*STRIDE+5] = dir.z;
	boids[id*STRIDE+6] = vel.x;
	boids[id*STRIDE+7] = vel.y;
	boids[id*STRIDE+8] = vel.z;
}

