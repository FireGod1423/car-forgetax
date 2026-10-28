"""Optimize the Tripo red hatchback for Roblox. Does not save the source GLB.

Reads blender/exports/Tripo/red hatchback 3d model.glb and writes
blender/exports/Tripo/optimized_hatchback/.
"""

import array
import json
import math
import os

import bmesh
import bpy
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
SRC = os.path.join(ROOT, "exports", "Tripo", "red hatchback 3d model.glb")
OUT = os.path.join(ROOT, "exports", "Tripo", "optimized_hatchback")
TARGET_LENGTH = 2.65

# Body counts below about 12,000 open the door seam and dent the rear arch.
# These budgets stay above that, so the shape wins over the 15k / 10k targets.
VARIANTS = (
	{"tag": "version_a", "body": 14000, "wheel": 2200},
	{"tag": "version_b", "body": 12000, "wheel": 1800},
)


def log(message):
	print("OPT %s" % message, flush=True)


def reset_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
	return [obj for obj in bpy.data.objects if obj.type == "MESH"]


def triangle_count(obj):
	obj.data.calc_loop_triangles()
	return len(obj.data.loop_triangles)


def bounds_of(objects):
	low = Vector((1e9, 1e9, 1e9))
	high = Vector((-1e9, -1e9, -1e9))
	for obj in objects:
		matrix = obj.matrix_world
		for vert in obj.data.vertices:
			world = matrix @ vert.co
			low = Vector((min(low.x, world.x), min(low.y, world.y), min(low.z, world.z)))
			high = Vector((max(high.x, world.x), max(high.y, world.y), max(high.z, world.z)))
	return low, high


def join_meshes():
	meshes = mesh_objects()
	bpy.ops.object.select_all(action="DESELECT")
	for obj in meshes:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	obj = bpy.context.view_layer.objects.active
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return obj


def weld(obj, distance):
	mesh = obj.data
	bm = bmesh.new()
	bm.from_mesh(mesh)
	before = len(bm.verts)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=distance)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(mesh)
	bm.free()
	mesh.update()
	log("weld %d -> %d verts, tris %d" % (before, len(mesh.vertices), triangle_count(obj)))


def clear_split_normals(obj):
	mesh = obj.data
	sharp = mesh.attributes.get("sharp_face")
	if sharp is not None:
		mesh.attributes.remove(sharp)
	if getattr(mesh, "has_custom_normals", False):
		bpy.ops.object.select_all(action="DESELECT")
		obj.select_set(True)
		bpy.context.view_layer.objects.active = obj
		bpy.ops.object.mode_set(mode="OBJECT")
		bpy.ops.object.mode_set(mode="EDIT")
		bpy.ops.mesh.customdata_custom_splitnormals_clear()
		bpy.ops.object.mode_set(mode="OBJECT")
	for poly in mesh.polygons:
		poly.use_smooth = True
	mesh.validate()
	mesh.update()


def soften_normal_maps():
	for mat in bpy.data.materials:
		if mat.node_tree is None:
			continue
		for node in mat.node_tree.nodes:
			if node.type == "NORMAL_MAP":
				node.inputs["Strength"].default_value = 0.35


def collapse_to(obj, target):
	current = triangle_count(obj)
	if current <= target:
		log("skip decimate %s tris %d" % (obj.name, current))
		clear_split_normals(obj)
		return current
	modifier = obj.modifiers.new("Decimate", "DECIMATE")
	modifier.decimate_type = "COLLAPSE"
	ratio = max(target / float(current), 0.001)
	modifier.ratio = ratio
	modifier.use_collapse_triangulate = True
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.modifier_apply(modifier=modifier.name)
	result = triangle_count(obj)
	log("decimate %s %d -> %d ratio %.4f target %d" % (obj.name, current, result, ratio, target))
	clear_split_normals(obj)
	return result


def vertex_array(obj):
	mesh = obj.data
	coords = array.array("f", [0.0]) * (len(mesh.vertices) * 3)
	mesh.vertices.foreach_get("co", coords)
	return coords


def median(values):
	ordered = sorted(values)
	mid = len(ordered) // 2
	if len(ordered) % 2:
		return ordered[mid]
	return (ordered[mid - 1] + ordered[mid]) * 0.5


