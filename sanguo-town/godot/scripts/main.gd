extends Node3D

const Models = preload("res://scripts/models.gd")
const Desktop = preload("res://scripts/desktop.gd")
const Production = preload("res://scripts/production.gd")
const PAPER = Color("f5f1e5")
const INK = Color("2b453d")
const MUTED = Color("6a7769")
const JADE = Color("416c5c")
const GOLD = Color("a37c43")

var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var actors: Dictionary = {}
var actor_data: Dictionary = {}
var structures: Dictionary = {}
var plot_markers: Dictionary = {}
var plot_branches: Node3D
var field_nodes: Dictionary = {}
var forest: Array = []
var snapshot: Dictionary = {}
var structure_signature = ""
var bridge_thread: Thread
var busy = false
var elapsed = 0.0
var since_snapshot = 0.0
var speed = 6
var orbit = 0.63
var camera_size = 25.0
var camera_target = Vector3(0, 0, 0)
var dragging = false
var clock_label: Label
var wallet_label: Label
var status_label: Label
var roster_label: Label
var modal: PanelContainer
var modal_body: VBoxContainer
var ui_root: Control
var overlay: ColorRect
var current_page = ""
var selected_hero = "xunyu"
var house_view: Node3D
var hero_view: Node3D
var smoke: Node3D
var smoke_time = 0.0
var reduce_motion = false
var request_error = ""
var heroes_refresh_pending = false
var desktop
var clock_owned = false
var production
var chain_labels: Array = []
var speed_selector: OptionButton
var last_running_speed = 6

func _ready() -> void:
	Engine.max_fps = 30
	DisplayServer.window_set_title("小城志 · 桌面大地图")
	build_lighting()
	build_terrain()
	build_camera()
	build_ui()
	production=Production.new()
	add_child(production)
	production.initialize(self)
	desktop = Desktop.new()
	add_child(desktop)
	clock_owned = desktop.initialize(self)
	if not clock_owned:
		status_label.text=desktop.error
		open_modal("小城已经在运行", "error")
		paragraph(desktop.error,17)
		modal_body.add_child(button("关闭这个重复窗口",func(): get_tree().quit()))
		return
	request({"operation":"snapshot", "seconds":0})

func build_lighting() -> void:
	environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("d8dfce")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e3ebd4")
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-28,0)
	sun.light_color = Color("fff0cb")
	sun.light_energy = .85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	sun.shadow_bias = 0.03
	add_child(sun)

func build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 150
	add_child(camera)
	camera.current = true
	position_camera()

func position_camera() -> void:
	camera.size = camera_size
	camera.position = camera_target + Vector3(sin(orbit)*32,28,cos(orbit)*32)
	camera.look_at(camera_target)

func world_point(point: Dictionary) -> Vector3:
	return Vector3((float(point.get("x",960))-960.0)/65.0,0.14,(540.0-float(point.get("y",540)))/65.0)

func build_terrain() -> void:
	var ground = Node3D.new()
	ground.name = "Landscape"
	add_child(ground)
	# The desktop map is a thin landscape sheet, not a floating display plinth.
	Models.box(ground,Vector3(0,-.04,0),Vector3(30.5,.10,19.2),"a99c79")
	Models.box(ground,Vector3(0,.015,0),Vector3(30.6,.06,19.3),"a8b98a")
	# River and bank extend to the eastern edge of the 1920x1080 world.
	Models.box(ground,Vector3(13.5,.071,0),Vector3(2.8,.03,19.25),"72a7a0")
	Models.box(ground,Vector3(11.96,.072,0),Vector3(.35,.04,19.25),"d2cfaa")
	for i in range(18):
		var wave = Models.box(ground,Vector3(12.8+float(i%3)*.4,.095,float(i)-8.5),Vector3(.42,.008,.025),"bad4bf")
		wave.rotation.y = .15
	var rng = RandomNumberGenerator.new()
	rng.seed = 71926
	for i in range(75):
		var x = rng.randf_range(-14.6,11.3)
		var z = rng.randf_range(-9,9)
		if absf(z+1.846)<.65 or absf(z-4.923)<.6 or absf(z+7.23)<.5 or absf(x+4)<.6: continue
		var grass = Models.ball(ground,Vector3(x,.11,z),Vector3(.18,.12,.16),["8da675","92ac7b","b5c295"][i%3])
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# layout6 authoritative main roads: 4 verticals x 5 horizontals.
	for y in [200.0,380.0,640.0,840.0,1000.0]:
		road(ground,world_point({"x":140,"y":y}),world_point({"x":1780,"y":y}),.34)
	for x in [140.0,680.0,1200.0,1780.0]:
		road(ground,world_point({"x":x,"y":200}),world_point({"x":x,"y":1000}),.34)
	for i in range(24):
		var tree = Models.tree(i)
		ground.add_child(tree)
		tree.position = world_point({"x":210+float(i%6)*38,"y":875+float(i/6)*38})
		tree.scale *= .8+float(i%3)*.08
		forest.append(tree)
		Models.cylinder(ground,tree.position+Vector3(0,.12,0),.13,.11,.24,"826543",7)
	for i in range(7):
		var tree = Models.tree(i+2)
		ground.add_child(tree)
		tree.position = Vector3(10.2,0.14,-7.8+float(i)*2.5)
	for i in range(7):
		Models.ball(ground,Vector3(-14.8,.30,6.2+float(i)*.37),Vector3(.50,.6,.55),"9b9e85")

