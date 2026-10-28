"""以現有 oil_drum.glb 升級材質。不重建桶身，不覆蓋 V1 檔案。

執行：
blender.exe --background --python blender/scripts/make_oil_drum_v2.py
"""

import math
import os
import sys

import bpy
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
SRC_GLB = os.path.join(ROOT, "exports", "oil_drum.glb")
OUT_DIR = os.path.join(ROOT, "exports", "v2")
PREVIEW_DIR = os.path.join(OUT_DIR, "previews")
os.makedirs(PREVIEW_DIR, exist_ok=True)

FBX_PATH = os.path.join(OUT_DIR, "oil_drum.fbx")
GLB_PATH = os.path.join(OUT_DIR, "oil_drum.glb")
FRONT_PATH = os.path.join(PREVIEW_DIR, "oil_drum_front.png")
ANGLE_PATH = os.path.join(PREVIEW_DIR, "oil_drum_threequarter.png")

PAINT = (0.30, 0.38, 0.40)
RUST = (0.62, 0.32, 0.13)
RUST_DARK = (0.42, 0.20, 0.08)
BARE = (0.36, 0.35, 0.34)
STEEL = (0.22, 0.22, 0.23)


def hash2(ix, iy):
	n = (ix * 374761393 + iy * 668265263) & 0xFFFFFFFF
	n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
	return (n & 0xFFFFFF) / 16777215.0


def value_noise(x, y):
	x0 = math.floor(x)
	y0 = math.floor(y)
	fx = x - x0
	fy = y - y0
	fx = fx * fx * (3 - 2 * fx)
	fy = fy * fy * (3 - 2 * fy)
	v00 = hash2(x0, y0)
	v10 = hash2(x0 + 1, y0)
	v01 = hash2(x0, y0 + 1)
	v11 = hash2(x0 + 1, y0 + 1)
	return v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy) + v01 * (1 - fx) * fy + v11 * fx * fy


def fbm(x, y):
	return (
		value_noise(x, y) * 0.55
		+ value_noise(x * 2.1 + 4.0, y * 2.1) * 0.3
		+ value_noise(x * 4.3 + 9.0, y * 4.3) * 0.15
	)


def scratch_mask(u, v, u0, v0, angle, length, width):
	cu = u - u0
	cv = v - v0
	ca = math.cos(angle)
	sa = math.sin(angle)
	along = cu * ca + cv * sa
	across = -cu * sa + cv * ca
	if along <= 0.0 or along >= length or abs(across) >= width:
		return 0.0
	return 1.0 - abs(across) / width


def lerp(a, b, t):
	t = max(0.0, min(1.0, t))
	return a * (1.0 - t) + b * t


def mix3(a, b, t):
	return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t))


