"""CarForgeTax T0 廢車場道具。霧面設定沿用 V3 油桶，不覆蓋 oil_drum。

執行：
blender.exe --background --python blender/scripts/make_rusty_props.py
"""

import json
import math
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(ROOT, "exports", "rusty_props")
PREVIEW_DIR = os.path.join(OUT_DIR, "previews")
os.makedirs(PREVIEW_DIR, exist_ok=True)

RUBBER = (0.13, 0.13, 0.14)
RUBBER_DUST = (0.20, 0.18, 0.15)
STEEL = (0.28, 0.28, 0.29)
PAINT = (0.34, 0.42, 0.45)
RIM_PAINT = (0.43, 0.44, 0.45)
RUST = (0.64, 0.32, 0.12)
RUST_DARK = (0.45, 0.20, 0.08)
RED_BROWN = (0.42, 0.20, 0.14)
WOOD = (0.50, 0.33, 0.18)
WOOD_DARK = (0.32, 0.20, 0.11)
NAIL = (0.22, 0.21, 0.20)


def png_chunk(tag, data):
	return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def png_rgb(width, height, rgb):
	raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
	header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
	return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header) + png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b"")


def save_image(name, width, height, pixels, path, non_color):
	image = bpy.data.images.new(name, width, height, alpha=False)
	image.pixels.foreach_set(pixels)
	if non_color:
		image.colorspace_settings.name = "Non-Color"
	image.filepath_raw = path
	image.file_format = "PNG"
	image.save()
	image.pack()
	return image


def hard_hit(u, v, cu, cv, ru, rv):
	du = min(abs(u - cu), 1.0 - abs(u - cu)) / ru
	dv = abs(v - cv) / rv
	return du * du + dv * dv <= 1.0


def scratch(u, v, u0, v0, angle, length, width):
	du = u - u0
	dv = v - v0
	along = du * math.cos(angle) + dv * math.sin(angle)
	across = -du * math.sin(angle) + dv * math.cos(angle)
	return 0.0 < along < length and abs(across) < width


def make_albedo(name, path, base, chips, scratches, bands=None):
	width = height = 128
	pixels = [0.0] * (width * height * 4)
	for y in range(height):
		v = (y + 0.5) / height
		for x in range(width):
			u = (x + 0.5) / width
			color = base
			if bands:
				for band_v, band_h, band_color in bands:
					if abs(v - band_v) < band_h:
						color = band_color
			for cu, cv, ru, rv, chip in chips:
				if hard_hit(u, v, cu, cv, ru, rv):
					color = chip
			for u0, v0, angle, length, mark in scratches:
				if scratch(u, v, u0, v0, angle, length, 0.008):
					color = mark
			i = (y * width + x) * 4
			pixels[i] = color[0]
			pixels[i + 1] = color[1]
			pixels[i + 2] = color[2]
			pixels[i + 3] = 1.0
	return save_image(name, width, height, pixels, path, False)


def assign_matte(obj, name, albedo, orm):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nodes = mat.node_tree.nodes
	links = mat.node_tree.links
	bsdf = nodes.get("Principled BSDF")
	color_node = nodes.new("ShaderNodeTexImage")
	color_node.image = albedo
	orm_node = nodes.new("ShaderNodeTexImage")
	orm_node.image = orm
	separate = nodes.new("ShaderNodeSeparateColor")
	links.new(color_node.outputs["Color"], bsdf.inputs["Base Color"])
	links.new(orm_node.outputs["Color"], separate.inputs["Color"])
	links.new(separate.outputs["Green"], bsdf.inputs["Roughness"])
	links.new(separate.outputs["Blue"], bsdf.inputs["Metallic"])
	bsdf.inputs["Metallic"].default_value = 0.0
	bsdf.inputs["Roughness"].default_value = 1.0
	for socket_name, value in (
		("Specular IOR Level", 0.0),
		("Specular Tint", (0.0, 0.0, 0.0, 1.0)),
		("Coat Weight", 0.0),
		("Coat Roughness", 1.0),
		("Sheen Weight", 0.0),
		("Transmission Weight", 0.0),
		("Emission Strength", 0.0),
	):
		if socket_name not in bsdf.inputs:
			continue
		current = bsdf.inputs[socket_name].default_value
		if hasattr(current, "__len__"):
			bsdf.inputs[socket_name].default_value = value if hasattr(value, "__len__") else (value, value, value, 1.0)
		else:
			bsdf.inputs[socket_name].default_value = value if not hasattr(value, "__len__") else value[0]
	if "IOR" in bsdf.inputs:
		bsdf.inputs["IOR"].default_value = 1.0
	obj.data.materials.clear()
	obj.data.materials.append(mat)


