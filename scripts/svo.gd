@tool class_name SVO extends Node3D

@export var scene: Node3D = null
@export_range(1, 12) var max_depth: int = 7
@export_dir var out_data: String = "res://data/"
@export var run_build_on_ready: bool = false
@export var run_build: bool = false:
	set(v):
		if v and Engine.is_editor_hint():
			run_build = false
			_run_build()

var _nodes: Array = []
var _origin: Vector3 = Vector3.ZERO
var _size: float = 1.0

func _ready() -> void:
	if run_build_on_ready:
		_run_build()

func _run_build() -> void:
	print("Building SVO for %s" % scene.name)
	var aabbs: Array[AABB] = []
	_collect_aabbs(scene, Transform3D.IDENTITY, aabbs)
	if aabbs.is_empty():
		push_error("Failed to collect any AABBs for %s" % scene.name)
		return
	print("Collected %d AABBs" % aabbs.size())
	var scene_min: Vector3 = Vector3(INF, INF, INF)
	var scene_max: Vector3 = Vector3(-INF, -INF, -INF)
	for aabb: AABB in aabbs:
		scene_min = scene_min.min(aabb.position)
		scene_max = scene_max.max(aabb.end)
	var padding: Vector3 = (scene_max - scene_min) * 0.005 + Vector3.ONE * 0.001
	scene_min -= padding
	scene_max += padding
	var extents: Vector3 = scene_max - scene_min
	_origin = scene_min
	_size = maxf(extents.x, maxf(extents.y, extents.z))
	_nodes.clear()
	_new_node()
	_subdivide(aabbs, 0, _origin, _size, 0)
	print("Collected %d nodes" % _nodes.size())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_data))
	_export_binary()
	_export_meta()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	print("Built SVO for %s" % scene.name)

func _collect_aabbs(node: Node, xform: Transform3D, out: Array[AABB]) -> void:
	if node is Node3D:
		xform = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			out.append(xform * mesh.get_aabb())
	for child in node.get_children():
		_collect_aabbs(child, xform, out)

func _new_node() -> int:
	var index: int = _nodes.size()
	_nodes.append([-1, -1, -1, -1, -1, -1, -1, -1])
	return index

func _subdivide(aabbs: Array[AABB], index: int, _min: Vector3, size: float, depth: int) -> void:
	var half: float = size * 0.5
	for ci in range(8):
		var child_min: Vector3 = _min + Vector3(
			half if (ci & 1) else 0.0,
			half if (ci & 2) else 0.0,
			half if (ci & 4) else 0.0)
		var child_max: Vector3 = child_min + Vector3(half, half, half)
		var cell: AABB = AABB(child_min, child_max - child_min)
		var _aabbs: Array[AABB] = []
		var is_solid: bool = false
		for aabb: AABB in aabbs:
			if aabb.encloses(cell):
				is_solid = true
				break
			if aabb.intersects(cell):
				_aabbs.append(aabb)
		# Solid leaf
		if is_solid:
			_nodes[index][ci] = -2
			continue
		# Empty leaf
		if _aabbs.is_empty():
			continue
		# Solid leaf at max depth
		if depth == max_depth - 1:
			_nodes[index][ci] = -2
			continue
		var child_index: int = _new_node()
		_nodes[index][ci] = child_index
		_subdivide(_aabbs, child_index, child_min, half, depth + 1)
		is_solid = true
		for v in _nodes[child_index]:
			if v != -2:
				is_solid = false
		if is_solid:
			_nodes[index][ci] = -2

func _export_binary() -> void:
	var path: String = ProjectSettings.globalize_path(out_data.path_join("svo.bin"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write to %s" % path)
		return
	for node in _nodes:
		for value in node:
			file.store_32(value)
	file.close()

func _export_meta() -> void:
	var meta: Dictionary = {
		"root_min_x": _origin.x,
		"root_min_y": _origin.y,
		"root_min_z": _origin.z,
		"root_size": _size,
		"max_depth": max_depth,
		"node_count": _nodes.size(),
	}
	var path: String = ProjectSettings.globalize_path(out_data.path_join("svo.json"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write to %s" % path)
		return
	file.store_string(JSON.stringify(meta, "\t"))
	file.close()