func road(parent: Node3D, a: Vector3, b: Vector3, width: float) -> void:
	var length = a.distance_to(b)
	if length < .01: return
	var middle = (a+b)*.5
	middle.y = .105
	var lane = Models.box(parent,middle,Vector3(width+.10,.065,length),"bcb997")
	lane.rotation.y = atan2(b.x-a.x,b.z-a.z)
	var pavement = Models.box(parent,middle+Vector3(0,.035,0),Vector3(width,.035,length),"dbd0af")
	pavement.rotation.y = lane.rotation.y
	var sections = int(length/.47)
	for i in range(sections):
		var p = a.lerp(b,(float(i)+.5)/max(1,sections))
		p.y = .16
		var line = Models.box(parent,p,Vector3(width*.84,.005,.015),"bfb99c")
		line.rotation.y = lane.rotation.y
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func sync_scene(data: Dictionary) -> void:
	var signature = JSON.stringify([data.get("buildings"),data.get("houseLevels"),data.get("plots",[]).map(func(p): return [p.id,p.level,p.service]),data.get("projects",[]).map(func(p): return [p.id,p.phase,p.completed])])
	if signature != structure_signature:
		structure_signature = signature
		for n in structures.values(): n.queue_free()
		structures.clear()
		for n in plot_markers.values(): n.queue_free()
		plot_markers.clear()
		if is_instance_valid(plot_branches):
			remove_child(plot_branches)
			plot_branches.queue_free()
		plot_branches=Node3D.new()
		plot_branches.name="Layout6Branches"
		add_child(plot_branches)
		var places = data.places
		var plots: Array=data.get("plots",[])
		if not plots.is_empty():
			for plot in plots:
				var p=world_point(plot.point)
				var marker=Node3D.new()
				add_child(marker)
				marker.position=p
				plot_markers[plot.id]=marker
				Models.box(marker,Vector3(0,.035,0),Vector3(2.45,.07,1.72),"c9c5a7" if int(plot.level)>0 else "b3b796")
				for corner in [Vector3(-1.06,.11,-.70),Vector3(1.06,.11,-.70),Vector3(-1.06,.11,.70),Vector3(1.06,.11,.70)]:
					Models.box(marker,corner,Vector3(.16,.13,.16),"dfd6b8" if int(plot.level)>0 else "8fa17f")
				var entry={"x":float(plot.point.x),"y":float(plot.point.y)-28.0}
				var road_ys=[200.0,380.0,640.0,840.0,1000.0]
				road_ys.sort_custom(func(a,b): return absf(a-float(entry.y))<absf(b-float(entry.y)))
				road(plot_branches,world_point(entry),world_point({"x":entry.x,"y":road_ys[0]}),.20)
				if int(plot.level)<=0: continue
				var kind=str(plot.kind)
				var model: Node3D
				if kind=="goldmine": model=Models.mine()
				elif kind=="smelter": model=Models.furnace()
				else: model=Models.building(kind,int(plot.level))
				place_building(str(plot.node),model,p)
				if kind=="tavern": place_building("kitchen",Models.kitchen(),p+Vector3(1.65,0,.15))
		else:
			# Compatibility projection for preview1 saves without formal plots.
			var pairs = [["hall","hall"],["granary","warehouse"],["farm","farm"],["tavern","tavern"],["workshop","workshop"]]
			for pair in pairs:
				if int(data.buildings.get(pair[0],0))<=0: continue
				place_building(pair[1],Models.building(pair[0]),world_point(places[pair[1]]))
			var levels = data.houseLevels
			for i in range(levels.size()): place_building("home-"+str(i),Models.building("house",int(levels[i])),world_point(places.home)+Vector3(float(i)*2.8,0,-.15))
			place_building("goldmine",Models.mine(),world_point(places.goldmine))
			place_building("smelter",Models.furnace(),world_point(places.smelter))
			place_building("kitchen",Models.kitchen(),world_point(places.kitchen))
		place_building("well",Models.well(),world_point(places.well))
		for project in data.projects:
			if project.completed: continue
			var scaffold = Node3D.new()
			var target=plots.filter(func(plot): return str(plot.id)==str(project.get("targetPlotID","")))
			var p = world_point(target[0].point) if not target.is_empty() else world_point(places.get(project.node,places.hall))
			for side in [-1,1]:
				Models.beam(scaffold,Vector3(side*1.35,0,1.15),Vector3(side*1.35,2.7,1.15),.035,"b39563")
			Models.beam(scaffold,Vector3(-1.35,1.4,1.15),Vector3(1.35,1.4,1.15),.05,"b39563")
			place_building("scaffold-"+project.id,scaffold,p)
	for i in range(mini(forest.size(),data.get("treeReady",[]).size())):
		forest[i].visible = int(data.treeReady[i])<=int(data.time)
	for field in data.fields:
		var key = str(field.id)+":"+str(field.state)
		if field_nodes.has(field.id) and field_nodes[field.id].get_meta("state")==key: continue
		if field_nodes.has(field.id): field_nodes[field.id].queue_free()
		var patch = Node3D.new()
		patch.set_meta("state",key)
		add_child(patch)
		patch.position = world_point(data.places[field.id])+Vector3(0,0,-.6)
		field_nodes[field.id] = patch
		Models.box(patch,Vector3(0,.01,0),Vector3(1.75,.08,1.2),"92734f")
		for row in range(4):
			Models.box(patch,Vector3(0,.07,float(row)*.27-.4),Vector3(1.65,.07,.09),"b09262")
			if field.state not in ["empty","sowing","water1","watering1"]:
				for col in range(6):
					var pos = Vector3(float(col)*.27-.67,.22,float(row)*.27-.4)
					Models.cylinder(patch,pos,.055,.02,.31,"d3bb66" if field.state in ["ripe","harvesting"] else "849d52",5)
	actor_data.clear()
	for hero in data.heroes:
		if not hero.has("x"): continue
		actor_data[hero.id] = hero
		if not actors.has(hero.id):
			var model = Models.hero(hero.id,hero.profile)
			add_child(model)
			actors[hero.id] = model
			model.position = world_point(hero)
		var actor = actors[hero.id]
		actor.visible = not hero.get("sleeping",false)
		var tool_kind=""
		if hero.route.is_empty() and hero.cargo=="":
			if hero.get("taskKind","")=="gather": tool_kind="axe" if hero.get("taskResource","")=="wood" else "pickaxe"
			elif hero.motion=="cultivate": tool_kind="hoe"
			elif hero.get("taskKind","")=="build": tool_kind="hammer"
		if actor.get_meta("tool","")!=tool_kind:
			actor.set_meta("tool",tool_kind)
			var arm=actor.get_node("Body/ArmR")
			if arm.has_node("WorkTool"):
				var old=arm.get_node("WorkTool");arm.remove_child(old);old.queue_free()
			if tool_kind!="":
				var tool=Models.tool(tool_kind);tool.name="WorkTool";arm.add_child(tool)
		var cargo_node = actor.get_node("Body/Cargo")
		if cargo_node.get_meta("resource","") != hero.cargo:
			for child in cargo_node.get_children(): child.queue_free()
			cargo_node.set_meta("resource",hero.cargo)
			if hero.cargo != "": cargo_node.add_child(Models.cargo(hero.cargo))
	if structures.has("smelter"):
		structures.smelter.get_node("Fire").visible = data.stations.smelter.phase == "passive"
	if structures.has("kitchen"):
		structures.kitchen.get_node("Fire").visible = data.stations.kitchen.phase in ["prepare","passive","finish"]
	var night = bool(data.night)
	sun.light_energy = .22 if night else .85
	sun.light_color = Color("a6b9cf") if night else Color("fff0cb")
	environment.environment.ambient_light_energy = .25 if night else .4
	environment.environment.background_color = Color("738b89") if night else Color("d8dfce")
	production.sync(data)