def paint_sample(u, v):
	n = fbm(u * 11.0, v * 7.0)
	rust = 0.0
	spots = (
		(0.16, 0.18, 0.07, 0.1),
		(0.38, 0.42, 0.11, 0.07),
		(0.63, 0.14, 0.06, 0.08),
		(0.74, 0.58, 0.09, 0.06),
		(0.28, 0.72, 0.08, 0.09),
		(0.52, 0.08, 0.1, 0.045),
		(0.88, 0.36, 0.055, 0.08),
		(0.46, 0.86, 0.07, 0.05),
	)
	for su, sv, rx, ry in spots:
		du = min(abs(u - su), 1.0 - abs(u - su)) / rx
		dv = (v - sv) / ry
		wobble = fbm(u * 16.0 + su * 9.0, v * 14.0 + sv * 7.0) - 0.5
		rust = max(rust, max(0.0, 1.0 - math.hypot(du, dv) - wobble * 0.55) ** 1.15)
	if v < 0.4:
		stain = fbm(u * 3.2 + 2.0, v * 6.0)
		if stain > 0.58:
			rust = max(rust, (stain - 0.58) / 0.42 * 0.85)
	rust = max(rust, max(0.0, (0.13 - v) / 0.13))
	rust = max(rust, max(0.0, (v - 0.91) / 0.09) * 0.8)
	if n > 0.8:
		rust = max(rust, (n - 0.8) / 0.2 * 0.7)
	rust = min(1.0, rust)
	chip = 1.0 if n > 0.9 and rust < 0.25 else 0.0
	grain = (fbm(u * 18.0, v * 14.0) - 0.5) * 0.05
	sc = 0.0
	sc = max(sc, scratch_mask(u, v, 0.12, 0.42, 0.2, 0.34, 0.004))
	sc = max(sc, scratch_mask(u, v, 0.48, 0.7, -0.35, 0.26, 0.0035))
	sc = max(sc, scratch_mask(u, v, 0.7, 0.22, 0.9, 0.18, 0.0035))
	color = (PAINT[0] + grain, PAINT[1] + grain, PAINT[2] + grain * 0.5)
	color = mix3(color, RUST if rust < 0.6 else RUST_DARK, rust)
	color = mix3(color, BARE, chip * 0.85)
	color = mix3(color, (0.17, 0.17, 0.18), sc * 0.85)
	rough = lerp(0.86, 0.96, rust)
	rough = lerp(rough, 0.62, chip)
	rough = lerp(rough, 0.58, sc)
	metal = lerp(0.08, 0.03, rust)
	metal = lerp(metal, 0.48, chip)
	height = rust * 0.28 - sc * 0.15
	return color, rough, metal, height


def lid_sample(u, v):
	dx = u - 0.5
	dy = v - 0.5
	radius = math.hypot(dx, dy) * 2.0
	ang = math.atan2(dy, dx)
	n = fbm(u * 6.0 + 2.0, v * 6.0)
	rust = max(0.0, radius - 0.72) * 2.2
	rust += max(0.0, n - 0.78) * 1.4
	rust += max(0.0, 0.62 - n) * max(0.0, radius - 0.45) * 0.8
	rust = max(0.0, min(1.0, rust))
	sc = scratch_mask(u, v, 0.32, 0.48, 0.4, 0.22, 0.006)
	sc = max(sc, scratch_mask(u, v, 0.58, 0.4, 2.2, 0.18, 0.005))
	color = PAINT
	color = mix3(color, RUST, rust)
	color = mix3(color, (0.18, 0.18, 0.19), sc * 0.7)
	if radius > 1.02:
		color = STEEL
	rough = lerp(0.72, 0.92, rust)
	metal = lerp(0.22, 0.08, rust)
	return color, rough, metal, rust * 0.4


def steel_sample(u, v):
	n = fbm(u * 7.0 + 2.0, v * 4.0)
	edge = max(max(0.0, 0.1 - v) / 0.1, max(0.0, v - 0.9) / 0.1)
	rust = edge * 0.85 + max(0.0, n - 0.86) * 1.5
	rust = max(0.0, min(1.0, rust))
	sc = scratch_mask(u, v, 0.18, 0.5, 0.02, 0.4, 0.012)
	shade = (n - 0.5) * 0.04
	color = (STEEL[0] + shade, STEEL[1] + shade, STEEL[2] + shade)
	color = mix3(color, RUST_DARK, rust)
	color = mix3(color, (0.28, 0.28, 0.29), sc * 0.45)
	rough = lerp(0.86, 0.95, rust)
	metal = lerp(0.42, 0.12, rust)
	return color, rough, metal, rust * 0.2


def new_image(name, width, height, path):
	image = bpy.data.images.new(name, width, height, alpha=False)
	image.filepath_raw = path
	image.file_format = "PNG"
	return image


def write_image(image, pixels, path, non_color):
	image.pixels.foreach_set(pixels)
	if non_color:
		image.colorspace_settings.name = "Non-Color"
	image.filepath_raw = path
	image.file_format = "PNG"
	image.save()
	image.pack()


