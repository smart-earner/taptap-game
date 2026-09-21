class_name TownModels
extends RefCounted

# Procedural low-poly mesh assets, with independent nodes for replacing them with glTF later.
static var materials: Dictionary = {}
static var meshes: Dictionary = {}
const TIMBER = "795c40"
const TILE = "406f68"
const PLASTER = "e8d9b5"
const INK = "293e38"

static func material(hex: String, glow: bool = false) -> StandardMaterial3D:
	var key = hex + str(glow)
	if materials.has(key): return materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 0.88
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		m.emission_enabled = true
		m.emission = Color(hex)
		m.emission_energy_multiplier = 1.25
	materials[key] = m
	return m

static func mesh_node(parent: Node3D, mesh: Mesh, pos: Vector3, size: Vector3, hex: String, glow: bool = false) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = material(hex, glow)
	n.position = pos
	n.scale = size
	parent.add_child(n)
	return n

static func box(parent: Node3D, pos: Vector3, size: Vector3, hex: String, glow: bool = false) -> MeshInstance3D:
	if not meshes.has("box"): meshes["box"] = BoxMesh.new()
	return mesh_node(parent, meshes["box"], pos, size, hex, glow)

static func ball(parent: Node3D, pos: Vector3, size: Vector3, hex: String) -> MeshInstance3D:
	if not meshes.has("ball"):
		var m = SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 8
		m.rings = 4
		meshes["ball"] = m
	return mesh_node(parent, meshes["ball"], pos, size, hex)

static func cylinder(parent: Node3D, pos: Vector3, bottom: float, top: float, height: float, hex: String, sides: int = 10) -> MeshInstance3D:
	var key = "cyl-%s-%s-%s-%s" % [bottom, top, height, sides]
	if not meshes.has(key):
		var m = CylinderMesh.new()
		m.bottom_radius = bottom
		m.top_radius = top
		m.height = height
		m.radial_segments = sides
		meshes[key] = m
	return mesh_node(parent, meshes[key], pos, Vector3.ONE, hex)

static func beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, hex: String) -> MeshInstance3D:
	var n = cylinder(parent, (a + b) * 0.5, radius, radius, a.distance_to(b), hex, 6)
	var direction = (b - a).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		n.quaternion = Quaternion(Vector3.UP, direction)
	return n

static func triangles(parent: Node3D, vertices: Array, hex: String) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices: st.add_vertex(vertex)
	st.generate_normals()
	return mesh_node(parent, st.commit(), Vector3.ZERO, Vector3.ONE, hex)

static func roof(parent: Node3D, width: float, depth: float, y: float, hex: String = TILE) -> void:
	# Curved eaves: actual shaded surfaces, not a flat triangle sprite.
	for side in [-1, 1]:
		var vertices: Array = []
		for row in range(4):
			var t0 = float(row) / 4.0
			var t1 = float(row + 1) / 4.0
			var z0 = side * depth * 0.5 * t0
			var z1 = side * depth * 0.5 * t1
			var h0 = y + 0.70 * pow(1.0-t0, 1.55) + 0.10 * pow(t0, 5)
			var h1 = y + 0.70 * pow(1.0-t1, 1.55) + 0.10 * pow(t1, 5)
			var a = Vector3(-width*0.5, h0+0.07, z0)
			var b = Vector3(width*0.5, h0+0.07, z0)
			var c = Vector3(width*0.5+0.08*t1, h1+0.07, z1)
			var d = Vector3(-width*0.5-0.08*t1, h1+0.07, z1)
			vertices.append_array([a,b,c,a,c,d])
		triangles(parent, vertices, hex)
		beam(parent, Vector3(-width*.5-.1,y+.14,side*depth*.5), Vector3(width*.5+.1,y+.14,side*depth*.5),.045,"739586")
		for column in range(11):
			var x = -width*0.5 + width*float(column)/10.0
			for row in range(4):
				var t0 = float(row)/4.0
				var t1 = float(row+1)/4.0
				var a = Vector3(x,y+.70*pow(1.0-t0,1.55)+.1*pow(t0,5)+.09,side*depth*.5*t0)
				var b = Vector3(x,y+.70*pow(1.0-t1,1.55)+.1*pow(t1,5)+.09,side*depth*.5*t1)
				beam(parent,a,b,.018,"668b7c")
	beam(parent,Vector3(-width*.5-.10,y+.78,0),Vector3(width*.5+.10,y+.78,0),.065,"8faa93")
	for side in [-1,1]:
		beam(parent,Vector3(side*width*.5,y+.78,0),Vector3(side*(width*.5+.17),y+.95,0),.045,"8faa93")

