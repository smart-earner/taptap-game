extends SceneTree

class FakeTown extends Node:
	var snapshot: Dictionary={}
	var speed := 2
	var since_snapshot := 0.0
	var visual_walks: Dictionary={}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var town=FakeTown.new()
	town.snapshot={
		"layoutVersion":7,
		"unlockedGrid":{"columns":8,"rows":5},
		"parcelByPlotID":{"house-1":14,"farm-1":0},
		"plots":[
			{"id":"house-1","kind":"house","level":1,"point":{"x":910.0,"y":760.0}},
			{"id":"farm-1","kind":"farm","level":1,"point":{"x":570.0,"y":730.0}}
		]
	}
	root.add_child(town)
	var map=load("res://scripts/desktop_map_2d.gd").new()
	map.town=town
	root.add_child(map)
	assert(map._parcel_unlocked(14,town.snapshot))
	assert(not map._parcel_unlocked(20,town.snapshot))
	var route=map._sandbox_route([
		{"x":910.0,"y":760.0},{"x":570.0,"y":730.0}
	])
	assert(route.size()>=3)
	for index in range(route.size()-1):
		var a: Vector2=route[index]
		var b: Vector2=route[index+1]
		if is_equal_approx(a.x,b.x):
			assert(map.COURTYARD_ROAD_X.has(a.x))
		else:
			assert(is_equal_approx(a.y,b.y))
			assert(map.COURTYARD_ROAD_Y.has(a.y))
	town.snapshot.heroes=[{
		"id":"walker","x":910.0,"y":760.0,"started":0,"due":20,
		"route":[{"x":910.0,"y":760.0},{"x":570.0,"y":730.0}]
	}]
	town.snapshot.time=0
	map._advance_visual_walks(.1)
	var first: Vector2=town.visual_walks.walker.position
	map._advance_visual_walks(.1)
	var second: Vector2=town.visual_walks.walker.position
	assert(first.distance_to(second)<=map.VISUAL_WALK_SPEED*.1+.001)
	town.snapshot.heroes[0].route=[]
	town.snapshot.heroes[0].x=570.0
	town.snapshot.heroes[0].y=730.0
	map._advance_visual_walks(.1)
	assert(town.visual_walks.has("walker"))
	assert((town.visual_walks.walker.position as Vector2).distance_to(second)<=map.VISUAL_WALK_SPEED*.1+.001)
	for i in range(300): map._advance_visual_walks(.1)
	assert(not town.visual_walks.has("walker"))
	print("ROAD_LAYOUT_PASS: walkers stay on streets and move at a capped visual speed without teleporting at task completion")
	map.queue_free()
	town.queue_free()
	await process_frame
	quit(0)
