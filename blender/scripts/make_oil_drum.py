"""精緻低面數生鏽油桶。1 Blender 單位 = 1 Roblox stud。

執行：
blender.exe --background --python blender/scripts/make_oil_drum.py
"""

import math
import os
import sys

import bpy
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
EXPORT_DIR = os.path.join(ROOT, "exports")
PREVIEW_DIR = os.path.join(EXPORT_DIR, "previews")
os.makedirs(PREVIEW_DIR, exist_ok=True)

RUST_PATH = os.path.join(EXPORT_DIR, "oil_drum_rust.png")
FBX_PATH = os.path.join(EXPORT_DIR, "oil_drum.fbx")
GLB_PATH = os.path.join(EXPORT_DIR, "oil_drum.glb")
PREVIEW_PATH = os.path.join(PREVIEW_DIR, "oil_drum.png")

SIDES = 18


def reset_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.unit_settings.system = "NONE"
	scene.unit_settings.scale_length = 1.0


def rust_image():
	width = 256
	height = 256
	image = bpy.data.images.new("OilDrumRust", width, height, alpha=False)
	pixels = [0.0] * (width * height * 4)
	for y in range(height):
		for x in range(width):
			u = x / width
			v = y / height
			grain = (
				math.sin(u * 48.0) * math.sin(v * 36.0) * 0.08
				+ math.sin((u + v) * 17.0) * 0.05
			)
			blotch = math.sin(u * 9.0 + 1.7) * math.sin(v * 7.0 + 0.4)
			blotch = max(0.0, blotch) ** 2
			pit = math.sin(u * 31.0 + v * 12.0) * math.sin(v * 27.0)
			pit = max(0.0, pit - 0.55)
			base_r, base_g, base_b = 0.45, 0.24, 0.13
			dark = 0.22 + blotch * 0.55 + pit * 0.8
			r = min(1.0, base_r * (1.15 - dark) + grain + pit * 0.15)
			g = min(1.0, base_g * (1.05 - dark * 0.8) + grain * 0.4)
			b = min(1.0, base_b * (0.85 - dark * 0.35))
			i = (y * width + x) * 4
			pixels[i] = r
			pixels[i + 1] = g
			pixels[i + 2] = b
			pixels[i + 3] = 1.0
	image.pixels.foreach_set(pixels)
	image.filepath_raw = RUST_PATH
	image.file_format = "PNG"
	image.save()
	image.pack()
	return image


def principled(name, color, metallic, roughness, image=None):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nodes = mat.node_tree.nodes
	links = mat.node_tree.links
	bsdf = nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	if image is not None:
		tex = nodes.new("ShaderNodeTexImage")
		tex.image = image
		links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	return mat


def add_cylinder(name, radius, depth, location, vertices, material):
	bpy.ops.mesh.primitive_cylinder_add(
		vertices=vertices,
		radius=radius,
		depth=depth,
		location=location,
	)
	obj = bpy.context.active_object
	obj.name = name
	obj.data.name = name
	obj.data.materials.append(material)
	bpy.ops.object.shade_smooth()
	return obj


def build(rust, metal, bung_mat):
	root = bpy.data.objects.new("OilDrum", None)
	bpy.context.scene.collection.objects.link(root)
	parts = [
		add_cylinder("DrumBody", 0.48, 1.18, (0.0, 0.0, 0.65), SIDES, rust),
		add_cylinder("DrumRimBot", 0.53, 0.07, (0.0, 0.0, 0.045), SIDES, metal),
		add_cylinder("DrumRimTop", 0.53, 0.07, (0.0, 0.0, 1.255), SIDES, metal),
		add_cylinder("DrumBandA", 0.505, 0.055, (0.0, 0.0, 0.42), SIDES, metal),
		add_cylinder("DrumBandB", 0.505, 0.055, (0.0, 0.0, 0.9), SIDES, metal),
		add_cylinder("DrumLid", 0.455, 0.05, (0.0, 0.0, 1.315), SIDES, rust),
		add_cylinder("DrumBung", 0.055, 0.045, (0.16, 0.0, 1.355), 8, bung_mat),
	]
	for obj in parts:
		obj.parent = root
	return root, parts