static func lantern(parent: Node3D, p: Vector3) -> void:
	beam(parent,p+Vector3(0,.2,0),p+Vector3(0,.48,0),.014,TIMBER)
	cylinder(parent,p,.11,.09,.27,"dcac65",8)
	cylinder(parent,p+Vector3(0,.15,0),.12,.12,.035,"724b36",8)
	cylinder(parent,p-Vector3(0,.15,0),.08,.08,.03,"724b36",8)
	beam(parent,p-Vector3(0,.15,0),p-Vector3(0,.28,0),.012,"a96943")

static func building(kind: String, level: int = 1, phase: int = -1) -> Node3D:
	var root = Node3D.new()
	root.name = "Building_" + kind
	var width = 2.0 if kind != "hall" else 2.65
	var depth = 1.5 if kind != "hall" else 1.9
	var height = 1.4 if level < 3 else 2.25
	box(root,Vector3(0,.08,0),Vector3(width+.48,.16,depth+.50),"a6ad92")
	for i in range(2): box(root,Vector3(0,.03+float(i)*.07,depth*.5+.4-float(i)*.13),Vector3(.95-float(i)*.13,.12,.3),"c0bca0")
	if phase == 0:
		for i in range(4): beam(root,Vector3(-.65,.24+float(i)*.08,-.3),Vector3(.65,.24+float(i)*.08,-.3),.05,TIMBER)
		return root
	for x in [-width*.46,width*.46]:
		for z in [-depth*.46,depth*.46]:
			cylinder(root,Vector3(x,height*.5+.14,z),.065,.065,height,TIMBER,8)
	if phase == 1:
		beam(root,Vector3(-width*.5,height,0),Vector3(width*.5,height,0),.07,TIMBER)
		beam(root,Vector3(-width*.5,height,-depth*.5),Vector3(-width*.5,height+.7,0),.045,TIMBER)
		beam(root,Vector3(width*.5,height,-depth*.5),Vector3(width*.5,height+.7,0),.045,TIMBER)
		return root
	box(root,Vector3(0,height*.5+.14,0),Vector3(width*.93,height,depth*.93),PLASTER)
	box(root,Vector3(0,.22,depth*.48),Vector3(width,.20,.07),TIMBER)
	box(root,Vector3(0,.70,depth*.485),Vector3(.50,1.02,.08),"52695a")
	box(root,Vector3(0,.70,depth*.535),Vector3(.024,1.0,.018),"bdab75")
	for x in [-width*.33,width*.33]:
		box(root,Vector3(x,1.0,depth*.48),Vector3(.32,.45,.10),"9ea580")
		for line in [-1,0,1]: box(root,Vector3(x+line*.095,1.,depth*.54),Vector3(.022,.45,.016),TIMBER)
		box(root,Vector3(x,1.,depth*.55),Vector3(.33,.025,.018),TIMBER)
	for y in [.35,1.32]: box(root,Vector3(0,y,-depth*.48),Vector3(width,.07,.07),TIMBER)
	if level >= 2:
		for x in [-width*.55,width*.55]:
			cylinder(root,Vector3(x,.69,depth*.70),.06,.06,1.3,TIMBER)
			box(root,Vector3(x,.35,depth*.66),Vector3(.07,.55,.40),TIMBER)
		box(root,Vector3(0,1.35,depth*.68),Vector3(width+0.25,.10,.15),TIMBER)
	if level >= 3:
		box(root,Vector3(0,1.5,0),Vector3(width+.13,.12,depth+.13),TIMBER)
		for x in [-.45,.45]:
			box(root,Vector3(x,1.95,depth*.48),Vector3(.37,.34,.09),"869d7d")
			box(root,Vector3(x,1.95,depth*.54),Vector3(.025,.36,.02),TIMBER)
	if phase != 2: roof(root,width+.42,depth+.48,height+.12)
	if kind == "hall":
		var upper = Node3D.new()
		root.add_child(upper)
		upper.position.y = height+.46
		box(upper,Vector3(0,.1,0),Vector3(1.25,.3,.65),PLASTER)
		roof(upper,1.65,1.05,.23)
		box(root,Vector3(0,height-.16,depth*.54),Vector3(.67,.22,.08),INK)
	if kind == "tavern":
		var awning = box(root,Vector3(0,1.12,depth*.76),Vector3(width+.30,.08,.73),"b8774e")
		awning.rotation.x = .12
		for x in [-width*.58,width*.58]: cylinder(root,Vector3(x,.55,depth*.99),.035,.035,1.1,TIMBER)
		cylinder(root,Vector3(width*.65,.28,depth*.43),.19,.14,.48,"99754e")
		cylinder(root,Vector3(width*.65,.55,depth*.43),.115,.115,.05,"d1bb8b")
		box(root,Vector3(-width*.70,.45,depth*.54),Vector3(.55,.09,.50),TIMBER)
		for x in [-width*.85,-width*.55]: box(root,Vector3(x,.21,depth*.54),Vector3(.065,.45,.065),TIMBER)
	if kind == "granary":
		for i in range(3): ball(root,Vector3(-.7+float(i)*.43,.29,depth*.65),Vector3(.36,.52,.37),"cbb57c")
	if kind == "house":
		cylinder(root,Vector3(-width*.63,.18,depth*.54),.14,.19,.33,"b5835e")
		ball(root,Vector3(-width*.63,.49,depth*.54),Vector3(.47,.45,.45),"698354")
	for x in [-width*.40,width*.40]: lantern(root,Vector3(x,height-.30,depth*.66))
	return root

