extends Control

# A deliberately flat desktop projection. It reads the same committed snapshot
# as the management window but owns no economy, commands or simulation clock.
var town: Node
var font: Font
var animation_time := 0.0
var ambient_time := 0.0
var drives_visual_walks := false
var is_night := false
var show_hud := true
var solid_background := false
var preview_camera := false

const WORLD_SIZE=Vector2(1920,1080)
const COURTYARD_WORLD_SIZE=Vector2(2640,1535)
const MAP_ZOOM=1.07
const INK=Color("304a40")
const MUTED=Color("66766b")
const GRASS=Color("d6dfbd")
const ROAD=Color("dfc9a0")
const WATER=Color("8ec3b7")
const BANK=Color("b7d1ad")
const TIMBER=Color("806648")
const PLASTER=Color("f2e5c7")
const SHADOW=Color("546954",.17)
const HERO_LOOKS={
	"xunyu":{"coat":"416d72","trim":"cfbe83","head":0,"beard":1,"build":1.0},
	"liubei":{"coat":"648365","trim":"dccc9a","head":1,"beard":1,"build":1.0},
	"zhangfei":{"coat":"8d483b","trim":"c9a36b","head":2,"beard":3,"build":1.23},
	"zhaoyun":{"coat":"c8d8d1","trim":"668d96","head":3,"beard":0,"build":.98},
	"huangyueying":{"coat":"cc9f53","trim":"547f74","head":4,"beard":0,"build":.96},
	# Keep the town projection in step with LifeHeroArt's roster/card identity.
	"liang":{"coat":"b7c4a1","trim":"577a75","head":5,"beard":2,"build":1.0},
	"guanyu":{"coat":"427362","trim":"d1b177","head":2,"beard":4,"build":1.14},
	"lusu":{"coat":"a08566","trim":"dfcb9b","head":0,"beard":2,"build":1.08},
	"caocao":{"coat":"435969","trim":"bf9a5c","head":0,"beard":2,"build":1.08},
	"sunquan":{"coat":"886949","trim":"ddc18b","head":1,"beard":2,"build":1.06},
	"simayi":{"coat":"645b72","trim":"bdbaa1","head":0,"beard":1,"build":.98},
	"guojia":{"coat":"7e9695","trim":"ddd0aa","head":5,"beard":0,"build":.96},
	"jiaxu":{"coat":"72624f","trim":"c5ac7a","head":0,"beard":2,"build":1.0},
	"pangtong":{"coat":"97775d","trim":"c6c7a2","head":5,"beard":3,"build":1.06},
	"xunyou":{"coat":"546e62","trim":"c0b58c","head":0,"beard":1,"build":1.02},
	"chenqun":{"coat":"717d8b","trim":"d7c39b","head":1,"beard":1,"build":1.0},
	"manchong":{"coat":"7b735c","trim":"c6b27c","head":2,"beard":1,"build":1.08},
	"zhangzhao":{"coat":"89795d","trim":"e0d0ad","head":0,"beard":4,"build":.98},
	"zhouyu":{"coat":"a45447","trim":"d8bd83","head":3,"beard":0,"build":1.0},
	"luxun":{"coat":"73a08b","trim":"e2caa0","head":1,"beard":0,"build":.97},
	"lumeng":{"coat":"537b82","trim":"ccad71","head":2,"beard":1,"build":1.1},
	"zhangliao":{"coat":"52738c","trim":"c6bea3","head":3,"beard":2,"build":1.1},
	"xuhuang":{"coat":"9b9c88","trim":"5f796b","head":2,"beard":2,"build":1.12},
	"xiahoudun":{"coat":"556169","trim":"bb9e73","head":3,"beard":2,"build":1.12},
	"xuchu":{"coat":"976449","trim":"dcc088","head":2,"beard":0,"build":1.28},
	"machao":{"coat":"d2d4bf","trim":"a77c4c","head":3,"beard":0,"build":1.06},
	"huangzhong":{"coat":"b78d51","trim":"d9d2b5","head":3,"beard":4,"build":1.1},
	"weiyan":{"coat":"865d50","trim":"b7aa7e","head":2,"beard":2,"build":1.13},
	"ganning":{"coat":"408b89","trim":"d6bc73","head":2,"beard":0,"build":1.06},
	"lvbu":{"coat":"805264","trim":"d0af6e","head":6,"beard":0,"build":1.16},
	"dianwei":{"coat":"6b5547","trim":"d2a979","head":2,"beard":2,"build":1.31},
	"huanggai":{"coat":"8a7658","trim":"dac697","head":3,"beard":4,"build":1.12},
	"taishici":{"coat":"4e7b83","trim":"d3c28e","head":3,"beard":0,"build":1.09},
	"sunce":{"coat":"986746","trim":"e0b875","head":3,"beard":0,"build":1.13},
	"sunshangxiang":{"coat":"ad785b","trim":"e0c5a1","head":4,"beard":0,"build":.99},
	"zhoutai":{"coat":"556f5d","trim":"bea77b","head":2,"beard":2,"build":1.19},
	"chengpu":{"coat":"7a6953","trim":"d3bd92","head":3,"beard":3,"build":1.1},
	"jiangwan":{"coat":"697d72","trim":"d8c7a2","head":0,"beard":1,"build":1.02},
	"feiyi":{"coat":"98a284","trim":"5f7771","head":5,"beard":0,"build":.94},
	"wangping":{"coat":"677b8d","trim":"d0b791","head":2,"beard":1,"build":1.08},
	"dingfeng":{"coat":"8a594b","trim":"d2bd95","head":2,"beard":2,"build":1.07},
	"handang":{"coat":"8c885f","trim":"d9c79e","head":3,"beard":3,"build":1.07},
	"jiangwei":{"coat":"557c76","trim":"d7d2b0","head":3,"beard":0,"build":1.08},
	"dengai":{"coat":"718b80","trim":"d7b98a","head":3,"beard":1,"build":1.05},
	"zhonghui":{"coat":"745f89","trim":"d6c2a2","head":0,"beard":0,"build":.98},
	"liaohua":{"coat":"7b8a64","trim":"d4bd83","head":2,"beard":2,"build":1.07},
	"masu":{"coat":"a38769","trim":"cfccad","head":5,"beard":1,"build":.97},
	"caopi":{"coat":"5b687d","trim":"dab882","head":0,"beard":1,"build":1.04},
	"caoren":{"coat":"596f71","trim":"cbb991","head":3,"beard":2,"build":1.17},
	"caohong":{"coat":"9a7055","trim":"d2c09b","head":2,"beard":1,"build":1.12},
	"yujin":{"coat":"6b7579","trim":"c8c2a7","head":3,"beard":1,"build":1.1},
	"lejin":{"coat":"a16953","trim":"dfc083","head":3,"beard":0,"build":1.05},
	"lidian":{"coat":"748463","trim":"e2ce9d","head":1,"beard":2,"build":1.01},
	"zhanghe":{"coat":"547a83","trim":"d4b9a0","head":3,"beard":1,"build":1.09},
	"xiahouyuan":{"coat":"74715e","trim":"d6b482","head":3,"beard":2,"build":1.13},
	"xusheng":{"coat":"628c80","trim":"e0caa0","head":2,"beard":1,"build":1.08},
	"zhuhuan":{"coat":"955f59","trim":"d3bb96","head":3,"beard":1,"build":1.07},
	"zhugejin":{"coat":"718e88","trim":"decda8","head":0,"beard":2,"build":1.03},
	"buzhi":{"coat":"8b8d72","trim":"d2c2a0","head":5,"beard":1,"build":.98},
	"yangxiu":{"coat":"947580","trim":"e5cba0","head":0,"beard":0,"build":.95}
}
const FALLBACK_COATS=["536f6a","8b7056","68788c","9b6a59","678767","7b6d86","628a85","a3835e"]
const FALLBACK_TRIMS=["d2bc86","d3c7a3","b3cdb8","d8aa79","b7c6a9","cfc0a8"]
const COURTYARD_ROAD_X=[235.0,675.0,1115.0,1555.0,1995.0,2435.0]
const COURTYARD_ROAD_Y=[432.5,740.0,1252.5]
const VISUAL_WALK_SPEED=90.0
const SANDBOX_ROAD_X=[150.0,370.0,590.0,810.0,1030.0,1250.0,1470.0,1690.0]
const SANDBOX_ROAD_Y=[192.0,447.0,702.0,957.0]
const SANDBOX_PLOTS={
	"farm-2":Vector2(260,830),"granary-2":Vector2(480,830),"house-3":Vector2(700,830),"house-4":Vector2(920,830),
	"stable-1":Vector2(1140,830),"station-1":Vector2(1360,830),"barracks-1":Vector2(1580,830),
	"farm-1":Vector2(260,575),"granary-1":Vector2(480,575),"house-1":Vector2(700,575),"house-2":Vector2(920,575),
	"hall-1":Vector2(1140,575),"market-1":Vector2(1360,575),"clinic-1":Vector2(1580,575),
	"goldmine-1":Vector2(260,320),"smelter-1":Vector2(480,320),"tavern-1":Vector2(700,320),
	"workshop-1":Vector2(920,320),"workshop-2":Vector2(1140,320)
}
var display_world_size := WORLD_SIZE

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font=ThemeDB.fallback_font

