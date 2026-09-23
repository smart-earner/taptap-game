extends Node

# Both views read one committed snapshot and one clock. This desktop view is a
# true 2D canvas and never calls the economic bridge.
const DesktopMap2D=preload("res://scripts/desktop_map_2d.gd")
var town: Node3D
var native: Object
var surface: Window
var flat_map: Control
var enabled = false
var manager_visible = true
var poll_elapsed = 0.0
var preferred_display = 0
var config = ConfigFile.new()
var status: Dictionary = {}
var error = ""
var clock_owned = false

func initialize(owner_town: Node3D) -> bool:
	town = owner_town
	if not ClassDB.class_exists("TownDesktopHost"):
		error = "桌面组件未加载，请使用打开Godot小城启动脚本。"
		return false
	native = ClassDB.instantiate("TownDesktopHost")
	var lock = command(9,0)
	if not lock.get("ok",false):
		error = lock.get("error","无法取得唯一经营时钟")
		return false
	clock_owned = true
	if DisplayServer.get_name() == "headless": return true
	config.load("user://desktop.cfg")
	preferred_display = int(config.get_value("desktop","display",0))
	command(5,DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE))
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(func():
		if enabled: hide_manager()
		else: get_tree().quit())
	if bool(config.get_value("desktop","enabled",false)): set_enabled(true)
	return true

func command(operation: int, value: int) -> Dictionary:
	if not is_instance_valid(native): return {"ok":false,"error":"桌面组件不可用"}
	var result = JSON.parse_string(native.command(operation,value))
	return result if result is Dictionary else {"ok":false,"error":"桌面组件返回异常"}

func save_preferences() -> void:
	# Test runs must not change player display preferences.
	if OS.get_environment("SANGUO_GODOT_SAVE")!="": return
	config.set_value("desktop","enabled",enabled)
	config.set_value("desktop","display",preferred_display)
	config.save("user://desktop.cfg")

func create_surface() -> bool:
	if surface: return true
	get_window().gui_embed_subwindows = false
	surface = Window.new()
	surface.title = "小城志 · 桌面城景"
	surface.visible = false
	surface.borderless = true
	surface.transparent = true
	surface.transparent_bg = true
	surface.unfocusable = true
	surface.mouse_passthrough = true
	surface.transient = false
	surface.size = Vector2i(640,400)
	add_child(surface)
	flat_map=DesktopMap2D.new()
	flat_map.town=town
	surface.add_child(flat_map)
	surface.show()
	command(2,preferred_display)
	status = command(0,DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,surface.get_window_id()))
	if not status.get("ok",false):
		error = status.get("error","桌面层创建失败")
		surface.queue_free();surface=null
		return false
	return true

func set_enabled(value: bool) -> void:
	if not clock_owned or DisplayServer.get_name()=="headless": return
	if value and not create_surface(): return
	enabled = value
	status = command(3,1 if enabled else 0)
	if not enabled and not manager_visible: show_manager()
	save_preferences()

func hide_manager() -> void:
	if not enabled: set_enabled(true)
	if not enabled: return
	town.close_modal()
	command(7,0)
	manager_visible = false
	# Desktop animation is slow and always behind ordinary app windows. The
	# lower refresh rate cuts the cost of redrawing a full Retina desktop while
	# keeping the management window at 30 FPS when the player interacts.
	Engine.max_fps = 15
	if is_instance_valid(flat_map): flat_map.drives_visual_walks = true
	if is_instance_valid(town.flat_manager_map):
		town.flat_manager_map.visible = false
		town.flat_manager_map.set_process(false)
	# Do not deactivate the root viewport here. On macOS Godot's secondary
	# native Window depends on the root render submission even though it owns a
	# separate viewport; deactivating it freezes the desktop canvas on its last
	# frame. Only its duplicate 2D map is paused; the desktop canvas keeps its
	# lower-rate walk cycle, and the simulation still has only one clock.

func show_manager(page: String = "") -> void:
	command(7,1)
	manager_visible = true
	Engine.max_fps = 30
	if is_instance_valid(flat_map): flat_map.drives_visual_walks = false
	if is_instance_valid(town.flat_manager_map):
		town.flat_manager_map.visible = true
		town.flat_manager_map.set_process(true)
	if page=="tavern": town.show_tavern()
	elif page=="heroes": town.show_heroes()
	elif page=="war": town.show_war()

func _process(delta: float) -> void:
	if not native or DisplayServer.get_name()=="headless": return
	poll_elapsed += delta
	if poll_elapsed<.25: return
	poll_elapsed = 0
	if is_instance_valid(flat_map): flat_map.queue_redraw()
	var event = int(command(4,0).get("event",0))
	match event:
		1: show_manager()
		2: show_manager("tavern")
		3: show_manager("heroes")
		4: show_manager("war")
		5: set_enabled(not enabled)
		6: town.set_speed(town.last_running_speed if town.speed==0 else 0)
		7: get_tree().quit()

func show_settings() -> void:
	town.open_modal("把小城放在桌面", "desktop")
	town.paragraph("二维大地图铺满桌面层，桌面图标与工作窗口仍在上面。武将照常经营，鼠标直接穿过。",17,town.INK)
	if not clock_owned:
		town.paragraph(error,15,Color("a6553e")); return
	status = command(1,0)
	town.paragraph("桌面城景："+("已开启" if enabled else "未开启"),17,town.JADE)
	var toggle = town.button("隐藏桌面小城" if enabled else "开启桌面平铺",func(): set_enabled(not enabled);show_settings(),true)
	town.modal_body.add_child(toggle)
	town.modal_body.add_child(town.button("收起管理窗口，回到桌面",hide_manager))
	town.paragraph("从系统菜单栏「小城」随时回来抽卡、培养或退出。关闭管理窗口不会关闭桌面城景。",14)
	town.paragraph("显示器",15,town.INK)
	var selector = OptionButton.new()
	selector.add_item("自动选择主屏",0)
	var screens = status.get("screens",[])
	for screen in screens:
		selector.add_item(screen.name,int(screen.id))
		if int(screen.id)==preferred_display: selector.select(selector.item_count-1)
	selector.item_selected.connect(func(index):
		preferred_display=selector.get_item_id(index)
		command(2,preferred_display)
		save_preferences())
	town.modal_body.add_child(selector)
	town.paragraph("拔掉外接屏会暂回主屏，重连后恢复所选屏幕。隐藏只撤去图层，退出才停止经营；不修改壁纸和桌面文件。",13)
	town.modal_body.add_child(town.button("保存并退出小城志",func(): get_tree().quit()))

func _exit_tree() -> void:
	if is_instance_valid(native):
		if is_instance_valid(town): town.finish_pending_save()
		command(6,0)
		native.free()