static func tree(variant: int = 0) -> Node3D:
	var root = Node3D.new()
	cylinder(root,Vector3(0,.62,0),.10,.07,1.25,"826543",7)
	beam(root,Vector3(0,.6,0),Vector3(.30,1.1,.08),.035,TIMBER)
	var palette = ["698d63","789869","8aa477"]
	ball(root,Vector3(0,1.35,0),Vector3(1.20,1.12,1.18),palette[variant%3])
	ball(root,Vector3(-.28,1.68,.1),Vector3(.88,.72,.80),palette[(variant+1)%3])
	return root

static func well() -> Node3D:
	var root = Node3D.new()
	cylinder(root,Vector3(0,.20,0),.42,.42,.40,"a3aa95",10)
	cylinder(root,Vector3(0,.415,0),.32,.32,.02,"4a7d7b",10)
	for x in [-.52,.52]: cylinder(root,Vector3(x,.72,0),.045,.045,1.44,TIMBER)
	roof(root,1.4,1.0,1.38)
	beam(root,Vector3(0,1.35,0),Vector3(0,.48,0),.014,"c1b383")
	return root

static func furnace() -> Node3D:
	var root = Node3D.new()
	box(root,Vector3(0,.08,0),Vector3(1.8,.16,1.4),"a4a68c")
	cylinder(root,Vector3(0,.55,0),.48,.39,1.0,"967c63",10)
	cylinder(root,Vector3(.1,1.43,-.13),.18,.15,1.15,"7d7b68",8)
	cylinder(root,Vector3(.1,2.01,-.13),.23,.23,.12,"a4a28a",8)
	box(root,Vector3(0,.35,.45),Vector3(.48,.44,.05),"344a40")
	var fire = ball(root,Vector3(0,.35,.49),Vector3(.30,.37,.08),"e6a14d")
	fire.material_override = material("e6a14d",true)
	fire.name = "Fire"
	box(root,Vector3(.73,.42,0),Vector3(.50,.10,.75),TIMBER)
	return root

static func kitchen() -> Node3D:
	var root = building("kitchen")
	cylinder(root,Vector3(1.22,.25,.72),.28,.25,.50,"977b5c",8)
	cylinder(root,Vector3(1.22,.54,.72),.31,.31,.09,"3e5146",10)
	cylinder(root,Vector3(1.22,.61,.72),.26,.07,.12,"6a7769",10)
	var fire = ball(root,Vector3(1.22,.23,.965),Vector3(.18,.22,.05),"e6a14d")
	fire.material_override = material("e6a14d",true)
	fire.name = "Fire"
	return root

static func mine() -> Node3D:
	var root = Node3D.new()
	for i in range(5):
		var rock = ball(root,Vector3(float(i%3)*.53-.5,.33+float(i/3)*.48,-.20-float(i%2)*.2),Vector3(1.2,.95,1.1),["939884","a9aa8d","7e8b7d"][i%3])
		rock.rotation.z = float(i)*.19
	box(root,Vector3(0,.39,.39),Vector3(.58,.73,.12),INK)
	for x in [-.36,.36]: box(root,Vector3(x,.38,.5),Vector3(.11,.76,.14),TIMBER)
	box(root,Vector3(0,.81,.5),Vector3(.86,.14,.16),TIMBER)
	beam(root,Vector3(-.55,.5,.2),Vector3(-.35,.91,.07),.06,"d8b466")
	for x in [-.2,.2]: beam(root,Vector3(x,.04,.5),Vector3(x,.04,1.1),.025,"737561")
	return root

static func cargo(resource: String) -> Node3D:
	var root = Node3D.new()
	if resource == "wood":
		for i in range(3): beam(root,Vector3(-.23,float(i)*.08,0),Vector3(.23,float(i)*.08,0),.05,"b89564")
	elif resource == "gold_ingot":
		box(root,Vector3(0,.08,0),Vector3(.34,.14,.20),"deb655")
	else:
		box(root,Vector3(0,.08,0),Vector3(.36,.20,.28),"b49465")
		ball(root,Vector3(0,.2,0),Vector3(.3,.18,.25),"ddbd68" if resource=="gold_ore" else "d6c698")
	return root