def fresh_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.unit_settings.system = "NONE"
	scene.unit_settings.scale_length = 1.0
	root = bpy.data.objects.new("Root", None)
	scene.collection.objects.link(root)
	orm = save_image(
		"Orm",
		8,
		8,
		[1.0, 1.0, 0.0, 1.0] * 64,
		os.path.join(OUT_DIR, "_orm.png"),
		True,
	)
	return root, orm


def look_at(obj, target):
	obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def bounds_of(objects):
	low = Vector((1e9, 1e9, 1e9))
	high = Vector((-1e9, -1e9, -1e9))
	for obj in objects:
		for corner in obj.bound_box:
			world = obj.matrix_world @ Vector(corner)
			low = Vector((min(low.x, world.x), min(low.y, world.y), min(low.z, world.z)))
			high = Vector((max(high.x, world.x), max(high.y, world.y), max(high.z, world.z)))
	return low, high


def triangle_count(objects):
	total = 0
	for obj in objects:
		obj.data.calc_loop_triangles()
		total += len(obj.data.loop_triangles)
	return total


def meshes_under(root):
	found = []
	for obj in bpy.context.scene.objects:
		if obj.type == "MESH" and (obj == root or obj.parent == root or (obj.parent and obj.parent.parent == root)):
			found.append(obj)
	return found


def rest_on_ground(root, meshes):
	bpy.context.view_layer.update()
	low, _high = bounds_of(meshes)
	root.location.z -= low.z
	bpy.context.view_layer.update()


def cylinder(name, radius, depth, location, rotation, verts, root, material, smooth=True):
	bpy.ops.mesh.primitive_cylinder_add(
		vertices=verts,
		radius=radius,
		depth=depth,
		location=location,
		rotation=rotation,
	)
	obj = bpy.context.active_object
	obj.name = name
	if smooth:
		bpy.ops.object.shade_smooth()
	assign_matte(obj, material[0], material[1], material[2])
	obj.parent = root
	return obj


def box(name, size, location, rotation, root, material):
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = Vector(size)
	bpy.ops.object.transform_apply(scale=True)
	bpy.ops.object.shade_flat()
	assign_matte(obj, material[0], material[1], material[2])
	obj.parent = root
	return obj


def radial_bar(name, length, thick, radius, angle, y, z_center, root, material):
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = (thick, thick * 0.65, length)
	bpy.ops.object.transform_apply(scale=True)
	direction = Vector((math.cos(angle), 0.0, math.sin(angle)))
	obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
	obj.location = (math.cos(angle) * radius, y, z_center + math.sin(angle) * radius)
	bpy.ops.object.shade_flat()
	assign_matte(obj, material[0], material[1], material[2])
	obj.parent = root
	return obj


def lift_object(obj, target_z):
	bpy.context.view_layer.update()
	low = min((obj.matrix_world @ Vector(corner)).z for corner in obj.bound_box)
	obj.location.z += target_z - low


def cut_hole(obj, radius, depth, location, rotation):
	bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=depth, location=location, rotation=rotation)
	cutter = bpy.context.active_object
	modifier = obj.modifiers.new("Hole", "BOOLEAN")
	modifier.operation = "DIFFERENCE"
	modifier.object = cutter
	if hasattr(modifier, "solver"):
		modifier.solver = "FLOAT"
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier=modifier.name)
	bpy.data.objects.remove(cutter, do_unlink=True)


