extends Control

# A deliberately flat desktop projection. It reads the same committed snapshot
# as the management window but owns no economy, commands or simulation clock.
var town: Node
var font: Font
var animation_time := 0.0
var is_night := false
var show_hud := true
var solid_background := false

const WORLD_SIZE=Vector2(1920,1080)
const INK=Color("27443b")
const MUTED=Color("66776b")
const GRASS=Color("dfe9bd")
const ROAD=Color("e4d3a9")
const WATER=Color("8ec3b7")
const BANK=Color("b7d1ad")

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font=ThemeDB.fallback_font

func _process(delta: float) -> void:
	animation_time += delta
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(town) or town.snapshot.is_empty(): return
	var data: Dictionary=town.snapshot
	var scale=minf(size.x/WORLD_SIZE.x,size.y/WORLD_SIZE.y)
	var origin=(size-WORLD_SIZE*scale)*.5
	var night=bool(data.get("night",false))
	is_night=night
	var grass=Color("829483") if night else GRASS
	# A translucent full-screen ground keeps the wallpaper present while making
	# the city read as one continuous desktop map rather than a floating window.
	draw_rect(Rect2(Vector2.ZERO,size),Color(grass,1.0 if solid_background else 0.90))
	var map_rect=Rect2(origin,WORLD_SIZE*scale)
	draw_rect(map_rect,Color(grass,1.0 if solid_background else 0.98))

	# River, bank and the fixed bridge side of the city.
	_draw_world_rect(Rect2(1740,0,180,1080),Color(WATER,0.96),origin,scale)
	_draw_world_rect(Rect2(1715,0,25,1080),Color(BANK,0.96),origin,scale)
	# Flowing highlights make it immediately clear that this is a living view,
	# without changing water or economic state in the simulation.
	for i in range(12):
		var wave_y=fposmod(float(i)*96.0+animation_time*42.0,1080.0)
		_draw_world_line(Vector2(1768,wave_y),Vector2(1838,wave_y+22),5,Color("d8ebe0",.72),origin,scale)
		_draw_world_line(Vector2(1840,wave_y+38),Vector2(1895,wave_y+55),4,Color("d8ebe0",.58),origin,scale)

	# Authoritative layout6 roads.
	for y in [200.0,380.0,640.0,840.0,1000.0]:
		_draw_world_line(Vector2(140,y),Vector2(1780,y),26,ROAD,origin,scale)
	for x in [140.0,680.0,1200.0,1780.0]:
		_draw_world_line(Vector2(x,200),Vector2(x,1000),26,ROAD,origin,scale)
	# The mine is an intentional western outpost, connected to the city instead
	# of looking like a building that slipped outside the map.
	_draw_world_line(Vector2(120,290),Vector2(140,290),18,ROAD,origin,scale)
	_draw_world_line(Vector2(1780,380),Vector2(1900,380),22,ROAD,origin,scale)
	_draw_world_line(Vector2(1780,350),Vector2(1900,350),8,Color("9a7a57"),origin,scale)
	_draw_world_line(Vector2(1780,410),Vector2(1900,410),8,Color("9a7a57"),origin,scale)

	# Stable plots stay authoritative. Unbuilt plots are only quiet planning
	# marks, so the player sees a town rather than an editor grid.
	for plot in data.get("plots",[]):
		var point=Vector2(float(plot.point.x),float(plot.point.y))
		if int(plot.level)>0:
			_draw_world_rect(Rect2(point-Vector2(58,38),Vector2(116,76)),Color("d5dcba"),origin,scale)
			_draw_world_outline(Rect2(point-Vector2(58,38),Vector2(116,76)),Color("a7b491"),2,origin,scale)
			_draw_building(plot,origin,scale)
		else:
			_draw_world_rect(Rect2(point-Vector2(34,20),Vector2(68,40)),Color("d6dfbd",.45),origin,scale)

	# Active farm beds come from the engine; unused planned beds stay empty.
	for field in data.get("fields",[]):
		var place=data.get("places",{}).get(field.id,{})
		if place.is_empty(): continue
		var center=Vector2(float(place.x),float(place.y))
		_draw_world_rect(Rect2(center-Vector2(42,24),Vector2(84,48)),Color("aa9865"),origin,scale)
		for row in range(4):
			var color=Color("8aa560") if str(field.state) not in ["empty","sowing"] else Color("c5b889")
			_draw_world_line(center+Vector2(-35,-17+row*11),center+Vector2(35,-17+row*11),5,color,origin,scale)

	# Forest blocks and the eastern shelter belt.
	for i in range(24):
		_draw_tree(Vector2(205+float(i%6)*42,875+float(i/6)*39),origin,scale,float(i)*.43)
	for i in range(8):
		_draw_tree(Vector2(1640,245+float(i)*92),origin,scale,float(i)*.61)

	# At night every hero can legitimately be asleep. Fireflies and chimney
	# smoke keep the desktop alive without inventing workers or production.
	if night:
		for i in range(18):
			var base=Vector2(250+float((i*137)%1320),250+float((i*83)%650))
			var drift=Vector2(sin(animation_time*.9+float(i))*18.0,cos(animation_time*.7+float(i)*.71)*12.0)
			var glow=_screen(base+drift,origin,scale)
			var pulse=3.5+sin(animation_time*4.0+float(i))*1.4
			draw_circle(glow,maxf(2.0,pulse*scale),Color("f0d978",.78))

	# Actual residents only; identity remains in the roster, never overhead.
	var hero_index=0
	for hero in data.get("heroes",[]):
		if not hero.has("x") or bool(hero.get("sleeping",false)): continue
		var route: Array=hero.get("route",[])
		var walking=route.size()>=2 and int(town.speed)>0
		_draw_hero(_hero_position(hero),str(hero.get("profile","balanced")),walking,str(hero.get("motion","")),origin,scale,float(hero_index)*.83)
		hero_index+=1

	if show_hud: _draw_hud(data,night)