static func tool(kind: String) -> Node3D:
	var root=Node3D.new()
	beam(root,Vector3(0,-.34,.03),Vector3(0,-.08,.46),.022,TIMBER)
	if kind=="pickaxe":
		beam(root,Vector3(-.18,-.08,.45),Vector3(.18,-.08,.45),.035,"879185")
	elif kind=="axe":
		box(root,Vector3(.08,-.08,.43),Vector3(.17,.12,.05),"879185")
	elif kind=="hoe":
		box(root,Vector3(0,-.10,.46),Vector3(.17,.025,.15),"879185")
	else:
		box(root,Vector3(0,-.08,.43),Vector3(.20,.11,.11),TIMBER)
	return root

static func hero(id: String, profile: String) -> Node3D:
	var root = Node3D.new()
	root.name = id
	var colors = {"xunyu":"3f696f","liubei":"5b7f60","zhangfei":"965844","zhaoyun":"c7d4ce","huangyueying":"c69b4b"}
	var fallback = {"food":"63867e","supply":"98765b","craft":"c49d61","logistics":"648c99","trade":"8c8265","guard":"737b83"}
	var coat = colors.get(id,fallback.get(profile,"6c8678"))
	var broad = 1.17 if id in ["zhangfei","xuchu","guanyu"] else 1.0
	var body = Node3D.new()
	body.name = "Body"
	root.add_child(body)
	for side in [-1,1]:
		var leg = Node3D.new()
		leg.name = "LegL" if side==-1 else "LegR"
		leg.position = Vector3(side*.105,.34,0)
		body.add_child(leg)
		box(leg,Vector3(0,-.14,0),Vector3(.13,.28,.15),"394b40")
		box(leg,Vector3(0,-.29,.055),Vector3(.15,.13,.24),INK)
	cylinder(body,Vector3(0,.52,0),.27*broad,.20*broad,.46,coat,8)
	cylinder(body,Vector3(0,.49,0),.265*broad,.265*broad,.06,"705842",8)
	box(body,Vector3(0,.49,.245),Vector3(.10,.07,.04),"d6b87b")
	beam(body,Vector3(-.13,.75,.145),Vector3(.10,.55,.23),.025,"e3d4aa")
	for side in [-1,1]:
		var arm = Node3D.new()
		arm.name = "ArmL" if side==-1 else "ArmR"
		arm.position = Vector3(side*.23*broad,.73,0)
		body.add_child(arm)
		cylinder(arm,Vector3(0,-.12,0),.09,.10,.31,coat,7)
		ball(arm,Vector3(0,-.31,.018),Vector3(.13,.16,.14),"e9be91")
	var head = Node3D.new()
	head.name = "Head"
	head.position.y = 1.03
	body.add_child(head)
	ball(head,Vector3(0,0,0),Vector3(.46,.48,.43),"e6be93")
	ball(head,Vector3(0,.075,-.06),Vector3(.47,.41,.36),INK)
	for x in [-.087,.087]:
		ball(head,Vector3(x,.015,.209),Vector3(.034,.047,.019),INK)
		beam(head,Vector3(x-.033,.065,.208),Vector3(x+.030,.069,.208),.008,INK)
	ball(head,Vector3(0,-.025,.225),Vector3(.04,.05,.045),"dbab7f")
	if id == "huangyueying":
		ball(head,Vector3(-.22,.11,-.04),Vector3(.19,.2,.21),INK)
		beam(head,Vector3(-.35,.14,-.04),Vector3(-.12,.14,-.04),.012,"d5b36a")
		box(body,Vector3(-.25,.48,.06),Vector3(.17,.22,.14),"826546")
	elif id in ["zhaoyun","machao","lvbu"]:
		cylinder(head,Vector3(0,.19,0),.24,.10,.23,coat,8)
		var plume = ball(head,Vector3(0,.43,-.04),Vector3(.09,.40,.18),"a95543")
		plume.rotation.x = -.30
		for x in [-.22,.22]: box(body,Vector3(x,.72,.04),Vector3(.18,.10,.30),"bccac0")
	elif profile in ["food","trade"]:
		box(head,Vector3(0,.27,-.015),Vector3(.29,.27,.25),INK)
		box(head,Vector3(0,.17,.02),Vector3(.43,.045,.34),"c5b57b")
	else:
		ball(head,Vector3(0,.29,-.06),Vector3(.19,.2,.20),INK)
		box(head,Vector3(0,.15,.11),Vector3(.43,.05,.14),"c4a770")
	if id in ["zhangfei","guanyu","liubei","xunyu"]:
		cylinder(head,Vector3(0,-.19,.14),.015,.15 if id=="zhangfei" else .08,.28 if id=="guanyu" else .16,INK,5)
	var carried = Node3D.new()
	carried.name = "Cargo"
	carried.position = Vector3(0,.50,.39)
	body.add_child(carried)
	root.scale = Vector3.ONE * 1.05
	return root