func _process(delta: float) -> void:
	animation_time += delta
	# The walking clock stays live, but optional environmental motion stops at
	# its current pose when the accessibility setting is enabled.
	if is_instance_valid(town) and town.get("reduce_motion")!=true: ambient_time += delta
	if drives_visual_walks and is_instance_valid(town) and not town.snapshot.is_empty():
		_advance_visual_walks(delta)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(town) or town.snapshot.is_empty(): return
	var data: Dictionary=town.snapshot
	var courtyard_mode=int(data.get("layoutVersion",6))>=7
	display_world_size=COURTYARD_WORLD_SIZE if courtyard_mode else WORLD_SIZE
	# Frame the opened town, not all 84 future parcels. The world coordinates
	# remain unchanged, so roads, workers and the desktop layer still agree.
	var view_size=_opened_view_size(data) if courtyard_mode else display_world_size
	var scale=minf(size.x/view_size.x,size.y/view_size.y)*(1.0 if courtyard_mode else MAP_ZOOM)
	var origin=(size-view_size*scale)*.5
	if preview_camera and courtyard_mode:
		# Art-review close-up only. The live desktop camera remains unchanged.
		scale=minf(size.x/900.0,size.y/520.0)
		origin=size*.5-Vector2(345.0,display_world_size.y-1255.0)*scale
	var night=bool(data.get("night",false))
	is_night=night
	var grass=Color("71877c") if night else GRASS
	# A translucent full-screen ground keeps the wallpaper present while making
	# the city read as one continuous desktop map rather than a floating window.
	draw_rect(Rect2(Vector2.ZERO,size),Color(grass,1.0 if solid_background else 0.72))
	var map_rect=Rect2(origin,display_world_size*scale)
	draw_rect(map_rect,Color(grass,1.0 if solid_background else 0.80))
	if courtyard_mode:
		_draw_courtyard_parcels(data,origin,scale)
	else:
		# Existing layout-6 desktop projection remains available for old snapshots.
		_draw_world_rect(Rect2(1740,0,180,1080),Color(WATER,0.96),origin,scale)
		_draw_world_rect(Rect2(1715,0,25,1080),Color(BANK,0.96),origin,scale)
		for i in range(12):
			var wave_y=fposmod(float(i)*96.0+ambient_time*42.0,1080.0)
			_draw_world_line(Vector2(1768,wave_y),Vector2(1838,wave_y+22),5,Color("d8ebe0",.72),origin,scale)
			_draw_world_line(Vector2(1840,wave_y+38),Vector2(1895,wave_y+55),4,Color("d8ebe0",.58),origin,scale)
		for y in SANDBOX_ROAD_Y:
			_draw_world_line(Vector2(140,y),Vector2(1780,y),26,ROAD,origin,scale)
		for x in SANDBOX_ROAD_X:
			_draw_world_line(Vector2(x,192),Vector2(x,957),26,ROAD,origin,scale)
		_draw_world_line(Vector2(1780,380),Vector2(1900,380),22,ROAD,origin,scale)
		_draw_world_line(Vector2(1780,350),Vector2(1900,350),8,Color("9a7a57"),origin,scale)
		_draw_world_line(Vector2(1780,410),Vector2(1900,410),8,Color("9a7a57"),origin,scale)

	# Stable plots stay authoritative. Unbuilt plots are only quiet planning
	# marks, so the player sees a town rather than an editor grid.
	for plot in data.get("plots",[]):
		if courtyard_mode and not _parcel_unlocked(int(data.get("parcelByPlotID",{}).get(str(plot.id),-1)),data): continue
		var point=_plot_display_point(plot)
		if courtyard_mode and int(plot.level)>0: _draw_courtyard_access(point,str(plot.kind),origin,scale)
		_draw_plot_pad(point,str(plot.kind),int(plot.level)>0,origin,scale)
		if int(plot.level)>0:
			var display_plot=plot.duplicate(true)
			display_plot.point={"x":point.x,"y":point.y}
			_draw_building(display_plot,origin,scale)
	for project in data.get("projects",[]):
		if not bool(project.get("completed",false)):
			_draw_project_site(project,data,origin,scale)
	_draw_workplace_activity(data,origin,scale)

	# Active farm beds come from the engine; unused planned beds stay empty.
	for field in data.get("fields",[]):
		var place=data.get("places",{}).get(field.id,{})
		if place.is_empty(): continue
		var center=_display_world_point(Vector2(float(place.x),float(place.y)))
		_draw_world_rect(Rect2(center-Vector2(12,7),Vector2(24,14)),Color("aa9865"),origin,scale)
		for row in range(4):
			var color=Color("8aa560") if str(field.state) not in ["empty","sowing"] else Color("c5b889")
			_draw_world_line(center+Vector2(-9,-5+row*3.2),center+Vector2(9,-5+row*3.2),2,color,origin,scale)

	# Forest blocks and the eastern shelter belt.
	if courtyard_mode:
		var parcel_rows: Array=data.get("parcelRows",[])
		for row in range(parcel_rows.size()):
			for col in range(12):
				# Undeveloped land is still real terrain, not a washed-out overlay.
				if str(parcel_rows[row])[col]=="L":
					_draw_tree(_parcel_point(row*12+col)+Vector2(18,-14),origin,scale,float(row*12+col)*.43)
	else:
		for i in range(12):
			_draw_tree(Vector2(82+float(i%2)*38,280+float(i/2)*118),origin,scale,float(i)*.43)
		for i in range(8):
			_draw_tree(Vector2(1722,245+float(i)*92),origin,scale,float(i)*.61)

	# At night every hero can legitimately be asleep. Fireflies and chimney
	# smoke keep the desktop alive without inventing workers or production.
	if night:
		for i in range(18):
			var base=Vector2(250+float((i*137)%1320),250+float((i*83)%650))
			var drift=Vector2(sin(ambient_time*.9+float(i))*18.0,cos(ambient_time*.7+float(i)*.71)*12.0)
			var glow=_screen(base+drift,origin,scale)
			var pulse=3.5+sin(ambient_time*4.0+float(i))*1.4
			draw_circle(glow,maxf(2.0,pulse*scale),Color("f0d978",.78))

	# Actual residents only; identity remains in the roster, never overhead.
	var hero_index=0
	var sleeping_slots: Dictionary={}
	var stationary_slots: Dictionary={}
	var clinic_plot: Dictionary={}
	var clinic_patients=0
	for plot in data.get("plots",[]):
		if str(plot.kind)=="clinic" and int(plot.level)>0:
			clinic_plot=plot
			break
	for hero in data.get("heroes",[]):
		if not hero.has("x"): continue
		if bool(hero.get("sleeping",false)):
			var home_key="%d:%d" % [int(hero.x),int(hero.y)]
			var sleep_slot=int(sleeping_slots.get(home_key,0))
			sleeping_slots[home_key]=sleep_slot+1
			_draw_sleeping_resident(_display_world_point(Vector2(float(hero.x),float(hero.y))),sleep_slot,str(hero.get("id","")),origin,scale)
			hero_index+=1
			continue
		var route: Array=hero.get("route",[])
		var visual: Dictionary=town.visual_walks.get(str(hero.get("id","")),{})
		var walking=(bool(visual.get("moving",false)) if courtyard_mode else route.size()>=2) and int(town.speed)>0
		var position: Vector2
		if courtyard_mode and visual.has("position"):
			position=visual.position
		else:
			position=_hero_position(hero)
		if not walking:
			var station_key="%d:%d" % [int(hero.x),int(hero.y)]
			var station_slot=int(stationary_slots.get(station_key,0))
			stationary_slots[station_key]=station_slot+1
			var phase=str(hero.get("treatmentPhase",""))
			if not clinic_plot.is_empty() and str(hero.get("healthCondition",""))!="" and phase in ["waiting_doctor","preparing","treating","rest_ready","resting","finish_ready","finishing"] and Vector2(float(hero.x),float(hero.y)).distance_to(Vector2(float(clinic_plot.point.x),float(clinic_plot.point.y)))<1.0:
				_draw_clinic_patient(_plot_display_point(clinic_plot),clinic_patients,str(hero.get("id","")),origin,scale)
				clinic_patients+=1
				hero_index+=1
				continue
			position+=_stationary_offset(station_slot)
		_draw_hero(position,str(hero.get("id","")),str(hero.get("profile","balanced")),int(hero.get("star",1)),walking,str(hero.get("motion","")),str(hero.get("healthCondition","")),str(hero.get("taskKind","")),str(hero.get("taskResource","")),str(hero.get("cargo","")),origin,scale,float(hero_index)*.83)
		hero_index+=1

	if show_hud: _draw_hud(data,night)

func _screen(world: Vector2,origin: Vector2,scale: float) -> Vector2:
	return origin+Vector2(world.x,display_world_size.y-world.y)*scale

func _opened_view_size(data: Dictionary) -> Vector2:
	var grid: Dictionary=data.get("unlockedGrid",{"columns":8,"rows":5})
	var columns=clampi(int(grid.get("columns",8)),1,12)
	var rows=clampi(int(grid.get("rows",5)),1,7)
	# Include the outer streets and a little landscape around the last parcel.
	return Vector2(minf(COURTYARD_WORLD_SIZE.x,360.0+float(columns)*220.0),minf(COURTYARD_WORLD_SIZE.y,355.0+float(rows)*205.0))

func _plot_display_point(plot: Dictionary) -> Vector2:
	if int(town.snapshot.get("layoutVersion",6))>=7:
		var parcel=int(town.snapshot.get("parcelByPlotID",{}).get(str(plot.id),-1))
		if parcel>=0: return _parcel_point(parcel)
	return SANDBOX_PLOTS.get(str(plot.id),Vector2(float(plot.point.x),float(plot.point.y)))

func _parcel_point(parcel: int) -> Vector2:
	return Vector2(125.0+float(parcel%12)*220.0,125.0+float(6-parcel/12)*205.0)

func _parcel_unlocked(parcel: int,data: Dictionary) -> bool:
	if parcel<0 or parcel>=84: return false
	var grid: Dictionary=data.get("unlockedGrid",{"columns":8,"rows":5})
	return parcel%12<int(grid.get("columns",8)) and parcel/12<int(grid.get("rows",5))

func _draw_courtyard_parcels(data: Dictionary,origin: Vector2,scale: float) -> void:
	# Zoning remains 12×7 in the save, but it is not painted as 84 square tiles.
	# Broad, irregular ground patches read as neighborhoods; narrow continuous
	# streets separate them. An I parcel is open civic ground, never a road tile.
	var patches=[
		[Vector2(390,1170),Vector2(680,340),Color("99b883",.20)],
		[Vector2(1080,1110),Vector2(720,420),Color("e9d6a9",.25)],
		[Vector2(530,520),Vector2(760,530),Color("adc79b",.22)],
		[Vector2(1400,560),Vector2(600,440),Color("e2cba0",.20)],
		[Vector2(2180,1090),Vector2(700,610),Color("a8c5a2",.20)],
		[Vector2(2060,270),Vector2(940,460),Color("b7cfaa",.19)]
	]
	for patch in patches:
		_draw_ground_patch(patch[0],patch[1],patch[2],origin,scale)
	# Sparse ground marks add hand-drawn texture without a per-frame noise pass.
	for mark in range(36):
		var x=75.0+float((mark*347)%2370)
		var y=90.0+float((mark*193)%1360)
		var tint=Color("839e78",.20) if mark%3 else Color("ede3bc",.35)
		_draw_world_line(Vector2(x-7,y),Vector2(x+5,y+2),2,tint,origin,scale)
	var grid: Dictionary=data.get("unlockedGrid",{"columns":8,"rows":5})
	var open_columns=int(grid.get("columns",8))
	var open_rows=int(grid.get("rows",5))
	var open_right=15.0+float(open_columns)*220.0
	var open_bottom=_parcel_point((open_rows-1)*12).y-102.5
	for road_x in COURTYARD_ROAD_X:
		_draw_courtyard_road(Vector2(road_x,36),Vector2(road_x,1498),origin,scale,true)
		if road_x<=open_right:
			_draw_courtyard_road(Vector2(road_x,maxf(36.0,open_bottom)),Vector2(road_x,1498),origin,scale)
	for road_y in COURTYARD_ROAD_Y:
		_draw_courtyard_road(Vector2(28,road_y),Vector2(2612,road_y),origin,scale,true)
		if road_y>=open_bottom:
			_draw_courtyard_road(Vector2(28,road_y),Vector2(minf(2612.0,open_right),road_y),origin,scale)
	if is_night:
		for road_x in COURTYARD_ROAD_X:
			if road_x>open_right: continue
			for road_y in COURTYARD_ROAD_Y:
				if road_y<open_bottom: continue
				var lamp=_screen(Vector2(road_x+22,road_y+17),origin,scale)
				draw_circle(lamp,16*scale,Color("efc67d",.11))
				draw_circle(lamp,4*scale,Color("f4d395",.86))
	# The infrastructure band becomes a planted civic promenade around the
	# central road, with only a few paths and benches rather than paving every lot.
	var rows: Array=data.get("parcelRows",[])
	if rows.size()>3:
		for column in range(12):
			var parcel=3*12+column
			if not _parcel_unlocked(parcel,data): continue
			var point=_parcel_point(parcel)
			if column%2==0:
				_draw_world_rect(Rect2(point+Vector2(-28,51),Vector2(56,8)),Color("a8bd91",.45),origin,scale)
				_draw_world_line(point+Vector2(-20,56),point+Vector2(20,56),3,Color("8c7655",.72),origin,scale)
			else:
				_draw_world_circle(point+Vector2(0,53),22,Color("a9c596",.40),origin,scale)
	var caption="共享院落 · %d×%d 街区开放 / 12×7 全图" % [int(grid.get("columns",8)),int(grid.get("rows",5))]
	draw_string(font,Vector2(34,size.y-58),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("536d5c",.84))