def setup_preview():
	scene = bpy.context.scene
	world = scene.world or bpy.data.worlds.new("World")
	scene.world = world
	world.use_nodes = True
	background = world.node_tree.nodes.get("Background")
	if background is not None:
		background.inputs["Color"].default_value = (0.20, 0.20, 0.21, 1.0)
		background.inputs["Strength"].default_value = 0.9
	for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
		try:
			scene.render.engine = engine
			break
		except TypeError:
			continue
	scene.render.resolution_x = 960
	scene.render.resolution_y = 960
	scene.render.image_settings.file_format = "PNG"
	if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
		scene.eevee.taa_render_samples = 16
	bpy.ops.mesh.primitive_plane_add(size=30, location=(0.0, 0.0, -0.004))
	ground = bpy.context.active_object
	ground.name = "PreviewGround"
	bpy.ops.object.light_add(type="SUN", location=(2.4, -1.8, 4.0))
	sun = bpy.context.active_object
	sun.data.energy = 3.4
	look_at(sun, Vector((0.0, 0.0, 0.4)))
	bpy.ops.object.light_add(type="AREA", location=(-2.4, -2.8, 2.2))
	fill = bpy.context.active_object
	fill.data.energy = 28.0
	fill.data.size = 4.0
	look_at(fill, Vector((0.0, 0.0, 0.4)))
	return ground


def render_views(meshes, slug):
	scene = bpy.context.scene
	low, high = bounds_of(meshes)
	center = (low + high) * 0.5
	span = max(high.x - low.x, high.y - low.y, high.z - low.z, 0.4)
	bpy.ops.object.camera_add()
	camera = bpy.context.active_object
	scene.camera = camera
	camera.data.lens = 50
	for view_name, location in (
		("front", Vector((center.x, center.y - span * 2.5, center.z))),
		("threequarter", Vector((center.x + span * 1.5, center.y - span * 1.8, center.z + span * 0.85))),
	):
		camera.location = location
		look_at(camera, center)
		path = os.path.join(PREVIEW_DIR, f"{slug}_{view_name}.png")
		scene.render.filepath = path
		bpy.ops.render.render(write_still=True)
		print("PREVIEW", path)


def patch_glb(path):
	with open(path, "rb") as handle:
		blob = handle.read()
	json_len, json_type = struct.unpack_from("<I4s", blob, 12)
	if json_type != b"JSON":
		raise SystemExit("GLB 缺少材質")
	payload = json.loads(blob[20:20 + json_len])
	bin_at = 20 + json_len
	bin_len, bin_type = struct.unpack_from("<I4s", blob, bin_at)
	bin_data = blob[bin_at + 8:bin_at + 8 + bin_len]
	for material in payload.get("materials", []):
		pbr = material.setdefault("pbrMetallicRoughness", {})
		pbr["metallicFactor"] = 0.0
		pbr["roughnessFactor"] = 1.0
		extensions = material.setdefault("extensions", {})
		extensions.pop("KHR_materials_clearcoat", None)
		extensions["KHR_materials_specular"] = {"specularFactor": 0.0}
	used = payload.setdefault("extensionsUsed", [])
	if "KHR_materials_specular" not in used:
		used.append("KHR_materials_specular")
	replacement = png_rgb(8, 8, (0, 255, 0))
	pieces = []
	replaced = 0
	for view in payload.get("bufferViews", []):
		offset = view.get("byteOffset", 0)
		data = bin_data[offset:offset + view["byteLength"]]
		if data.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">II", data[16:24]) == (8, 8):
			data = replacement
			replaced += 1
		pieces.append(data)
	if replaced < 1:
		raise SystemExit(f"{path} 沒有寫入霧面貼圖")
	new_bin = bytearray()
	for view, data in zip(payload.get("bufferViews", []), pieces):
		while len(new_bin) % 4:
			new_bin.append(0)
		view["byteOffset"] = len(new_bin)
		view["byteLength"] = len(data)
		new_bin.extend(data)
	while len(new_bin) % 4:
		new_bin.append(0)
	payload["buffers"][0]["byteLength"] = len(new_bin)
	raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
	raw += b" " * ((4 - (len(raw) % 4)) % 4)
	bin_data = bytes(new_bin)
	total = 12 + 8 + len(raw) + 8 + len(bin_data)
	packed = struct.pack("<4sII", b"glTF", 2, total)
	packed += struct.pack("<I4s", len(raw), b"JSON") + raw
	packed += struct.pack("<I4s", len(bin_data), bin_type) + bin_data
	with open(path, "wb") as handle:
		handle.write(packed)