func place_building(key: String, model: Node3D, p: Vector3) -> void:
	add_child(model)
	# Shared work-point is a courtyard entrance; the facade sits behind it.
	model.position = p + Vector3(0,0,-.72)
	structures[key] = model

func request(payload: Dictionary) -> void:
	if busy or not clock_owned: return
	busy = true
	bridge_thread = Thread.new()
	bridge_thread.start(Callable(self,"execute_bridge").bind(payload))

func execute_bridge(payload: Dictionary) -> Dictionary:
	var binary = ProjectSettings.globalize_path("res://bin/SanguoLifeCLI")
	var output: Array = []
	var args = ["--godot-request-b64",Marshalls.utf8_to_base64(JSON.stringify(payload))]
	var fixture = OS.get_environment("SANGUO_GODOT_SAVE")
	if fixture != "": args.append_array(["--godot-save",fixture])
	var code = OS.execute(binary,args,output,false)
	if code != 0 or output.is_empty(): return {"ok":false,"error":"经营引擎未连接，请运行 scripts/run-godot.sh。"}
	var parsed = JSON.parse_string(str(output[0]))
	if not parsed is Dictionary: return {"ok":false,"error":"经营引擎返回格式不正确，未应用状态。"}
	if not parsed.get("ok",false): push_warning(str(parsed.get("detail",parsed.get("error","bridge failure"))))
	return parsed