def build_texture(name, width, height, sampler, path_prefix):
	albedo = [0.0] * (width * height * 4)
	rough = [0.0] * (width * height * 4)
	metal = [0.0] * (width * height * 4)
	height_map = [0.0] * (width * height)
	for y in range(height):
		for x in range(width):
			color, roughness, metallic, h = sampler((x + 0.5) / width, (y + 0.5) / height)
			i = (y * width + x) * 4
			albedo[i] = color[0]
			albedo[i + 1] = color[1]
			albedo[i + 2] = color[2]
			albedo[i + 3] = 1.0
			rough[i] = rough[i + 1] = rough[i + 2] = roughness
			rough[i + 3] = 1.0
			metal[i] = metal[i + 1] = metal[i + 2] = metallic
			metal[i + 3] = 1.0
			height_map[y * width + x] = h
	normal = [0.0] * (width * height * 4)
	for y in range(height):
		for x in range(width):
			hl = height_map[y * width + (x - 1) % width]
			hr = height_map[y * width + (x + 1) % width]
			hd = height_map[((y - 1) % height) * width + x]
			hu = height_map[((y + 1) % height) * width + x]
			dx = (hr - hl) * 4.0
			dy = (hu - hd) * 4.0
			length = math.sqrt(dx * dx + dy * dy + 1.0)
			i = (y * width + x) * 4
			normal[i] = (-dx / length) * 0.5 + 0.5
			normal[i + 1] = (-dy / length) * 0.5 + 0.5
			normal[i + 2] = (1.0 / length) * 0.5 + 0.5
			normal[i + 3] = 1.0
	images = {}
	for key, pixels, non_color in (
		("albedo", albedo, False),
		("roughness", rough, True),
		("metallic", metal, True),
		("normal", normal, True),
	):
		path = f"{path_prefix}_{key}.png"
		image = new_image(f"{name}_{key}", width, height, path)
		write_image(image, pixels, path, non_color)
		images[key] = image
	return images


def assign_pbr(obj, name, images, normal_strength):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nodes = mat.node_tree.nodes
	links = mat.node_tree.links
	bsdf = nodes.get("Principled BSDF")
	albedo = nodes.new("ShaderNodeTexImage")
	albedo.image = images["albedo"]
	rough = nodes.new("ShaderNodeTexImage")
	rough.image = images["roughness"]
	metal = nodes.new("ShaderNodeTexImage")
	metal.image = images["metallic"]
	normal_tex = nodes.new("ShaderNodeTexImage")
	normal_tex.image = images["normal"]
	normal_map = nodes.new("ShaderNodeNormalMap")
	normal_map.inputs["Strength"].default_value = normal_strength
	links.new(albedo.outputs["Color"], bsdf.inputs["Base Color"])
	links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
	links.new(metal.outputs["Color"], bsdf.inputs["Metallic"])
	links.new(normal_tex.outputs["Color"], normal_map.inputs["Color"])
	links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
	if "Specular IOR Level" in bsdf.inputs:
		bsdf.inputs["Specular IOR Level"].default_value = 0.22
	obj.data.materials.clear()
	obj.data.materials.append(mat)


def apply_transform(obj):
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def wrap_angle(angle):
	while angle > math.pi:
		angle -= math.pi * 2.0
	while angle < -math.pi:
		angle += math.pi * 2.0
	return angle


def dent_body(obj):
	dents = (
		(0.4, 0.62, 0.34, 0.028),
		(2.4, 0.88, 0.22, 0.014),
		(-1.3, 0.36, 0.26, 0.02),
	)
	for vertex in obj.data.vertices:
		x, y, z = vertex.co
		radial = math.hypot(x, y)
		if radial < 0.25:
			continue
		angle = math.atan2(y, x)
		push = 0.0
		for dent_angle, dent_z, radius, depth in dents:
			dist = math.hypot(wrap_angle(angle - dent_angle) * 0.42, z - dent_z)
			if dist < radius:
				falloff = 1.0 - dist / radius
				push += depth * falloff * falloff
		if push > 0.0:
			scale = max(0.92, (radial - push) / radial)
			vertex.co.x *= scale
			vertex.co.y *= scale
	obj.data.update()


