@tool
extends EditorScript

## Bake icon PNGs from 3D models, inside the editor.
##
##   1. Put your models (.glb / .gltf / .tscn) under MODELS_DIR.
##   2. Edit the constants below if you want a different size or angle.
##   3. Open this file in the script editor and press Ctrl+Shift+X
##      (File > Run). PNGs land in OUT_DIR as <model name>.png.
##   4. Drag a PNG onto an InvItemDef's Icon field.
##
## Re-run whenever models change; existing PNGs are overwritten.

const MODELS_DIR := "res://models"
const OUT_DIR := "res://icons"
const SIZE := 64
const YAW := 45.0
const PITCH := -30.0
const MARGIN := 1.15


func _run() -> void:
	var baker := InvIconBaker.new()
	baker.size = SIZE
	baker.yaw_degrees = YAW
	baker.pitch_degrees = PITCH
	baker.margin = MARGIN
	# The rig has to be in the editor's tree to render. The baker removes
	# itself when the batch is done.
	EditorInterface.get_base_control().add_child(baker)
	_bake(baker)


func _bake(baker: InvIconBaker) -> void:
	var report: Dictionary = await baker.bake_folder(MODELS_DIR, OUT_DIR)
	print("InvIconBaker: baked %d, skipped %d, failed %d" % [report["baked"].size(), report["skipped"].size(), report["failed"].size()])
	for p in report["baked"]:
		print("  + ", p)
	for p in report["failed"]:
		print("  ! failed: ", p)
	if report["baked"].is_empty() and report["failed"].is_empty():
		print("  (no models found under %s)" % MODELS_DIR)
	EditorInterface.get_resource_filesystem().scan()
	baker.queue_free()