func _screen(world: Vector2,origin: Vector2,scale: float) -> Vector2:
	return origin+Vector2(world.x,WORLD_SIZE.y-world.y)*scale

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
	var wide=54.0 if kind=="hall" else 43.0
	var body=Rect2(p+Vector2(-wide,-16)*scale,Vector2(wide*2,46)*scale)
	if kind=="goldmine":
		_draw_mine(Vector2(float(plot.point.x),float(plot.point.y)),origin,scale)
		return
	var plaster=Color("dfd4aa")
	draw_rect(body,plaster)
	draw_rect(body,Color("9ca98d"),false,maxf(1,2*scale))
	var roof_color=Color("607f70") if kind not in ["tavern","smelter"] else Color("a76d4d")
	var roof=PackedVector2Array([
		p+Vector2(-wide-9,-16)*scale,p+Vector2(-wide+5,-37)*scale,
		p+Vector2(wide-5,-37)*scale,p+Vector2(wide+9,-16)*scale])
	draw_colored_polygon(roof,roof_color)
	var door=Rect2(p+Vector2(-8,9)*scale,Vector2(16,21)*scale)
	draw_rect(door,Color("41594d"))
	for side in [-1,1]:
		var window_color=Color("efd278") if is_night else Color("90aaa0")
		if is_night: window_color=window_color.lightened((sin(animation_time*3.2+float(plot.index)+float(side))+1.0)*.06)
		draw_rect(Rect2(p+Vector2(float(side)*25-6,-1)*scale,Vector2(12,11)*scale),window_color)
	if kind in ["house","hall","tavern"]:
		var chimney=p+Vector2(wide*.55,-32)*scale
		draw_rect(Rect2(chimney+Vector2(-3,-8)*scale,Vector2(7,13)*scale),Color("796b56"))
		for puff in range(3):
			var rise=fposmod(animation_time*22.0+float(puff)*17.0+float(plot.index)*3.0,52.0)
			var smoke_p=chimney+Vector2(sin(animation_time*1.8+float(puff))*5.0,-10.0-rise)*scale
			draw_circle(smoke_p,(7.0+float(puff)*2.0)*scale,Color("e5e5d6",.48-float(puff)*.08))
	var title=_building_title(kind)
	draw_string(font,p+Vector2(-wide,47)*scale,title,HORIZONTAL_ALIGNMENT_CENTER,wide*2*scale,maxi(10,int(14*scale)),INK)

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
	return {"hall":"官署","house":"民居","farm":"农庄","granary":"粮仓","market":"集市","workshop":"工造院","tavern":"酒馆","stable":"马厩","station":"驿站","barracks":"营地","goldmine":"金矿","smelter":"冶金坊"}.get(kind,kind)