func _process(delta: float) -> void:
	if busy and bridge_thread and not bridge_thread.is_alive():
		var result = bridge_thread.wait_to_finish()
		bridge_thread = null
		busy = false
		if result.get("ok",false):
			snapshot = result
			since_snapshot = 0
			request_error = ""
			sync_scene(snapshot)
			update_hud()
			if result.has("receipt") and result.receipt.get("draws",[]).size()>0: show_results(result.receipt.draws)
			elif current_page == "heroes" and (result.has("receipt") or heroes_refresh_pending): show_heroes()
		else:
			request_error = result.get("error","保存失败，未扣费")
			status_label.text = request_error
			if current_page == "tavern": show_tavern()
			elif current_page == "heroes":
				show_heroes()
				paragraph(request_error,13,Color("a6553e"))
		sync_buttons()
	since_snapshot += delta
	elapsed += delta
	if elapsed >= 1.0 and not busy and not snapshot.is_empty():
		elapsed = 0
		if speed > 0: request({"operation":"advance","seconds":speed})
	var t = Time.get_ticks_msec()/1000.0
	for id in actors:
		if not actor_data.has(id): continue
		var actor = actors[id]
		var info = actor_data[id]
		var target = world_point(info)
		var route: Array = info.route
		if route.size()>=2:
			var clock = minf(float(snapshot.time)+since_snapshot*speed,float(info.due))
			var fraction = clampf((clock-float(info.started))/maxf(1,float(info.due)-float(info.started)),0,1)
			var total = 0.0
			for i in range(route.size()-1): total += world_point(route[i]).distance_to(world_point(route[i+1]))
			var distance = total*fraction
			for i in range(route.size()-1):
				var a = world_point(route[i])
				var b = world_point(route[i+1])
				var length = a.distance_to(b)
				if distance <= length:
					target = a.lerp(b,distance/maxf(.001,length))
					var direction = b-a
					if direction.length()>.01: actor.rotation.y = atan2(direction.x,direction.z)
					break
				distance -= length
		actor.position = target
		var walking = route.size()>=2 and speed>0
		var wave = sin(t*8.0+float(id.hash()%20)) if not reduce_motion else 0.0
		actor.get_node("Body/LegL").rotation.x = wave*.42 if walking else 0.0
		actor.get_node("Body/LegR").rotation.x = -wave*.42 if walking else 0.0
		actor.get_node("Body/ArmL").rotation.x = -wave*.38 if walking else 0.0
		var working = info.motion in ["hammer","chop","cultivate"] and speed>0
		actor.get_node("Body/ArmR").rotation.x = (-.8+wave*.6) if working else (wave*.38 if walking else 0.0)
		actor.get_node("Body").position.y = absf(wave)*.025 if walking else 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		close_modal()
	if modal.visible: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT: dragging=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:
			camera_size=clampf(camera_size-1,10,38);position_camera()
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			camera_size=clampf(camera_size+1,10,38);position_camera()
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var closest = ""
			var distance = 38.0
			for id in actors:
				if not actors[id].visible: continue
				var p = camera.unproject_position(actors[id].position+Vector3(0,.6,0))
				if p.distance_to(event.position)<distance:
					distance=p.distance_to(event.position);closest=id
			if closest != "": selected_hero=closest;show_heroes()
	if event is InputEventMouseMotion and dragging:
		orbit -= event.relative.x*.008
		position_camera()

func _exit_tree() -> void:
	finish_pending_save()

func finish_pending_save() -> void:
	if bridge_thread:
		bridge_thread.wait_to_finish()
		bridge_thread=null
		busy=false

func set_speed(value: int) -> void:
	speed=value
	if speed>0: last_running_speed=speed
	if speed_selector: speed_selector.select([0,1,6,30].find(speed))

func panel_style(color: Color, radius: int = 18) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(20)
	style.border_color = Color("dcd9c4")
	style.set_border_width_all(1)
	return style

func label(text: String, size: int = 16, color: Color = INK) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_color_override("font_color",color)
	node.add_theme_font_size_override("font_size",size)
	return node

func button(text: String, action: Callable, primary: bool = false) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size.y = 42
	b.add_theme_stylebox_override("normal",panel_style(JADE if primary else Color("fcf9ef"),10))
	b.add_theme_stylebox_override("hover",panel_style(Color("547969") if primary else Color("e7eadb"),10))
	b.add_theme_stylebox_override("pressed",panel_style(Color("344f44"),10))
	b.add_theme_stylebox_override("disabled",panel_style(Color("daddce"),10))
	b.add_theme_color_override("font_color",PAPER if primary else INK)
	b.add_theme_color_override("font_hover_color",PAPER if primary else INK)
	b.add_theme_color_override("font_disabled_color",MUTED)
	for state in ["normal","hover","pressed","disabled"]:
		var style = b.get_theme_stylebox(state)
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		style.content_margin_left = 14
		style.content_margin_right = 14
	b.pressed.connect(action)
	return b

