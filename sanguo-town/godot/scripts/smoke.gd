extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.speed = 0
	for i in range(200):
		await create_timer(.05).timeout
		if not scene.snapshot.is_empty(): break
	if scene.snapshot.is_empty():
		push_error("Bridge did not produce a snapshot: " + scene.request_error + " busy=" + str(scene.busy))
		quit(1)
		return
	scene.speed = 0
	assert(scene.actors.is_empty())
	assert(is_instance_valid(scene.flat_manager_map))
	assert(scene.flat_manager_map.town==scene)
	assert(scene.flat_manager_map.solid_background and not scene.flat_manager_map.show_hud)
	assert(scene.camera == null and scene.structures.is_empty() and scene.plot_markers.is_empty())
	assert(int(scene.snapshot.get("layoutVersion",0)) >= 7)
	assert(scene.snapshot.get("plots",[]).size() >= 18)
	assert(str(scene.snapshot.get("debugLogPath","")).ends_with("/debug/engine-debug.jsonl"))
	assert(FileAccess.file_exists(str(scene.snapshot.debugLogPath)))
	assert(str(scene.debug_log_path).ends_with("/debug/godot-debug.jsonl"))
	assert(FileAccess.file_exists(scene.debug_log_path))
	assert(scene.resource_strip_label.text.begins_with("金币 "))
	assert(scene.flat_manager_map._resource_summary(scene.snapshot).contains("工具"))
	assert(scene.snapshot.has("idlePersonnel"))
	assert(scene.resource_strip_label.text.contains("空闲 %d 人" % int(scene.snapshot.idlePersonnel)))
	assert(scene.flat_manager_map._resource_summary(scene.snapshot)==scene.resource_strip_label.text)
	var resident_entities=scene.snapshot.get("heroes",[]).filter(func(hero): return int(hero.get("star",0))>0 and hero.has("x"))
	assert(resident_entities.size() == 5)
	var first_house=scene.snapshot.get("plots",[]).filter(func(plot): return str(plot.id)=="house-1")[0]
	assert(scene.flat_manager_map._plot_display_point(first_house)!=Vector2(float(first_house.point.x),float(first_house.point.y)))
	var sandbox_plots=scene.snapshot.get("plots",[])
	for first_index in range(sandbox_plots.size()):
		for second_index in range(first_index+1,sandbox_plots.size()):
			if int(sandbox_plots[first_index].level)<=0 or int(sandbox_plots[second_index].level)<=0: continue
			var first_rect=scene.flat_manager_map._plot_pad_rect(sandbox_plots[first_index])
			var second_rect=scene.flat_manager_map._plot_pad_rect(sandbox_plots[second_index])
			assert(not first_rect.intersects(second_rect))
	for callback in [scene.show_tavern,scene.show_heroes,scene.show_resources]:
		callback.call()
		await process_frame
		assert(scene.modal.visible)
	for level in [1,2,3]:
		scene.show_building_preview(level)
		await process_frame
	scene.close_modal()
	assert(not scene.modal.visible)
	var coins = int(scene.snapshot.coins)
	if coins >= 100:
		scene.issue("draw",{"count":1})
		for i in range(200):
			await create_timer(.05).timeout
			if not scene.busy: break
		assert(not scene.busy)
		assert(int(scene.snapshot.coins) == coins-100)
		assert(scene.current_page == "results")
	print("GODOT_SMOKE_PASS: real bridge, layout7 flat map without hidden 3D city, five residents, tavern, roster, resources, three building levels, committed draw result")
	scene.queue_free()
	await process_frame
	quit(0)