func _hero_position(hero: Dictionary) -> Vector2:
	var target=Vector2(float(hero.x),float(hero.y))
	var route: Array=hero.get("route",[])
	if route.size()<2 or int(town.speed)<=0: return target
	var started=float(hero.get("started",town.snapshot.get("time",0)))
	var due=float(hero.get("due",started+1))
	var clock=minf(float(town.snapshot.get("time",0))+float(town.since_snapshot)*float(town.speed),due)
	var fraction=clampf((clock-started)/maxf(1.0,due-started),0.0,1.0)
	var total=0.0
	for i in range(route.size()-1):
		total+=Vector2(float(route[i].x),float(route[i].y)).distance_to(Vector2(float(route[i+1].x),float(route[i+1].y)))
	var distance=total*fraction
	for i in range(route.size()-1):
		var a=Vector2(float(route[i].x),float(route[i].y))
		var b=Vector2(float(route[i+1].x),float(route[i+1].y))
		var length=a.distance_to(b)
		if distance<=length: return a.lerp(b,distance/maxf(.001,length))
		distance-=length
	return target

func _draw_tree(world: Vector2,origin: Vector2,scale: float,phase: float) -> void:
	var p=_screen(world,origin,scale)
	draw_rect(Rect2(p+Vector2(-3,5)*scale,Vector2(6,18)*scale),Color("7d6848"))
	var crown=p+Vector2(sin(animation_time*1.55+phase)*2.8,0)*scale
	draw_circle(crown,17*scale,Color("668963"))
	draw_circle(crown+Vector2(-9,-3)*scale,12*scale,Color("78996b"))
	draw_circle(crown+Vector2(9,-4)*scale,12*scale,Color("89a46f"))

func _draw_hero(world: Vector2,profile: String,walking: bool,motion: String,origin: Vector2,scale: float,phase: float) -> void:
	var step=sin(animation_time*9.0+phase)
	var working=motion in ["hammer","chop","cultivate"] and int(town.speed)>0
	var bob=absf(step)*2.0 if walking else (sin(animation_time*5.0+phase)*1.2 if working else 0.0)
	var p=_screen(world,origin,scale)+Vector2(0,-bob)*scale
	var robe={"command":"4d6b63","martial":"6f6046","civic":"627568","craft":"775f4f","balanced":"536c62"}.get(profile,"536c62")
	draw_circle(p+Vector2(0,-12)*scale,7*scale,Color("d5a66d"))
	draw_rect(Rect2(p+Vector2(-7,-5)*scale,Vector2(14,21)*scale),Color(robe))
	draw_rect(Rect2(p+Vector2(-8,-21)*scale,Vector2(16,6)*scale),Color("263d39"))
	var leg_swing=step*5.0 if walking else 0.0
	draw_line(p+Vector2(-4,16)*scale,p+Vector2(-5-leg_swing,26)*scale,Color("293e38"),maxf(1,3*scale))
	draw_line(p+Vector2(4,16)*scale,p+Vector2(5+leg_swing,26)*scale,Color("293e38"),maxf(1,3*scale))
	var arm_swing=step*6.0 if walking else 0.0
	draw_line(p+Vector2(-7,0)*scale,p+Vector2(-11-arm_swing,12)*scale,Color(robe),maxf(1,3*scale))
	var hand=Vector2(13+arm_swing,10)
	if working: hand=Vector2(11+step*8,-6+absf(step)*12)
	draw_line(p+Vector2(7,0)*scale,p+hand*scale,Color(robe),maxf(1,3*scale))

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
	draw_string(font,Vector2(58,144),status,HORIZONTAL_ALIGNMENT_LEFT,305,15,MUTED,TextServer.JUSTIFICATION_CONSTRAIN_ELLIPSIS)
	var pulse_color=Color("78a66d",.55+.35*(sin(animation_time*4.5)+1.0)*.5)
	draw_circle(Vector2(64,178),6,pulse_color)
	draw_string(font,Vector2(78,184),"城务时钟 %d× 运行中" % int(town.speed),HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)