def bounds_of(objects):
	low = Vector((1e9, 1e9, 1e9))
	high = Vector((-1e9, -1e9, -1e9))
	for obj in objects:
		for corner in obj.bound_box:
			world = obj.matrix_world @ Vector(corner)
			low.x = min(low.x, world.x)
			low.y = min(low.y, world.y)
			low.z = min(low.z, world.z)
			high.x = max(high.x, world.x)
			high.y = max(high.y, world.y)
			high.z = max(high.z, world.z)
	return low, high


def triangle_count(objects):
	total = 0
	for obj in objects:
		mesh = obj.data
		mesh.calc_loop_triangles()
		total += len(mesh.loop_triangles)
	return total


def look_at(camera, target):
	direction = target - camera.location
	camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def frame_scene(objects):
	scene = bpy.context.scene
	world = scene.world or bpy.data.worlds.new("World")
	scene.world = world
	world.use_nodes = True
	background = world.node_tree.nodes.get("Background")
	if background is not None:
		background.inputs["Color"].default_value = (0.045, 0.045, 0.05, 1.0)
		background.inputs["Strength"].default_value = 1.0

	low, high = bounds_of(objects)
	center = (low + high) * 0.5
	bpy.ops.object.camera_add(location=(center.x + 1.85, center.y - 2.15, center.z + 0.85))
	camera = bpy.context.active_object
	camera.name = "PreviewCamera"
	look_at(camera, center)
	scene.camera = camera

	bpy.ops.object.light_add(type="SUN", location=(2.0, -1.5, 4.0))
	sun = bpy.context.active_object
	sun.data.energy = 3.2
	look_at(sun, center)
	bpy.ops.object.light_add(type="AREA", location=(-1.6, -0.8, 2.2))
	fill = bpy.context.active_object
	fill.data.energy = 40.0
	fill.data.size = 2.0
	look_at(fill, center)

	for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
		try:
			scene.render.engine = engine
			break
		except TypeError:
			continue
	scene.render.resolution_x = 960
	scene.render.resolution_y = 960
	scene.render.filepath = PREVIEW_PATH
	scene.render.image_settings.file_format = "PNG"
	scene.render.film_transparent = False
	if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
		scene.eevee.taa_render_samples = 16
	bpy.ops.render.render(write_still=True)


def export(root, parts):
	bpy.ops.object.select_all(action="DESELECT")
	root.select_set(True)
	for obj in parts:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = root
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
	)


def main():
	print("PYTHON", sys.version.replace("\n", " "))
	print("BLENDER", bpy.app.version_string)
	reset_scene()
	image = rust_image()
	rust = principled("Rust", (0.45, 0.22, 0.12), 0.35, 0.72, image)
	metal = principled("Steel", (0.18, 0.17, 0.16), 0.85, 0.38)
	bung = principled("Bung", (0.55, 0.42, 0.22), 0.7, 0.42)
	root, parts = build(rust, metal, bung)
	low, high = bounds_of(parts)
	size = high - low
	tris = triangle_count(parts)
	print(f"SIZE studs x={size.x:.3f} y={size.y:.3f} z={size.z:.3f}")
	print(f"TRIANGLES {tris}")
	frame_scene(parts)
	export(root, parts)
	print("PREVIEW", PREVIEW_PATH)
	print("FBX", FBX_PATH)
	print("GLB", GLB_PATH)
	if tris > 3000:
		raise SystemExit(f"面數過高：{tris}")
	if not (1.2 <= size.z <= 1.8) or not (0.9 <= size.x <= 1.3):
		raise SystemExit(f"比例不對：{size}")


if __name__ == "__main__":
	main()
