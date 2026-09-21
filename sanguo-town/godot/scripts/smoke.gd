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
	assert(scene.actors.size() >= 5)
	assert(int(scene.snapshot.get("layoutVersion",0)) == 6)
	assert(scene.snapshot.get("plots",[]).size() == 18)
	assert(scene.plot_markers.size() == 18)
	assert(is_instance_valid(scene.plot_branches))
	assert(scene.structures.has("tavern"))
	assert(scene.structures.has("smelter"))
	assert(scene.forest.size() == 24)
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
	print("GODOT_SMOKE_PASS: real bridge, layout6 18-plot map, five actors, tavern, roster, resources, three building levels, committed draw result")
	scene.queue_free()
	await process_frame
	quit(0)