func _draw_ground_patch(center: Vector2,extent: Vector2,color: Color,origin: Vector2,scale: float) -> void:
	var half=extent*.5
	var corners=[
		center+Vector2(-half.x*.88,-half.y*.85),center+Vector2(-half.x*.23,-half.y),
		center+Vector2(half.x*.63,-half.y*.91),center+Vector2(half.x,half.y*.03),
		center+Vector2(half.x*.72,half.y*.87),center+Vector2(-half.x*.18,half.y),
		center+Vector2(-half.x,half.y*.48)
	]
	var polygon=PackedVector2Array()
	for corner in corners: polygon.append(_screen(corner,origin,scale))
	draw_colored_polygon(polygon,color)

func _draw_courtyard_road(a: Vector2,b: Vector2,origin: Vector2,scale: float,planned: bool=false) -> void:
	if planned:
		_draw_world_line(a,b,5,Color("8da58c",.48),origin,scale)
		return
	_draw_world_line(a+Vector2(4,-4),b+Vector2(4,-4),48,SHADOW,origin,scale)
	_draw_world_line(a,b,42,Color("ae926d",.60),origin,scale)
	_draw_world_line(a,b,34,Color("b9aa8b") if is_night else ROAD,origin,scale)
	# Warm irregular stepping-stone marks, not traffic lane markings or a tile grid.
	var length=a.distance_to(b)
	for index in range(1,int(length/96.0)):
		var mark=a.lerp(b,float(index)*96.0/length)
		var side=Vector2(1,0) if absf(a.x-b.x)<1.0 else Vector2(0,1)
		var shift=sin(float(index)*2.71)*4.0
		_draw_world_line(mark-side*(9+shift),mark+side*(7-shift),1.5,Color("b29c76",.43),origin,scale)

func _draw_courtyard_access(point: Vector2,kind: String,origin: Vector2,scale: float) -> void:
	var road_x=_nearest_lane(point.x,COURTYARD_ROAD_X)
	var direction=signf(road_x-point.x)
	var front=point+Vector2(direction*_plot_pad_size(kind).x*.42,0)
	_draw_world_line(front,Vector2(road_x,point.y),14,Color("d2c09a",.72),origin,scale)
	_draw_world_line(front,Vector2(road_x,point.y),9,Color("ede0be"),origin,scale)

func _draw_world_circle(center: Vector2,radius: float,color: Color,origin: Vector2,scale: float) -> void:
	draw_circle(_screen(center,origin,scale),radius*scale,color)

func _display_world_point(world: Vector2) -> Vector2:
	if int(town.snapshot.get("layoutVersion",6))>=7:
		var plots: Array=town.snapshot.get("plots",[])
		for plot in plots:
			var source=Vector2(float(plot.point.x),float(plot.point.y))
			if world.distance_to(source)<1.0: return _plot_display_point(plot)
		for index in range(24):
			var field=Vector2(400+float(index%4)*105,405+float(index/4)*52)
			if world.distance_to(field)<1.0:
				var farm_id="farm-1" if index<12 else "farm-2"
				for plot in plots:
					if str(plot.id)==farm_id:
						return _plot_display_point(plot)+Vector2(-55+float(index%4)*24,-33+float((index%12)/4)*20)
		return Vector2(clampf(world.x/1920.0*2640.0,35.0,2605.0),clampf(world.y/1080.0*1535.0,35.0,1500.0))
	var anchors=[
		[Vector2(570,470),SANDBOX_PLOTS["farm-2"]],[Vector2(580,930),SANDBOX_PLOTS["granary-2"]],
		[Vector2(920,930),SANDBOX_PLOTS["house-3"]],[Vector2(1080,930),SANDBOX_PLOTS["house-4"]],
		[Vector2(1540,470),SANDBOX_PLOTS["stable-1"]],[Vector2(1460,290),SANDBOX_PLOTS["station-1"]],
		[Vector2(1610,740),SANDBOX_PLOTS["barracks-1"]],[Vector2(570,730),SANDBOX_PLOTS["farm-1"]],
		[Vector2(560,550),SANDBOX_PLOTS["granary-1"]],[Vector2(910,760),SANDBOX_PLOTS["house-1"]],
		[Vector2(770,750),SANDBOX_PLOTS["house-2"]],[Vector2(1060,760),SANDBOX_PLOTS["hall-1"]],
		[Vector2(910,550),SANDBOX_PLOTS["market-1"]],[Vector2(1370,930),SANDBOX_PLOTS["clinic-1"]],
		[Vector2(120,290),SANDBOX_PLOTS["goldmine-1"]],[Vector2(1370,400),SANDBOX_PLOTS["smelter-1"]],
		[Vector2(1060,550),SANDBOX_PLOTS["tavern-1"]],[Vector2(1370,540),SANDBOX_PLOTS["workshop-1"]],
		[Vector2(1370,790),SANDBOX_PLOTS["workshop-2"]],
		[Vector2(200,900),Vector2(105,900)],[Vector2(390,160),Vector2(105,440)],
		[Vector2(180,160),Vector2(105,320)],[Vector2(1570,210),Vector2(1760,380)]
	]
	for pair in anchors:
		if world.distance_to(pair[0])<1.0: return pair[1]
	for index in range(24):
		var source=Vector2(400+float(index%4)*105,405+float(index/4)*52)
		if world.distance_to(source)<1.0:
			var farm_center=SANDBOX_PLOTS["farm-1"] if index<12 else SANDBOX_PLOTS["farm-2"]
			var local_index=index%12
			return farm_center+Vector2(-74+float(local_index%4)*27,-48+float(local_index/4)*22)
	return world

func _draw_plot_pad(point: Vector2,kind: String,built: bool,origin: Vector2,scale: float) -> void:
	var pad_size=_plot_pad_size(kind)
	if int(town.snapshot.get("layoutVersion",6))>=7: pad_size*=.85
	var rect=Rect2(point-pad_size*.5,pad_size)
	if int(town.snapshot.get("layoutVersion",6))>=7:
		if not built: return
		var bevel=Vector2(13,10)
		var vertices=[
			Vector2(rect.position.x+bevel.x,rect.position.y),Vector2(rect.end.x-bevel.x,rect.position.y),
			Vector2(rect.end.x,rect.position.y+bevel.y),Vector2(rect.end.x,rect.end.y-bevel.y),
			Vector2(rect.end.x-bevel.x,rect.end.y),Vector2(rect.position.x+bevel.x,rect.end.y),
			Vector2(rect.position.x,rect.end.y-bevel.y),Vector2(rect.position.x,rect.position.y+bevel.y)
		]
		var polygon=PackedVector2Array()
		for vertex in vertices: polygon.append(_screen(vertex,origin,scale))
		draw_colored_polygon(polygon,Color("d4dcb9",.88))
		return
	if built: _draw_world_rect(Rect2(rect.position+Vector2(5,-5),rect.size),Color("6c745d",.12),origin,scale)
	_draw_world_rect(rect,Color("d7ddba",.92 if built else .34),origin,scale)
	_draw_world_outline(rect,Color("99a587",.9 if built else .34),2,origin,scale)
	if built:
		_draw_world_line(Vector2(rect.position.x+13,point.y-pad_size.y*.33),Vector2(rect.end.x-13,point.y-pad_size.y*.33),3,Color("c9bd97",.72),origin,scale)

func _plot_pad_size(kind: String) -> Vector2:
	if kind=="house": return Vector2(190,125)
	if kind=="hall": return Vector2(210,145)
	if kind=="farm": return Vector2(200,150)
	if kind in ["granary","workshop","tavern","clinic"]: return Vector2(175,118)
	return Vector2(160,110)

func _plot_pad_rect(plot: Dictionary) -> Rect2:
	var point=_plot_display_point(plot)
	var pad_size=_plot_pad_size(str(plot.kind))
	return Rect2(point-pad_size*.5,pad_size)

func _draw_world_rect(rect: Rect2,color: Color,origin: Vector2,scale: float) -> void:
	var top_left=_screen(Vector2(rect.position.x,rect.position.y+rect.size.y),origin,scale)
	draw_rect(Rect2(top_left,rect.size*scale),color)

func _draw_world_outline(rect: Rect2,color: Color,width: float,origin: Vector2,scale: float) -> void:
	var top_left=_screen(Vector2(rect.position.x,rect.position.y+rect.size.y),origin,scale)
	draw_rect(Rect2(top_left,rect.size*scale),color,false,maxf(1,width*scale))

func _draw_world_line(a: Vector2,b: Vector2,width: float,color: Color,origin: Vector2,scale: float) -> void:
	draw_line(_screen(a,origin,scale),_screen(b,origin,scale),color,maxf(1,width*scale),true)