func build_ui() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC","Noto Sans CJK SC","Arial"])
	var theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	ui_root.theme = theme
	var heading = VBoxContainer.new()
	heading.position = Vector2(32,26)
	heading.add_theme_constant_override("separation",7)
	ui_root.add_child(heading)
	var title = label("小城志",36)
	var serif = SystemFont.new()
	serif.font_names = PackedStringArray(["Songti SC","Noto Serif CJK SC"])
	title.add_theme_font_override("font",serif)
	heading.add_child(title)
	heading.add_child(label("山 水 之 间   ·   各 有 所 忙",13,MUTED))
	heading.add_child(label("LAYOUT 6  /  桌面大地图",10,MUTED))
	var top = PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.offset_left=-330;top.offset_right=-26;top.offset_top=26;top.offset_bottom=148
	top.add_theme_stylebox_override("panel",panel_style(Color(0.97,0.96,.9,.94)))
	ui_root.add_child(top)
	var top_box = VBoxContainer.new()
	top_box.add_theme_constant_override("separation",8)
	top.add_child(top_box)
	clock_label=label("正在开启小城…",14)
	top_box.add_child(clock_label)
	wallet_label=label("金币由真实采金冶炼获得",13,GOLD)
	top_box.add_child(wallet_label)
	roster_label=label("五位武将，与城同生长",11,MUTED)
	top_box.add_child(roster_label)
	var dock = PanelContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left=26;dock.offset_right=-26;dock.offset_top=-100;dock.offset_bottom=-25
	dock.add_theme_stylebox_override("panel",panel_style(Color(.97,.96,.91,.97)))
	ui_root.add_child(dock)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	dock.add_child(row)
	row.add_child(button("酒馆招募",show_tavern,true))
	row.add_child(button("武将名册",show_heroes))
	row.add_child(button("建筑形态",func(): show_building_preview(1)))
	row.add_child(button("物资小笺",show_resources))
	row.add_child(button("桌面模式",func(): desktop.show_settings()))
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(spacer)
	var speeds = OptionButton.new()
	speed_selector=speeds
	for text in ["暂停观景","原速 1×","演示 6×","快看 30×"]: speeds.add_item(text)
	speeds.select(2)
	speeds.item_selected.connect(func(i): set_speed([0,1,6,30][i]))
	row.add_child(speeds)
	row.add_child(button("归位",func(): orbit=.63;camera_size=25.0;camera_target=Vector3.ZERO;position_camera()))
	var footer=VBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top=-147;footer.offset_left=35;footer.offset_right=-35;footer.offset_bottom=-107
	ui_root.add_child(footer)
	status_label=label("右键拖动旋转 · 滚轮缩放 · 点击武将查看详情",12,INK)
	status_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(status_label)
	footer.add_child(label("玩家招贤与培养，太守安排经营。存档独立，不改旧城。",11,MUTED))
	overlay=ColorRect.new()
	overlay.color=Color(.10,.18,.14,.27)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(overlay)
	overlay.hide()
	modal=PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal.offset_left=-420;modal.offset_right=420;modal.offset_top=-325;modal.offset_bottom=325
	modal.add_theme_stylebox_override("panel",panel_style(PAPER,22))
	ui_root.add_child(modal)
	modal_body=VBoxContainer.new()
	modal_body.add_theme_constant_override("separation",14)
	modal.add_child(modal_body)
	modal.hide()

func update_hud() -> void:
	clock_label.text="第 %d 日  ·  %s" % [int(snapshot.time)/2880+1,"灯火可亲" if snapshot.night else "风和日暖"]
	wallet_label.text="%d 金币   ·   %d 将魂" % [snapshot.coins,snapshot.souls]
	var owned=snapshot.heroes.filter(func(h): return h.star>0).size()
	roster_label.text="%d 位武将  ·  饭食 %d%%  ·  %d 正式床位" % [owned,int(snapshot.food)/100,snapshot.housing]
	if not snapshot.records.is_empty(): status_label.text=snapshot.records[-1].text
	if current_page=="chain": update_gold_chain()

func sync_buttons() -> void:
	for b in get_tree().get_nodes_in_group("paid_action"):
		b.disabled=busy or (int(snapshot.get("coins",0))<int(b.get_meta("cost",0))) or snapshot.get("complete",false)

func open_modal(title: String, page: String) -> void:
	current_page=page
	for child in modal_body.get_children():
		modal_body.remove_child(child);child.queue_free()
	overlay.show();modal.show()
	var header=HBoxContainer.new()
	modal_body.add_child(header)
	var heading=label(title,27)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(button("关闭  ×",close_modal))

func close_modal() -> void:
	modal.hide();overlay.hide();current_page=""

func paragraph(text: String, size: int = 14, color: Color = MUTED) -> Label:
	var p=label(text,size,color)
	p.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	modal_body.add_child(p)
	return p

