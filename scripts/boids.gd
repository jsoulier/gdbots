extends Node3D

static var UPDATE_SHADER: RDShaderFile = preload("res://resources/update.glsl")

@export var boid_count:      int   = 100
@export var view_radius:     float = 5.0
@export var avoid_radius:    float = 2.0
@export var min_speed:       float = 1.0
@export var max_speed:       float = 5.0
@export var align_weight:    float = 1.0
@export var cohesion_weight: float = 1.0
@export var separate_weight: float = 1.5

var _rd: RenderingDevice

var _boid_buffer: RID
var _cone_buffer: RID

var _update_shader:      RID
var _update_pipeline:    RID
var _update_uniform_set: RID


func _ready() -> void:
	_rd = RenderingServer.get_rendering_device()
	_init_boid_buffer()
	_init_cone_buffer()
	_create_update_pipeline()
	_create_update_uniform_set()

	var effect := BoidsEffect.new()
	effect.setup(self)

	var compositor := Compositor.new()
	compositor.compositor_effects = [effect]

	var camera := get_viewport().get_camera_3d()
	camera.compositor = compositor


func _process(delta: float) -> void:
	_dispatch_update(delta)


# ---------------------------------------------------------------------------
# Buffers
# ---------------------------------------------------------------------------
func _init_boid_buffer() -> void:
	var data := PackedFloat32Array()
	data.resize(boid_count * 22)
	data.fill(0.0)
	for i in range(boid_count):
		var base := i * 22
		data[base + 0] = global_position.x
		data[base + 1] = global_position.y
		data[base + 2] = global_position.z
		data[base + 3] = 0.0
		data[base + 4] = 0.0
		data[base + 5] = 1.0
	_boid_buffer = _rd.storage_buffer_create(data.size() * 4, data.to_byte_array())


func _init_cone_buffer() -> void:
	const SEGMENTS := 6
	const RADIUS   := 0.5
	const HEIGHT   := 1.0
	var verts := PackedFloat32Array()
	for i in range(SEGMENTS):
		var a0 := (float(i)      / SEGMENTS) * TAU
		var a1 := (float(i + 1) / SEGMENTS) * TAU
		var b0  := Vector3(cos(a0) * RADIUS, 0.0, sin(a0) * RADIUS)
		var b1  := Vector3(cos(a1) * RADIUS, 0.0, sin(a1) * RADIUS)
		var tip := Vector3(0.0, HEIGHT, 0.0)
		verts.append_array([tip.x, tip.y, tip.z, b0.x, b0.y, b0.z, b1.x, b1.y, b1.z])
		var origin := Vector3.ZERO
		verts.append_array([origin.x, origin.y, origin.z, b1.x, b1.y, b1.z, b0.x, b0.y, b0.z])
	_cone_buffer = _rd.vertex_buffer_create(verts.size() * 4, verts.to_byte_array())


func get_cone_vertex_count() -> int:
	return 6 * 2 * 3


func get_boid_buffer() -> RID:
	return _boid_buffer


func get_cone_buffer() -> RID:
	return _cone_buffer


# ---------------------------------------------------------------------------
# Update pipeline
# ---------------------------------------------------------------------------
func _create_update_pipeline() -> void:
	var spirv        := UPDATE_SHADER.get_spirv()
	_update_shader    = _rd.shader_create_from_spirv(spirv)
	_update_pipeline  = _rd.compute_pipeline_create(_update_shader)


func _create_update_uniform_set() -> void:
	var boid_uniform          := RDUniform.new()
	boid_uniform.uniform_type  = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	boid_uniform.binding       = 0
	boid_uniform.add_id(_boid_buffer)
	_update_uniform_set = _rd.uniform_set_create([boid_uniform], _update_shader, 0)


func _dispatch_update(delta: float) -> void:
	var push := PackedFloat32Array()
	push.resize(12)
	push[0]  = float(boid_count)
	push[1]  = view_radius
	push[2]  = avoid_radius
	push[3]  = min_speed
	push[4]  = max_speed
	push[5]  = align_weight
	push[6]  = cohesion_weight
	push[7]  = separate_weight
	push[8]  = delta
	push[9]  = 0.0
	push[10] = 0.0
	push[11] = 0.0

	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _update_pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _update_uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push.to_byte_array(), push.size() * 4)
	_rd.compute_list_dispatch(compute_list, int(ceil(float(boid_count) / 1024.0)), 1, 1)
	_rd.compute_list_end()


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in [_boid_buffer, _cone_buffer,
					_update_pipeline, _update_shader, _update_uniform_set]:
			if rid.is_valid(): _rd.free_rid(rid)