func _draw_building(plot: Dictionary,origin: Vector2,scale: float) -> void:
	var p=_screen(Vector2(float(plot.point.x),float(plot.point.y)),origin,scale)
	var kind=str(plot.kind)
	if int(town.snapshot.get("layoutVersion",6))>=7:
		match kind:
			"house": _draw_shared_courtyard(plot,origin,scale)
			"hall": _draw_open_hall(p,scale)
			"farm": _draw_open_farm(p,scale)
			"granary": _draw_open_granary(p,scale)
			"market": _draw_open_market(p,scale)
			"workshop": _draw_open_workshop(p,scale)
			"tavern": _draw_open_tavern(p,scale)
			"stable": _draw_open_stable(p,scale)
			"station": _draw_open_station(p,scale)
			"barracks": _draw_open_barracks(p,scale)
			"goldmine": _draw_open_goldmine(p,scale)
			"smelter": _draw_open_smelter(p,scale)
			"clinic": _draw_open_clinic(p,scale,int(plot.level))
			_: _draw_open_generic(p,scale,_building_title(kind))
		return
	var art_scale=scale*1.22
	var wide=54.0 if kind=="hall" else 43.0
	var body=Rect2(p+Vector2(-wide,-16)*art_scale,Vector2(wide*2,46)*art_scale)
	if kind=="goldmine":
		_draw_mine(Vector2(float(plot.point.x),float(plot.point.y)),origin,scale)
		return
	var plaster=Color("dfd4aa")
	draw_rect(body,plaster)
	draw_rect(body,Color("9ca98d"),false,maxf(1,2*scale))
	var roof_color=Color("607f70") if kind not in ["tavern","smelter"] else Color("a76d4d")
	var roof=PackedVector2Array([
		p+Vector2(-wide-9,-16)*art_scale,p+Vector2(-wide+5,-37)*art_scale,
		p+Vector2(wide-5,-37)*art_scale,p+Vector2(wide+9,-16)*art_scale])
	draw_colored_polygon(roof,roof_color)
	var door=Rect2(p+Vector2(-8,9)*art_scale,Vector2(16,21)*art_scale)
	draw_rect(door,Color("41594d"))
	if kind=="clinic":
		var sign_center=p+Vector2(0,-7)*art_scale
		draw_rect(Rect2(sign_center-Vector2(13,11)*art_scale,Vector2(26,22)*art_scale),Color("f2ecd8"))
		draw_rect(Rect2(sign_center+Vector2(-3,-8)*art_scale,Vector2(6,16)*art_scale),Color("a85b4c"))
		draw_rect(Rect2(sign_center+Vector2(-8,-3)*art_scale,Vector2(16,6)*art_scale),Color("a85b4c"))
	for side in [-1,1]:
		var window_color=Color("efd278") if is_night else Color("90aaa0")
		if is_night: window_color=window_color.lightened((sin(ambient_time*3.2+float(plot.index)+float(side))+1.0)*.06)
		draw_rect(Rect2(p+Vector2(float(side)*25-6,-1)*art_scale,Vector2(12,11)*art_scale),window_color)
	if kind in ["house","hall","tavern"]:
		var chimney=p+Vector2(wide*.55,-32)*art_scale
		draw_rect(Rect2(chimney+Vector2(-3,-8)*art_scale,Vector2(7,13)*art_scale),Color("796b56"))
		for puff in range(3):
			var rise=fposmod(ambient_time*22.0+float(puff)*17.0+float(plot.index)*3.0,52.0)
			var smoke_p=chimney+Vector2(sin(ambient_time*1.8+float(puff))*5.0,-10.0-rise)*art_scale
			draw_circle(smoke_p,(7.0+float(puff)*2.0)*art_scale,Color("e5e5d6",.48-float(puff)*.08))
	var title=_building_title(kind)
	draw_string(font,p+Vector2(-wide,50)*art_scale,title,HORIZONTAL_ALIGNMENT_CENTER,wide*2*art_scale,maxi(10,int(14*scale)),INK)

func _draw_shared_courtyard(plot: Dictionary,origin: Vector2,scale: float) -> void:
	var center=_screen(Vector2(float(plot.point.x),float(plot.point.y)),origin,scale)
	var outer=Rect2(center+Vector2(-82,-61)*scale,Vector2(164,122)*scale)
	draw_rect(Rect2(outer.position+Vector2(5,6)*scale,outer.size),SHADOW)
	draw_rect(outer,Color("e9d6ad"))
	var court=Rect2(center+Vector2(-72,-20)*scale,Vector2(144,70)*scale)
	draw_rect(court,Color("c5d0a7"))
	for step in range(5):
		var stone=center+Vector2(-55+float(step)*28,25+sin(float(step)*2.3)*5)*scale
		draw_circle(stone,5*scale,Color("e9dfbd",.88))
	# Three low walls leave the near side and gate open; this is a floor plan,
	# never a roof covering residents.
	for side in [-1.0,1.0]:
		draw_line(center+Vector2(side*79,-59)*scale,center+Vector2(side*79,54)*scale,TIMBER,maxf(2,6*scale))
	draw_line(center+Vector2(-80,-59)*scale,center+Vector2(80,-59)*scale,TIMBER,maxf(2,7*scale))
	draw_line(center+Vector2(-80,57)*scale,center+Vector2(-18,57)*scale,TIMBER,maxf(2,5*scale))
	draw_line(center+Vector2(18,57)*scale,center+Vector2(80,57)*scale,TIMBER,maxf(2,5*scale))
	var planter=center+Vector2(52,21)*scale
	draw_circle(planter,11*scale,Color("a77b54"))
	draw_circle(planter,8*scale,Color("71966a"))
	draw_circle(planter+Vector2(-4,-3)*scale,4*scale,Color("9fbd82"))
	var count=[0,2,3,4][clampi(int(plot.level),0,3)]
	var occupied=0
	for unit in town.snapshot.get("courtyardUnits",{}).values():
		if str(unit.get("plotID",""))==str(plot.id) and unit.get("occupantHouseholdID")!=null: occupied+=1
	for index in range(count):
		var x=-74.0+float(index)*39.0
		var room=Rect2(center+Vector2(x,-51)*scale,Vector2(34,31)*scale)
		var inhabited=index<occupied
		draw_rect(room,Color("f3e3bf") if inhabited else Color("ded4b1"))
		draw_line(room.position,room.position+Vector2(0,30)*scale,Color("927352"),maxf(1,3*scale))
		draw_line(room.position,room.position+Vector2(34,0)*scale,Color("927352"),maxf(1,3*scale))
		draw_line(room.position+Vector2(34,0)*scale,room.position+Vector2(34,30)*scale,Color("927352"),maxf(1,3*scale))
		var mat=Rect2(room.position+Vector2(4,6)*scale,Vector2(14,9)*scale)
		draw_rect(mat,Color("9eaa89") if inhabited else Color("b5b89f"))
		draw_line(mat.position+Vector2(3,3)*scale,mat.position+Vector2(11,3)*scale,Color("e5dec5"),maxf(1,scale))
		var lantern=room.position+Vector2(27,11)*scale
		if is_night and inhabited: draw_circle(lantern,11*scale,Color("efc779",.23))
		draw_circle(lantern,3*scale,Color("efc779") if is_night and inhabited else Color("a7845d"))
		var curtain=room.position+Vector2(21,30)*scale
		draw_rect(Rect2(curtain,Vector2(11,6)*scale),Color("a77556") if inhabited else Color("b1a48b"))
	var legacy=maxi(0,int(plot.get("occupancy",0))-occupied)
	var label="共居院  %d/%d户" % [occupied,count]
	if legacy>0: label+="  旧住%d" % legacy
	draw_string(font,center+Vector2(-80,-68)*scale,label,HORIZONTAL_ALIGNMENT_CENTER,160*scale,maxi(10,int(14*scale)),INK)

func _draw_open_room_base(p: Vector2,scale: float,floor_tint: Color) -> void:
	var floor=Rect2(p+Vector2(-69,-46)*scale,Vector2(138,92)*scale)
	draw_rect(Rect2(floor.position+Vector2(5,6)*scale,floor.size),SHADOW)
	draw_rect(floor,PLASTER)
	draw_rect(Rect2(p+Vector2(-62,-39)*scale,Vector2(124,77)*scale),floor_tint)
	for side in [-1.0,1.0]:
		draw_line(p+Vector2(side*68,-45)*scale,p+Vector2(side*68,44)*scale,TIMBER,maxf(2,7*scale))
	draw_line(p+Vector2(-69,-45)*scale,p+Vector2(69,-45)*scale,TIMBER,maxf(2,8*scale))
	draw_line(p+Vector2(-69,45)*scale,p+Vector2(-20,45)*scale,TIMBER,maxf(2,6*scale))
	draw_line(p+Vector2(20,45)*scale,p+Vector2(69,45)*scale,TIMBER,maxf(2,6*scale))
	for corner in [-1.0,1.0]:
		draw_circle(p+Vector2(corner*65,-42)*scale,4*scale,Color("ac845b"))

func _draw_open_tavern(p: Vector2,scale: float) -> void:
	_draw_open_room_base(p,scale,Color("e8d0a9"))
	# A preparation counter, round dining tables and visible hearth replace the
	# old sealed roof; steam is added separately only by the real kitchen phase.
	draw_rect(Rect2(p+Vector2(-56,-30)*scale,Vector2(65,15)*scale),Color("9b7150"))
	draw_line(p+Vector2(-53,-27)*scale,p+Vector2(5,-27)*scale,Color("d5a777"),maxf(1,2*scale))
	for bowl in range(3):
		var bowl_p=p+Vector2(-44+float(bowl)*19,-23)*scale
		draw_circle(bowl_p,4*scale,Color("f4e8cd"))
		draw_circle(bowl_p,2*scale,Color("b5764f"))
	var hearth=p+Vector2(41,-21)*scale
	draw_circle(hearth,17*scale,Color("b0936e"))
	draw_circle(hearth,12*scale,Color("5a5d4c"))
	draw_circle(hearth,7*scale,Color("a87045"))
	for table_x in [-29.0,24.0]:
		var table=p+Vector2(table_x,18)*scale
		draw_circle(table+Vector2(2,3)*scale,16*scale,Color("6c5947",.18))
		draw_circle(table,15*scale,Color("a87951"))
		draw_circle(table,11*scale,Color("c79d69"))
		draw_circle(table+Vector2(2,-2)*scale,3*scale,Color("f0e2bd"))
		draw_rect(Rect2(table+Vector2(-5,17)*scale,Vector2(10,5)*scale),Color("806a4f"))
	draw_rect(Rect2(p+Vector2(-67,-53)*scale,Vector2(27,8)*scale),Color("a25e4a"))
	draw_string(font,p+Vector2(-55,-57)*scale,"酒馆",HORIZONTAL_ALIGNMENT_CENTER,110*scale,maxi(11,int(15*scale)),INK)