def detect_wheels(obj):
	coords = vertex_array(obj)
	count = len(coords) // 3
	quadrants = {(sx, sy): [] for sx in (-1, 1) for sy in (-1, 1)}
	for index in range(count):
		x = coords[index * 3]
		y = coords[index * 3 + 1]
		z = coords[index * 3 + 2]
		if z < 0.08 and abs(x) > 0.08 and abs(y) > 0.18:
			quadrants[(1 if x >= 0 else -1, 1 if y >= 0 else -1)].append((x, y, z))
	wheels = []
	for (sx, sy), points in quadrants.items():
		if len(points) < 20:
			raise RuntimeError("wheel quadrant %s %s has %d points" % (sx, sy, len(points)))
		contact = [point for point in points if point[2] < 0.02] or points
		center_x = median([point[0] for point in contact])
		center_y = median([point[1] for point in contact])
		nearby = []
		for index in range(count):
			x = coords[index * 3]
			y = coords[index * 3 + 1]
			z = coords[index * 3 + 2]
			if abs(x - center_x) < 0.16 and abs(y - center_y) < 0.22 and z < 0.32:
				nearby.append((x, y, z))
		best_radius = 0.09
		best_hits = -1
		for step in range(16):
			radius = 0.065 + step * 0.005
			hits = 0
			for x, y, z in nearby:
				if abs(x - center_x) > 0.09:
					continue
				if abs(math.hypot(y - center_y, z - radius) - radius) < 0.008:
					hits += 1
			if hits > best_hits:
				best_hits = hits
				best_radius = radius
		radius = best_radius
		center_z = radius
		widths = []
		for x, y, z in nearby:
			if abs(math.hypot(y - center_y, z - center_z) - radius) < 0.012:
				widths.append(abs(x - center_x))
		if len(widths) < 30:
			raise RuntimeError("wheel width %s %s has %d points" % (sx, sy, len(widths)))
		widths.sort()
		half_width = widths[min(int(len(widths) * 0.97), len(widths) - 1)]
		log("wheel measure hits %d widths %d" % (best_hits, len(widths)))
		name = ("F" if sy < 0 else "R") + ("R" if sx > 0 else "L")
		wheel = {
			"name": "Wheel_" + name,
			"center": (center_x, center_y, center_z),
			"radius": radius,
			"half_width": max(half_width, 0.035),
		}
		wheels.append(wheel)
		log(
			"wheel %s center %.3f %.3f %.3f radius %.3f half %.3f"
			% (wheel["name"], center_x, center_y, center_z, radius, wheel["half_width"])
		)
	return wheels


def face_in_wheel(center, wheel):
	cx, cy, cz = wheel["center"]
	radial = math.hypot(center.y - cy, center.z - cz)
	return abs(center.x - cx) <= wheel["half_width"] * 1.12 and radial <= wheel["radius"] * 1.03


def copy_wheel_faces(faces, uv_layers, name, source):
	mesh = bpy.data.meshes.new(name)
	bm = bmesh.new()
	dst_uvs = [bm.loops.layers.uv.new(layer.name) for layer in uv_layers]
	copied = {}
	for face in faces:
		new_verts = []
		for vert in face.verts:
			made = copied.get(vert.index)
			if made is None:
				made = bm.verts.new(vert.co)
				copied[vert.index] = made
			new_verts.append(made)
		try:
			new_face = bm.faces.new(new_verts)
		except ValueError:
			continue
		new_face.smooth = True
		new_face.material_index = face.material_index
		for src_loop, dst_loop in zip(face.loops, new_face.loops):
			for src_uv, dst_uv in zip(uv_layers, dst_uvs):
				dst_loop[dst_uv].uv = src_loop[src_uv].uv
	bm.to_mesh(mesh)
	bm.free()
	mesh.update()
	obj = bpy.data.objects.new(name, mesh)
	for slot in source.material_slots:
		obj.data.materials.append(slot.material)
	bpy.context.collection.objects.link(obj)
	return obj


