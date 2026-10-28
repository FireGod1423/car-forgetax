"""CarForgeTax Common～Epic 四台玩具車。

車頭朝 Blender -Y，匯出 Y-up 後在 Roblox 朝向 -Z。
單位是公尺，匯入 Roblox 時約等於 stud。車長約 2.7～3.1。
烤漆是這四台車自己的顏色，不是品質 UI 色。

只做第一台：
blender.exe --background --python blender/scripts/make_starter_cars.py -- hatch

四台都做：
blender.exe --background --python blender/scripts/make_starter_cars.py -- all
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(ROOT, "exports", "cars")
PREVIEW_DIR = os.path.join(OUT_DIR, "previews")
os.makedirs(PREVIEW_DIR, exist_ok=True)


def argv_after_dd():
	if "--" not in sys.argv:
		return ["hatch"]
	return sys.argv[sys.argv.index("--") + 1 :] or ["hatch"]


def set_input(node, names, value):
	for name in names:
		socket = node.inputs.get(name)
		if socket is not None:
			socket.default_value = value
			return


def make_material(name, color, rough=0.84, metal=0.0, transmission=0.0, emit=0.0):
	material = bpy.data.materials.new(name)
	material.use_nodes = True
	material.diffuse_color = (*color, 1)
	bsdf = material.node_tree.nodes.get("Principled BSDF")
	set_input(bsdf, ("Base Color",), (*color, 1))
	set_input(bsdf, ("Roughness",), rough)
	set_input(bsdf, ("Metallic",), metal)
	set_input(bsdf, ("Transmission Weight", "Transmission"), transmission)
	set_input(bsdf, ("IOR",), 1.45)
	if emit > 0:
		set_input(bsdf, ("Emission Color", "Emission"), (*color, 1))
		set_input(bsdf, ("Emission Strength",), emit)
	if transmission > 0:
		material.blend_method = "BLEND"
		set_input(bsdf, ("Alpha",), 0.35)
	return material


def link_object(mesh, name, material):
	obj = bpy.data.objects.new(name, mesh)
	obj.data.materials.append(material)
	bpy.context.collection.objects.link(obj)
	return obj


def box(name, center, size, material, bevel=0.018):
	bm = bmesh.new()
	geom = bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, verts=geom["verts"], vec=size)
	bmesh.ops.translate(bm, verts=geom["verts"], vec=center)
	if bevel > 0:
		bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES", profile=0.5)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	return link_object(mesh, name, material)


def move_verts(obj, predicate, shift):
	for vert in obj.data.vertices:
		if predicate(vert.co):
			vert.co += Vector(shift)


def slope_high(obj, axis_value, toward_negative, drop):
	coords = [vert.co[1] for vert in obj.data.vertices]
	limit = min(coords) if toward_negative else max(coords)
	zs = [vert.co.z for vert in obj.data.vertices]
	z_mid = (min(zs) + max(zs)) * 0.5
	span = max(abs(axis_value - limit), 1e-4)
	for vert in obj.data.vertices:
		on_side = vert.co.y < axis_value if toward_negative else vert.co.y > axis_value
		if on_side and vert.co.z >= z_mid:
			amount = abs(axis_value - vert.co.y) / span
			vert.co.z -= drop * amount


def spin_mesh(obj, axis, angle, pivot=None):
	center = Vector((0, 0, 0)) if pivot is None else Vector(pivot)
	if pivot is None:
		for vert in obj.data.vertices:
			center += vert.co
		center /= max(len(obj.data.vertices), 1)
	rotation = Matrix.Rotation(angle, 4, axis)
	for vert in obj.data.vertices:
		vert.co = center + rotation @ (vert.co - center)


def cylinder(name, center, radius, depth, axis, material, segs=16):
	bm = bmesh.new()
	geom = bmesh.ops.create_cone(
		bm,
		cap_ends=True,
		cap_tris=False,
		segments=segs,
		radius1=radius,
		radius2=radius,
		depth=depth,
	)
	if axis == "X":
		matrix = Matrix.Rotation(math.pi / 2, 3, "Y")
		bmesh.ops.rotate(bm, verts=geom["verts"], cent=(0, 0, 0), matrix=matrix)
	elif axis == "Y":
		matrix = Matrix.Rotation(math.pi / 2, 3, "X")
		bmesh.ops.rotate(bm, verts=geom["verts"], cent=(0, 0, 0), matrix=matrix)
	bmesh.ops.translate(bm, verts=geom["verts"], vec=center)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	return link_object(mesh, name, material)


def wheel(prefix, x, y, z, radius, tire, rim, accent, spokes=5, width=0.16):
	side = 1 if x >= 0 else -1
	parts = [
		cylinder(prefix + "Tire", (x, y, z), radius, width * 0.72, "X", tire, 18),
		cylinder(prefix + "Rim", (x + side * width * 0.42, y, z), radius * 0.62, width * 0.28, "X", rim, 18),
		cylinder(prefix + "Hub", (x + side * width * 0.52, y, z), radius * 0.16, width * 0.18, "X", accent, 10),
	]
	for index in range(spokes):
		angle = (math.pi * 2 / spokes) * index
		length = radius * 0.52
		spoke = box(
			prefix + "Spoke" + str(index),
			(x + side * 0.018, y, z),
			(0.02, 0.035, length),
			rim,
			bevel=0.004,
		)
		spin_mesh(spoke, "X", angle, (x, y, z))
		parts.append(spoke)
	return parts


def lamp(name, center, radius, material, segs=10):
	return cylinder(name, center, radius, radius * 0.45, "Y", material, segs)


def clear_scene():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete()
	for block in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras):
		for item in list(block):
			if item.users == 0:
				block.remove(item)


def bounds(objects):
	low = Vector((1e9, 1e9, 1e9))
	high = Vector((-1e9, -1e9, -1e9))
	for obj in objects:
		for corner in obj.bound_box:
			world = obj.matrix_world @ Vector(corner)
			low = Vector((min(low.x, world.x), min(low.y, world.y), min(low.z, world.z)))
			high = Vector((max(high.x, world.x), max(high.y, world.y), max(high.z, world.z)))
	return low, high


def look_at(obj, target):
	obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_view(objects, location, filepath):
	scene = bpy.context.scene
	low, high = bounds(objects)
	center = (low + high) * 0.5
	if scene.camera is None:
		camera_data = bpy.data.cameras.new("PreviewCam")
		camera = bpy.data.objects.new("PreviewCam", camera_data)
		bpy.context.collection.objects.link(camera)
		scene.camera = camera
	camera = scene.camera
	camera.location = location
	look_at(camera, center + Vector((0, 0, 0.05)))
	scene.render.filepath = filepath
	bpy.ops.render.render(write_still=True)


def prepare_render():
	scene = bpy.context.scene
	for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
		try:
			scene.render.engine = engine
			break
		except TypeError:
			continue
	scene.render.resolution_x = 1100
	scene.render.resolution_y = 760
	scene.render.image_settings.file_format = "PNG"
	if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
		scene.eevee.taa_render_samples = 24
	world = bpy.data.worlds.new("CarPreview")
	world.use_nodes = True
	background = world.node_tree.nodes.get("Background")
	if background is not None:
		background.inputs["Color"].default_value = (0.23, 0.36, 0.42, 1)
		background.inputs["Strength"].default_value = 0.85
	scene.world = world
	sun_data = bpy.data.lights.new("Sun", "SUN")
	sun_data.energy = 3.2
	sun_data.angle = 0.4
	sun = bpy.data.objects.new("Sun", sun_data)
	sun.rotation_euler = (math.radians(52), 0, math.radians(-28))
	bpy.context.collection.objects.link(sun)
	fill_data = bpy.data.lights.new("Fill", "AREA")
	fill_data.energy = 180
	fill_data.size = 4
	fill = bpy.data.objects.new("Fill", fill_data)
	fill.location = (-2.4, -1.6, 2.4)
	look_at(fill, Vector((0, 0, 0.5)))
	bpy.context.collection.objects.link(fill)


def export_car(key, objects):
	root = bpy.data.objects.new(key, None)
	bpy.context.collection.objects.link(root)
	for obj in objects:
		obj.parent = root
	bpy.ops.object.select_all(action="DESELECT")
	root.select_set(True)
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	folder = os.path.join(OUT_DIR, key)
	os.makedirs(folder, exist_ok=True)
	blend_path = os.path.join(folder, key + ".blend")
	glb_path = os.path.join(folder, key + ".glb")
	bpy.ops.wm.save_as_mainfile(filepath=blend_path)
	bpy.ops.export_scene.gltf(
		filepath=glb_path,
		export_format="GLB",
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials="EXPORT",
	)
	low, high = bounds(objects)
	size = high - low
	tris = 0
	for obj in objects:
		obj.data.calc_loop_triangles()
		tris += len(obj.data.loop_triangles)
	print("CAR %s size %.2f x %.2f x %.2f tris %d ground %.3f" % (key, size.x, size.y, size.z, tris, low.z))
	if size.y < 2.3 or size.y > 3.4 or size.x < 1.0 or size.x > 1.75 or low.z < -0.02 or low.z > 0.05:
		raise SystemExit("尺寸或貼地不對：" + key)
	if tris > 8000:
		raise SystemExit("面數過高：" + key)
	front = os.path.join(PREVIEW_DIR, key + "_front.png")
	angle = os.path.join(PREVIEW_DIR, key + "_threequarter.png")
	render_view(objects, Vector((0.05, -4.6, 1.15)), front)
	render_view(objects, Vector((-2.8, -3.5, 1.55)), angle)


def build_hatch():
	paint = make_material("HatchPaint", (176 / 255, 72 / 255, 78 / 255), 0.9, 0.0)
	trim = make_material("HatchTrim", (0.10, 0.10, 0.11), 0.72, 0.0)
	glass = make_material("HatchGlass", (0.45, 0.58, 0.64), 0.08, 0.0, 0.55)
	tire = make_material("HatchTire", (0.07, 0.07, 0.08), 0.9, 0.0)
	rim = make_material("HatchRim", (0.72, 0.73, 0.75), 0.35, 0.45)
	lamp_white = make_material("HatchLamp", (0.95, 0.94, 0.88), 0.25, 0.0, emit=2.2)
	amber = make_material("HatchAmber", (0.95, 0.45, 0.12), 0.35, 0.0, emit=1.4)
	tail = make_material("HatchTail", (0.75, 0.08, 0.07), 0.4, 0.0, emit=1.2)
	seat = make_material("HatchSeat", (0.55, 0.40, 0.26), 0.8, 0.0)
	parts = []
	body = box("Body", (0, 0.02, 0.48), (1.18, 2.52, 0.36), paint, 0.04)
	slope_high(body, -0.15, True, 0.14)
	parts.append(body)
	cabin = box("Cabin", (0, 0.42, 0.78), (1.02, 1.05, 0.36), paint, 0.03)
	slope_high(cabin, 0.12, True, 0.22)
	slope_high(cabin, 0.62, False, 0.16)
	parts.append(cabin)
	parts.append(box("Hatch", (0, 0.95, 0.62), (1.08, 0.42, 0.16), paint, 0.02))
	parts.append(box("Bumper", (0, -1.22, 0.34), (1.2, 0.14, 0.16), trim, 0.014))
	parts.append(box("Valance", (0, 1.24, 0.34), (1.16, 0.1, 0.12), trim, 0.01))
	parts.append(box("Grille", (0, -1.26, 0.46), (0.62, 0.04, 0.12), trim, 0.006))
	parts.append(box("Windshield", (0, -0.02, 0.86), (0.94, 0.035, 0.34), glass, 0.0))
	spin_mesh(parts[-1], "X", math.radians(-34))
	parts.append(box("RearGlass", (0, 0.92, 0.84), (0.9, 0.03, 0.28), glass, 0.0))
	spin_mesh(parts[-1], "X", math.radians(28))
	parts.append(box("SideGlass", (0.52, 0.42, 0.84), (0.025, 0.42, 0.2), glass, 0.0))
	parts.append(box("SideGlass", (-0.52, 0.42, 0.84), (0.025, 0.42, 0.2), glass, 0.0))
	parts.append(box("Seat", (0.2, 0.48, 0.66), (0.26, 0.26, 0.18), seat, 0.008))
	parts.append(box("Seat", (-0.2, 0.48, 0.66), (0.26, 0.26, 0.18), seat, 0.008))
	for side, x in (("L", -0.38), ("R", 0.38)):
		parts.append(lamp("Head" + side + "Outer", (x, -1.28, 0.48), 0.07, lamp_white))
		parts.append(lamp("Head" + side + "Inner", (x * 0.42, -1.28, 0.48), 0.055, lamp_white))
	parts.append(lamp("TurnL", (-0.58, -1.2, 0.36), 0.03, amber, 8))
	parts.append(lamp("TurnR", (0.58, -1.2, 0.36), 0.03, amber, 8))
	parts.append(box("TailL", (-0.4, 1.28, 0.55), (0.2, 0.03, 0.09), tail, 0.004))
	parts.append(box("TailR", (0.4, 1.28, 0.55), (0.2, 0.03, 0.09), tail, 0.004))
	parts.append(box("Mirror", (0.58, 0.08, 0.8), (0.08, 0.07, 0.04), trim, 0.004))
	parts.append(box("Mirror", (-0.58, 0.08, 0.8), (0.08, 0.07, 0.04), trim, 0.004))
	radius = 0.31
	for label, x, y in (("FL", -0.62, -0.72), ("FR", 0.62, -0.72), ("RL", -0.62, 0.82), ("RR", 0.62, 0.82)):
		parts.extend(wheel(label, x, y, radius, radius, tire, rim, trim, spokes=5, width=0.18))
	return parts


def build_coupe():
	paint = make_material("CoupePaint", (46 / 255, 96 / 255, 62 / 255), 0.86, 0.0)
	roof = make_material("CoupeRoof", (0.08, 0.08, 0.09), 0.7, 0.0)
	trim = make_material("CoupeTrim", (0.08, 0.08, 0.09), 0.55, 0.05)
	glass = make_material("CoupeGlass", (0.45, 0.52, 0.55), 0.08, 0.0, 0.75)
	tire = make_material("CoupeTire", (0.06, 0.06, 0.07), 0.9, 0.0)
	rim = make_material("CoupeRim", (0.72, 0.55, 0.32), 0.38, 0.55)
	lamp = make_material("CoupeLamp", (0.95, 0.95, 0.9), 0.2, 0.0, emit=2.4)
	tail = make_material("CoupeTail", (0.8, 0.1, 0.08), 0.35, 0.0, emit=1.3)
	parts = []
	body = box("Body", (0, 0.0, 0.46), (1.22, 2.85, 0.36), paint, 0.026)
	slope_high(body, -0.15, True, 0.05)
	parts.append(body)
	hood = box("Hood", (0, -0.72, 0.64), (1.12, 1.05, 0.12), paint, 0.02)
	slope_high(hood, -0.35, True, 0.08)
	parts.append(hood)
	cabin = box("Cabin", (0, 0.42, 0.78), (1.05, 1.15, 0.32), paint, 0.022)
	slope_high(cabin, 0.15, True, 0.14)
	parts.append(cabin)
	parts.append(box("Roof", (0, 0.48, 0.96), (0.92, 0.85, 0.08), roof, 0.016))
	parts.append(box("Bumper", (0, -1.42, 0.34), (1.24, 0.18, 0.18), trim, 0.012))
	parts.append(box("Grille", (0, -1.46, 0.50), (0.78, 0.05, 0.18), trim, 0.006))
	parts.append(box("GrilleBar", (0, -1.47, 0.50), (0.70, 0.03, 0.035), rim, 0.0))
	parts.append(box("Skirt", (0, 0.1, 0.28), (1.24, 2.4, 0.07), trim, 0.008))
	parts.append(box("Windshield", (0, -0.05, 0.84), (0.98, 0.035, 0.28), glass, 0.0))
	spin_mesh(parts[-1], "X", math.radians(-32))
	parts.append(box("SideGlass", (0.54, 0.48, 0.84), (0.025, 0.48, 0.18), glass, 0.0))
	parts.append(box("SideGlass", (-0.54, 0.48, 0.84), (0.025, 0.48, 0.18), glass, 0.0))
	parts.append(box("HeadL", (-0.42, -1.46, 0.52), (0.28, 0.04, 0.08), lamp, 0.004))
	parts.append(box("HeadR", (0.42, -1.46, 0.52), (0.28, 0.04, 0.08), lamp, 0.004))
	parts.append(box("Tail", (0, 1.42, 0.55), (0.9, 0.04, 0.08), tail, 0.004))
	parts.append(box("Mirror", (0.66, 0.12, 0.78), (0.08, 0.1, 0.045), trim, 0.004))
	parts.append(box("Mirror", (-0.66, 0.12, 0.78), (0.08, 0.1, 0.045), trim, 0.004))
	radius = 0.31
	for label, x, y in (("FL", -0.66, -0.95), ("FR", 0.66, -0.95), ("RL", -0.66, 0.95), ("RR", 0.66, 0.95)):
		parts.extend(wheel(label, x, y, radius, radius, tire, rim, trim, spokes=7, width=0.18))
	return parts


def build_sports():
	paint = make_material("SportsPaint", (176 / 255, 180 / 255, 184 / 255), 0.8, 0.04)
	roof = make_material("SportsRoof", (0.12, 0.12, 0.13), 0.62, 0.0)
	trim = make_material("SportsTrim", (0.07, 0.07, 0.08), 0.5, 0.08)
	glass = make_material("SportsGlass", (0.62, 0.68, 0.72), 0.06, 0.0, 0.7)
	tire = make_material("SportsTire", (0.05, 0.05, 0.06), 0.92, 0.0)
	rim = make_material("SportsRim", (0.16, 0.16, 0.17), 0.32, 0.7)
	gold = make_material("SportsCaliper", (0.78, 0.55, 0.16), 0.4, 0.4)
	lamp_mat = make_material("SportsLamp", (0.92, 0.93, 0.9), 0.18, 0.0, emit=2.0)
	tail = make_material("SportsTail", (0.7, 0.08, 0.07), 0.35, 0.0, emit=1.2)
	parts = []
	body = box("Body", (0, 0.05, 0.44), (1.28, 2.72, 0.34), paint, 0.028)
	parts.append(body)
	hood = box("Hood", (0, -0.55, 0.60), (1.16, 1.25, 0.10), paint, 0.02)
	slope_high(hood, -0.2, True, 0.06)
	parts.append(hood)
	fender_l = box("HipL", (-0.52, 0.55, 0.52), (0.28, 0.85, 0.28), paint, 0.02)
	fender_r = box("HipR", (0.52, 0.55, 0.52), (0.28, 0.85, 0.28), paint, 0.02)
	parts.extend((fender_l, fender_r))
	cabin = box("Cabin", (0, 0.35, 0.74), (1.02, 0.95, 0.30), paint, 0.02)
	slope_high(cabin, 0.1, True, 0.12)
	slope_high(cabin, 0.55, False, 0.12)
	parts.append(cabin)
	parts.append(box("Roof", (0, 0.38, 0.92), (0.86, 0.7, 0.07), roof, 0.014))
	parts.append(box("Bumper", (0, -1.32, 0.32), (1.26, 0.16, 0.16), trim, 0.01))
	parts.append(box("Intake", (0, -1.34, 0.30), (0.7, 0.06, 0.08), trim, 0.004))
	parts.append(box("Windshield", (0, -0.02, 0.80), (0.94, 0.03, 0.26), glass, 0.0))
	spin_mesh(parts[-1], "X", math.radians(-26))
	parts.append(box("RearGlass", (0, 0.78, 0.78), (0.9, 0.03, 0.22), glass, 0.0))
	spin_mesh(parts[-1], "X", math.radians(22))
	parts.append(lamp("HeadL", (-0.38, -1.34, 0.52), 0.07, lamp_mat))
	parts.append(lamp("HeadR", (0.38, -1.34, 0.52), 0.07, lamp_mat))
	parts.append(box("TailL", (-0.4, 1.38, 0.52), (0.24, 0.035, 0.08), tail, 0.004))
	parts.append(box("TailR", (0.4, 1.38, 0.52), (0.24, 0.035, 0.08), tail, 0.004))
	radius = 0.32
	for label, x, y in (("FL", -0.64, -0.82), ("FR", 0.64, -0.82), ("RL", -0.68, 0.82), ("RR", 0.68, 0.82)):
		parts.extend(wheel(label, x, y, radius, radius, tire, rim, gold, spokes=8, width=0.19))
	return parts


def build_gt():
	paint = make_material("GtPaint", (36 / 255, 64 / 255, 128 / 255), 0.84, 0.02)
	roof = make_material("GtRoof", (0.07, 0.07, 0.08), 0.6, 0.0)
	trim = make_material("GtTrim", (0.06, 0.06, 0.07), 0.48, 0.1)
	glass = make_material("GtGlass", (0.5, 0.6, 0.68), 0.08, 0.0, 0.72)
	tire = make_material("GtTire", (0.05, 0.05, 0.06), 0.9, 0.0)
	rim = make_material("GtRim", (0.14, 0.14, 0.15), 0.3, 0.72)
	lamp = make_material("GtLamp", (0.9, 0.95, 1.0), 0.15, 0.0, emit=3.0)
	tail = make_material("GtTail", (0.85, 0.12, 0.1), 0.3, 0.0, emit=1.6)
	parts = []
	body = box("Body", (0, 0.02, 0.44), (1.26, 2.95, 0.34), paint, 0.024)
	parts.append(body)
	hood = box("Hood", (0, -0.7, 0.60), (1.14, 1.2, 0.11), paint, 0.018)
	slope_high(hood, -0.25, True, 0.07)
	parts.append(hood)
	cabin = box("Cabin", (0, 0.48, 0.74), (1.04, 1.05, 0.30), paint, 0.02)
	slope_high(cabin, 0.22, True, 0.15)
	slope_high(cabin, 0.7, False, 0.16)
	parts.append(cabin)
	parts.append(box("Roof", (0, 0.5, 0.92), (0.9, 0.72, 0.07), roof, 0.012))
	parts.append(box("Deck", (0, 1.15, 0.58), (1.1, 0.45, 0.08), paint, 0.012))
	parts.append(box("Splitter", (0, -1.48, 0.28), (1.22, 0.12, 0.04), trim, 0.004))
	parts.append(box("Skirt", (0.64, 0.1, 0.32), (0.06, 2.2, 0.08), trim, 0.004))
	parts.append(box("Skirt", (-0.64, 0.1, 0.32), (0.06, 2.2, 0.08), trim, 0.004))
	parts.append(box("Intake", (0, -1.42, 0.36), (0.62, 0.08, 0.1), trim, 0.004))
	parts.append(box("Windshield", (0, 0.05, 0.82), (0.96, 0.03, 0.28), glass, 0.0))
	spin_mesh(parts[-1], "X", math.radians(-30))
	parts.append(box("RearGlass", (0, 0.95, 0.78), (0.88, 0.03, 0.2), glass, 0.0))
	spin_mesh(parts[-1], "X", math.radians(24))
	parts.append(box("LightL", (-0.4, -1.46, 0.5), (0.36, 0.03, 0.045), lamp, 0.002))
	parts.append(box("LightR", (0.4, -1.46, 0.5), (0.36, 0.03, 0.045), lamp, 0.002))
	parts.append(box("TailBar", (0, 1.46, 0.56), (1.0, 0.03, 0.05), tail, 0.002))
	parts.append(box("Spoiler", (0, 1.28, 0.78), (0.9, 0.16, 0.025), trim, 0.004))
	radius = 0.32
	for label, x, y in (("FL", -0.66, -0.98), ("FR", 0.66, -0.98), ("RL", -0.68, 1.0), ("RR", 0.68, 1.0)):
		parts.extend(wheel(label, x, y, radius, radius, tire, rim, trim, spokes=6, width=0.2))
	return parts


BUILDERS = {
	"hatch": ("hatch_common", build_hatch),
	"coupe": ("coupe_uncommon", build_coupe),
	"sports": ("sedan_rare", build_sports),
	"gt": ("muscle_epic", build_gt),
}


def main():
	choice = argv_after_dd()[0]
	keys = list(BUILDERS) if choice == "all" else [choice]
	prepare_render()
	for key in keys:
		mesh_key, builder = BUILDERS[key]
		clear_scene()
		prepare_render()
		objects = builder()
		export_car(mesh_key, objects)


if __name__ == "__main__":
	main()