func _draw_open_workshop(p: Vector2,scale: float) -> void:
	_draw_open_room_base(p,scale,Color("dccca8"))
	var bench=Rect2(p+Vector2(-55,-26)*scale,Vector2(94,18)*scale)
	draw_rect(Rect2(bench.position+Vector2(3,4)*scale,bench.size),SHADOW)
	draw_rect(bench,Color("97714d"))
	for plank in range(3):
		var y=-22.0+float(plank)*5.0
		draw_line(p+Vector2(-50,y)*scale,p+Vector2(34,y)*scale,Color("c49766",.78),maxf(1,scale))
	var anvil=p+Vector2(-28,18)*scale
	draw_rect(Rect2(anvil+Vector2(-15,-2)*scale,Vector2(30,13)*scale),Color("4f6763"))
	draw_rect(Rect2(anvil+Vector2(-7,10)*scale,Vector2(14,8)*scale),Color("59675e"))
	draw_line(anvil+Vector2(-14,0)*scale,anvil+Vector2(14,0)*scale,Color("a7ada0"),maxf(1,2*scale))
	for log_index in range(3):
		var log=p+Vector2(34,14+float(log_index)*10)*scale
		draw_rect(Rect2(log,Vector2(22,7)*scale),Color("b68655"))
		draw_circle(log+Vector2(22,3.5)*scale,4*scale,Color("d2ac77"))
	for peg in range(3):
		var peg_p=p+Vector2(-44+float(peg)*21,-36)*scale
		draw_line(peg_p,peg_p+Vector2(0,11)*scale,Color("556b63"),maxf(1,2*scale))
	draw_string(font,p+Vector2(-55,-57)*scale,"工造院",HORIZONTAL_ALIGNMENT_CENTER,110*scale,maxi(11,int(15*scale)),INK)

func _draw_open_label(p: Vector2,scale: float,title: String) -> void:
	draw_string(font,p+Vector2(-60,-57)*scale,title,HORIZONTAL_ALIGNMENT_CENTER,120*scale,maxi(11,int(15*scale)),INK)

func _draw_open_hall(p: Vector2,scale: float) -> void:
	var s=scale*1.13
	_draw_open_room_base(p,s,Color("d9dfc2"))
	# Long council table and three independent writing places; documents are
	# furniture, while a working hero still needs a real administration task.
	draw_rect(Rect2(p+Vector2(-49,-27)*s,Vector2(98,21)*s),Color("7d694b"))
	draw_line(p+Vector2(-44,-22)*s,p+Vector2(44,-22)*s,Color("ba9e70"),maxf(1,2*s))
	for seat in range(3):
		var x=-31.0+float(seat)*31.0
		draw_rect(Rect2(p+Vector2(x,-18)*s,Vector2(17,10)*s),Color("eee0b9"))
		draw_line(p+Vector2(x+4,-13)*s,p+Vector2(x+12,-13)*s,Color("8b765c"),maxf(1,s))
		draw_rect(Rect2(p+Vector2(x+3,17)*s,Vector2(12,6)*s),Color("9b7b55"))
	var seal=p+Vector2(0,23)*s
	draw_circle(seal,10*s,Color("bc9c6b"))
	draw_circle(seal,6*s,Color("a65d4b"))
	for side in [-1.0,1.0]:
		var shelf=p+Vector2(side*51,5)*s
		draw_line(shelf+Vector2(0,-16)*s,shelf+Vector2(0,21)*s,TIMBER,maxf(1,3*s))
		draw_line(shelf+Vector2(-8,15)*s,shelf+Vector2(8,15)*s,TIMBER,maxf(1,3*s))
	_draw_open_label(p,s,"官署")

func _draw_open_farm(p: Vector2,scale: float) -> void:
	var s=scale*1.12
	_draw_open_room_base(p,s,Color("cbd6a9"))
	# The actual crop sprites are drawn only from snapshot fields. These are
	# permanent bare beds, a well and tool hooks, never a fake harvest.
	for bed in range(3):
		var bed_rect=Rect2(p+Vector2(-54+float(bed)*37,-27)*s,Vector2(29,25)*s)
		draw_rect(bed_rect,Color("ad9469"))
		for furrow in range(3):
			draw_line(bed_rect.position+Vector2(4,6+float(furrow)*6)*s,bed_rect.position+Vector2(25,6+float(furrow)*6)*s,Color("d3b783"),maxf(1,2*s))
	var basin=p+Vector2(39,19)*s
	draw_circle(basin,17*s,Color("967c5d"))
	draw_circle(basin,12*s,Color("7daaa4"))
	for hook in range(2):
		var x=-40.0+float(hook)*23.0
		draw_line(p+Vector2(x,13)*s,p+Vector2(x+5,34)*s,TIMBER,maxf(1,3*s))
		draw_line(p+Vector2(x+1,31)*s,p+Vector2(x+11,31)*s,Color("6e7a66"),maxf(1,2*s))
	_draw_open_label(p,s,"农庄")

func _draw_open_granary(p: Vector2,scale: float) -> void:
	_draw_open_room_base(p,scale,Color("e0d5ae"))
	# Empty wooden compartments stay legible even when the warehouse has zero
	# stock; sacks appear only as a carried lot on a real worker.
	for bin_index in range(3):
		var x=-54.0+float(bin_index)*36.0
		var bin_rect=Rect2(p+Vector2(x,-30)*scale,Vector2(29,30)*scale)
		draw_rect(bin_rect,Color("9e805a"))
		draw_rect(Rect2(bin_rect.position+Vector2(4,5)*scale,Vector2(21,20)*scale),Color("d2bd91"))
		draw_line(bin_rect.position+Vector2(3,24)*scale,bin_rect.position+Vector2(27,24)*scale,Color("735c42"),maxf(1,3*scale))
	for rail in range(2):
		var y=13.0+float(rail)*16.0
		draw_line(p+Vector2(-49,y)*scale,p+Vector2(49,y)*scale,TIMBER,maxf(1,4*scale))
	_draw_open_label(p,scale,"粮仓")

func _draw_open_market(p: Vector2,scale: float) -> void:
	_draw_open_room_base(p,scale,Color("e4d5ae"))
	for stall in range(2):
		var x=-49.0+float(stall)*57.0
		draw_rect(Rect2(p+Vector2(x,-25)*scale,Vector2(42,17)*scale),Color("a67a54"))
		draw_line(p+Vector2(x,-28)*scale,p+Vector2(x+42,-28)*scale,Color("d4a275"),maxf(1,3*scale))
		for leg in [5.0,37.0]:
			draw_line(p+Vector2(x+leg,-8)*scale,p+Vector2(x+leg,2)*scale,TIMBER,maxf(1,3*scale))
		var basket=p+Vector2(x+21,23)*scale
		draw_arc(basket,12*scale,0,PI,12,Color("9e7c58"),maxf(1,3*scale))
		draw_line(basket+Vector2(-11,0)*scale,basket+Vector2(11,0)*scale,Color("9e7c58"),maxf(1,3*scale))
	_draw_open_label(p,scale,"集市")

func _draw_open_stable(p: Vector2,scale: float) -> void:
	_draw_open_room_base(p,scale,Color("d4c49d"))
	for stall in range(3):
		var x=-50.0+float(stall)*34.0
		draw_line(p+Vector2(x,-35)*scale,p+Vector2(x,16)*scale,TIMBER,maxf(1,4*scale))
		draw_rect(Rect2(p+Vector2(x+5,-20)*scale,Vector2(22,12)*scale),Color("8c7656"))
		draw_rect(Rect2(p+Vector2(x+8,-17)*scale,Vector2(16,6)*scale),Color("aa9971"))
	draw_line(p+Vector2(-54,25)*scale,p+Vector2(53,25)*scale,Color("9d8058"),maxf(1,5*scale))
	# No horse silhouette unless an actual animal entity is supplied later.
	_draw_open_label(p,scale,"马厩")

func _draw_open_station(p: Vector2,scale: float) -> void:
	_draw_open_room_base(p,scale,Color("d3dbc0"))
	var table=Rect2(p+Vector2(-49,-26)*scale,Vector2(96,19)*scale)
	draw_rect(table,Color("947758"))
	draw_line(table.position+Vector2(4,4)*scale,table.position+Vector2(91,4)*scale,Color("cab18a"),maxf(1,2*scale))
	var route_board=Rect2(p+Vector2(-35,9)*scale,Vector2(70,24)*scale)
	draw_rect(route_board,Color("ece1bf"))
	draw_rect(route_board,Color("9b896a"),false,maxf(1,2*scale))
	for line_index in range(3):
		draw_line(route_board.position+Vector2(8,6+float(line_index)*6)*scale,route_board.position+Vector2(59,6+float(line_index)*6)*scale,Color("8ba494"),maxf(1,2*scale))
	_draw_open_label(p,scale,"驿站")

func _draw_open_barracks(p: Vector2,scale: float) -> void:
	_draw_open_room_base(p,scale,Color("c7d2b3"))
	var ring=p+Vector2(-20,10)*scale
	draw_arc(ring,22*scale,0,TAU,24,Color("a28b64"),maxf(1,4*scale))
	draw_arc(ring,15*scale,0,TAU,24,Color("d7c79e"),maxf(1,2*scale))
	var target=p+Vector2(39,-12)*scale
	draw_circle(target,17*scale,Color("9b7954"))
	draw_circle(target,12*scale,Color("e4d3ad"))
	draw_circle(target,5*scale,Color("a76550"))
	draw_line(p+Vector2(-53,-29)*scale,p+Vector2(48,-29)*scale,TIMBER,maxf(1,3*scale))
	_draw_open_label(p,scale,"营地")

func _draw_open_goldmine(p: Vector2,scale: float) -> void:
	var ground=Rect2(p+Vector2(-66,-45)*scale,Vector2(132,90)*scale)
	draw_rect(Rect2(ground.position+Vector2(5,6)*scale,ground.size),SHADOW)
	draw_rect(ground,Color("c8c9a5"))
	draw_rect(ground,Color("8d9276"),false,maxf(1,3*scale))
	var pit=p+Vector2(-7,0)*scale
	draw_circle(pit,37*scale,Color("a39f78"))
	draw_circle(pit,28*scale,Color("777d69"))
	draw_circle(pit,19*scale,Color("3e5650"))
	draw_line(p+Vector2(33,-33)*scale,p+Vector2(33,27)*scale,TIMBER,maxf(1,4*scale))
	draw_line(p+Vector2(45,-33)*scale,p+Vector2(45,27)*scale,TIMBER,maxf(1,4*scale))
	for rung in range(4):
		var y=-25.0+float(rung)*15.0
		draw_line(p+Vector2(33,y)*scale,p+Vector2(45,y)*scale,Color("c0a477"),maxf(1,3*scale))
	_draw_open_label(p,scale,"金矿")

