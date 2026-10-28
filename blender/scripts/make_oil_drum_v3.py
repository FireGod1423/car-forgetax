"""把 V2 油桶改成霧面。不改網格，不覆蓋 V2。

Metallic 固定為 0，Roughness 為 1。金屬度貼圖全黑，粗糙度貼圖全白。
執行：
blender.exe --background --python blender/scripts/make_oil_drum_v3.py
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
SRC_GLB = os.path.join(ROOT, "exports", "v2", "oil_drum.glb")
OUT_DIR = os.path.join(ROOT, "exports", "v3")
PREVIEW_DIR = os.path.join(OUT_DIR, "previews")
os.makedirs(PREVIEW_DIR, exist_ok=True)

FBX_PATH = os.path.join(OUT_DIR, "oil_drum.fbx")
GLB_PATH = os.path.join(OUT_DIR, "oil_drum.glb")
FRONT_PATH = os.path.join(PREVIEW_DIR, "oil_drum_front.png")
ANGLE_PATH = os.path.join(PREVIEW_DIR, "oil_drum_threequarter.png")
ROUGH_PATH = os.path.join(OUT_DIR, "oil_drum_v3_roughness.png")
METAL_PATH = os.path.join(OUT_DIR, "oil_drum_v3_metalness.png")

PAINT = (0.34, 0.42, 0.45)
RUST = (0.64, 0.32, 0.12)
RUST_DARK = (0.46, 0.22, 0.08)
CHIP = (0.40, 0.38, 0.36)
STEEL = (0.26, 0.26, 0.27)


def hash2(ix, iy):
	n = (int(ix) * 374761393 + int(iy) * 668265263) & 0xFFFFFFFF
	n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
	return (n & 0xFFFFFF) / 16777215.0


def wrap_u(u, origin):
	du = u - origin
	if du > 0.5:
		du -= 1.0
	if du < -0.5:
		du += 1.0
	return du


def jagged_disk(u, v, cx, cy, radius, seed):
	du = wrap_u(u, cx)
	dv = v - cy
	if du == 0.0 and dv == 0.0:
		return True
	angle = math.atan2(dv, du)
	wedge = int((angle + math.pi) / (math.pi * 2.0) * 7.0)
	reach = radius * (0.55 + hash2(seed, wedge) * 0.7)
	return math.hypot(du, dv) < reach


def rust_cluster(u, v, cx, cy, seed):
	for piece in range(6):
		ox = (hash2(seed, piece) - 0.5) * 0.1
		oy = (hash2(seed + 5, piece) - 0.5) * 0.07
		radius = 0.018 + hash2(seed, piece + 11) * 0.04
		if jagged_disk(u, v, cx + ox, cy + oy, radius, seed + piece * 3):
			return True
	return False


def scratch_hit(u, v, u0, v0, angle, length, width):
	cu = wrap_u(u, u0)
	cv = v - v0
	along = cu * math.cos(angle) + cv * math.sin(angle)
	across = -cu * math.sin(angle) + cv * math.cos(angle)
	return 0.0 < along < length and abs(across) < width


def paint_color(u, v):
	rusty = False
	dark = False
	spots = (
		(0.18, 0.22, 4),
		(0.41, 0.16, 9),
		(0.63, 0.38, 15),
		(0.77, 0.62, 21),
		(0.32, 0.71, 28),
		(0.54, 0.84, 33),
		(0.88, 0.28, 40),
		(0.12, 0.55, 47),
	)
	for cx, cy, seed in spots:
		if rust_cluster(u, v, cx, cy, seed):
			rusty = True
			dark = hash2(seed, 2) > 0.55
			break
	bottom = 0.075 + 0.012 * math.sin(u * 17.0) + 0.008 * math.sin(u * 43.0 + 1.3)
	top = 0.93 + 0.01 * math.sin(u * 23.0 + 0.4)
	if v < bottom or v > top:
		rusty = True
		dark = dark or math.sin(u * 11.0) > 0.2
	if scratch_hit(u, v, 0.15, 0.46, 0.18, 0.32, 0.003):
		return (0.22, 0.24, 0.25)
	if scratch_hit(u, v, 0.58, 0.68, -0.42, 0.22, 0.0025):
		return (0.22, 0.24, 0.25)
	if hash2(int(u * 64.0), int(v * 64.0)) > 0.985 and not rusty:
		return CHIP
	if rusty:
		return RUST_DARK if dark else RUST
	return PAINT


def lid_color(u, v):
	dx = u - 0.5
	dy = v - 0.5
	radius = math.hypot(dx, dy) * 2.0
	angle = math.atan2(dy, dx)
	wedge = int((angle + math.pi) / (math.pi * 2.0) * 10.0)
	rim = 0.78 + (hash2(wedge, 3) - 0.5) * 0.08
	if radius > 1.05:
		return STEEL
	if radius > rim or rust_cluster(u, v, 0.42, 0.58, 12) or rust_cluster(u, v, 0.62, 0.4, 19):
		return RUST if hash2(wedge, 6) > 0.5 else RUST_DARK
	if scratch_hit(u, v, 0.38, 0.5, 0.5, 0.16, 0.004):
		return (0.22, 0.24, 0.25)
	return PAINT


def steel_color(u, v):
	edge = 0.08 + 0.015 * math.sin(u * 21.0)
	if v < edge or v > 1.0 - edge:
		return RUST_DARK if math.sin(u * 13.0) > 0.15 else RUST
	if rust_cluster(u, v, 0.3, 0.5, 8) or rust_cluster(u, v, 0.72, 0.48, 16):
		return RUST
	return STEEL


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


def color_image(name, width, height, sampler, path):
	pixels = [0.0] * (width * height * 4)
	for y in range(height):
		for x in range(width):
			color = sampler((x + 0.5) / width, (y + 0.5) / height)
			i = (y * width + x) * 4
			pixels[i] = color[0]
			pixels[i + 1] = color[1]
			pixels[i + 2] = color[2]
			pixels[i + 3] = 1.0
	return save_image(name, width, height, pixels, path, False)


def solid_image(name, width, height, rgb, path):
	pixels = []
	for _ in range(width * height):
		pixels.extend((rgb[0], rgb[1], rgb[2], 1.0))
	return save_image(name, width, height, pixels, path, True)


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
	obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


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


def glb_materials(path):
	with open(path, "rb") as handle:
		blob = handle.read()
	if blob[:4] != b"glTF":
		raise SystemExit("匯出的檔案不是 GLB")
	chunk_len, chunk_type = struct.unpack_from("<I4s", blob, 12)
	if chunk_type != b"JSON":
		raise SystemExit("GLB 缺少材質資料")
	payload = json.loads(blob[20:20 + chunk_len].decode("utf-8"))
	return payload.get("materials", [])


def png_chunk(tag, data):
	return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def png_rgb(width, height, rgb):
	raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
	header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
	return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header) + png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b"")


def patch_glb_factors():
	with open(GLB_PATH, "rb") as handle:
		blob = handle.read()
	json_len, json_type = struct.unpack_from("<I4s", blob, 12)
	if json_type != b"JSON":
		raise SystemExit("GLB 缺少材質資料")
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
	# 匯出器會把這張小圖烤成全黑，粗糙度通道變 0，Roblox 就會反光。
	# 改成 R=0、G=255、B=0：粗糙度全白，金屬度全黑。
	replacement = png_rgb(8, 8, (0, 255, 0))
	views = payload.get("bufferViews", [])
	pieces = []
	for view in views:
		offset = view.get("byteOffset", 0)
		data = bin_data[offset:offset + view["byteLength"]]
		if data.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">II", data[16:24]) == (8, 8):
			data = replacement
		pieces.append(data)
	new_bin = bytearray()
	for view, data in zip(views, pieces):
		while len(new_bin) % 4:
			new_bin.append(0)
		view["byteOffset"] = len(new_bin)
		view["byteLength"] = len(data)
		new_bin.extend(data)
	while len(new_bin) % 4:
		new_bin.append(0)
	if payload.get("buffers"):
		payload["buffers"][0]["byteLength"] = len(new_bin)
	bin_data = bytes(new_bin)
	raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
	raw += b" " * ((4 - (len(raw) % 4)) % 4)
	total = 12 + 8 + len(raw) + 8 + len(bin_data)
	packed = struct.pack("<4sII", b"glTF", 2, total)
	packed += struct.pack("<I4s", len(raw), b"JSON") + raw
	packed += struct.pack("<I4s", len(bin_data), bin_type) + bin_data
	with open(GLB_PATH, "wb") as handle:
		handle.write(packed)


def assert_exported_factors():
	materials = glb_materials(GLB_PATH)
	if not materials:
		raise SystemExit("GLB 沒有材質")
	for material in materials:
		pbr = material.get("pbrMetallicRoughness", {})
		if "metallicFactor" not in pbr or pbr["metallicFactor"] != 0.0:
			raise SystemExit(f"{material.get('name')} 的 metallicFactor 不是 0：{pbr.get('metallicFactor')}")
		if pbr.get("roughnessFactor", 1.0) < 0.95:
			raise SystemExit(f"{material.get('name')} 的 roughnessFactor 過低")
		extensions = material.get("extensions", {})
		if "KHR_materials_clearcoat" in extensions:
			raise SystemExit("GLB 含有 clearcoat")
		specular = extensions.get("KHR_materials_specular", {}).get("specularFactor", 1.0)
		if specular != 0.0:
			raise SystemExit(f"{material.get('name')} 的 specularFactor 不是 0")
		if "baseColorTexture" not in pbr or "metallicRoughnessTexture" not in pbr:
			raise SystemExit(f"{material.get('name')} 缺少顏色或粗糙度貼圖")
		print(
			f"GLB {material.get('name')} metallicFactor=0 roughnessFactor={pbr.get('roughnessFactor')} specularFactor=0"
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
	checked = 0
	for obj in meshes:
		for slot in obj.material_slots:
			mat = slot.material
			if mat is None or mat.node_tree is None:
				continue
			bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
			if bsdf is None:
				continue
			metal = bsdf.inputs["Metallic"].default_value
			rough = bsdf.inputs["Roughness"].default_value
			coat = bsdf.inputs["Coat Weight"].default_value if "Coat Weight" in bsdf.inputs else 0.0
			specular = bsdf.inputs["Specular IOR Level"].default_value if "Specular IOR Level" in bsdf.inputs else 0.0
			if not bsdf.inputs["Base Color"].is_linked or not bsdf.inputs["Roughness"].is_linked:
				raise SystemExit(f"{obj.name} 匯入後貼圖遺失")
			if metal != 0.0 or coat != 0.0:
				raise SystemExit(
					f"{obj.name} 匯入後材質不對 metal={metal} rough={rough} coat={coat} specular={specular}"
				)
			print(f"REIMPORT {obj.name} metal={metal} rough={rough} specular={specular}")
			checked += 1
	for image in bpy.data.images:
		if image.size[0] == 0 or image.size[0] > 32:
			continue
		pixel = tuple(round(channel, 3) for channel in image.pixels[:4])
		print(f"IMAGE {image.name} {pixel}")
		if pixel[1] < 0.95 or pixel[2] > 0.02:
			raise SystemExit(f"粗糙度或金屬度通道錯誤：{pixel}")
	print(f"VERIFY meshes={len(meshes)} tris={tris} matte={checked} size=({size.x:.3f},{size.y:.3f},{size.z:.3f})")
	if tris != expected_tris or checked < len(meshes):
		raise SystemExit("重新匯入後幾何或霧面材質不完整")
	if not (1.2 <= size.z <= 1.8 and 0.9 <= max(size.x, size.y) <= 1.3):
		raise SystemExit(f"重新匯入後比例不對：{size}")


def main():
	print("PYTHON", sys.version.replace("\n", " "))
	print("SOURCE", SRC_GLB)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=SRC_GLB)
	meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
	root = next((obj for obj in bpy.context.scene.objects if obj.type == "EMPTY"), None)
	if not any(obj.name.startswith("DrumBody") for obj in meshes):
		raise SystemExit("找不到 V2 桶身")
	before = triangle_count(meshes)
	# 匯出時場景裡只能有這一張 ORM。G=1 是粗糙，B=0 是非金屬。
	orm = solid_image("Orm", 8, 8, (1.0, 1.0, 0.0), os.path.join(OUT_DIR, "oil_drum_v3_orm.png"))
	paint = color_image("Paint", 512, 512, paint_color, os.path.join(OUT_DIR, "oil_drum_v3_paint_albedo.png"))
	lid = color_image("Lid", 256, 256, lid_color, os.path.join(OUT_DIR, "oil_drum_v3_lid_albedo.png"))
	steel = color_image("Steel", 256, 256, steel_color, os.path.join(OUT_DIR, "oil_drum_v3_steel_albedo.png"))
	for obj in meshes:
		if obj.name.startswith("DrumBody"):
			assign_matte(obj, "DrumPaintMatte", paint, orm)
		elif obj.name.startswith("DrumLid"):
			assign_matte(obj, "DrumLidMatte", lid, orm)
		else:
			assign_matte(obj, "DrumSteelMatte", steel, orm)
	after = triangle_count(meshes)
	low, high = bounds_of(meshes)
	size = high - low
	print(f"SIZE studs x={size.x:.3f} y={size.y:.3f} z={size.z:.3f}")
	print(f"TRIANGLES {after}")
	if after != before:
		raise SystemExit("V3 不該改變面數")
	scene = bpy.context.scene
	world = scene.world or bpy.data.worlds.new("World")
	scene.world = world
	world.use_nodes = True
	background = world.node_tree.nodes.get("Background")
	if background is not None:
		background.inputs["Color"].default_value = (0.22, 0.22, 0.23, 1.0)
		background.inputs["Strength"].default_value = 1.0
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
	bpy.ops.object.light_add(type="SUN", location=(2.2, -1.6, 3.4))
	sun = bpy.context.active_object
	sun.data.energy = 3.6
	look_at(sun, Vector((0.0, 0.0, 0.7)))
	bpy.ops.object.light_add(type="AREA", location=(-2.2, -2.4, 1.8))
	fill = bpy.context.active_object
	fill.data.energy = 30.0
	fill.data.size = 3.0
	look_at(fill, Vector((0.0, 0.0, 0.7)))
	bpy.ops.object.light_add(type="POINT", location=(0.55, -0.9, 1.15))
	probe = bpy.context.active_object
	probe.data.energy = 8.0
	render_view(meshes, Vector((0.0, -2.7, 0.72)), FRONT_PATH)
	render_view(meshes, Vector((1.85, -2.05, 1.55)), ANGLE_PATH)
	export_models(root, meshes)
	solid_image("Roughness", 8, 8, (1.0, 1.0, 1.0), ROUGH_PATH)
	solid_image("Metalness", 8, 8, (0.0, 0.0, 0.0), METAL_PATH)
	patch_glb_factors()
	assert_exported_factors()
	print("FRONT", FRONT_PATH)
	print("ANGLE", ANGLE_PATH)
	print("GLB", GLB_PATH)
	verify_roundtrip(after)


if __name__ == "__main__":
	main()