def export_glb(root, meshes, path):
	bpy.ops.object.select_all(action="DESELECT")
	root.select_set(True)
	for obj in meshes:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	bpy.ops.export_scene.gltf(
		filepath=path,
		export_format="GLB",
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials="EXPORT",
		export_image_format="AUTO",
	)
	patch_glb(path)


def verify_glb(path, expected_tris):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=path)
	meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
	if not meshes:
		raise SystemExit(f"{path} 重新匯入後沒有網格")
	low, high = bounds_of(meshes)
	size = high - low
	tris = triangle_count(meshes)
	if tris != expected_tris:
		raise SystemExit(f"{path} 面數改變 {tris} != {expected_tris}")
	checked = 0
	for obj in meshes:
		if not obj.material_slots:
			raise SystemExit(f"{obj.name} 沒有材質")
		for slot in obj.material_slots:
			mat = slot.material
			bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
			if bsdf is None or not bsdf.inputs["Base Color"].is_linked:
				raise SystemExit(f"{obj.name} 匯入後顏色貼圖遺失")
			if bsdf.inputs["Metallic"].default_value != 0.0:
				raise SystemExit(f"{obj.name} 金屬度不是 0")
			if "Coat Weight" in bsdf.inputs and bsdf.inputs["Coat Weight"].default_value != 0.0:
				raise SystemExit(f"{obj.name} 有 clearcoat")
			checked += 1
	for image in bpy.data.images:
		if image.size[0] == 0 or image.size[0] > 32:
			continue
		pixel = tuple(image.pixels[:4])
		if pixel[1] < 0.95 or pixel[2] > 0.02:
			raise SystemExit(f"{path} 粗糙度或金屬度通道錯誤 {pixel}")
	print(f"VERIFY {os.path.basename(path)} tris={tris} size=({size.x:.3f},{size.y:.3f},{size.z:.3f}) mats={checked}")
	return size, tris


def publish(root, slug):
	meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name != "PreviewGround"]
	rest_on_ground(root, meshes)
	ground = setup_preview()
	render_views(meshes, slug)
	bpy.data.objects.remove(ground, do_unlink=True)
	path = os.path.join(OUT_DIR, f"{slug}.glb")
	tris = triangle_count(meshes)
	low, high = bounds_of(meshes)
	size = high - low
	print(f"SIZE {slug} x={size.x:.3f} y={size.y:.3f} z={size.z:.3f} tris={tris}")
	export_glb(root, meshes, path)
	verified, verified_tris = verify_glb(path, tris)
	return {"slug": slug, "path": path, "tris": verified_tris, "size": verified}


def rubber_material(orm):
	albedo = make_albedo(
		"RubberAlbedo",
		os.path.join(OUT_DIR, "old_tire_rubber.png"),
		RUBBER,
		(
			(0.2, 0.55, 0.08, 0.05, RUBBER_DUST),
			(0.72, 0.4, 0.1, 0.04, RUBBER_DUST),
			(0.45, 0.8, 0.06, 0.03, (0.14, 0.13, 0.12)),
		),
		((0.15, 0.35, 0.15, 0.35, (0.16, 0.15, 0.14)),),
		bands=((0.5, 0.08, (0.12, 0.12, 0.13)),),
	)
	return ("TireRubber", albedo, orm)


def steel_material(orm, filename, base=STEEL):
	albedo = make_albedo(
		"SteelAlbedo",
		os.path.join(OUT_DIR, filename),
		base,
		(
			(0.25, 0.2, 0.07, 0.06, RUST),
			(0.68, 0.72, 0.09, 0.05, RUST_DARK),
			(0.5, 0.4, 0.04, 0.04, RUST),
			(0.82, 0.15, 0.05, 0.07, RUST_DARK),
		),
		((0.1, 0.6, -0.2, 0.28, (0.18, 0.18, 0.19)),),
	)
	return ("MatteSteel", albedo, orm)