func _draw_open_smelter(p: Vector2,scale: float) -> void:
	_draw_open_room_base(p,scale,Color("d7c59f"))
	var furnace=p+Vector2(0,17)*scale
	draw_circle(furnace,25*scale,Color("896c55"))
	draw_circle(furnace,18*scale,Color("544f43"))
	draw_circle(furnace,10*scale,Color("3c514a"))
	for side in [-1.0,1.0]:
		var vent=p+Vector2(side*42,-19)*scale
		draw_rect(Rect2(vent-Vector2(12,10)*scale,Vector2(24,20)*scale),Color("8e7355"))
		draw_line(vent+Vector2(-7,-5)*scale,vent+Vector2(7,-5)*scale,Color("d0ab7a"),maxf(1,2*scale))
	_draw_open_label(p,scale,"冶金坊")

func _draw_open_clinic(p: Vector2,scale: float,level: int) -> void:
	_draw_open_room_base(p,scale,Color("dce0c3"))
	var count=clampi(level,1,3)*2
	for bed in range(count):
		var x=-52.0+float(bed%3)*39.0
		var y=-31.0+float(bed/3)*34.0
		var mat=Rect2(p+Vector2(x,y)*scale,Vector2(31,21)*scale)
		draw_rect(mat,Color("9eaf9c"))
		draw_rect(Rect2(mat.position+Vector2(3,3)*scale,Vector2(25,14)*scale),Color("e8e4cf"))
		draw_rect(Rect2(mat.position+Vector2(4,4)*scale,Vector2(9,5)*scale),Color("b8cab5"))
	var sign=p+Vector2(49,-30)*scale
	draw_circle(sign,10*scale,Color("f2ecd8"))
	draw_line(sign+Vector2(-5,0)*scale,sign+Vector2(5,0)*scale,Color("a46a58"),maxf(1,3*scale))
	draw_line(sign+Vector2(0,-5)*scale,sign+Vector2(0,5)*scale,Color("a46a58"),maxf(1,3*scale))
	_draw_open_label(p,scale,"医舍")

func _draw_open_generic(p: Vector2,scale: float,title: String) -> void:
	_draw_open_room_base(p,scale,Color("d9ddbe"))
	draw_rect(Rect2(p+Vector2(-39,-20)*scale,Vector2(78,31)*scale),Color("a68a62"))
	_draw_open_label(p,scale,title)

func _draw_project_site(project: Dictionary,data: Dictionary,origin: Vector2,scale: float) -> void:
	var point=Vector2.ZERO
	var found=false
	var target_id=str(project.get("targetPlotID",""))
	for plot in data.get("plots",[]):
		if str(plot.id)==target_id:
			point=_plot_display_point(plot);found=true;break
	if not found:
		var place=data.get("places",{}).get(str(project.get("node","")),{})
		if not place.is_empty(): point=_display_world_point(Vector2(float(place.x),float(place.y)));found=true
	if not found: return
	var p=_screen(point,origin,scale)
	var stage=clampi(int(project.get("phase",0)),0,3)
	var total=maxi(1,int(project.get("totalWork",1)))
	var progress=clampi(int(round(float(project.get("completedWork",0))*100.0/float(total))),0,100)
	var site=Rect2(p+Vector2(-56,-36)*scale,Vector2(112,72)*scale)
	draw_rect(site,Color("d8c894",.42))
	draw_rect(site,Color("9c8058",.86),false,maxf(1,2*scale))
	for side in [-1.0,1.0]:
		draw_line(p+Vector2(side*44,30)*scale,p+Vector2(side*44,-23)*scale,Color("876642"),maxf(1,3*scale))
	if stage>=1:
		for x in [-30.0,0.0,30.0]: draw_line(p+Vector2(x,26)*scale,p+Vector2(x,-24)*scale,Color("876642"),maxf(1,4*scale))
	if stage>=2:
		draw_line(p+Vector2(-45,-7)*scale,p+Vector2(45,-7)*scale,Color("765739"),maxf(1,5*scale))
		draw_line(p+Vector2(-45,-24)*scale,p+Vector2(45,-24)*scale,Color("765739"),maxf(1,4*scale))
	if stage>=3:
		draw_line(p+Vector2(-50,-24)*scale,p+Vector2(0,-44)*scale,Color("607b6d"),maxf(1,6*scale))
		draw_line(p+Vector2(0,-44)*scale,p+Vector2(50,-24)*scale,Color("607b6d"),maxf(1,6*scale))
	if bool(project.get("stageStarted",false)) or int(project.get("completedWork",0))>0:
		for i in range(3): draw_line(p+Vector2(-51,18+float(i)*5)*scale,p+Vector2(-25,18+float(i)*5)*scale,Color("9b7145"),maxf(1,3*scale))
	# Only show fresh sawdust when a real builder is working at this project.
	for hero in data.get("heroes",[]):
		if str(hero.get("taskKind",""))!="build" or str(hero.get("taskJob",""))=="carpenter" or bool(hero.get("sleeping",false)) or not hero.get("route",[]).is_empty(): continue
		if not hero.has("x") or int(town.speed)<=0: continue
		var work_point=_display_world_point(Vector2(float(hero.x),float(hero.y)))
		if work_point.distance_to(point)>125.0: continue
		for fleck in range(3):
			var spark=p+Vector2(-23+float(fleck)*20,-10+sin(ambient_time*5.0+float(fleck))*4.0)*scale
			draw_circle(spark,2.0*scale,Color("bd9866",.76))
		break
	draw_string(font,p+Vector2(-52,55)*scale,"营造 %d%%" % progress,HORIZONTAL_ALIGNMENT_CENTER,104*scale,maxi(9,int(12*scale)),MUTED)

func _draw_workplace_activity(data: Dictionary,origin: Vector2,scale: float) -> void:
	var stations: Dictionary=data.get("stations",{})
	var kitchen_phase=str(stations.get("kitchen",{}).get("phase","idle"))
	var smelter_phase=str(stations.get("smelter",{}).get("phase","idle"))
	for plot in data.get("plots",[]):
		if int(plot.level)<=0: continue
		var kind=str(plot.kind)
		var p=_screen(_plot_display_point(plot),origin,scale)
		if kind=="tavern" and kitchen_phase in ["prepare","passive","finish"]:
			for i in range(4):
				var rise=fposmod(ambient_time*26.0+float(i)*14.0,58.0)
				var steam=p+Vector2(35+float(i%2)*12+sin(ambient_time*2.1+float(i))*3.0,-24-rise)*scale
				draw_circle(steam,(5.0+float(i%2)*2.0)*scale,Color("eee9d5",.54))
			for i in range(3):
				draw_arc(p+Vector2(37+float(i)*9,24)*scale,5*scale,0,PI,10,Color("a16f4b"),maxf(1,2*scale))
		elif kind=="smelter" and smelter_phase in ["prepare","passive","finish"]:
			var glow=p+Vector2(0,17)*scale
			draw_circle(glow,(8.0+sin(ambient_time*7.0)*2.0)*scale,Color("e88943",.76))
			for i in range(5):
				var spark=glow+Vector2(sin(ambient_time*5.0+float(i))*15.0,-fposmod(ambient_time*31.0+float(i)*9.0,38.0))*scale
				draw_circle(spark,maxf(1,2*scale),Color("f4c66b",.82))

func _draw_mine(world: Vector2,origin: Vector2,scale: float) -> void:
	var p=_screen(world,origin,scale)
	var ridge=PackedVector2Array([
		p+Vector2(-55,25)*scale,p+Vector2(-38,-17)*scale,
		p+Vector2(-8,-35)*scale,p+Vector2(21,-19)*scale,
		p+Vector2(52,25)*scale])
	draw_colored_polygon(ridge,Color("8b9274"))
	draw_circle(p+Vector2(0,13)*scale,18*scale,Color("394a43"))
	draw_rect(Rect2(p+Vector2(-24,-3)*scale,Vector2(48,7)*scale),Color("6e5439"))
	draw_string(font,p+Vector2(-45,47)*scale,"金矿",HORIZONTAL_ALIGNMENT_CENTER,90*scale,maxi(10,int(14*scale)),INK)

func _building_title(kind: String) -> String:
	return {"hall":"官署","house":"民居","farm":"农庄","granary":"粮仓","market":"集市","workshop":"工造院","tavern":"酒馆","stable":"马厩","station":"驿站","barracks":"营地","goldmine":"金矿","smelter":"冶金坊","clinic":"医舍"}.get(kind,kind)

func _stationary_offset(slot: int) -> Vector2:
	# Simulation nodes identify buildings, not exact chair/workbench positions.
	# Spread poses inside open courtyards; the simulation position is unchanged.
	var columns=[-48.0,-24.0,0.0,24.0,48.0]
	return Vector2(columns[slot%columns.size()],-17.0-float(slot/columns.size())*20.0)

func _hero_position(hero: Dictionary) -> Vector2:
	var target=_display_world_point(Vector2(float(hero.x),float(hero.y)))
	var route: Array=hero.get("route",[])
	if route.size()<2 or int(town.speed)<=0: return target
	var display_route=_sandbox_route(route)
	var started=float(hero.get("started",town.snapshot.get("time",0)))
	var due=float(hero.get("due",started+1))
	var clock=minf(float(town.snapshot.get("time",0))+float(town.since_snapshot),due)
	var fraction=clampf((clock-started)/maxf(1.0,due-started),0.0,1.0)
	var total=0.0
	for i in range(display_route.size()-1): total+=display_route[i].distance_to(display_route[i+1])
	var distance=total*fraction
	for i in range(display_route.size()-1):
		var a: Vector2=display_route[i]
		var b: Vector2=display_route[i+1]
		var length=a.distance_to(b)
		if distance<=length: return a.lerp(b,distance/maxf(.001,length))
		distance-=length
	return target

func _advance_visual_walks(delta: float) -> void:
	if int(town.snapshot.get("layoutVersion",6))<7: return
	var states: Dictionary=town.visual_walks
	var seen: Dictionary={}
	var stationary_slots: Dictionary={}
	var walk_speed=VISUAL_WALK_SPEED*clampf(sqrt(float(maxi(1,int(town.speed)))/2.0),.7,2.0)
	for hero in town.snapshot.get("heroes",[]):
		if not hero.has("x"): continue
		var id=str(hero.get("id",""))
		if id=="": continue
		seen[id]=true
		if bool(hero.get("sleeping",false)):
			states.erase(id)
			continue
		var route: Array=hero.get("route",[])
		var goal=_display_world_point(Vector2(float(hero.x),float(hero.y)))
		var state: Dictionary=states.get(id,{})
		if route.size()>=2 and int(town.speed)>0:
			var signature="%s:%s:%s:%s" % [str(hero.get("started",0)),str(hero.get("due",0)),str(route[-1].x),str(route[-1].y)]
			if state.is_empty() or str(state.get("signature",""))!=signature:
				var finish=_sandbox_route(route)[-1]
				var start: Vector2
				if state.has("position"):
					start=state.position
				else:
					start=_hero_position(hero)
				state={"signature":signature,"position":start,"points":_visual_connection_route(start,finish),"next":1,"moving":true}
			if _step_visual_path(state,walk_speed*delta):
				state.moving=false
			states[id]=state
			continue
		var station_key="%d:%d" % [int(hero.x),int(hero.y)]
		var slot=int(stationary_slots.get(station_key,0))
		stationary_slots[station_key]=slot+1
		goal+=_stationary_offset(slot)
		if state.is_empty(): continue
		if int(town.speed)>0 and bool(state.get("moving",false)):
			if _step_visual_path(state,walk_speed*delta): state.moving=false
		if not bool(state.get("moving",false)) and int(town.speed)>0:
			state.position=(state.position as Vector2).move_toward(goal,walk_speed*delta)
			state.moving=(state.position as Vector2).distance_to(goal)>1.0
		if not bool(state.get("moving",false)):
			states.erase(id)
		else:
			states[id]=state
	for id in states.keys():
		if not seen.has(id): states.erase(id)
	town.visual_walks=states

