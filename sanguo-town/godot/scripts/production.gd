extends Node3D

const Models = preload("res://scripts/models.gd")
var town: Node3D
var stock_nodes: Dictionary = {}
var smoke_nodes: Array = []
var last_minted = -1
var smelting = false
var effect_time = 0.0

func initialize(owner_town: Node3D) -> void:
	town=owner_town
	for i in range(5):
		var puff=Models.ball(self,Vector3.ZERO,Vector3.ONE*.25,"c2c4ab")
		puff.visible=false
		puff.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke_nodes.append(puff)

func sync(data: Dictionary) -> void:
	var gold=data.get("goldChain",{})
	var piles=[
		["mine","goldmine","gold_ore",int(gold.get("atMine",0))],
		["warehouse","warehouse","gold_ore",int(gold.get("atWarehouse",0))],
		["furnace","smelter","gold_ingot",int(gold.get("readyIngots",0))]]
	for entry in piles:
		var count=mini(5,int(ceil(float(entry[3])/1000.0)))
		if stock_nodes.has(entry[0]) and stock_nodes[entry[0]].get_meta("count")==count: continue
		if stock_nodes.has(entry[0]): stock_nodes[entry[0]].queue_free()
		var pile=Node3D.new();pile.set_meta("count",count);add_child(pile);stock_nodes[entry[0]]=pile
		pile.position=town.world_point(data.places[entry[1]])+Vector3(.78,.1,.55)
		for i in range(count):
			var load=Models.cargo(entry[2]);pile.add_child(load)
			load.position=Vector3(float(i%3)*.40,float(i/3)*.24,0)
	smelting=data.stations.smelter.phase=="passive"
	for puff in smoke_nodes: puff.visible=smelting
	if last_minted>=0 and int(data.minted)>last_minted:
		var gain=Label3D.new()
		gain.text="+%d 金币" % (int(data.minted)-last_minted)
		gain.font_size=52;gain.pixel_size=.012;gain.modulate=Color("d2a354")
		gain.outline_size=8;gain.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		add_child(gain);gain.position=town.world_point(data.places.hall)+Vector3(0,2.5,0)
		var tween=create_tween().set_parallel(true)
		tween.tween_property(gain,"position:y",gain.position.y+1.1,2.0)
		tween.tween_property(gain,"modulate:a",0.0,2.0)
		tween.chain().tween_callback(gain.queue_free)
	last_minted=int(data.minted)

func _process(delta: float) -> void:
	if not smelting or town.snapshot.is_empty(): return
	if town.speed>0 and not town.reduce_motion: effect_time+=delta
	var origin=town.world_point(town.snapshot.places.smelter)+Vector3(.1,2.1,-.85)
	for i in range(smoke_nodes.size()):
		var phase=fmod(effect_time*.32+float(i)/5.0,1.0)
		smoke_nodes[i].position=origin+Vector3(phase*.32,phase*1.2,0)
		smoke_nodes[i].scale=Vector3.ONE*(.11+.18*sin(phase*PI))