def separate_wheels(obj, wheels):
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bm.faces.ensure_lookup_table()
	uv_layers = list(bm.loops.layers.uv)
	groups = {wheel["name"]: [] for wheel in wheels}
	for face in bm.faces:
		center = face.calc_center_median()
		for wheel in wheels:
			if face_in_wheel(center, wheel):
				groups[wheel["name"]].append(face)
				break
	created = []
	remove = []
	for wheel in wheels:
		faces = groups[wheel["name"]]
		if len(faces) < 30 or len(faces) > len(bm.faces) * 0.3:
			bm.free()
			raise RuntimeError("%s selected %d faces" % (wheel["name"], len(faces)))
		new_obj = copy_wheel_faces(faces, uv_layers, wheel["name"], obj)
		created.append(new_obj)
		remove.extend(faces)
		log("separated %s faces %d" % (wheel["name"], len(faces)))
	bmesh.ops.delete(bm, geom=remove, context="FACES")
	bm.to_mesh(obj.data)
	bm.free()
	obj.data.update()
	obj.name = "Body"
	obj.data.name = "Body"
	for wheel in created:
		low, high = bounds_of([wheel])
		span_y = max(high.y - low.y, 1e-6)
		log(
			"wheel mesh %s tris %d size %.3f %.3f %.3f round %.3f"
			% (wheel.name, triangle_count(wheel), high.x - low.x, high.y - low.y, high.z - low.z, (high.z - low.z) / span_y)
		)
	log("body tris %d" % triangle_count(obj))
	return obj, created


def scale_to_length(objects):
	low, high = bounds_of(objects)
	length = high.y - low.y
	factor = TARGET_LENGTH / length
	for obj in objects:
		for vert in obj.data.vertices:
			vert.co *= factor
	low, high = bounds_of(objects)
	drop = low.z
	for obj in objects:
		for vert in obj.data.vertices:
			vert.co.z -= drop
	low, high = bounds_of(objects)
	size = high - low
	log("scaled size %.3f x %.3f x %.3f ground %.4f factor %.3f" % (size.x, size.y, size.z, low.z, factor))
	return low, high


def set_origin(obj, world_point):
	point = Vector(world_point)
	for vert in obj.data.vertices:
		vert.co -= point
	obj.location = point


def wheel_centers_from_mesh(objects):
	found = []
	for obj in objects:
		if not obj.name.startswith("Wheel_"):
			continue
		low, high = bounds_of([obj])
		center = (low + high) * 0.5
		found.append((obj, center))
	return found


def parent_under(name, objects):
	root = bpy.data.objects.new(name, None)
	bpy.context.collection.objects.link(root)
	for obj in objects:
		obj.parent = root
		obj.matrix_parent_inverse = root.matrix_world.inverted()
	return root


def material_report(obj):
	rows = []
	for slot in obj.material_slots:
		mat = slot.material
		if mat is None or mat.node_tree is None:
			rows.append({"name": None})
			continue
		entry = {"name": mat.name, "images": []}
		bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
		if bsdf is not None:
			for socket_name in ("Roughness", "Metallic", "Specular IOR Level", "Alpha", "Emission Strength", "Transmission Weight"):
				socket = bsdf.inputs.get(socket_name)
				if socket is None or socket.links:
					entry[socket_name] = "linked" if socket is not None and socket.links else "missing"
				else:
					value = socket.default_value
					entry[socket_name] = float(value) if not hasattr(value, "__len__") else [round(float(channel), 4) for channel in value]
		for node in mat.node_tree.nodes:
			if node.type == "TEX_IMAGE" and node.image is not None:
				entry["images"].append(
					{"name": node.image.name, "size": [int(node.image.size[0]), int(node.image.size[1])]}
				)
		rows.append(entry)
	return rows


def export_glb(root, objects, filepath):
	bpy.ops.object.select_all(action="DESELECT")
	root.select_set(True)
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		export_format="GLB",
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials="EXPORT",
	)