func _step_visual_path(state: Dictionary,distance: float) -> bool:
	var points: Array=state.get("points",[])
	var next_index=int(state.get("next",1))
	var position: Vector2=state.get("position",Vector2.ZERO)
	while distance>0.0 and next_index<points.size():
		var target: Vector2=points[next_index]
		var remaining=position.distance_to(target)
		if remaining<=distance+0.001:
			position=target
			distance-=remaining
			next_index+=1
		else:
			position=position.move_toward(target,distance)
			distance=0.0
	state.position=position
	state.next=next_index
	return next_index>=points.size()

func _visual_connection_route(start: Vector2,finish: Vector2) -> Array:
	var start_x=_nearest_lane(start.x,COURTYARD_ROAD_X)
	var finish_x=_nearest_lane(finish.x,COURTYARD_ROAD_X)
	var cross_y=_nearest_lane(start.y,COURTYARD_ROAD_Y)
	var candidates=[start,Vector2(start_x,start.y),Vector2(start_x,cross_y),Vector2(finish_x,cross_y),Vector2(finish_x,finish.y),finish]
	var result: Array=[]
	for waypoint in candidates:
		if result.is_empty() or result[-1]!=waypoint: result.append(waypoint)
	return result

func _sandbox_route(route: Array) -> Array:
	var start=_display_world_point(Vector2(float(route[0].x),float(route[0].y)))
	var finish=_display_world_point(Vector2(float(route[-1].x),float(route[-1].y)))
	if int(town.snapshot.get("layoutVersion",6))>=7:
		# A resident appears at the nearest frontage, then remains on the
		# connected street network until reaching the destination frontage.
		var start_x=_nearest_lane(start.x,COURTYARD_ROAD_X)
		var finish_x=_nearest_lane(finish.x,COURTYARD_ROAD_X)
		var start_y=_nearest_lane(start.y,COURTYARD_ROAD_Y)
		var finish_y=_nearest_lane(finish.y,COURTYARD_ROAD_Y)
		var corridor: Array=[Vector2(start_x,start.y),Vector2(start_x,start_y),Vector2(finish_x,start_y),Vector2(finish_x,finish_y),Vector2(finish_x,finish.y)]
		var compact: Array=[]
		for waypoint in corridor:
			if compact.is_empty() or compact[-1]!=waypoint: compact.append(waypoint)
		return compact
	var start_x=_nearest_lane(start.x,SANDBOX_ROAD_X)
	var finish_x=_nearest_lane(finish.x,SANDBOX_ROAD_X)
	var cross_y=_nearest_lane((start.y+finish.y)*.5,SANDBOX_ROAD_Y)
	var candidates: Array=[start,Vector2(start_x,start.y),Vector2(start_x,cross_y),Vector2(finish_x,cross_y),Vector2(finish_x,finish.y),finish]
	var result: Array=[]
	for point in candidates:
		if result.is_empty() or result[-1]!=point: result.append(point)
	return result

func _nearest_lane(value: float,lanes: Array) -> float:
	var nearest=float(lanes[0])
	for lane in lanes:
		if absf(float(lane)-value)<absf(nearest-value): nearest=float(lane)
	return nearest

func _draw_tree(world: Vector2,origin: Vector2,scale: float,phase: float) -> void:
	var p=_screen(world,origin,scale)
	draw_rect(Rect2(p+Vector2(-3,5)*scale,Vector2(6,18)*scale),Color("7d6848"))
	var crown=p+Vector2(sin(ambient_time*1.55+phase)*2.8,0)*scale
	draw_circle(crown,17*scale,Color("668963"))
	draw_circle(crown+Vector2(-9,-3)*scale,12*scale,Color("78996b"))
	draw_circle(crown+Vector2(9,-4)*scale,12*scale,Color("89a46f"))

func _hero_look(hero_id: String,profile: String) -> Dictionary:
	if HERO_LOOKS.has(hero_id): return HERO_LOOKS[hero_id]
	var signature=posmod(hero_id.hash(),FALLBACK_COATS.size()*FALLBACK_TRIMS.size())
	var head=3 if profile=="martial" else (0 if profile in ["command","civic"] else 1+signature%2)
	return {"coat":FALLBACK_COATS[signature%FALLBACK_COATS.size()],"trim":FALLBACK_TRIMS[(signature/FALLBACK_COATS.size())%FALLBACK_TRIMS.size()],"head":head,"beard":signature%4,"build":1.0+float(signature%5-2)*.045}

func _draw_hero(world: Vector2,hero_id: String,profile: String,star: int,walking: bool,motion: String,health_condition: String,task_kind: String,task_resource: String,cargo: String,origin: Vector2,scale: float,phase: float) -> void:
	var step=sin(animation_time*(5.5 if walking else 7.0)+phase) if walking or town.get("reduce_motion")!=true else 0.0
	var working=not walking and (motion in ["hammer","chop","cultivate","carry"] or task_kind in ["eat","prepare","finish","administration","survey"]) and int(town.speed)>0
	var bob=absf(step)*1.8 if walking else (sin(ambient_time*4.5+phase)*.8 if working else 0.0)
	var p=_screen(world,origin,scale)+Vector2(0,-bob)*scale
	var art_scale=scale*(0.80 if int(town.snapshot.get("layoutVersion",6))>=7 else 1.12)
	var look=_hero_look(hero_id,profile)
	var coat=Color(str(look.get("coat","536f6a")))
	var trim=Color(str(look.get("trim","d2bc86")))
	var build=float(look.get("build",1.0))
	var width=11.0*build
	var dark=Color("293e3a")
	var skin=Color("dfb58e")
	# Identity is a stable layered silhouette. Task tools are drawn afterward and
	# never replace coat, headgear, beard or personal accessories.
	draw_circle(p+Vector2(0,24)*art_scale,12*art_scale,SHADOW)
	var leg_swing=step*4.5 if walking else 0.0
	draw_line(p+Vector2(-5,15)*art_scale,p+Vector2(-6-leg_swing,28)*art_scale,dark,maxf(1,4*art_scale))
	draw_line(p+Vector2(5,15)*art_scale,p+Vector2(6+leg_swing,28)*art_scale,dark,maxf(1,4*art_scale))
	var robe_points=PackedVector2Array([
		p+Vector2(-width,-5)*art_scale,p+Vector2(width,-5)*art_scale,
		p+Vector2(width+4,20)*art_scale,p+Vector2(-width-4,20)*art_scale])
	draw_colored_polygon(robe_points,coat)
	var border=robe_points.duplicate()
	border.append(robe_points[0])
	draw_polyline(border,dark,maxf(1,art_scale),true)
	draw_line(p+Vector2(-width+2,5)*art_scale,p+Vector2(width-2,5)*art_scale,trim,maxf(1,3*art_scale))
	draw_line(p+Vector2(0,-4)*art_scale,p+Vector2(0,19)*art_scale,trim.darkened(.15),maxf(1,2*art_scale))
	var arm_swing=step*5.0 if walking else 0.0
	draw_line(p+Vector2(-width,-2)*art_scale,p+Vector2(-width-6-arm_swing,12)*art_scale,coat.darkened(.12),maxf(1,7*art_scale))
	var hand=Vector2(width+6+arm_swing,12)
	if working: hand=Vector2(width+5+step*7,-4+absf(step)*13)
	draw_line(p+Vector2(width,-2)*art_scale,p+hand*art_scale,coat.darkened(.08),maxf(1,7*art_scale))
	draw_circle(p+hand*art_scale,2.7*art_scale,skin)
	draw_circle(p+Vector2(0,-17)*art_scale,8*art_scale,skin)
	for eye in [-3.0,3.0]: draw_circle(p+Vector2(eye,-18)*art_scale,1.0*art_scale,dark)
	var head_kind=int(look.get("head",1))
	match head_kind:
		0:
			var crown=PackedVector2Array([p+Vector2(-9,-23)*art_scale,p+Vector2(-7,-36)*art_scale,p+Vector2(7,-36)*art_scale,p+Vector2(9,-23)*art_scale])
			draw_colored_polygon(crown,dark)
			draw_line(p+Vector2(-10,-25)*art_scale,p+Vector2(10,-25)*art_scale,trim,maxf(1,3*art_scale))
		1:
			draw_circle(p+Vector2(0,-28)*art_scale,6*art_scale,dark)
			draw_line(p+Vector2(-11,-24)*art_scale,p+Vector2(11,-24)*art_scale,trim,maxf(1,3*art_scale))
			draw_line(p+Vector2(-10,-24)*art_scale,p+Vector2(-16,-18)*art_scale,coat,maxf(1,3*art_scale))
		2:
			draw_circle(p+Vector2(0,-29)*art_scale,7*art_scale,dark)
			draw_line(p+Vector2(-12,-25)*art_scale,p+Vector2(12,-25)*art_scale,trim,maxf(1,4*art_scale))
		3:
			var helm=PackedVector2Array([p+Vector2(-11,-22)*art_scale,p+Vector2(-10,-30)*art_scale,p+Vector2(0,-37)*art_scale,p+Vector2(10,-30)*art_scale,p+Vector2(11,-22)*art_scale])
			draw_colored_polygon(helm,coat.darkened(.22))
			draw_line(p+Vector2(0,-34)*art_scale,p+Vector2(0,-44)*art_scale,trim,maxf(1,3*art_scale))
			draw_line(p+Vector2(0,-44)*art_scale,p+Vector2(6,-39)*art_scale,Color("a85d4d"),maxf(1,3*art_scale))
		4:
			draw_circle(p+Vector2(-9,-27)*art_scale,6*art_scale,dark)
			draw_line(p+Vector2(-15,-29)*art_scale,p+Vector2(4,-28)*art_scale,trim,maxf(1,2*art_scale))
			draw_circle(p+Vector2(-15,-29)*art_scale,2*art_scale,Color("659789"))
		5:
			var cap=PackedVector2Array([p+Vector2(-11,-23)*art_scale,p+Vector2(-8,-35)*art_scale,p+Vector2(0,-39)*art_scale,p+Vector2(10,-33)*art_scale,p+Vector2(12,-23)*art_scale])
			draw_colored_polygon(cap,coat.darkened(.2))
			draw_line(p+Vector2(-12,-24)*art_scale,p+Vector2(12,-24)*art_scale,trim,maxf(1,2*art_scale))
		6:
			var helm=PackedVector2Array([p+Vector2(-11,-22)*art_scale,p+Vector2(-10,-30)*art_scale,p+Vector2(0,-37)*art_scale,p+Vector2(10,-30)*art_scale,p+Vector2(11,-22)*art_scale])
			draw_colored_polygon(helm,coat.darkened(.22))
			draw_line(p+Vector2(0,-34)*art_scale,p+Vector2(0,-47)*art_scale,trim,maxf(1,3*art_scale))
			draw_line(p+Vector2(-2,-43)*art_scale,p+Vector2(-15,-54)*art_scale,trim,maxf(1,2*art_scale))
			draw_line(p+Vector2(2,-43)*art_scale,p+Vector2(15,-54)*art_scale,trim,maxf(1,2*art_scale))
	var beard=int(look.get("beard",0))
	if beard>0:
		var beard_length=7.0+float(beard)*3.5
		var beard_shape=PackedVector2Array([p+Vector2(-4,-10)*art_scale,p+Vector2(4,-10)*art_scale,p+Vector2(1,-10+beard_length)*art_scale,p+Vector2(-2,-10+beard_length*.75)*art_scale])
		draw_colored_polygon(beard_shape,Color("d4d1b9") if hero_id in ["huangzhong","zhangzhao"] else dark)
	if hero_id=="xiahoudun":
		draw_line(p+Vector2(-7,-17)*art_scale,p+Vector2(7,-19)*art_scale,dark,maxf(1,2*art_scale))
	if hero_id=="huangyueying":
		draw_rect(Rect2(p+Vector2(-width-9,2)*art_scale,Vector2(9,12)*art_scale),Color("705b42"))
		draw_line(p+Vector2(-width-8,-2)*art_scale,p+Vector2(8,12)*art_scale,trim,maxf(1,2*art_scale))
	if hero_id=="liubei":
		draw_line(p+Vector2(-width,7)*art_scale,p+Vector2(width,7)*art_scale,Color("d4b879"),maxf(1,2*art_scale))
	if star>=3:
		draw_circle(p+Vector2(-width+2,-1)*art_scale,3*art_scale,trim.lightened(.15))
	_draw_activity_prop(p,task_kind,task_resource,cargo,motion,not walking and int(town.speed)>0,art_scale,phase)
	if health_condition!="":
		var badge=p+Vector2(17,-34)*art_scale
		draw_circle(badge,6*art_scale,Color("f2ecd8"))
		draw_rect(Rect2(badge-Vector2(1.5,4)*art_scale,Vector2(3,8)*art_scale),Color("a85b4c"))
		draw_rect(Rect2(badge-Vector2(4,1.5)*art_scale,Vector2(8,3)*art_scale),Color("a85b4c"))