def write_uv(obj, mode):
	mesh = obj.data
	if not mesh.uv_layers:
		mesh.uv_layers.new(name="UVMap")
	layer = mesh.uv_layers.active
	world = [obj.matrix_world @ vertex.co for vertex in mesh.vertices]
	zs = [point.z for point in world]
	z0 = min(zs)
	z1 = max(zs)
	span = max(1e-6, z1 - z0)
	for poly in mesh.polygons:
		if mode == "lid" or abs(poly.normal.z) > 0.65:
			for loop_index in poly.loop_indices:
				point = world[mesh.loops[loop_index].vertex_index]
				layer.data[loop_index].uv = (point.x * 0.85 + 0.5, point.y * 0.85 + 0.5)
			continue
		angles = []
		for loop_index in poly.loop_indices:
			point = world[mesh.loops[loop_index].vertex_index]
			angles.append((math.atan2(point.y, point.x) + math.pi) / (math.pi * 2.0))
		if max(angles) - min(angles) > 0.5:
			angles = [angle + 1.0 if angle < 0.5 else angle for angle in angles]
		for loop_index, angle in zip(poly.loop_indices, angles):
			point = world[mesh.loops[loop_index].vertex_index]
			layer.data[loop_index].uv = (angle, (point.z - z0) / span)


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


def look_at(obj, target):
	direction = target - obj.location
	obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_view(objects, location, filepath):
	scene = bpy.context.scene
	low, high = bounds_of(objects)
	center = (low + high) * 0.5
	if scene.camera is None:
		bpy.ops.object.camera_add()
		scene.camera = bpy.context.active_object
	camera = scene.camera
	camera.location = location
	look_at(camera, center)
	scene.render.filepath = filepath
	bpy.ops.render.render(write_still=True)


def export_models(root, meshes):
	bpy.ops.object.select_all(action="DESELECT")
	if root is not None:
		root.select_set(True)
	for obj in meshes:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	bpy.ops.export_scene.fbx(
		filepath=FBX_PATH,
		use_selection=True,
		apply_scale_options="FBX_SCALE_ALL",
		global_scale=1.0,
		apply_unit_scale=False,
		bake_space_transform=True,
		axis_forward="-Z",
		axis_up="Y",
		mesh_smooth_type="FACE",
		use_mesh_modifiers=True,
		object_types={"EMPTY", "MESH"},
		path_mode="COPY",
		embed_textures=True,
	)
	bpy.ops.export_scene.gltf(
		filepath=GLB_PATH,
		export_format="GLB",
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials="EXPORT",
		export_image_format="AUTO",
	)


def verify_roundtrip(expected_tris):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=GLB_PATH)
	meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
	if not meshes:
		raise SystemExit("重新匯入後沒有網格")
	low, high = bounds_of(meshes)
	size = high - low
	tris = triangle_count(meshes)
	textured = 0
	for obj in meshes:
		for slot in obj.material_slots:
			mat = slot.material
			if mat is None or not mat.node_tree:
				continue
			bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
			base = None if bsdf is None else bsdf.inputs.get("Base Color")
			rough_in = None if bsdf is None else bsdf.inputs.get("Roughness")
			if base is not None and base.is_linked and rough_in is not None and rough_in.is_linked:
				source = base.links[0].from_node
				if source.type == "TEX_IMAGE" and source.image is not None and source.image.size[0] > 0:
					textured += 1
	print(f"VERIFY meshes={len(meshes)} tris={tris} textured={textured} size=({size.x:.3f},{size.y:.3f},{size.z:.3f})")
	if tris != expected_tris:
		raise SystemExit(f"重新匯入後面數改變：{tris} != {expected_tris}")
	if textured < len(meshes):
		raise SystemExit(f"重新匯入後有網格沒有貼圖：{textured}/{len(meshes)}")
	if not (1.2 <= size.z <= 1.8 and 0.9 <= max(size.x, size.y) <= 1.3):
		raise SystemExit(f"重新匯入後比例不對：{size}")