def wood_material(orm):
	albedo = make_albedo(
		"WoodAlbedo",
		os.path.join(OUT_DIR, "parts_crate_wood.png"),
		WOOD,
		(
			(0.3, 0.25, 0.06, 0.04, WOOD_DARK),
			(0.75, 0.7, 0.08, 0.03, (0.38, 0.24, 0.12)),
		),
		(
			(0.05, 0.2, 0.04, 0.7, WOOD_DARK),
			(0.2, 0.55, 0.02, 0.5, WOOD_DARK),
			(0.55, 0.4, -0.3, 0.25, (0.24, 0.15, 0.08)),
		),
		bands=((0.18, 0.015, WOOD_DARK), (0.47, 0.012, WOOD_DARK), (0.73, 0.015, WOOD_DARK)),
	)
	return ("CrateWood", albedo, orm)


def paint_material(orm, filename, base=PAINT):
	albedo = make_albedo(
		"PaintAlbedo",
		os.path.join(OUT_DIR, filename),
		base,
		(
			(0.22, 0.3, 0.08, 0.06, RUST),
			(0.6, 0.62, 0.1, 0.05, RUST_DARK),
			(0.78, 0.18, 0.05, 0.07, RUST),
		),
		((0.12, 0.48, 0.25, 0.3, (0.2, 0.22, 0.23)),),
	)
	return ("MattePaint", albedo, orm)


def build_tire():
	root, orm = fresh_scene()
	root.name = "OldTire"
	rubber = rubber_material(orm)
	steel = steel_material(orm, "old_tire_steel.png", (0.34, 0.35, 0.36))
	axis = (math.pi / 2.0, 0.0, 0.0)
	center = 0.74
	core = cylinder("TreadCore", 0.68, 0.36, (0.0, 0.0, center), axis, 24, root, rubber)
	cut_hole(core, 0.5, 0.7, (0.0, 0.0, center), axis)
	for offset in (-0.11, 0.0, 0.11):
		rib = cylinder("TreadRib", 0.725, 0.05, (0.0, offset, center), axis, 24, root, rubber)
		cut_hole(rib, 0.5, 0.2, (0.0, offset, center), axis)
	for offset in (-0.19, 0.19):
		wall = cylinder("Sidewall", 0.735, 0.045, (0.0, offset, center), axis, 24, root, rubber)
		cut_hole(wall, 0.5, 0.16, (0.0, offset, center), axis)
	barrel = cylinder("RimBarrel", 0.46, 0.2, (0.0, 0.0, center), axis, 20, root, steel)
	cut_hole(barrel, 0.3, 0.36, (0.0, 0.0, center), axis)
	for offset in (-0.09, 0.09):
		flange = cylinder("RimFlange", 0.5, 0.028, (0.0, offset, center), axis, 20, root, steel)
		cut_hole(flange, 0.4, 0.1, (0.0, offset, center), axis)
	hub = cylinder("Hub", 0.14, 0.12, (0.0, 0.0, center), axis, 16, root, steel)
	cut_hole(hub, 0.05, 0.22, (0.0, 0.0, center), axis)
	for index in range(5):
		angle = index * math.pi * 2.0 / 5.0
		radial_bar("Spoke", 0.32, 0.055, 0.28, angle, 0.0, center, root, steel)
	cylinder("Valve", 0.016, 0.05, (0.0, 0.0, center + 0.75), (0.0, 0.0, 0.0), 8, root, rubber, smooth=False)
	return publish(root, "old_tire")