func issue(operation: String, extra: Dictionary = {}) -> void:
	if busy:
		request_error="正在保存城务，本次操作未执行，请稍后再点一次。"
		paragraph(request_error,12,Color("a6553e"))
		return
	var payload={"operation":operation,"seconds":0,"commandID":Crypto.new().generate_random_bytes(16).hex_encode()}
	payload.merge(extra)
	request(payload)
	sync_buttons()

func show_tavern() -> void:
	if snapshot.is_empty(): return
	open_modal("酒馆招贤", "tavern")
	paragraph("煮一壶酒，等一位同路人。",18,INK)
	add_model_view(Models.building("tavern",2),250)
	paragraph("可用 %d 金币  ·  距离传奇保底还有 %d 抽" % [snapshot.coins,20-int(snapshot.pity)],17,GOLD)
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",16);modal_body.add_child(row)
	for count in [1,10]:
		var b=button("招募一次 · 100金币" if count==1 else "十次招募 · 1000金币",func(): issue("draw",{"count":count}),count==1)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		b.add_to_group("paid_action");b.set_meta("cost",count*100);row.add_child(b)
	sync_buttons()
	paragraph("基础概率：良才70% / 名士25% / 传奇5%。单个角色分别为7% / 约2.0833% / 0.625%；连续19次非传奇，第20次必为传奇。传奇可能重复。",12)
	if request_error!="": paragraph(request_error,13,Color("a6553e"))
	paragraph("常驻30人池，含开局五将；无每日重置、无自动抽卡。",12)
	modal_body.add_child(button("金币从哪里来？看看采金进度",show_gold_chain))

func show_results(draws: Array) -> void:
	open_modal("酒馆来信 · 已保存", "results")
	paragraph("关闭或重开不会改变结果，也不会自动分解重复卡。",13)
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;modal_body.add_child(scroll)
	var list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	for result in draws:
		var definition=snapshot.heroes.filter(func(h): return h.id==result.heroID)[0]
		var text="%s    ·    %s    ·    %s" % [definition.name,rarity(result.rarity),"新武将，30秒后抵达" if result.isNew else "同名重复卡 +1"]
		list.add_child(label(text,18))
		var profiles={"food":"农事与供餐","supply":"采矿与供料","craft":"施工与营造","logistics":"搬运与配送","trade":"仓储与冶炼","guard":"城务与守备"}
		list.add_child(label("专长：%s · %s" % [profiles.get(definition.profile,"日常经营"),"太守会安排住处与工作" if result.isNew else "可手动升星或分解，不增加居民"],13,MUTED))
		list.add_child(HSeparator.new())
	if draws.size()==1:
		var h=snapshot.heroes.filter(func(item): return item.id==draws[0].heroID)[0]
		add_model_view(Models.hero(h.id,h.profile),260,true)
	modal_body.add_child(button("收好来信，回城看看",close_modal,true))

func show_heroes() -> void:
	if snapshot.is_empty(): return
	heroes_refresh_pending = busy
	open_modal("武将名册", "heroes")
	var selector=OptionButton.new()
	var owned=snapshot.heroes.filter(func(h): return int(h.star)>0)
	for i in range(owned.size()):
		selector.add_item(owned[i].name+"  "+"★".repeat(int(owned[i].star)))
		if owned[i].id==selected_hero: selector.select(i)
	selector.item_selected.connect(func(i): selected_hero=owned[i].id;show_heroes())
	modal_body.add_child(selector)
	modal_body.add_child(button("查看专长、星技与实际作用",func(): show_skills(selected_hero)))
	var matches=owned.filter(func(h): return h.id==selected_hero)
	var h=matches[0] if not matches.is_empty() else owned[0]
	selected_hero=h.id
	add_model_view(Models.hero(h.id,h.profile),155,true)
	paragraph("%s  ·  %s  ·  %s" % [h.name,rarity(h.rarity),h.get("action","正在赴城")],17,INK)
	paragraph("%d 星 · 同名卡 %d 张（未锁定 %d）\n1/3/5星解锁技能，2/4星强化。城中工作由太守安排。" % [h.star,h.cards,h.unlockedCards],13)
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",10);modal_body.add_child(row)
	var cost=int(h.star)
	var star_button=button("升一星 · %d 张同名卡" % cost,func(): confirm_action("消耗 %d 张未锁定同名卡，为%s升一星？不可撤销。" % [cost,h.name],func(): issue("star",{"hero":h.id,"target":int(h.star)+1})),true)
	star_button.disabled=busy or int(h.star)>=5 or int(h.unlockedCards)<cost
	row.add_child(star_button)
	var price={"talent":40,"renowned":120,"legend":400}[h.rarity]
	var remaining=0
	for required in range(int(h.star),5): remaining+=required
	remaining=maxi(0,remaining-int(h.cards))
	var exchange_quantity=SpinBox.new();exchange_quantity.min_value=1;exchange_quantity.max_value=maxi(1,mini(10,remaining));exchange_quantity.value=1
	exchange_quantity.custom_minimum_size=Vector2(76,38);row.add_child(exchange_quantity)
	var exchange=button("兑换同名卡",func():
		var quantity=int(exchange_quantity.value)
		confirm_action("花费%d将魂兑换%s同名卡%d张，不自动升星。" % [price*quantity,h.name,quantity],func(): issue("exchange",{"hero":h.id,"count":quantity})))
	exchange.disabled=busy or remaining<=0 or snapshot.souls<price or int(h.star)>=5
	row.add_child(exchange)
	var cards=snapshot.cards.filter(func(c): return c.heroID==h.id)
	var selection_inputs:Array=[]
	for c in cards:
		var card_row=HBoxContainer.new();card_row.add_theme_constant_override("separation",8);modal_body.add_child(card_row)
		card_row.add_child(label("重复卡批次 · %d张%s" % [c.count," · 已锁" if c.locked else ""],13))
		var quantity=SpinBox.new();quantity.min_value=0;quantity.max_value=c.count;quantity.value=0;quantity.editable=not c.locked
		quantity.custom_minimum_size=Vector2(76,34);card_row.add_child(quantity)
		card_row.add_child(button("解锁" if c.locked else "锁定",func(): issue("lock",{"card":c.id,"locked":not c.locked})))
		selection_inputs.append({"card":c,"quantity":quantity})
	if not cards.is_empty():
		modal_body.add_child(button("分解所选卡片",func(): submit_disassembly(h,selection_inputs)))
	paragraph("分解默认不选择任何卡；每批可锁定。未满星卡也能分解，但确认页会提示可能失去升星资格。",11)

