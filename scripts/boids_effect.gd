class_name BoidsEffect extends CompositorEffect

static var RENDER_SHADER: RDShaderFile = preload("res://resources/render.glsl")

var _boid_buffer:        RID
var _cone_buffer:        RID
var _cone_vertex_count:  int = 0
var _boid_count:         int = 0

func setup(boids: Node3D) -> void:
	_boid_buffer       = boids.get_boid_buffer()
	_cone_buffer       = boids.get_cone_buffer()
	_cone_vertex_count = boids.get_cone_vertex_count()
	_boid_count        = boids.boid_count

var _rd: RenderingDevice

var _render_shader:      RID
var _render_pipeline:    RID
var _render_uniform_set: RID
var _vertex_format:      int = -1
var _vertex_array:       RID

var _pipeline_fb_format: int = -1  # track which framebuffer format the pipeline was built for


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE
	RenderingServer.call_on_render_thread(_init_render.bind())


func _init_render() -> void:
	_rd = RenderingServer.get_rendering_device()


# ---------------------------------------------------------------------------
# Called every frame by the compositor on the render thread
# ---------------------------------------------------------------------------
func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	if _boid_buffer == RID() or _rd == null:
		return

	var render_scene_buffers: RenderSceneBuffers = render_data.get_render_scene_buffers()
	if render_scene_buffers == null:
		return

	var fb = render_scene_buffers.get_color_layer(0)  # main color buffer
	if not fb.is_valid():
		return

	var fb_format := _rd.framebuffer_get_format(
		_rd.framebuffer_create([fb])
	)

	# Rebuild pipeline if framebuffer format changed (e.g. on resize)
	if fb_format != _pipeline_fb_format:
		_build_render_pipeline(fb_format)
		_pipeline_fb_format = fb_format

	# Rebuild uniform set if needed (boid buffer may have been recreated)
	if not _render_uniform_set.is_valid():
		_create_render_uniform_set()

	# Build view-proj from render_data
	var render_scene_data := render_data.get_render_scene_data()
	var view_proj          := render_scene_data.get_cam_projection() * \
							  Projection(render_scene_data.get_cam_transform().inverse())

	var push := PackedFloat32Array()
	push.resize(20)
	for col in range(4):
		for row in range(4):
			push[col * 4 + row] = view_proj[col][row]
	push[16] = float(_cone_vertex_count)
	push[17] = float(_boid_count)
	push[18] = 0.0
	push[19] = 0.0

	var framebuffer := _rd.framebuffer_create([fb])
	var draw_list := _rd.draw_list_begin(
		framebuffer,
		RenderingDevice.DRAW_DEFAULT_ALL,
		[]
	)
	_rd.draw_list_bind_render_pipeline(draw_list, _render_pipeline)
	_rd.draw_list_bind_uniform_set(draw_list, _render_uniform_set, 0)
	_rd.draw_list_bind_vertex_array(draw_list, _vertex_array)
	_rd.draw_list_set_push_constant(draw_list, push.to_byte_array(), push.size() * 4)
	_rd.draw_list_draw(draw_list, false, _boid_count)
	_rd.draw_list_end()


# ---------------------------------------------------------------------------
# Pipeline — built once per unique framebuffer format
# ---------------------------------------------------------------------------
func _build_render_pipeline(fb_format: int) -> void:
	# Free old pipeline if it exists
	if _render_pipeline.is_valid(): _rd.free_rid(_render_pipeline)
	if _render_shader.is_valid():   _rd.free_rid(_render_shader)

	var spirv         := RENDER_SHADER.get_spirv()
	_render_shader     = _rd.shader_create_from_spirv(spirv)

	var attr      := RDVertexAttribute.new()
	attr.location  = 0
	attr.format    = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	attr.stride    = 12
	attr.offset    = 0
	_vertex_format = _rd.vertex_format_create([attr])

	_vertex_array = _rd.vertex_array_create(
		_cone_vertex_count, _vertex_format, [_cone_buffer])

	var blend := RDPipelineColorBlendState.new()
	blend.attachments.append(RDPipelineColorBlendStateAttachment.new())

	var depth_stencil                   := RDPipelineDepthStencilState.new()
	depth_stencil.enable_depth_test      = true
	depth_stencil.enable_depth_write     = true
	depth_stencil.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS

	var raster      := RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_BACK

	_render_pipeline = _rd.render_pipeline_create(
		_render_shader,
		fb_format,
		_vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		raster,
		RDPipelineMultisampleState.new(),
		depth_stencil,
		blend
	)

	_create_render_uniform_set()


func _create_render_uniform_set() -> void:
	if _render_uniform_set.is_valid(): _rd.free_rid(_render_uniform_set)
	var boid_uniform          := RDUniform.new()
	boid_uniform.uniform_type  = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	boid_uniform.binding       = 0
	boid_uniform.add_id(_boid_buffer)
	_render_uniform_set = _rd.uniform_set_create([boid_uniform], _render_shader, 0)


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in [_render_pipeline, _render_shader, _render_uniform_set]:
			if rid.is_valid(): _rd.free_rid(rid)
