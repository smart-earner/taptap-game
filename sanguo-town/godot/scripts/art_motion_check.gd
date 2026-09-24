extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var preview=load("res://art_style_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var art=preview.map
	preview.town.reduce_motion=true
	var ambient_before: float=art.ambient_time
	var walking_before: float=art.animation_time
	await create_timer(.25).timeout
	if absf(art.ambient_time-ambient_before)>.001 or art.animation_time<=walking_before:
		push_error("ART_MOTION_FAIL: reduced motion must freeze ambient effects, not real walking")
		quit(1)
		return
	preview.town.reduce_motion=false
	await create_timer(.12).timeout
	if art.ambient_time<=ambient_before:
		push_error("ART_MOTION_FAIL: ambient effects must resume when enabled")
		quit(1)
		return
	print("ART_MOTION_PASS")
	quit(0)
