extends Node3D

@export var svo: SVO = null
@export_range(0, 20) var max_depth: int = 10
@export var color: Color = Color(0.2, 0.8, 0.4, 1.0)

var _lines : Array = []

func _ready() -> void:
	if svo == null:
		push_error("Missing SVO")
		return
	var binary_path: String = svo.out_data.path_join("svo.bin")
	var meta_path: String = svo.out_data.path_join("svo.json")
	var meta_file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
	if meta_file == null:
		push_error("Failed to open SVO %s" % meta_path)
		return
	var meta : Dictionary = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	var root_min: Vector3 = Vector3(meta.root_min_x, meta.root_min_y, meta.root_min_z)
	var root_size: float = float(meta.root_size)
	var _max_depth: int = int(meta.max_depth)
	var node_count: int = int(meta.node_count)
	var binary_file: FileAccess = FileAccess.open(binary_path, FileAccess.READ)
	if binary_file == null:
		push_error("Failed to open SVO %s" % binary_path)
		return
	var nodes: PackedInt32Array = PackedInt32Array()
	nodes.resize(node_count * 8)
	for i in range(nodes.size()):
		nodes[i] = binary_file.get_32()
	binary_file.close()
	_max_depth = min(max_depth, _max_depth)
	var stack: Array = [[0, root_min, root_size, 0]]
	while not stack.is_empty():
		var element: Array = stack.pop_back()
		var index: int = element[0]
		var _min: Vector3 = element[1]
		var size: float = element[2]
		var depth: int = element[3]
		if depth > _max_depth:
			continue
		var half: float = size * 0.5
		for slot in range(8):
			var child_index: int = nodes[index * 8 + slot]
			var cmin: Vector3 = _min + Vector3(
				half if (slot & 1) else 0.0,
				half if (slot & 2) else 0.0,
				half if (slot & 4) else 0.0)
			if child_index == -2:
				_add_box(cmin, cmin + Vector3(half, half, half))
			elif child_index >= 0 and depth + 1 <= _max_depth:
				stack.push_back([child_index, cmin, half, depth + 1])

func _add_box(bmin: Vector3, bmax: Vector3) -> void:
	var cell: Array[Vector3] = [
		Vector3(bmin.x, bmin.y, bmin.z),
		Vector3(bmax.x, bmin.y, bmin.z),
		Vector3(bmax.x, bmax.y, bmin.z),
		Vector3(bmin.x, bmax.y, bmin.z),
		Vector3(bmin.x, bmin.y, bmax.z),
		Vector3(bmax.x, bmin.y, bmax.z),
		Vector3(bmax.x, bmax.y, bmax.z),
		Vector3(bmin.x, bmax.y, bmax.z),
	]
	const EDGES = [
		[0,1],[1,2],[2,3],[3,0],
		[4,5],[5,6],[6,7],[7,4],
		[0,4],[1,5],[2,6],[3,7]
	]
	for edge in EDGES:
		_lines.append(cell[edge[0]])
		_lines.append(cell[edge[1]])

func _process(_delta: float) -> void:
	if not visible:
		return
	@warning_ignore("integer_division")
	for i in range(_lines.size() / 2):
		DebugDraw3D.draw_line(_lines[i * 2 + 0], _lines[i * 2 + 1], color)