def build_crate():
	root, orm = fresh_scene()
	root.name = "PartsCrate"
	wood = wood_material(orm)
	nails = steel_material(orm, "parts_crate_nails.png", NAIL)
	height = 0.78
	for index, x in enumerate((-0.42, -0.14, 0.14, 0.42)):
		box("FloorPlank", (0.24, 0.96, 0.06), (x, 0.0, 0.03), (0.0, 0.0, 0.0), root, wood)
	for x, y in ((-0.62, -0.48), (0.62, -0.48), (-0.62, 0.48), (0.62, 0.48)):
		box("CornerPost", (0.08, 0.08, height), (x, y, height * 0.5), (0.0, 0.0, 0.0), root, wood)
	for z in (0.2, 0.4, 0.6):
		box("SidePlank", (1.16, 0.055, 0.12), (0.0, -0.5, z), (0.0, 0.0, 0.0), root, wood)
		box("SidePlank", (1.16, 0.055, 0.12), (0.0, 0.5, z), (0.0, 0.0, 0.0), root, wood)
		box("EndPlank", (0.055, 0.88, 0.12), (-0.64, 0.0, z), (0.0, 0.0, 0.0), root, wood)
		box("EndPlank", (0.055, 0.88, 0.12), (0.64, 0.0, z), (0.0, 0.0, 0.0), root, wood)
	box("TopRail", (1.28, 0.07, 0.06), (0.0, -0.5, 0.74), (0.0, 0.0, 0.0), root, wood)
	box("TopRail", (1.28, 0.07, 0.06), (0.0, 0.5, 0.74), (0.0, 0.0, 0.0), root, wood)
	box("TopRail", (0.07, 0.96, 0.06), (-0.64, 0.0, 0.74), (0.0, 0.0, 0.0), root, wood)
	box("TopRail", (0.07, 0.96, 0.06), (0.64, 0.0, 0.74), (0.0, 0.0, 0.0), root, wood)
	for x, y in ((-0.58, -0.46), (0.58, -0.46), (-0.58, 0.46), (0.58, 0.46)):
		cylinder("Nail", 0.018, 0.02, (x, y, 0.76), (0.0, 0.0, 0.0), 6, root, nails, smooth=False)
	return publish(root, "parts_crate")


def build_engine():
	root, orm = fresh_scene()
	root.name = "ScrapEngineParts"
	paint = paint_material(orm, "scrap_engine_paint.png")
	steel = steel_material(orm, "scrap_engine_steel.png")
	box("EngineBlock", (0.46, 0.30, 0.24), (0.0, 0.0, 0.12), (0.0, 0.0, 0.0), root, paint)
	box("EngineHead", (0.40, 0.24, 0.08), (0.0, 0.0, 0.28), (0.0, 0.0, 0.0), root, paint)
	for index, x in enumerate((-0.12, -0.04, 0.04, 0.12)):
		cylinder("Cap", 0.028, 0.045, (x, 0.0, 0.345), (0.0, 0.0, 0.0), 8, root, steel, smooth=False)
	cylinder("Exhaust", 0.04, 0.22, (0.28, 0.08, 0.16), (0.0, math.pi / 2.0, 0.15), 10, root, steel)
	cylinder("GearDisc", 0.11, 0.045, (0.34, -0.16, 0.11), (0.0, 0.0, 0.0), 16, root, steel)
	for index in range(8):
		angle = index * math.pi * 2.0 / 8.0
		box(
			"GearTooth",
			(0.045, 0.05, 0.04),
			(0.34 + math.cos(angle) * 0.125, -0.16 + math.sin(angle) * 0.125, 0.11),
			(0.0, 0.0, angle),
			root,
			steel,
		)
	cylinder("Pulley", 0.07, 0.04, (-0.28, 0.0, 0.16), (0.0, math.pi / 2.0, 0.0), 14, root, steel)
	for index, spot in enumerate(((0.1, 0.1, 0.33), (-0.14, -0.08, 0.33), (0.22, -0.18, 0.03))):
		cylinder("Bolt", 0.02, 0.025, spot, (0.0, 0.0, 0.0), 6, root, steel, smooth=False)
	return publish(root, "scrap_engine_parts")