def look_at(obj, target):
	obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def studio(center):
	for obj in list(bpy.data.objects):
		if obj.type == "LIGHT" or obj.name in {"Floor", "Cam"}:
			bpy.data.objects.remove(obj, do_unlink=True)
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
	scene.render.film_transparent = False
	if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
		scene.eevee.taa_render_samples = 32
	world = bpy.data.worlds.new("Studio")
	world.use_nodes = True
	background = world.node_tree.nodes.get("Background")
	if background is not None:
		background.inputs[0].default_value = (0.56, 0.57, 0.59, 1)
		background.inputs[1].default_value = 0.45
	scene.world = world
	for name, location, energy, size in (
		("Key", center + Vector((-2.2, -2.4, 2.6)), 380, 2.2),
		("Fill", center + Vector((2.5, -1.4, 1.4)), 130, 3.0),
		("Rim", center + Vector((1.2, 2.8, 2.2)), 240, 1.6),
	):
		data = bpy.data.lights.new(name, "AREA")
		data.energy = energy
		data.size = size
		light = bpy.data.objects.new(name, data)
		light.location = location
		look_at(light, center)
		bpy.context.collection.objects.link(light)
	floor_mesh = bpy.data.meshes.new("Floor")
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1)
	for vert in bm.verts:
		vert.co.x *= 16
		vert.co.y *= 16
		vert.co.z *= 0.02
		vert.co.z -= 0.02
	bm.to_mesh(floor_mesh)
	bm.free()
	floor = bpy.data.objects.new("Floor", floor_mesh)
	material = bpy.data.materials.new("Floor")
	material.use_nodes = True
	bsdf = material.node_tree.nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = (0.35, 0.36, 0.38, 1)
	bsdf.inputs["Roughness"].default_value = 0.95
	floor.data.materials.append(material)
	bpy.context.collection.objects.link(floor)


def render_views(objects, folder):
	os.makedirs(folder, exist_ok=True)
	shown = set(objects)
	for obj in bpy.data.objects:
		if obj.type == "MESH":
			obj.hide_render = obj not in shown
	low, high = bounds_of(objects)
	center = (low + high) * 0.5
	span = max(high.x - low.x, high.y - low.y, high.z - low.z)
	studio(center)
	scene = bpy.context.scene
	camera = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	bpy.context.collection.objects.link(camera)
	scene.camera = camera
	camera.data.lens = 50
	camera.data.dof.use_dof = False
	camera.data.clip_start = 0.05
	camera.data.clip_end = 80
	views = {
		"front_threequarter": Vector((-1.05, -1.45, 0.62)),
		"side": Vector((2.35, 0.04, 0.38)),
		"rear_threequarter": Vector((-1.05, 1.45, 0.62)),
	}
	paths = {}
	for name, direction in views.items():
		camera.location = center + direction.normalized() * span * 2.15
		look_at(camera, center + Vector((0, 0, span * 0.02)))
		filepath = os.path.join(folder, name + ".png")
		scene.render.filepath = filepath
		bpy.ops.render.render(write_still=True)
		paths[name] = filepath
		log("render %s" % filepath)
	return paths


def import_source():
	reset_scene()
	before = os.stat(SRC)
	bpy.ops.import_scene.gltf(filepath=SRC)
	after = os.stat(SRC)
	if before.st_mtime != after.st_mtime or before.st_size != after.st_size:
		raise RuntimeError("source GLB changed during import")
	return join_meshes()


def build_base():
	obj = import_source()
	log("source tris %d" % triangle_count(obj))
	wheels = detect_wheels(obj)
	weld(obj, 0.00001)
	body, wheel_objects = separate_wheels(obj, wheels)
	soften_normal_maps()
	work = os.path.join(OUT, "_work")
	os.makedirs(work, exist_ok=True)
	meta_path = os.path.join(work, "wheels.json")
	with open(meta_path, "w", encoding="utf-8") as handle:
		json.dump(wheels, handle, indent=2)
	bpy.ops.wm.save_as_mainfile(filepath=os.path.join(work, "intermediate.blend"))
	log("intermediate saved")
	return current_parts()


def current_parts():
	body = bpy.data.objects["Body"]
	wheels = [bpy.data.objects[name] for name in ("Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR")]
	return body, wheels


def load_intermediate():
	reset_scene()
	bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, "_work", "intermediate.blend"))
	return current_parts()


def clone_parts(body, wheels, suffix):
	clones = []
	for obj in [body] + wheels:
		clone = obj.copy()
		clone.data = obj.data.copy()
		clone.name = obj.name + suffix
		bpy.context.collection.objects.link(clone)
		clones.append(clone)
	return clones[0], clones[1:]


