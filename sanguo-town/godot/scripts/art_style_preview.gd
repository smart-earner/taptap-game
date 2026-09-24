extends Control

# A self-contained visual fixture. It never creates the Swift bridge, opens a
# player save, or advances the economy; the real town uses the same 2D renderer.
const DesktopMap2D=preload("res://scripts/desktop_map_2d.gd")

class PreviewTown extends Node:
	var snapshot: Dictionary={}
	var speed := 2
	var since_snapshot := 0.0
	var visual_walks: Dictionary={}
	var reduce_motion := false

var town: PreviewTown
var map: Control
var toggle_button: Button
var camera_button: Button
var preview_time := 0.0

func _ready() -> void:
	get_window().title="小城志 · 二维美术样板（不使用玩家存档）"
	Engine.max_fps=15
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	town=PreviewTown.new()
	town.snapshot=_sample_snapshot()
	add_child(town)
	map=DesktopMap2D.new()
	map.town=town
	map.show_hud=false
	map.solid_background=true
	map.preview_camera=true
	add_child(map)
	var toolbar=HBoxContainer.new()
	toolbar.anchor_left=1.0
	toolbar.anchor_right=1.0
	toolbar.offset_left=-560
	toolbar.offset_right=-28
	toolbar.offset_top=22
	toolbar.offset_bottom=76
	toolbar.add_theme_constant_override("separation",12)
	add_child(toolbar)
	var caption=Label.new()
	caption.text="二维美术样板 · N 昼夜 / F 镜头"
	caption.add_theme_font_size_override("font_size",16)
	caption.add_theme_color_override("font_color",Color("243f38"))
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	toolbar.add_child(caption)
	toggle_button=Button.new()
	toggle_button.text="看夜景"
	toggle_button.pressed.connect(_toggle_night)
	toolbar.add_child(toggle_button)
	camera_button=Button.new()
	camera_button.text="看全图比例"
	camera_button.pressed.connect(_toggle_camera)
	toolbar.add_child(camera_button)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_N: _toggle_night()
		elif event.keycode==KEY_F: _toggle_camera()

func _process(delta: float) -> void:
	if town.snapshot.night: return
	preview_time+=delta
	var distance=fposmod(preview_time*90.0,880.0)
	var walker_x=125.0+distance if distance<440.0 else 565.0-(distance-440.0)
	town.visual_walks["zhaoyun"]={"position":Vector2(walker_x,1252.5),"moving":true}

func _toggle_night() -> void:
	var night=not bool(town.snapshot.get("night",false))
	town.snapshot.night=night
	town.snapshot.stations.kitchen.phase="idle" if night else "prepare"
	for index in range(town.snapshot.heroes.size()):
		var hero: Dictionary=town.snapshot.heroes[index]
		hero.sleeping=night
		hero.x=125.0 if night else float(hero.get("workX",hero.x))
		hero.y=(1355.0 if index<3 else 1150.0) if night else float(hero.get("workY",hero.y))
	if night: town.visual_walks.clear()
	toggle_button.text="看白天" if night else "看夜景"
	map.queue_redraw()

func _toggle_camera() -> void:
	map.preview_camera=not map.preview_camera
	camera_button.text="看局部" if not map.preview_camera else "看全图比例"
	map.queue_redraw()

func _sample_snapshot() -> Dictionary:
	var plots=[
		{"id":"house-1","kind":"house","level":3,"index":0,"point":{"x":125.0,"y":1355.0},"occupancy":3},
		{"id":"tavern-1","kind":"tavern","level":2,"index":1,"point":{"x":345.0,"y":1355.0}},
		{"id":"workshop-1","kind":"workshop","level":2,"index":2,"point":{"x":565.0,"y":1355.0}},
		{"id":"house-2","kind":"house","level":1,"index":3,"point":{"x":125.0,"y":1150.0},"occupancy":2}
	]
	var heroes=[
		{"id":"xunyu","profile":"civic","star":2,"x":125.0,"y":1355.0,"workX":125.0,"workY":1355.0,"route":[],"motion":"read","taskKind":"administration","cargo":"","sleeping":false},
		{"id":"liubei","profile":"balanced","star":1,"x":345.0,"y":1355.0,"workX":345.0,"workY":1355.0,"route":[],"motion":"hammer","taskKind":"prepare","cargo":"","sleeping":false},
		{"id":"zhangfei","profile":"martial","star":3,"x":565.0,"y":1355.0,"workX":565.0,"workY":1355.0,"route":[],"motion":"hammer","taskKind":"build","cargo":"","sleeping":false},
		{"id":"zhaoyun","profile":"martial","star":1,"x":125.0,"y":1355.0,"workX":125.0,"workY":1355.0,"route":[],"motion":"carry","taskKind":"haul","cargo":"grain","sleeping":false},
		{"id":"huangyueying","profile":"craft","star":2,"x":565.0,"y":1355.0,"workX":565.0,"workY":1355.0,"route":[],"motion":"hammer","taskKind":"build","cargo":"","sleeping":false}
	]
	return {
		"layoutVersion":7,"unlockedGrid":{"columns":4,"rows":3},"parcelRows":["....LLLLLLLL","....LLLLLLLL","....LLLLLLLL","LLLLLLLLLLLL","LLLLLLLLLLLL","LLLLLLLLLLLL","LLLLLLLLLLLL"],
		"parcelByPlotID":{"house-1":0,"tavern-1":1,"workshop-1":2,"house-2":12},
		"plots":plots,"heroes":heroes,"night":false,"time":0,"coins":500,
		"courtyardUnits":{"unit-a":{"plotID":"house-1","occupantHouseholdID":"household-a"},"unit-b":{"plotID":"house-1","occupantHouseholdID":"household-b"},"unit-c":{"plotID":"house-1","occupantHouseholdID":"household-c"},"unit-d":{"plotID":"house-2","occupantHouseholdID":"household-d"},"unit-e":{"plotID":"house-2","occupantHouseholdID":"household-e"}},
		"stations":{"kitchen":{"phase":"prepare"},"smelter":{"phase":"idle"}},
		"projects":[],"fields":[],"places":{},"resources":{},"records":[]
	}