def build_rim():
	root, orm = fresh_scene()
	root.name = "WornRim"
	paint = paint_material(orm, "worn_rim_paint.png", RIM_PAINT)
	axis = (math.pi / 2.0, 0.0, 0.0)
	center = 0.54
	disc = cylinder("RimDisc", 0.52, 0.08, (0.0, 0.0, center), axis, 24, root, paint)
	cut_hole(disc, 0.34, 0.16, (0.0, 0.0, center), axis)
	cylinder("OuterLip", 0.54, 0.035, (0.0, 0.045, center), axis, 24, root, paint)
	hub = cylinder("Hub", 0.14, 0.09, (0.0, 0.02, center), axis, 16, root, paint)
	cut_hole(hub, 0.055, 0.16, (0.0, 0.02, center), axis)
	for index in range(5):
		angle = index * math.pi * 2.0 / 5.0 + 0.25
		radial_bar("Spoke", 0.26, 0.07, 0.25, angle, 0.02, center, root, paint)
	return publish(root, "worn_rim")


def build_pile():
	root, orm = fresh_scene()
	root.name = "ScrapPile"
	gray = steel_material(orm, "scrap_pile_gray.png", (0.24, 0.25, 0.26))
	blue = paint_material(orm, "scrap_pile_blue.png", PAINT)
	red = paint_material(orm, "scrap_pile_red.png", RED_BROWN)
	box("BasePlate", (0.95, 0.62, 0.045), (0.0, 0.0, 0.025), (0.0, 0.0, 0.12), root, gray)
	box("MidPlate", (0.7, 0.4, 0.04), (0.06, 0.02, 0.07), (0.0, 0.0, -0.35), root, blue)
	lean = box("LeanPlate", (0.55, 0.28, 0.035), (-0.05, -0.02, 0.2), (0.9, 0.05, 0.4), root, red)
	lift_object(lean, 0.05)
	cylinder("Pipe", 0.06, 0.7, (0.62, 0.18, 0.06), (0.0, math.pi / 2.0, 0.15), 12, root, gray)
	box("BracketFoot", (0.22, 0.05, 0.05), (-0.38, 0.22, 0.07), (0.0, 0.0, 0.2), root, gray)
	box("BracketPost", (0.05, 0.05, 0.22), (-0.46, 0.22, 0.16), (0.0, 0.0, 0.2), root, gray)
	fender = cylinder("Fender", 0.16, 0.2, (0.18, -0.28, 0.16), (math.pi / 2.0, 0.0, 0.5), 16, root, red)
	cut_hole(fender, 0.1, 0.28, (0.18, -0.28, 0.16), (math.pi / 2.0, 0.0, 0.5))
	lift_object(fender, 0.05)
	cylinder("Bolt", 0.022, 0.02, (0.16, 0.04, 0.1), (0.0, 0.0, 0.0), 6, root, gray, smooth=False)
	return publish(root, "scrap_pile")


def render_lineup(results):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	cursor = 0.0
	gap = 0.45
	for result in results:
		before = set(bpy.data.objects)
		bpy.ops.import_scene.gltf(filepath=result["path"])
		imported = [obj for obj in bpy.data.objects if obj not in before]
		meshes = [obj for obj in imported if obj.type == "MESH"]
		roots = [obj for obj in imported if obj.parent is None]
		for obj in roots:
			obj.location.x += cursor
		bpy.context.view_layer.update()
		low, high = bounds_of(meshes)
		width = high.x - low.x
		# import already includes the cursor shift in bounds
		cursor = high.x + gap
	setup_preview()
	meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name != "PreviewGround"]
	low, high = bounds_of(meshes)
	center = (low + high) * 0.5
	span = max(high.x - low.x, 1.0)
	bpy.ops.object.camera_add(location=(center.x + span * 0.15, center.y - span * 0.72, center.z + span * 0.28))
	camera = bpy.context.active_object
	scene.camera = camera
	camera.data.lens = 38
	look_at(camera, center)
	scene.render.resolution_x = 1600
	scene.render.resolution_y = 900
	path = os.path.join(PREVIEW_DIR, "all_props.png")
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	print("LINEUP", path)


def main():
	print("PYTHON", sys.version.replace("\n", " "))
	results = [
		build_tire(),
		build_crate(),
		build_engine(),
		build_rim(),
		build_pile(),
	]
	render_lineup(results)
	for result in results:
		size = result["size"]
		print(
			f"ASSET {result['slug']} tris={result['tris']} "
			f"size=({size.x:.3f},{size.y:.3f},{size.z:.3f}) glb={result['path']}"
		)


if __name__ == "__main__":
	main()