func submit_disassembly(hero:Dictionary,inputs:Array) -> void:
	var selected:Array=[]
	var total=0
	for item in inputs:
		var quantity=int(item.quantity.value)
		if quantity>0:
			selected.append({"lotID":item.card.id,"quantity":quantity});total+=quantity
	if selected.is_empty():
		request_error="请先选择要分解的重复卡；默认不会勾选。"
		show_heroes();paragraph(request_error,13,Color("a6553e"));return
	var warning="分解%d张%s重复卡，不可撤销；武将本体始终保留。" % [total,hero.name]
	if int(hero.star)<5 and int(hero.unlockedCards)-total<int(hero.star): warning+=" 分解后可能失去当前升星资格。"
	confirm_action(warning,func(): issue("decompose_batch",{"cards":selected,"confirmed":true}))

func confirm_action(text: String, action: Callable) -> void:
	var dialog=ConfirmationDialog.new()
	dialog.dialog_text=text
	dialog.title="确认手动培养"
	dialog.ok_button_text="确认"
	dialog.cancel_button_text="保留"
	ui_root.add_child(dialog)
	dialog.confirmed.connect(func(): action.call();dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(500,180))

func show_resources() -> void:
	if snapshot.is_empty(): return
	open_modal("物资小笺", "resources")
	paragraph("太守安排采集、运输与冶炼。每1份金锭真实运抵府署，兑换10金币。",16,INK)
	var names={"grain":"食粮","wood":"木材","stone":"石材","iron":"铁料","tools":"器材","meal":"饭菜","gold_ore":"金矿石","gold_ingot":"金锭"}
	for key in names: paragraph("%s    %.1f" % [names[key],float(snapshot.resources.get(key,0))/1000.0],16,INK)
	paragraph("累计铸币：%d。金币不支付建筑与日常生活。" % snapshot.minted,13)
	paragraph("独立存档，不改旧城。收起管理窗口后桌面继续经营；菜单栏退出后才停止模拟。",12)
	modal_body.add_child(button("查看采金与冶炼进度",show_gold_chain))

func show_gold_chain() -> void:
	if snapshot.is_empty(): return
	open_modal("金币的来路", "chain")
	paragraph("采矿、搬运、冶炼、入库——每一步都由真实武将完成。",16,INK)
	chain_labels.clear()
	for title in ["一 · 矿山开采","二 · 矿石运输","三 · 冶炼收锭","四 · 送抵府署"]:
		paragraph(title,18,JADE)
		chain_labels.append(paragraph("",14))
	update_gold_chain()
	var row=HBoxContainer.new();modal_body.add_child(row)
	for entry in [["看看金矿","goldmine"],["看看冶金坊","smelter"],["看看府署","hall"]]:
		row.add_child(button(entry[0],func():
			close_modal();camera_target=world_point(snapshot.places[entry[1]]);camera_size=12;position_camera()))
	paragraph("画面中的矿筐、金锭、炉火只表示实际库存与工序。炉火结束后等待收锭，金锭运到府署才加金币。",12)
	modal_body.add_child(button("去酒馆招募",show_tavern,true))

