extends "res://scripts/art_style_preview.gd"

# Review fixture only: 19 canonical plots and the complete 60-person catalog.
# None of these actors, tasks or resources enter the real Swift save.
const CANONICAL_ROSTER=preload("res://scripts/desktop_map_2d.gd").HERO_LOOKS
const PLOT_IDS=[
	"farm-1","farm-2","granary-1","house-1","house-2","hall-1","market-1","station-1",
	"goldmine-1","smelter-1","workshop-1","workshop-2","tavern-1","stable-1","barracks-1","clinic-1",
	"granary-2","house-3","house-4"
]
const PARCELS=[0,2,4,6,12,14,16,18,24,26,28,30,48,50,52,54,60,62,64]

func _ready() -> void:
	super._ready()
	assert(town.snapshot.heroes.size()==60)
	get_window().title="小城志 · 全城二维美术预览（不使用玩家存档）"
	map.preview_camera=false
	camera_button.hide()
	var toolbar: HBoxContainer
	for child in get_children():
		if child is HBoxContainer:
			toolbar=child
			break
	if toolbar:
		toolbar.anchor_top=1.0
		toolbar.anchor_bottom=1.0
		toolbar.offset_top=-88
		toolbar.offset_bottom=-32
		var caption=toolbar.get_child(0) as Label
		if caption: caption.text="全城示意 · N 昼夜"
	map.queue_redraw()

func _process(_delta: float) -> void:
	# The fixture tests still poses and art coverage; the live map owns walking.
	pass

func _sample_snapshot() -> Dictionary:
	var plots: Array=[]
	var parcel_by_plot: Dictionary={}
	for i in range(PLOT_IDS.size()):
		var plot_id=PLOT_IDS[i]
		var kind=plot_id.get_slice("-",0)
		var parcel=PARCELS[i]
		var point=Vector2(125.0+float(parcel%12)*220.0,125.0+float(6-parcel/12)*205.0)
		plots.append({"id":plot_id,"kind":kind,"level":3 if kind in ["house","clinic"] else 2,"index":i,"point":{"x":point.x,"y":point.y},"occupancy":0})
		parcel_by_plot[plot_id]=parcel
	var heroes: Array=[]
	var ids: Array=CANONICAL_ROSTER.keys()
	ids.sort()
	for i in range(ids.size()):
		var plot: Dictionary=plots[i%plots.size()]
		var point: Dictionary=plot.point
		heroes.append({"id":ids[i],"profile":"balanced","star":1,"x":point.x,"y":point.y,"workX":point.x,"workY":point.y,"route":[],"motion":"","taskKind":"","cargo":"","sleeping":false})
	# A few explicit fixture poses exercise state-bound props and the clinic.
	heroes[2].motion="cultivate";heroes[2].taskKind="harvest"
	heroes[8].motion="hammer";heroes[8].taskKind="build"
	heroes[12].motion="carry";heroes[12].taskKind="haul";heroes[12].cargo="grain"
	var clinic_point: Dictionary=plots[15].point
	heroes[5].x=clinic_point.x;heroes[5].y=clinic_point.y
	heroes[5].workX=clinic_point.x;heroes[5].workY=clinic_point.y
	heroes[5].healthCondition="overwork";heroes[5].treatmentPhase="resting";heroes[5].taskKind="clinic_rest"
	heroes[7].x=clinic_point.x;heroes[7].y=clinic_point.y
	heroes[7].workX=clinic_point.x;heroes[7].workY=clinic_point.y
	heroes[7].taskKind="clinic_consult";heroes[7].motion="read"
	var units: Dictionary={}
	for house_id in ["house-1","house-2","house-3","house-4"]:
		for room in range(4):
			units["%s-room-%d" % [house_id,room]]={"plotID":house_id,"occupantHouseholdID":"fixture-%s-%d" % [house_id,room]}
	var rows: Array=[]
	for row in range(7): rows.append("........LLLL" if row<6 else "LLLLLLLLLLLL")
	return {"layoutVersion":7,"unlockedGrid":{"columns":8,"rows":6},"parcelRows":rows,
		"parcelByPlotID":parcel_by_plot,"plots":plots,"heroes":heroes,"night":false,"time":0,"coins":0,
		"courtyardUnits":units,"stations":{"kitchen":{"phase":"idle"},"smelter":{"phase":"idle"}},
		"projects":[],"fields":[],"places":{},"resources":{},"records":[]}

func _toggle_night() -> void:
	var night=not bool(town.snapshot.get("night",false))
	town.snapshot.night=night
	for i in range(town.snapshot.heroes.size()):
		var hero: Dictionary=town.snapshot.heroes[i]
		hero.sleeping=night
		var home: Dictionary=town.snapshot.plots[3+i%2 if i<30 else 17+i%2].point
		hero.x=home.x if night else hero.workX
		hero.y=home.y if night else hero.workY
	toggle_button.text="看白天" if night else "看夜景"
	map.queue_redraw()