def main():
	print("PYTHON", sys.version.replace("\n", " "))
	print("SOURCE", SRC_GLB)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=SRC_GLB)
	meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
	root = next((obj for obj in bpy.context.scene.objects if obj.type == "EMPTY"), None)
	names = ", ".join(sorted(obj.name for obj in meshes))
	print("IMPORTED", names)
	if not any(obj.name.startswith("DrumBody") for obj in meshes):
		raise SystemExit("找不到原本的桶身")
	for obj in meshes:
		apply_transform(obj)
	body = next(obj for obj in meshes if obj.name.startswith("DrumBody"))
	before = triangle_count(meshes)
	dent_body(body)
	for obj in meshes:
		if obj.name.startswith("DrumLid"):
			write_uv(obj, "lid")
		else:
			write_uv(obj, "cylinder")
		worst = 0.0
		layer = obj.data.uv_layers.active
		for poly in obj.data.polygons:
			if abs(poly.normal.z) > 0.65:
				continue
			us = [layer.data[loop_index].uv.x for loop_index in poly.loop_indices]
			worst = max(worst, max(us) - min(us))
		if worst > 0.25:
			raise SystemExit(f"{obj.name} 的 UV 接縫過寬：{worst:.3f}")
	paint = build_texture("Paint", 512, 512, paint_sample, os.path.join(OUT_DIR, "oil_drum_v2_paint"))
	lid = build_texture("Lid", 256, 256, lid_sample, os.path.join(OUT_DIR, "oil_drum_v2_lid"))
	steel = build_texture("Steel", 256, 256, steel_sample, os.path.join(OUT_DIR, "oil_drum_v2_steel"))
	for obj in meshes:
		if obj.name.startswith("DrumBody"):
			assign_pbr(obj, "DrumPaint", paint, 0.22)
		elif obj.name.startswith("DrumLid"):
			assign_pbr(obj, "DrumLidMetal", lid, 0.16)
		else:
			assign_pbr(obj, "DrumSteel", steel, 0.12)
	after = triangle_count(meshes)
	low, high = bounds_of(meshes)
	size = high - low
	print(f"SIZE studs x={size.x:.3f} y={size.y:.3f} z={size.z:.3f}")
	print(f"TRIANGLES {after} before={before}")
	if after != before:
		raise SystemExit("凹痕不該增加面數")
	scene = bpy.context.scene
	world = scene.world or bpy.data.worlds.new("World")
	scene.world = world
	world.use_nodes = True
	background = world.node_tree.nodes.get("Background")
	if background is not None:
		background.inputs["Color"].default_value = (0.2, 0.2, 0.21, 1.0)
		background.inputs["Strength"].default_value = 0.85
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
	bpy.ops.object.light_add(type="SUN", location=(2.4, -1.4, 3.6))
	sun = bpy.context.active_object
	sun.data.energy = 3.4
	look_at(sun, Vector((0.0, 0.0, 0.7)))
	bpy.ops.object.light_add(type="AREA", location=(-2.4, -2.6, 2.2))
	fill = bpy.context.active_object
	fill.data.energy = 18.0
	fill.data.size = 4.0
	look_at(fill, Vector((0.0, 0.0, 0.7)))
	render_view(meshes, Vector((0.0, -2.7, 0.72)), FRONT_PATH)
	render_view(meshes, Vector((1.85, -2.05, 1.55)), ANGLE_PATH)
	export_models(root, meshes)
	print("FRONT", FRONT_PATH)
	print("ANGLE", ANGLE_PATH)
	print("FBX", FBX_PATH)
	print("GLB", GLB_PATH)
	verify_roundtrip(after)


if __name__ == "__main__":
	main()
