@tool
class_name InvIconBaker
extends Node

## Renders 3D models to icon textures so items with a model never need a
## hand-made PNG. Works in the editor (see tools/bake_icons.gd) and at
## runtime (bake once at load, assign to def.icon).
##
##   var baker := InvIconBaker.new()
##   add_child(baker)
##   var tex: ImageTexture = await baker.bake_scene(load("res://models/axe.glb"))
##   axe_def.icon = tex
##
## The model is framed automatically: its visual AABB is centred, the camera
## is orthographic and sized to fit with `margin`, and the background is
## transparent. Tweak `yaw_degrees` / `pitch_degrees` for the angle,
## `size` for resolution, `light_*` for shading. Set `environment` to your
## own Environment for matching tone-mapping/ambient light.

## Output resolution (square).
@export var size: int = 64
## Camera orbit. Yaw 45 / pitch -30 is the classic 3/4 view.
@export var yaw_degrees: float = 45.0
@export var pitch_degrees: float = -30.0
## Extra room around the model (1.0 = touch the edges).
@export var margin: float = 1.15
@export var transparent_background: bool = true
@export var light_direction: Vector3 = Vector3(-0.5, -1.0, -0.6)
@export var light_energy: float = 1.2
@export var ambient_color: Color = Color(0.45, 0.45, 0.5)
@export var environment: Environment = null
## Frames to wait before grabbing the image (2 is enough for static meshes;
## raise it if materials stream in late).
@export var settle_frames: int = 2

var _viewport: SubViewport
var _camera: Camera3D
var _light: DirectionalLight3D
var _world_env: WorldEnvironment
var _stage: Node3D


func _ready() -> void:
	_build_rig()


func _build_rig() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = transparent_background
	_viewport.size = Vector2i(size, size)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_viewport.add_child(_camera)

	_light = DirectionalLight3D.new()
	_light.light_energy = light_energy
	_light.shadow_enabled = false
	_viewport.add_child(_light)
	_light.look_at_from_position(-light_direction.normalized() * 10.0, Vector3.ZERO, Vector3.UP if absf(light_direction.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD)

	_world_env = WorldEnvironment.new()
	var env := environment
	if env == null:
		env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0, 0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = ambient_color
		env.ambient_light_energy = 1.0
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world_env.environment = env
	_viewport.add_child(_world_env)

	_stage = Node3D.new()
	_viewport.add_child(_stage)


# ------------------------------------------------------------------ baking

## Render a PackedScene (a .glb, .gltf or .tscn) to a texture. Await it.
func bake_scene(scene: PackedScene) -> ImageTexture:
	if scene == null:
		return null
	var inst := scene.instantiate()
	if not inst is Node3D:
		push_warning("InvIconBaker: scene root is not a Node3D (%s)" % scene.resource_path)
		inst.free()
		return null
	var tex: ImageTexture = await bake_node(inst)
	inst.queue_free()
	return tex


## Render an already-instantiated Node3D (it is reparented into the rig for
## the shot and left there — free it yourself afterwards).
func bake_node(model: Node3D) -> ImageTexture:
	_build_rig()
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	_stage.add_child(model)
	# Frame it.
	var aabb := _visual_aabb(model)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	model.transform.origin -= model.transform.basis * aabb.get_center()
	var extent := aabb.size.length() * 0.5
	var dir := Vector3.FORWARD.rotated(Vector3.RIGHT, deg_to_rad(pitch_degrees)).rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	_camera.look_at_from_position(-dir * (extent * 4.0 + 1.0), Vector3.ZERO, Vector3.UP)
	# Tight fit: project the 8 box corners into camera space and frame the
	# real 2D bounds (a half-diagonal fit leaves thin objects tiny).
	var inv_cam := _camera.global_transform.affine_inverse()
	var basis_m := model.transform.basis
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in 8:
		var corner_local := aabb.get_endpoint(k) - aabb.get_center()
		var p := inv_cam * (basis_m * corner_local)
		lo = lo.min(Vector2(p.x, p.y))
		hi = hi.max(Vector2(p.x, p.y))
	var span := hi - lo
	var centre := (hi + lo) * 0.5
	_camera.global_position += _camera.global_transform.basis * Vector3(centre.x, centre.y, 0.0)
	_camera.size = maxf(maxf(span.x, span.y) * margin, 0.01)
	_camera.near = 0.01
	_camera.far = extent * 10.0 + 10.0
	_viewport.size = Vector2i(size, size)
	_viewport.transparent_bg = transparent_background
	_light.light_energy = light_energy

	for i in maxi(settle_frames, 1):
		await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	_stage.remove_child(model)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## Bake every model in `models_dir` (recursively) to `out_dir/<name>.png`.
## Returns {"baked": [paths], "skipped": [paths], "failed": [paths]}.
## Existing PNGs are overwritten unless `skip_existing`.
func bake_folder(models_dir: String, out_dir: String, extensions: PackedStringArray = PackedStringArray([".glb", ".gltf", ".tscn", ".scn"]), skip_existing: bool = false) -> Dictionary:
	var report := {"baked": [], "skipped": [], "failed": []}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for path in _list_files(models_dir, extensions):
		var out_path := out_dir.path_join(path.get_file().get_basename() + ".png")
		if skip_existing and FileAccess.file_exists(out_path):
			report["skipped"].append(path)
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			report["failed"].append(path)
			continue
		var tex: ImageTexture = await bake_scene(scene)
		if tex == null:
			report["failed"].append(path)
			continue
		var err := tex.get_image().save_png(out_path)
		if err != OK:
			report["failed"].append(path)
		else:
			report["baked"].append(out_path)
	return report


## Runtime helper: for every def in `db` without an icon, look up a model
## via `model_for(def) -> PackedScene` (return null to skip) and bake it.
func bake_missing_icons(db: InvItemDatabase, model_for: Callable) -> int:
	var n := 0
	for id in db.all_ids():
		var def := db.get_def(id)
		if def.icon != null:
			continue
		var scene: PackedScene = model_for.call(def)
		if scene == null:
			continue
		var tex: ImageTexture = await bake_scene(scene)
		if tex != null:
			def.icon = tex
			n += 1
	return n


# ---------------------------------------------------------------- internals

static func _visual_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var local := vi.get_aabb()
			if local.size != Vector3.ZERO:
				var xf: Transform3D = root.global_transform.affine_inverse() * vi.global_transform
				var world := xf * local
				if first:
					result = world
					first = false
				else:
					result = result.merge(world)
		for c in n.get_children():
			stack.append(c)
	return result


static func _list_files(dir_path: String, extensions: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_list_files(dir_path.path_join(name), extensions))
		else:
			var lower := name.to_lower()
			for ext in extensions:
				if lower.ends_with(ext) and not lower.ends_with(".import"):
					out.append(dir_path.path_join(name))
					break
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
