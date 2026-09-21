extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func require(value: bool, message: String) -> bool:
	if not value:
		push_error("DESKTOP_FAIL: " + message)
		quit(1)
		return false
	print("PASS ",message)
	return true

func run() -> void:
	if not require(OS.get_environment("SANGUO_GODOT_SAVE").get_file().begins_with("godot-fixture-"),"isolated test save"): return
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.speed=0
	for i in range(200):
		await create_timer(.05).timeout
		if not scene.snapshot.is_empty(): break
	if not require(not scene.snapshot.is_empty(),"authoritative snapshot loaded"): return
	var desktop=scene.desktop
	var rival=ClassDB.instantiate("TownDesktopHost")
	var rival_status=JSON.parse_string(rival.command(9,0))
	if not require(not rival_status.ok,"second frontend cannot own city clock"): return
	rival.free()
	desktop.set_enabled(true)
	await create_timer(.6).timeout
	var state=desktop.command(1,0)
	print("DESKTOP_NATIVE_STATE ",JSON.stringify(state))
	if not require(state.visible and state.mouse_passthrough and not state.opaque,"visible transparent mouse-through native desktop"): return
	if not require(state.level<state.icon_level and state.level<state.normal_level,"desktop below icons and normal apps"): return
	if not require(not state.can_become_key,"desktop cannot steal keyboard focus"): return
	if not require(is_instance_valid(desktop.flat_map) and desktop.flat_map.town==scene,"desktop 2D map reads the authoritative committed scene snapshot"): return
	if not require(desktop.flat_map.get_script()==scene.flat_manager_map.get_script(),"desktop and manager use the exact same 2D renderer"): return
	var preferred=state.active_display
	desktop.command(2,4294967294)
	state=desktop.command(1,0)
	if not require(state.preferred_display==4294967294 and state.active_display!=4294967294,"missing monitor falls back while retaining preference"): return
	desktop.command(2,preferred)
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered=desktop.surface.get_texture().get_image()
	var translucent_pixels=0
	var opaque_pixels=0
	for y in range(0,rendered.get_height(),20):
		for x in range(0,rendered.get_width(),20):
			if rendered.get_pixel(x,y).a<.98: translucent_pixels+=1
			if rendered.get_pixel(x,y).a>.05: opaque_pixels+=1
	if not require(translucent_pixels>100 and opaque_pixels>100,"render keeps wallpaper translucency and visible 2D town"): return
	await create_timer(.35).timeout
	await RenderingServer.frame_post_draw
	var animated=desktop.surface.get_texture().get_image()
	var changed_pixels=0
	for y in range(0,rendered.get_height(),16):
		for x in range(0,rendered.get_width(),16):
			var before_color=rendered.get_pixel(x,y)
			var after_color=animated.get_pixel(x,y)
			var difference=absf(before_color.r-after_color.r)+absf(before_color.g-after_color.g)+absf(before_color.b-after_color.b)+absf(before_color.a-after_color.a)
			if difference>.02: changed_pixels+=1
	if not require(changed_pixels>20,"desktop 2D layer visibly animates between frames"): return
	var output=ProjectSettings.globalize_path("res://../dist/godot-desktop-tests")
	DirAccess.make_dir_recursive_absolute(output)
	rendered.save_png(output+"/desktop-layer.png")
	var before=int(scene.snapshot.time)
	scene.elapsed=0;scene.speed=1
	desktop.hide_manager()
	await create_timer(.35).timeout
	await RenderingServer.frame_post_draw
	var hidden_frame_a=desktop.surface.get_texture().get_image()
	await create_timer(.35).timeout
	await RenderingServer.frame_post_draw
	var hidden_frame_b=desktop.surface.get_texture().get_image()
	var hidden_changed_pixels=0
	for y in range(0,hidden_frame_a.get_height(),16):
		for x in range(0,hidden_frame_a.get_width(),16):
			var hidden_before=hidden_frame_a.get_pixel(x,y)
			var hidden_after=hidden_frame_b.get_pixel(x,y)
			var hidden_difference=absf(hidden_before.r-hidden_after.r)+absf(hidden_before.g-hidden_after.g)+absf(hidden_before.b-hidden_after.b)+absf(hidden_before.a-hidden_after.a)
			if hidden_difference>.02: hidden_changed_pixels+=1
	if not require(hidden_changed_pixels>20,"desktop keeps animating after manager window is hidden"): return
	await create_timer(2.5).timeout
	scene.speed=0
	while scene.busy: await process_frame
	var advanced=int(scene.snapshot.time)-before
	if not require(advanced>=1 and advanced<=3,"one clock continues with manager hidden ("+str(advanced)+" seconds)"): return
	desktop.show_manager("tavern")
	if not require(scene.current_page=="tavern","manager returns to tavern"): return
	desktop.set_enabled(false)
	if not require(not desktop.command(1,0).visible,"hide removes desktop layer"): return
	desktop.set_enabled(true)
	if not require(desktop.command(1,0).visible,"desktop can be restored"): return
	desktop.command(6,0)
	state=desktop.command(1,0)
	if not require(not state.visible and not state.menu_installed and not state.clock_owner,"exit cleanup removes layer/menu and releases clock"): return
	print("DESKTOP_SMOKE_PASS")
	scene.queue_free()
	await process_frame
	quit(0)