func _draw_activity_prop(p: Vector2,task_kind: String,task_resource: String,cargo: String,motion: String,active: bool,scale: float,phase: float) -> void:
	var beat=sin(animation_time*5.0+phase) if active and town.get("reduce_motion")!=true else 0.0
	if task_kind=="eat":
		var bowl=p+Vector2(13,11)*scale
		draw_arc(bowl,6*scale,0,PI,12,Color("9b6848"),maxf(1,2*scale))
		for i in range(2):
			var drift=sin(ambient_time*2.8+phase+float(i))*2.0
			draw_line(bowl+Vector2(-2+float(i)*4,-3)*scale,bowl+Vector2(drift,-11)*scale,Color("e7e2cb",.76),maxf(1,scale))
	elif cargo!="":
		var cargo_color={"grain":"c6aa58","wood":"856344","stone":"8a9088","iron":"667477","tools":"78644e","gold_ore":"b58c42","gold_ingot":"d6ae49","meal":"b87552"}.get(cargo,"8d7657")
		var load=p+Vector2(12,4+beat*1.5)*scale
		draw_rect(Rect2(load,Vector2(16,14)*scale),Color(cargo_color))
		draw_rect(Rect2(load,Vector2(16,14)*scale),Color("493f33"),false,maxf(1,scale))
		draw_line(load,load+Vector2(16,14)*scale,Color("493f33"),maxf(1,scale))
	elif task_kind=="haul" and active:
		# Loading/unloading is a real assigned task even when no cargo is in hand.
		# An open empty crate shows that work without inventing resources.
		var crate=p+Vector2(13,11-beat*2)*scale
		draw_rect(Rect2(crate,Vector2(16,8)*scale),Color("c5a777"))
		draw_rect(Rect2(crate,Vector2(16,8)*scale),Color("755c42"),false,maxf(1,scale))
		draw_line(crate+Vector2(2,2)*scale,crate+Vector2(14,2)*scale,Color("ead5a9"),maxf(1,scale))
	elif motion=="cultivate" and active:
		var grip=p+Vector2(10,-1)*scale
		var tip=p+Vector2(21+beat*3,23)*scale
		draw_line(grip,tip,Color("795e3e"),maxf(1,3*scale))
		draw_line(tip+Vector2(-5,0)*scale,tip+Vector2(6,1)*scale,Color("64796e"),maxf(1,3*scale))
	elif motion in ["hammer","chop"] and active:
		var grip=p+Vector2(10,5)*scale
		var tip=p+Vector2(20+beat*5,-11+absf(beat)*10)*scale
		draw_line(grip,tip,Color("795e3e"),maxf(1,3*scale))
		var head_color=Color("827e67") if task_resource in ["stone","iron","gold_ore"] else Color("656e60")
		draw_line(tip+Vector2(-6,-2)*scale,tip+Vector2(6,2)*scale,head_color,maxf(1,5*scale))
		if absf(beat)>.82:
			draw_circle(p+Vector2(24,20)*scale,2.5*scale,Color("d6b36b",.76))
	elif motion=="read":
		var scroll=p+Vector2(11,4)*scale
		draw_rect(Rect2(scroll,Vector2(10,12)*scale),Color("e8d7a9"))
		draw_line(scroll+Vector2(3,4)*scale,scroll+Vector2(8,4)*scale,Color("8e7758"),maxf(1,scale))
		draw_line(scroll+Vector2(3,8)*scale,scroll+Vector2(8,8)*scale,Color("8e7758"),maxf(1,scale))

func _draw_sleeping_resident(world: Vector2,slot: int,hero_id: String,origin: Vector2,scale: float) -> void:
	# Sleeping residents remain visible as quiet indoor silhouettes. Slots are
	# deterministic per home, so multiple newly recruited heroes never collapse
	# into one marker and no anonymous resident is invented.
	var column=slot%4
	var row=slot/4
	var p=_screen(world,origin,scale)+Vector2(-27.0+float(column)*18.0,-1.0+float(row)*15.0)*scale
	var blanket=Color(str(_hero_look(hero_id,"balanced").get("coat","536f6a")))
	draw_circle(p+Vector2(0,-4)*scale,3.5*scale,Color("30483f",.72))
	draw_rect(Rect2(p+Vector2(-4,0)*scale,Vector2(8,8)*scale),Color(blanket,.82))
	if slot==0:
		draw_string(font,p+Vector2(31,-8)*scale,"眠",HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(8,int(10*scale)),Color(MUTED,.72))

func _draw_clinic_patient(world: Vector2,slot: int,hero_id: String,origin: Vector2,scale: float) -> void:
	# A real admitted patient occupies one of the clinic's 2/4/6 visible mats.
	var p=_screen(world,origin,scale)+Vector2(-52.0+float(slot%3)*39.0,-31.0+float(slot/3)*34.0)*scale
	var coat=Color(str(_hero_look(hero_id,"balanced").get("coat","536f6a")))
	draw_circle(p+Vector2(7,10)*scale,4*scale,Color("dfb58e"))
	draw_rect(Rect2(p+Vector2(11,7)*scale,Vector2(17,9)*scale),coat)
	draw_line(p+Vector2(13,13)*scale,p+Vector2(25,13)*scale,Color("efe9d7"),maxf(1,scale))

func _draw_hud(data: Dictionary,night: bool) -> void:
	var panel=Rect2(34,30,360,172)
	draw_rect(panel,Color("f6f2df",.92))
	draw_rect(panel,Color("d7d3ba",.9),false,2)
	var day=int(data.get("time",0))/2880+1
	draw_string(font,Vector2(58,70),"第 %d 日 · %s" % [day,"灯火可亲" if night else "风和日暖"],HORIZONTAL_ALIGNMENT_LEFT,-1,24,INK)
	draw_string(font,Vector2(58,108),"%d 金币 · %d 位武将" % [int(data.get("coins",0)),data.get("heroes",[]).filter(func(hero): return int(hero.get("star",0))>0).size()],HORIZONTAL_ALIGNMENT_LEFT,-1,18,INK)
	var records=data.get("records",[])
	var residents=data.get("heroes",[]).filter(func(hero): return int(hero.get("star",0))>0)
	var all_sleeping=not residents.is_empty() and residents.all(func(hero): return bool(hero.get("sleeping",false)))
	var status="夜深休息中 · 天亮后恢复城务" if all_sleeping else ("太守正在安排城务" if records.is_empty() else str(records[-1].text))
	# The transparent secondary window can render long CJK text as fallback boxes
	# when TextServer's constrained ellipsis shaping is used. Clip before drawing.
	var short_status: String=status.left(18)+"…" if status.length()>18 else status
	draw_string(font,Vector2(58,144),short_status,HORIZONTAL_ALIGNMENT_LEFT,-1,15,MUTED)
	var pulse_color=Color("78a66d",.55+.35*(sin(ambient_time*4.5)+1.0)*.5)
	draw_circle(Vector2(64,178),6,pulse_color)
	draw_string(font,Vector2(78,184),"城务时钟 %d× 运行中" % int(town.speed),HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)
	draw_string(font,Vector2(34,size.y-34),_resource_summary(data),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(MUTED,.82))

func _resource_summary(data: Dictionary) -> String:
	var resources: Dictionary=data.get("resources",{})
	return "金币 %d  ·  粮 %.1f  ·  木 %.1f  ·  石 %.1f  ·  铁 %.1f  ·  工具 %.1f  ·  空闲 %d 人" % [int(data.get("coins",0)),float(resources.get("grain",0))/1000.0,float(resources.get("wood",0))/1000.0,float(resources.get("stone",0))/1000.0,float(resources.get("iron",0))/1000.0,float(resources.get("tools",0))/1000.0,int(data.get("idlePersonnel",0))]
