extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not OS.get_environment("SANGUO_GODOT_SAVE").get_file().begins_with("godot-fixture-"):
		push_error("Use an isolated godot-fixture- save");quit(1);return
	var scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.speed=0
	await create_timer(.7).timeout
	await click_text(scene,"桌面模式")
	assert(scene.current_page=="desktop")
	await click_text(scene,"关闭  ×")
	await click_text(scene,"酒馆招募")
	assert(scene.current_page=="tavern")
	await click_text(scene,"金币从哪里来？看看采金进度")
	assert(scene.current_page=="chain")
	await click_text(scene,"关闭  ×")
	await click_text(scene,"武将名册")
	assert(scene.current_page=="heroes")
	await click_text(scene,"查看专长、星技与实际作用")
	assert(scene.current_page=="skills")
	print("UI_INPUT_PASS: desktop, tavern, gold chain, roster and skills via pointer events")
	scene.queue_free()
	await process_frame
	quit(0)

func click_text(scene: Node, text: String) -> void:
	await process_frame
	var candidates=scene.ui_root.find_children("*","Button",true,false)
	for button in candidates:
		if button.text!=text or not button.is_visible_in_tree(): continue
		var p=button.get_global_rect().get_center()
		var motion=InputEventMouseMotion.new();motion.position=p;motion.global_position=p
		root.push_input(motion,true)
		for pressed in [true,false]:
			var input=InputEventMouseButton.new()
			input.position=p;input.global_position=p;input.button_index=MOUSE_BUTTON_LEFT
			input.pressed=pressed;input.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
			root.push_input(input,true)
			await process_frame
		return
	push_error("Button missing: "+text)
	quit(1)
