"""CarForgeTax Common hatch v2。

連續曲面的掀背車，不覆蓋舊的 hatch_common。
車頭朝 Blender -Y。單位是公尺，約等於 Roblox stud。

blender.exe --background --python blender/scripts/make_hatch_v2.py
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(ROOT, "exports", "cars")
PREVIEW_DIR = os.path.join(OUT_DIR, "previews")
KEY = "hatch_common_v2"

FRONT_AXLE = -0.76
REAR_AXLE = 0.70
ARCH_R = 0.335
WHEEL_R = 0.295
WHEEL_Z = 0.307
TRACK = 0.575
NOSE = -1.36
TAIL = 1.34

CENTER = [
	(-1.32, 0.48),
	(-1.16, 0.54),
	(-1.06, 0.56),
	(-0.91, 0.58),
	(-0.76, 0.66),
	(-0.61, 0.82),
	(-0.46, 0.96),
	(-0.32, 1.02),
	(0.02, 1.05),
	(0.22, 1.05),
	(0.40, 1.04),
	(0.55, 0.98),
	(0.70, 0.86),
	(0.85, 0.72),
	(1.00, 0.60),
	(1.16, 0.50),
	(1.28, 0.46),
]
FENDER = [
	(-1.32, 0.46),
	(-1.16, 0.56),
	(-1.06, 0.64),
	(-0.91, 0.70),
	(-0.76, 0.74),
	(-0.61, 0.80),
	(-0.46, 0.94),
	(-0.32, 1.00),
	(0.02, 1.01),
	(0.22, 1.01),
	(0.40, 1.00),
	(0.55, 0.94),
	(0.70, 0.82),
	(0.85, 0.70),
	(1.00, 0.58),
	(1.16, 0.48),
	(1.28, 0.42),
]
WIDTH = [
	(-1.32, 0.50),
	(-1.16, 0.60),
	(-1.06, 0.64),
	(-0.91, 0.68),
	(-0.76, 0.70),
	(-0.61, 0.68),
	(-0.46, 0.64),
	(-0.32, 0.63),
	(0.02, 0.62),
	(0.22, 0.62),
	(0.40, 0.64),
	(0.55, 0.68),
	(0.70, 0.70),
	(0.85, 0.66),
	(1.00, 0.60),
	(1.16, 0.52),
	(1.28, 0.44),
]
BELT = [
	(-0.16, 0.66),
	(0.10, 0.72),
	(0.42, 0.735),
	(0.66, 0.70),
	(0.90, 0.62),
]
SECTION = [
	(0.00, 0.00, 0.00),
	(0.30, 0.42, 0.00),
	(0.58, 0.78, 0.00),
	(0.86, 1.00, 0.00),
	(1.01, 0.72, 0.28),
	(1.045, 0.46, 0.54),
	(1.00, 0.20, 0.80),
	(0.93, 0.00, 1.00),
]


def smoothstep(t):
	t = max(0.0, min(1.0, t))
	return t * t * (3.0 - 2.0 * t)


def sample(keys, y):
	if y <= keys[0][0]:
		return keys[0][1]
	if y >= keys[-1][0]:
		return keys[-1][1]
	for index in range(len(keys) - 1):
		y0, value0 = keys[index]
		y1, value1 = keys[index + 1]
		if y0 <= y <= y1:
			span = max(y1 - y0, 1e-6)
			return value0 + (value1 - value0) * ((y - y0) / span)
	return keys[-1][1]


def flare(y):
	return 0.0


def half_width(y):
	return sample(WIDTH, y) + flare(y)


def z_center(y):
	return sample(CENTER, y)


def z_fender(y):
	return max(sample(FENDER, y), z_lip(y) + 0.04)


def base_lip(y):
	if y < FRONT_AXLE - ARCH_R:
		return sample([(-1.36, 0.155), (-1.12, 0.175), (-0.95, 0.20)], y)
	if y > REAR_AXLE + ARCH_R:
		return sample([(1.08, 0.20), (1.22, 0.17), (1.34, 0.155)], y)
	return 0.20


def z_lip(y):
	blended = None
	for axle in (FRONT_AXLE, REAR_AXLE):
		delta = abs(y - axle)
		if delta < ARCH_R:
			opening = WHEEL_Z + math.sqrt(max(ARCH_R * ARCH_R - delta * delta, 0.0))
			blended = opening if blended is None else max(blended, opening)
		elif delta < ARCH_R + 0.11:
			edge = WHEEL_Z
			mix = smoothstep((delta - ARCH_R) / 0.11)
			value = edge + (base_lip(y) - edge) * mix
			blended = value if blended is None else max(blended, value)
	if blended is None:
		return base_lip(y)
	return blended


def in_arch(y):
	return abs(y - FRONT_AXLE) < ARCH_R - 0.015 or abs(y - REAR_AXLE) < ARCH_R - 0.015


def station_ys():
	return [-1.32, -1.16, -1.06, -0.91, -0.76, -0.61, -0.46, -0.32, 0.02, 0.22, 0.40, 0.55, 0.70, 0.85, 1.00, 1.16, 1.28]


def set_input(node, names, value):
	for name in names:
		socket = node.inputs.get(name)
		if socket is not None:
			socket.default_value = value
			return


def make_material(name, color, rough=0.55, metal=0.0, emit=0.0, specular=0.4, coat=0.0):
	material = bpy.data.materials.new(name)
	material.use_nodes = True
	material.diffuse_color = (*color, 1)
	bsdf = material.node_tree.nodes.get("Principled BSDF")
	set_input(bsdf, ("Base Color",), (*color, 1))
	set_input(bsdf, ("Roughness",), rough)
	set_input(bsdf, ("Metallic",), metal)
	set_input(bsdf, ("Specular IOR Level", "Specular"), specular)
	set_input(bsdf, ("Coat Weight", "Clearcoat"), coat)
	set_input(bsdf, ("Coat Roughness", "Clearcoat Roughness"), 0.45)
	if emit > 0:
		set_input(bsdf, ("Emission Color", "Emission"), (*color, 1))
		set_input(bsdf, ("Emission Strength",), emit)
	return material


def link_mesh(bm, name, materials):
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(name, mesh)
	for material in materials:
		obj.data.materials.append(material)
	bpy.context.collection.objects.link(obj)
	return obj


def new_face(bm, verts):
	if len(verts) < 3 or len({id(vert) for vert in verts}) < len(verts):
		return None
	try:
		return bm.faces.new(tuple(verts))
	except ValueError:
		return None


def skin(bm, ring_a, ring_b):
	count = min(len(ring_a), len(ring_b))
	for index in range(count - 1):
		new_face(bm, (ring_a[index], ring_b[index], ring_b[index + 1], ring_a[index + 1]))
	if len(ring_a) == len(ring_b) and len(ring_a) > 2:
		new_face(bm, (ring_a[-1], ring_b[-1], ring_b[0], ring_a[0]))


def orient_outward(bm, inside):
	bm.normal_update()
	for face in bm.faces:
		center = face.calc_center_median()
		if face.normal.dot(center - inside) < 0:
			face.normal_flip()
	bm.normal_update()


def finish_object(obj, angle_degrees):
	mesh = obj.data
	for polygon in mesh.polygons:
		polygon.use_smooth = True
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	modifier = obj.modifiers.new("EdgeSplit", "EDGE_SPLIT")
	modifier.split_angle = math.radians(angle_degrees)
	modifier.use_edge_angle = True
	try:
		bpy.ops.object.modifier_apply(modifier=modifier.name)
	except RuntimeError:
		pass
	mesh.update()


def keep_roof_up(bm):
	bm.normal_update()
	top = None
	top_z = -1e9
	for face in bm.faces:
		z = face.calc_center_median().z
		if z > top_z:
			top_z = z
			top = face
	if top is not None and top.normal.z < 0:
		for face in bm.faces:
			face.normal_flip()
		bm.normal_update()


def recess_windows(bm):
	for vert in bm.verts:
		x, y, z = vert.co.x, vert.co.y, vert.co.z
		if 0.05 < y < 0.58 and abs(x) > 0.40:
			belt = sample(BELT, y)
			rail = z_fender(y)
			if belt + 0.035 < z < rail - 0.035:
				vert.co.x = x * 0.955
		if -0.24 < y < 0.08 and abs(x) < 0.42 and z > z_center(y) - 0.05:
			vert.co.y += 0.012
			vert.co.z -= 0.01
		if 0.78 < y < 1.04 and abs(x) < 0.36 and z > z_center(y) - 0.045:
			vert.co.y -= 0.01
			vert.co.z -= 0.008


def build_body(paint, trim):
	bm = bmesh.new()
	stations = []
	ys = station_ys()
	for y in ys:
		width = half_width(y)
		crown = z_center(y)
		brow = z_fender(y)
		lip = min(z_lip(y), brow - 0.04)
		positive = []
		for row_index, (x_mul, crown_mix, lip_mix) in enumerate(SECTION):
			x = x_mul * width
			z = crown + (brow - crown) * crown_mix
			z = z + (lip - z) * lip_mix
			positive.append(bm.verts.new((x, y, z)))
		chain = []
		for vert in reversed(positive[1:]):
			chain.append(bm.verts.new((-vert.co.x, vert.co.y, vert.co.z)))
		chain.append(positive[0])
		chain.extend(positive[1:])
		belly = None
		if not in_arch(y):
			belly_z = min(0.175, lip - 0.02)
			belly = [
				bm.verts.new((0.40 * width, y, belly_z)),
				bm.verts.new((0.0, y, belly_z - 0.012)),
				bm.verts.new((-0.40 * width, y, belly_z)),
			]
		stations.append((chain, belly))
	for index in range(len(stations) - 1):
		chain_a, belly_a = stations[index]
		chain_b, belly_b = stations[index + 1]
		skin_open = len(chain_a) == len(chain_b)
		if skin_open:
			count = len(chain_a)
			for vert_index in range(count - 1):
				new_face(
					bm,
					(chain_a[vert_index], chain_b[vert_index], chain_b[vert_index + 1], chain_a[vert_index + 1]),
				)
		if belly_a is not None and belly_b is not None:
			right_a = chain_a[-1]
			left_a = chain_a[0]
			right_b = chain_b[-1]
			left_b = chain_b[0]
			new_face(bm, (right_a, belly_a[0], belly_b[0], right_b))
			new_face(bm, (belly_a[0], belly_a[1], belly_b[1], belly_b[0]))
			new_face(bm, (belly_a[1], belly_a[2], belly_b[2], belly_b[1]))
			new_face(bm, (belly_a[2], left_a, left_b, belly_b[2]))
		elif belly_a is not None:
			new_face(bm, (chain_a[-1], belly_a[0], belly_a[1], belly_a[2], chain_a[0]))
		elif belly_b is not None:
			new_face(bm, (chain_b[0], belly_b[2], belly_b[1], belly_b[0], chain_b[-1]))
	first_chain, first_belly = stations[0]
	last_chain, last_belly = stations[-1]
	new_face(bm, list(reversed(first_chain + (first_belly or []))))
	new_face(bm, last_chain + (last_belly or []))
	keep_roof_up(bm)
	obj = link_mesh(bm, "Body", [paint, trim])
	for polygon in obj.data.polygons:
		center = polygon.center
		lower = center.z < 0.235
		bumper = center.y < -0.98 or center.y > 1.02
		sill = abs(center.x) > 0.34 and FRONT_AXLE + 0.05 < center.y < REAR_AXLE - 0.05
		if lower and (bumper or sill or center.z < 0.17):
			polygon.material_index = 1
	return obj


def add_grid(bm, points):
	rows = len(points)
	cols = len(points[0])
	verts = [[bm.verts.new(point) for point in row] for row in points]
	for row in range(rows - 1):
		for col in range(cols - 1):
			new_face(
				bm,
				(
					verts[row][col],
					verts[row][col + 1],
					verts[row + 1][col + 1],
					verts[row + 1][col],
				),
			)
	return verts


def build_glass(glass, seal):
	parts = []
	windshield = []
	y0, y1 = -0.78, -0.28
	x_half = 0.50
	normal = Vector((0, -0.58, 0.70)).normalized()
	for row in range(7):
		y = y0 + (y1 - y0) * row / 6
		line = []
		for col in range(9):
			x = -x_half + (2 * x_half) * col / 8
			bow = 1 - (x / x_half) ** 2
			z = z_center(y) - 0.008 + bow * 0.008
			line.append(Vector((x, y, z)) + normal * 0.003)
		windshield.append(line)
	bm = bmesh.new()
	add_grid(bm, windshield)
	orient_outward(bm, Vector((0, 0.2, 0.45)))
	parts.append(link_mesh(bm, "Windshield", [glass]))

	bm = bmesh.new()
	gasket = []
	for row in windshield:
		gasket.append([point - normal * 0.01 for point in row])
	# Slightly larger seal sits behind the glass.
	grown = []
	for row_index, row in enumerate(gasket):
		grown_row = []
		ty = row_index / max(len(gasket) - 1, 1)
		for col_index, point in enumerate(row):
			tx = col_index / max(len(row) - 1, 1)
			grow_x = (tx - 0.5) * 0.03
			grow_y = (ty - 0.5) * 0.02
			grown_row.append(point + Vector((grow_x, grow_y, 0)))
		grown.append(grown_row)
	add_grid(bm, grown)
	orient_outward(bm, Vector((0, 0.2, 0.45)))
	parts.append(link_mesh(bm, "WindshieldSeal", [seal]))

	for sign, label in ((1, "R"), (-1, "L")):
		panel = []
		y0, y1 = -0.20, 0.48
		for row in range(6):
			y = y0 + (y1 - y0) * row / 5
			x = sign * (half_width(y) * 1.025)
			line = []
			z_bottom = sample(BELT, y) + 0.015
			z_top = z_fender(y) - 0.035
			for col in range(4):
				mix = col / 3
				z = z_bottom + (z_top - z_bottom) * mix
				line.append(Vector((x + sign * 0.004, y, z)))
			panel.append(line)
		bm = bmesh.new()
		add_grid(bm, panel)
		orient_outward(bm, Vector((0, 0.3, 0.7)))
		parts.append(link_mesh(bm, "SideGlass" + label, [glass]))
		bm = bmesh.new()
		seal_panel = []
		for row in panel:
			seal_panel.append([Vector((point.x - sign * 0.008, point.y, point.z)) for point in row])
		add_grid(bm, seal_panel)
		orient_outward(bm, Vector((0, 0.3, 0.7)))
		parts.append(link_mesh(bm, "SideSeal" + label, [seal]))

	rear = []
	y0, y1 = 0.52, 1.02
	normal = Vector((0, 0.62, 0.64)).normalized()
	x_half = 0.44
	for row in range(6):
		y = y0 + (y1 - y0) * row / 5
		line = []
		for col in range(8):
			x = -x_half + (2 * x_half) * col / 7
			z = z_center(y) - 0.02
			line.append(Vector((x, y, z)) + normal * 0.003)
		rear.append(line)
	bm = bmesh.new()
	add_grid(bm, rear)
	orient_outward(bm, Vector((0, 0.4, 0.55)))
	parts.append(link_mesh(bm, "RearGlass", [glass]))
	bm = bmesh.new()
	rear_seal = []
	for row in rear:
		rear_seal.append([point - normal * 0.01 for point in row])
	add_grid(bm, rear_seal)
	orient_outward(bm, Vector((0, 0.4, 0.55)))
	parts.append(link_mesh(bm, "RearSeal", [seal]))
	return parts


def loop_ring(bm, x, y, z, radius, segs):
	ring = []
	for index in range(segs):
		angle = math.pi * 2 * index / segs
		ring.append(bm.verts.new((x, y + math.sin(angle) * radius, z + math.cos(angle) * radius)))
	return ring


def bridge(bm, ring_a, ring_b, material_index):
	faces = []
	segs = len(ring_a)
	for index in range(segs):
		nxt = (index + 1) % segs
		face = new_face(bm, (ring_a[index], ring_a[nxt], ring_b[nxt], ring_b[index]))
		if face is not None:
			face.material_index = material_index
			faces.append(face)
	return faces


def add_spoke(bm, x_inner, x_outer, y, z, angle, r0, r1, w0, w1):
	def corner(axial, radius, width):
		ty = math.cos(angle)
		tz = -math.sin(angle)
		sy = math.sin(angle)
		sz = math.cos(angle)
		return (
			axial,
			y + sy * radius + ty * width,
			z + sz * radius + tz * width,
		)

	verts = []
	for axial in (x_inner, x_outer):
		for radius, width in ((r0, w0), (r1, w1)):
			for sign in (-0.5, 0.5):
				verts.append(bm.verts.new(corner(axial, radius, sign * width)))
	quads = (
		(0, 1, 5, 4),
		(2, 6, 7, 3),
		(0, 4, 6, 2),
		(1, 3, 7, 5),
		(0, 2, 3, 1),
		(4, 5, 7, 6),
	)
	for quad in quads:
		face = new_face(bm, [verts[index] for index in quad])
		if face is not None:
			face.material_index = 1


def build_wheel(name, x, y, tire_mat, rim_mat, disc_mat):
	bm = bmesh.new()
	side = 1 if x >= 0 else -1
	z = WHEEL_Z
	width = 0.152
	segs = 20
	inner = x - side * width * 0.5
	profile = (
		(0.00, 0.68),
		(0.12, 0.84),
		(0.26, 0.97),
		(0.48, 1.00),
		(0.70, 0.98),
		(0.86, 0.86),
		(1.00, 0.70),
	)
	rings = []
	for frac, scale in profile:
		axial = inner + side * frac * width
		rings.append(loop_ring(bm, axial, y, z, WHEEL_R * scale, segs))
	for index in range(len(rings) - 1):
		bridge(bm, rings[index], rings[index + 1], 0)
	lip = loop_ring(bm, inner + side * 0.90 * width, y, z, WHEEL_R * 0.60, segs)
	dish = loop_ring(bm, inner + side * 0.74 * width, y, z, WHEEL_R * 0.34, segs)
	hub = loop_ring(bm, inner + side * 0.84 * width, y, z, WHEEL_R * 0.13, segs)
	cap = loop_ring(bm, inner + side * 0.90 * width, y, z, WHEEL_R * 0.06, segs)
	bridge(bm, rings[-1], lip, 1)
	bridge(bm, lip, dish, 1)
	bridge(bm, dish, hub, 1)
	bridge(bm, hub, cap, 1)
	cap_center = bm.verts.new((inner + side * 0.92 * width, y, z))
	for index in range(segs):
		face = new_face(bm, (cap[index], cap[(index + 1) % segs], cap_center))
		if face is not None:
			face.material_index = 1
	disc_a = loop_ring(bm, inner + side * 0.62 * width, y, z, WHEEL_R * 0.46, segs)
	disc_b = loop_ring(bm, inner + side * 0.66 * width, y, z, WHEEL_R * 0.46, segs)
	disc_hole_a = loop_ring(bm, inner + side * 0.62 * width, y, z, WHEEL_R * 0.16, segs)
	disc_hole_b = loop_ring(bm, inner + side * 0.66 * width, y, z, WHEEL_R * 0.16, segs)
	bridge(bm, disc_a, disc_b, 2)
	bridge(bm, disc_hole_a, disc_hole_b, 2)
	for index in range(5):
		angle = -0.45 + index * math.pi * 2 / 5
		inner_x = inner + side * 0.78 * width
		outer_x = inner + side * 0.88 * width
		add_spoke(bm, inner_x, outer_x, y, z, angle, WHEEL_R * 0.16, WHEEL_R * 0.56, 0.022, 0.040)
	center = Vector((x, y, z))
	bm.normal_update()
	for face in bm.faces:
		if face.normal.dot(face.calc_center_median() - center) < 0:
			face.normal_flip()
	return link_mesh(bm, name, [tire_mat, rim_mat, disc_mat])


def build_liner(name, axle_y, x_sign, liner_mat):
	bm = bmesh.new()
	segs = 14
	inner_x = x_sign * 0.30
	outer_x = x_sign * 0.62
	radius = ARCH_R - 0.012
	rings = []
	for axial in (inner_x, outer_x):
		ring = []
		for index in range(segs + 1):
			angle = math.radians(-115 + 230 * index / segs)
			ring.append(
				bm.verts.new(
					(
						axial,
						axle_y + math.sin(angle) * radius,
						WHEEL_Z + math.cos(angle) * radius,
					)
				)
			)
		rings.append(ring)
	for index in range(segs):
		new_face(bm, (rings[0][index], rings[0][index + 1], rings[1][index + 1], rings[1][index]))
	orient_outward(bm, Vector((0, axle_y, WHEEL_Z)))
	return link_mesh(bm, name, [liner_mat])


def primitive(name, location, scale, material, kind):
	bm = bmesh.new()
	if kind == "sphere":
		bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=1.0)
	else:
		bmesh.ops.create_cube(bm, size=1.0)
	for vert in bm.verts:
		vert.co.x *= scale[0]
		vert.co.y *= scale[1]
		vert.co.z *= scale[2]
		vert.co += Vector(location)
	if kind == "cube":
		bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(scale) * 0.18, segments=1, affect="EDGES")
	orient_outward(bm, Vector(location))
	return link_mesh(bm, name, [material])


def build_details(paint, trim, lamp, amber, tail, seal):
	parts = []
	for sign, label in ((-1, "L"), (1, "R")):
		parts.append(primitive("HeadHousing" + label, (sign * 0.32, -1.345, 0.50), (0.20, 0.016, 0.062), seal, "cube"))
		parts.append(primitive("HeadLamp" + label, (sign * 0.32, -1.358, 0.50), (0.16, 0.012, 0.046), lamp, "cube"))
		parts.append(primitive("Turn" + label, (sign * 0.52, -1.30, 0.40), (0.05, 0.014, 0.028), amber, "cube"))
		parts.append(primitive("Tail" + label, (sign * 0.34, 1.332, 0.52), (0.22, 0.014, 0.058), tail, "cube"))
		parts.append(primitive("TailSide" + label, (sign * 0.50, 1.30, 0.50), (0.04, 0.04, 0.04), tail, "cube"))
		stalk = primitive("MirrorStalk" + label, (sign * 0.66, 0.04, 0.78), (0.12, 0.03, 0.026), paint, "cube")
		head = primitive("Mirror" + label, (sign * 0.73, 0.02, 0.785), (0.055, 0.10, 0.05), paint, "cube")
		face = primitive("MirrorFace" + label, (sign * 0.735, 0.00, 0.79), (0.012, 0.07, 0.032), seal, "cube")
		handle = primitive("Handle" + label, (sign * 0.66, 0.20, 0.66), (0.016, 0.08, 0.018), trim, "cube")
		parts.extend((stalk, head, face, handle))
	parts.append(primitive("Grille", (0, -1.255, 0.325), (0.42, 0.018, 0.11), seal, "cube"))
	for index, height in enumerate((0.355, 0.325, 0.295)):
		parts.append(primitive("Slat" + str(index), (0, -1.272, height), (0.36, 0.012, 0.012), trim, "cube"))
	parts.append(primitive("Intake", (0, -1.30, 0.23), (0.50, 0.016, 0.055), seal, "cube"))
	parts.append(primitive("PlateFront", (0, -1.318, 0.30), (0.26, 0.012, 0.07), trim, "cube"))
	parts.append(primitive("PlateRear", (0, 1.312, 0.34), (0.26, 0.012, 0.07), trim, "cube"))
	return parts


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


def studio(target):
	scene = bpy.context.scene
	for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
		try:
			scene.render.engine = engine
			break
		except TypeError:
			continue
	scene.render.resolution_x = 1400
	scene.render.resolution_y = 900
	scene.render.image_settings.file_format = "PNG"
	scene.render.film_transparent = False
	if hasattr(scene, "eevee"):
		if hasattr(scene.eevee, "taa_render_samples"):
			scene.eevee.taa_render_samples = 48
		if hasattr(scene.eevee, "use_bloom"):
			scene.eevee.use_bloom = False
	try:
		scene.view_settings.view_transform = "AgX"
	except TypeError:
		pass
	world = bpy.data.worlds.new("Studio")
	world.use_nodes = True
	background = world.node_tree.nodes.get("Background")
	if background is not None:
		background.inputs["Color"].default_value = (0.58, 0.59, 0.61, 1)
		background.inputs["Strength"].default_value = 0.42
	scene.world = world
	lights = (
		("Key", (-2.4, -2.6, 2.8), 420, 2.4),
		("Fill", (2.6, -1.8, 1.5), 140, 3.2),
		("Rim", (1.4, 3.0, 2.4), 260, 1.6),
	)
	for name, location, energy, size in lights:
		data = bpy.data.lights.new(name, "AREA")
		data.energy = energy
		data.size = size
		data.color = (1, 0.98, 0.96)
		obj = bpy.data.objects.new(name, data)
		obj.location = location
		look_at(obj, target)
		bpy.context.collection.objects.link(obj)
	floor = primitive("Floor", (0, 0, -0.004), (14, 14, 0.01), make_material("Floor", (0.34, 0.35, 0.37), 0.92, 0.0, specular=0.15), "cube")
	return floor


def render_view(objects, location, filepath, lens=50, ortho=False, ortho_scale=3.2):
	scene = bpy.context.scene
	low, high = bounds(objects)
	center = (low + high) * 0.5
	center.z += 0.02
	if scene.camera is None:
		camera = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
		bpy.context.collection.objects.link(camera)
		scene.camera = camera
	camera = scene.camera
	camera.location = location
	look_at(camera, center)
	camera.data.lens = lens
	camera.data.type = "ORTHO" if ortho else "PERSP"
	camera.data.ortho_scale = ortho_scale
	camera.data.dof.use_dof = False
	camera.data.clip_start = 0.02
	camera.data.clip_end = 80
	scene.render.filepath = filepath
	bpy.ops.render.render(write_still=True)


def export_car(objects):
	root = bpy.data.objects.new(KEY, None)
	bpy.context.collection.objects.link(root)
	for obj in objects:
		obj.parent = root
	bpy.ops.object.select_all(action="DESELECT")
	root.select_set(True)
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	folder = os.path.join(OUT_DIR, KEY)
	os.makedirs(folder, exist_ok=True)
	bpy.ops.wm.save_as_mainfile(filepath=os.path.join(folder, KEY + ".blend"))
	bpy.ops.export_scene.gltf(
		filepath=os.path.join(folder, KEY + ".glb"),
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
	print("CAR %s size %.2f x %.2f x %.2f tris %d ground %.3f" % (KEY, size.x, size.y, size.z, tris, low.z))
	if size.y < 2.3 or size.y > 3.4 or size.x < 1.0 or size.x > 1.75 or low.z < -0.02 or low.z > 0.05:
		raise SystemExit("尺寸或貼地不對")
	if tris > 9500:
		raise SystemExit("面數過高")
	os.makedirs(PREVIEW_DIR, exist_ok=True)
	render_view(objects, Vector((0.0, -4.9, 0.95)), os.path.join(PREVIEW_DIR, KEY + "_front.png"), 55)
	render_view(objects, Vector((-2.55, -3.35, 1.25)), os.path.join(PREVIEW_DIR, KEY + "_threequarter.png"), 48)
	render_view(objects, Vector((5.4, 0.05, 0.95)), os.path.join(PREVIEW_DIR, KEY + "_side.png"), 70)


def main():
	clear_scene()
	paint = make_material("HatchPaint", (168 / 255, 58 / 255, 64 / 255), 0.48, 0.05, specular=0.36, coat=0.18)
	trim = make_material("HatchTrim", (0.07, 0.07, 0.075), 0.68, 0.02, specular=0.25)
	glass = make_material("HatchGlass", (0.025, 0.028, 0.032), 0.22, 0.0, specular=0.55)
	seal = make_material("HatchSeal", (0.015, 0.015, 0.016), 0.78, 0.0, specular=0.2)
	tire = make_material("HatchTire", (0.015, 0.015, 0.016), 0.86, 0.0, specular=0.2)
	rim = make_material("HatchRim", (0.74, 0.75, 0.77), 0.32, 0.82, specular=0.5)
	disc = make_material("HatchDisc", (0.12, 0.12, 0.13), 0.45, 0.65, specular=0.4)
	liner = make_material("HatchLiner", (0.03, 0.03, 0.032), 0.9, 0.0, specular=0.1)
	lamp = make_material("HatchLamp", (0.95, 0.96, 0.93), 0.18, 0.0, emit=5.0, specular=0.4)
	amber = make_material("HatchAmber", (0.95, 0.42, 0.08), 0.28, 0.0, emit=2.2, specular=0.35)
	tail = make_material("HatchTail", (0.72, 0.045, 0.035), 0.24, 0.0, emit=2.4, specular=0.4)
	body = build_body(paint, trim)
	finish_object(body, 26)
	objects = [body]
	objects.extend(build_glass(glass, seal))
	for obj in objects[1:]:
		finish_object(obj, 55)
	wheel_names = (("FL", -TRACK, FRONT_AXLE), ("FR", TRACK, FRONT_AXLE), ("RL", -TRACK, REAR_AXLE), ("RR", TRACK, REAR_AXLE))
	for name, x, y in wheel_names:
		wheel = build_wheel(name, x, y, tire, rim, disc)
		finish_object(wheel, 55)
		objects.append(wheel)
	detail_start = len(objects)
	objects.extend(build_details(paint, trim, lamp, amber, tail, seal))
	for obj in objects[detail_start:]:
		finish_object(obj, 50)
	studio(Vector((0, 0, 0.5)))
	export_car(objects)


if __name__ == "__main__":
	main()