func update_gold_chain() -> void:
	if chain_labels.size()!=4: return
	var gold=snapshot.get("goldChain",{})
	chain_labels[0].text="%s · 矿区待运 %.1f 份" % ["正在开采" if int(gold.get("mining",0))>0 else "等待太守安排 / 保供优先",float(gold.get("atMine",0))/1000]
	chain_labels[1].text="仓内矿石 %.1f 份 · 在途金矿物资 %.1f 份" % [float(gold.get("atWarehouse",0))/1000,float(gold.get("inTransit",0))/1000]
	var phase=snapshot.stations.smelter.phase
	var phase_text={"idle":"等待物资或调度","prepare":"准备冶炼","passive":"炉火冶炼中","finish":"收取成品","ready":"等待收取成品"}.get(phase,phase)
	chain_labels[2].text="%s · 炉边待运金锭 %.1f 份" % [phase_text,float(gold.get("readyIngots",0))/1000]
	chain_labels[3].text="累计入库金锭 %.1f 份 → %d 金币 · 现在可招募 %d 次" % [float(gold.get("deliveredIngots",0))/1000,int(snapshot.minted),int(snapshot.coins)/100]

func show_skills(hero_id: String) -> void:
	var matches=snapshot.heroes.filter(func(h): return h.id==hero_id)
	if matches.is_empty(): return
	var hero=matches[0]
	open_modal(hero.name+" · 专长与星技", "skills")
	var jobs={"farmer":"农事","cook":"炊煮","server":"供餐","miner":"采矿","logger":"伐木","builder":"营造","smith":"加工","porter":"搬运","courier":"配送","clerk":"仓储","merchant":"贸易","guard":"守备","handyman":"杂务","prefect":"城务"}
	paragraph("太守按城镇需要调度；技能仅在对应工作中生效，不是全城无条件加成。",15,INK)
	for skill in hero.get("skills",[]):
		var unlocked=int(hero.star)>=int(skill.unlockStar)
		paragraph("%d星技能 · %s" % [skill.unlockStar,"已解锁" if unlocked else "待解锁"],18,JADE if unlocked else MUTED)
		if skill.kind=="work_rate":
			var value=int(skill.values[maxi(int(hero.star)-1,int(skill.unlockStar)-1)])
			var names: Array=[]
			for job in skill.jobs: names.append(jobs.get(job,job))
			paragraph("%s：作业效率 +%.1f%%" % [" / ".join(names),float(value)/100],15)
		else:
			var signature={"food":"解锁丰盛饭制作，由具备专长的武将亲自炊煮。","supply":"提高本人完成采集时的实际物资产出。","craft":"开工前进行勘测，为真实建设项目节约材料。","logistics":"提高本人单趟搬运容量，仍需实际走完配送路线。","trade":"本人负责冶炼备料时节省木材燃料。","guard":"本人完成晚巡后提供环境增益，仍需真实巡逻。"}
			paragraph(signature.get(hero.profile,"专属经营能力"),15)
	if hero.has("taskRate"):
		paragraph("当前任务：%s · 作业倍率 %.2f×（含属性、成长及有效加成）" % [hero.action,float(hero.taskRate)/10000],13)
	paragraph("2星、4星强化已有星技；具体加成由经营引擎结算，动画不生产资源。",12)
	modal_body.add_child(button("返回武将培养",show_heroes,true))

func show_building_preview(level: int) -> void:
	open_modal("营造图录 · 建筑形态", "building")
	paragraph("一阶安居，二阶添廊，三阶成楼。",18,INK)
	add_model_view(Models.building("house",level),360)
	var row=HBoxContainer.new();modal_body.add_child(row)
	for i in [1,2,3]:
		var b=button(["一阶 · 民居","二阶 · 回廊","三阶 · 小楼"][i-1],func(): show_building_preview(i),i==level)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(b)
	paragraph("仅比较模型，不修改城镇等级、不消耗资源。真正的扩建与升级仍由太守按物资和人口需求安排。",13)

func add_model_view(model: Node3D, height: int, character: bool = false) -> void:
	var container=SubViewportContainer.new()
	container.custom_minimum_size=Vector2(740,height)
	container.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	container.stretch=true
	container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	modal_body.add_child(container)
	var viewport=SubViewport.new()
	viewport.size=Vector2i(740,height)
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	container.add_child(viewport)
	var root=Node3D.new();viewport.add_child(root)
	root.add_child(model)
	model.rotation.y=-.3
	var env_node=WorldEnvironment.new();var env=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=PAPER
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.4
	env.ambient_light_color=PAPER;env.ambient_light_sky_contribution=0.0
	env_node.environment=env;root.add_child(env_node)
	var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-30,0);light.light_energy=.85;light.shadow_enabled=true;root.add_child(light)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=2.1 if character else 4.3
	root.add_child(cam)
	cam.position=Vector3(2.3,1.8,4) if character else Vector3(4,3.8,5)
	cam.look_at(Vector3(0,.72 if character else 1.2,0));cam.current=true

func rarity(value: String) -> String:
	return {"talent":"良才","renowned":"名士","legend":"传奇"}.get(value,value)