def shade_parts(objects):
	bpy.ops.object.select_all(action="DESELECT")
	for obj in objects:
		obj.hide_set(False)
		obj.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))


def finish_variant(tag, body_budget, wheel_budget, body, wheels):
	log("budgets %s body %d wheel %d" % (tag, body_budget, wheel_budget))
	collapse_to(body, body_budget)
	for wheel in wheels:
		collapse_to(wheel, wheel_budget)
	parts = [body] + wheels
	shade_parts(parts)
	scale_to_length(parts)
	for wheel, center in wheel_centers_from_mesh(wheels):
		set_origin(wheel, center)
		log("origin %s %s" % (wheel.name, tuple(round(value, 3) for value in wheel.location)))
	root = parent_under(tag, parts)
	folder = os.path.join(OUT, tag)
	os.makedirs(folder, exist_ok=True)
	bpy.ops.wm.save_as_mainfile(filepath=os.path.join(folder, tag + ".blend"))
	export_glb(root, parts, os.path.join(folder, tag + ".glb"))
	stats = {
		"tag": tag,
		"body_tris": triangle_count(body),
		"wheels": {wheel.name: triangle_count(wheel) for wheel in wheels},
		"materials": material_report(body),
	}
	stats["total_tris"] = stats["body_tris"] + sum(stats["wheels"].values())
	low, high = bounds_of(parts)
	stats["size"] = [round(high.x - low.x, 3), round(high.y - low.y, 3), round(high.z - low.z, 3)]
	stats["ground"] = round(low.z, 4)
	render_views(parts, folder)
	with open(os.path.join(folder, "stats.json"), "w", encoding="utf-8") as handle:
		json.dump(stats, handle, indent=2)
	log("variant %s total %d" % (tag, stats["total_tris"]))
	return stats


def render_original():
	obj = import_source()
	low, high = bounds_of([obj])
	factor = TARGET_LENGTH / (high.y - low.y)
	for vert in obj.data.vertices:
		vert.co *= factor
	low, high = bounds_of([obj])
	drop = low.z
	for vert in obj.data.vertices:
		vert.co.z -= drop
	folder = os.path.join(OUT, "original")
	render_views([obj], folder)
	log("original preview only, source not saved")


def verify_glb(filepath):
	reset_scene()
	bpy.ops.import_scene.gltf(filepath=filepath)
	rows = []
	for obj in mesh_objects():
		rows.append({
			"name": obj.name,
			"tris": triangle_count(obj),
			"location": [round(obj.location.x, 3), round(obj.location.y, 3), round(obj.location.z, 3)],
			"materials": material_report(obj),
		})
	low, high = bounds_of(mesh_objects())
	log("reimport %s objects %s size %.3f %.3f %.3f" % (
		os.path.basename(filepath),
		[row["name"] for row in rows],
		high.x - low.x,
		high.y - low.y,
		high.z - low.z,
	))
	return {"file": filepath, "objects": rows, "size": [round(high.x - low.x, 3), round(high.y - low.y, 3), round(high.z - low.z, 3)], "ground": round(low.z, 4)}


def main():
	source_stat = os.stat(SRC)
	os.makedirs(OUT, exist_ok=True)
	results = []
	for index, item in enumerate(VARIANTS):
		if index == 0:
			body, wheels = build_base()
		else:
			body, wheels = load_intermediate()
		results.append(finish_variant(item["tag"], item["body"], item["wheel"], body, wheels))
	render_original()
	checks = [verify_glb(os.path.join(OUT, item["tag"], item["tag"] + ".glb")) for item in VARIANTS]
	report = {"source_tris": 1953042, "variants": results, "reimport": checks}
	with open(os.path.join(OUT, "stats.json"), "w", encoding="utf-8") as handle:
		json.dump(report, handle, indent=2)
	after = os.stat(SRC)
	if source_stat.st_mtime != after.st_mtime or source_stat.st_size != after.st_size:
		raise RuntimeError("source GLB was modified")
	log("source unchanged size %d" % after.st_size)


if __name__ == "__main__":
	main()
