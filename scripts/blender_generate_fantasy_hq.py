"""
Fantasy HQ Building Generator
===============================
Generates a detailed fantasy fortress/keep with:
  - Stone keep with arched doorway
  - Four corner turrets with crenellations (battlements)
  - Peaked conical turret roofs
  - Wooden door and beam accents
  - Glowing crystal spire on top
  - Procedural stone, wood, and metal PBR materials (baked to textures)
  - Weathering, moss, edge wear

Output: .glb and .usdc at 512x512 textures (hero structure per PRD)

Usage:
    Blender UI:  Scripting tab → Open → Run Script
    Headless:    /Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/blender_generate_fantasy_hq.py
"""

import bpy
import bmesh
import os
import math
from mathutils import Vector, Matrix

# ─── Configuration ────────────────────────────────────────────────

PROJECT_DIR = "/Users/maxconrad/Workspace/factory-defense"
OUTPUT_DIR = os.path.join(PROJECT_DIR, "Assets", "Models")

TEX_SIZE = 512  # Hero structure gets 512x512 per PRD

# Building proportions (fits within ~1x1 tile footprint, origin at center-bottom)
KEEP_WIDTH = 0.7       # main body width (X and Y)
KEEP_HEIGHT = 0.8      # main body height
WALL_THICKNESS = 0.06

TURRET_RADIUS = 0.12
TURRET_HEIGHT = 1.0
TURRET_SEGMENTS = 12
TURRET_ROOF_HEIGHT = 0.25

DOOR_WIDTH = 0.18
DOOR_HEIGHT = 0.30
DOOR_DEPTH = 0.08

BATTLEMENT_HEIGHT = 0.08
BATTLEMENT_WIDTH = 0.06
BATTLEMENT_GAP = 0.06

CRYSTAL_RADIUS = 0.04
CRYSTAL_HEIGHT = 0.22

ROOF_OVERHANG = 0.04
ROOF_HEIGHT = 0.20

BEAM_WIDTH = 0.02
BEAM_DEPTH = 0.015

# ─── Scene Setup ─────────────────────────────────────────────────

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in [bpy.data.meshes, bpy.data.materials, bpy.data.images,
                  bpy.data.textures, bpy.data.node_groups]:
        for item in block:
            if not item.users or item.users == 0:
                block.remove(item)


def ensure_collection(name):
    if name not in bpy.data.collections:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return bpy.data.collections[name]


# ─── Geometry Helpers ────────────────────────────────────────────

def new_object(name, mesh_data):
    obj = bpy.data.objects.new(name, mesh_data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in obj.modifiers:
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except:
            pass


def add_bevel(obj, width=0.008, segments=2, angle_limit=50):
    bevel = obj.modifiers.new("Bevel", 'BEVEL')
    bevel.width = width
    bevel.segments = segments
    bevel.limit_method = 'ANGLE'
    bevel.angle_limit = math.radians(angle_limit)
    return bevel


def add_subdivision(obj, levels=1, render_levels=2):
    sub = obj.modifiers.new("Subsurf", 'SUBSURF')
    sub.levels = levels
    sub.render_levels = render_levels
    return sub


# ─── Main Keep Body ─────────────────────────────────────────────

def create_keep_body():
    """Main stone keep — a box with slight taper (wider at base)."""
    bm = bmesh.new()

    hw = KEEP_WIDTH / 2
    h = KEEP_HEIGHT

    # Base footprint (slightly wider)
    taper = 0.015
    base_hw = hw + taper
    top_hw = hw - taper

    # Bottom face verts
    v0 = bm.verts.new((-base_hw, 0,      -base_hw))
    v1 = bm.verts.new(( base_hw, 0,      -base_hw))
    v2 = bm.verts.new(( base_hw, 0,       base_hw))
    v3 = bm.verts.new((-base_hw, 0,       base_hw))

    # Mid-height (slight bulge for foundation line)
    foundation_h = 0.08
    mid_hw = base_hw + 0.01
    v4 = bm.verts.new((-mid_hw,  foundation_h, -mid_hw))
    v5 = bm.verts.new(( mid_hw,  foundation_h, -mid_hw))
    v6 = bm.verts.new(( mid_hw,  foundation_h,  mid_hw))
    v7 = bm.verts.new((-mid_hw,  foundation_h,  mid_hw))

    # Top face verts
    v8  = bm.verts.new((-top_hw, h, -top_hw))
    v9  = bm.verts.new(( top_hw, h, -top_hw))
    v10 = bm.verts.new(( top_hw, h,  top_hw))
    v11 = bm.verts.new((-top_hw, h,  top_hw))

    # Bottom face
    bm.faces.new([v3, v2, v1, v0])

    # Foundation band (bottom to mid)
    bm.faces.new([v0, v1, v5, v4])
    bm.faces.new([v1, v2, v6, v5])
    bm.faces.new([v2, v3, v7, v6])
    bm.faces.new([v3, v0, v4, v7])

    # Main walls (mid to top)
    bm.faces.new([v4, v5, v9,  v8])
    bm.faces.new([v5, v6, v10, v9])
    bm.faces.new([v6, v7, v11, v10])
    bm.faces.new([v7, v4, v8,  v11])

    # Top face
    bm.faces.new([v8, v9, v10, v11])

    bm.normal_update()

    mesh = bpy.data.meshes.new("keep_body_mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = new_object("keep_body", mesh)
    add_bevel(obj, width=0.006, segments=2, angle_limit=40)
    apply_modifiers(obj)
    return obj


# ─── Arched Doorway ──────────────────────────────────────────────

def create_arched_doorway():
    """Stone archway with recessed door frame on front face."""
    bm = bmesh.new()

    w = DOOR_WIDTH / 2
    h = DOOR_HEIGHT
    d = DOOR_DEPTH
    arch_segments = 8
    arch_radius = w

    # Create the door frame as an extruded arch profile
    # Front face position (Z = -KEEP_WIDTH/2)
    front_z = -KEEP_WIDTH / 2 - 0.001

    # Outer frame points
    frame_w = w + 0.03
    frame_h = h + 0.04

    # Door recess (inset box with arch top)
    # Left pillar
    verts = []

    # Build arch profile in XY plane, then position in world
    # Bottom-left of door
    profile = []
    profile.append((-w, 0))
    profile.append((-w, h - arch_radius))

    # Arch curve
    for i in range(arch_segments + 1):
        angle = math.pi / 2 + (math.pi / 2) * (i / arch_segments)
        x = math.cos(angle) * arch_radius
        y = (h - arch_radius) + math.sin(angle) * arch_radius
        profile.append((x, y))

    profile.append((w, h - arch_radius))
    profile.append((w, 0))

    # Create front and back rings of vertices
    front_verts = []
    back_verts = []
    for px, py in profile:
        front_verts.append(bm.verts.new((px, py, front_z)))
        back_verts.append(bm.verts.new((px, py, front_z + d)))

    # Connect front to back with faces
    n = len(profile)
    for i in range(n - 1):
        bm.faces.new([front_verts[i], front_verts[i+1], back_verts[i+1], back_verts[i]])

    # Front face (archway outline)
    # We'll just do the side faces — the door opening is empty

    # Keystone (decorative wedge at top of arch)
    top_idx = len(profile) // 2
    if top_idx < len(front_verts):
        ks_w = 0.025
        ks_h = 0.035
        ks_y = h + 0.005
        kv0 = bm.verts.new((-ks_w, ks_y - ks_h, front_z - 0.005))
        kv1 = bm.verts.new(( ks_w, ks_y - ks_h, front_z - 0.005))
        kv2 = bm.verts.new(( ks_w * 0.6, ks_y, front_z - 0.005))
        kv3 = bm.verts.new((-ks_w * 0.6, ks_y, front_z - 0.005))
        bm.faces.new([kv0, kv1, kv2, kv3])

    bm.normal_update()
    mesh = bpy.data.meshes.new("doorway_mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = new_object("doorway", mesh)
    add_bevel(obj, width=0.004, segments=1)
    apply_modifiers(obj)
    return obj


# ─── Corner Turrets ──────────────────────────────────────────────

def create_turret(position, name="turret"):
    """Cylindrical turret with crenellations and conical roof."""
    objects = []

    # ── Turret cylinder ──
    bpy.ops.mesh.primitive_cylinder_add(
        radius=TURRET_RADIUS,
        depth=TURRET_HEIGHT,
        vertices=TURRET_SEGMENTS,
        location=(position[0], TURRET_HEIGHT / 2, position[1])  # Blender Z-up
    )
    cylinder = bpy.context.active_object
    cylinder.name = f"{name}_body"

    # Slight taper — scale top ring smaller
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(cylinder.data)
    bm.verts.ensure_lookup_table()
    top_z = TURRET_HEIGHT / 2
    for v in bm.verts:
        if abs(v.co.z - top_z) < 0.01:
            v.co.x *= 0.92
            v.co.y *= 0.92
    bmesh.update_edit_mesh(cylinder.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    add_bevel(cylinder, width=0.005, segments=1, angle_limit=80)
    apply_modifiers(cylinder)
    objects.append(cylinder)

    # ── Crenellations (battlements) ──
    battlement_y = TURRET_HEIGHT
    num_battlements = 8
    for i in range(num_battlements):
        if i % 2 == 0:  # alternating merlons and gaps
            angle = (2 * math.pi * i) / num_battlements
            bx = position[0] + (TURRET_RADIUS - 0.01) * math.cos(angle)
            bz = position[1] + (TURRET_RADIUS - 0.01) * math.sin(angle)

            bpy.ops.mesh.primitive_cube_add(
                size=1,
                location=(bx, battlement_y + BATTLEMENT_HEIGHT / 2, bz),
                scale=(BATTLEMENT_WIDTH, BATTLEMENT_HEIGHT, BATTLEMENT_WIDTH)
            )
            merlon = bpy.context.active_object
            merlon.name = f"{name}_merlon_{i}"
            bpy.ops.object.transform_apply(scale=True)
            objects.append(merlon)

    # ── Conical roof ──
    bpy.ops.mesh.primitive_cone_add(
        radius1=TURRET_RADIUS + ROOF_OVERHANG,
        radius2=0.01,
        depth=TURRET_ROOF_HEIGHT,
        vertices=TURRET_SEGMENTS,
        location=(position[0], TURRET_HEIGHT + BATTLEMENT_HEIGHT + TURRET_ROOF_HEIGHT / 2, position[1])
    )
    roof = bpy.context.active_object
    roof.name = f"{name}_roof"
    objects.append(roof)

    # ── Foundation ring (wider base) ──
    bpy.ops.mesh.primitive_cylinder_add(
        radius=TURRET_RADIUS + 0.02,
        depth=0.06,
        vertices=TURRET_SEGMENTS,
        location=(position[0], 0.03, position[1])
    )
    base_ring = bpy.context.active_object
    base_ring.name = f"{name}_base"
    objects.append(base_ring)

    return objects


# ─── Main Keep Battlements ───────────────────────────────────────

def create_keep_battlements():
    """Crenellations along the top of the main keep."""
    objects = []
    hw = KEEP_WIDTH / 2 - 0.015  # slightly inset from wall edge
    y = KEEP_HEIGHT

    num_per_side = 5
    spacing = KEEP_WIDTH / num_per_side

    for side in range(4):
        for i in range(num_per_side):
            if i % 2 == 0:
                t = -hw + spacing * (i + 0.5)

                if side == 0:    # front
                    pos = (t, y + BATTLEMENT_HEIGHT / 2, -hw)
                elif side == 1:  # back
                    pos = (t, y + BATTLEMENT_HEIGHT / 2, hw)
                elif side == 2:  # left
                    pos = (-hw, y + BATTLEMENT_HEIGHT / 2, t)
                else:            # right
                    pos = (hw, y + BATTLEMENT_HEIGHT / 2, t)

                bpy.ops.mesh.primitive_cube_add(
                    size=1,
                    location=pos,
                    scale=(BATTLEMENT_WIDTH, BATTLEMENT_HEIGHT, BATTLEMENT_WIDTH)
                )
                merlon = bpy.context.active_object
                merlon.name = f"keep_merlon_{side}_{i}"
                bpy.ops.object.transform_apply(scale=True)
                add_bevel(merlon, width=0.003, segments=1)
                apply_modifiers(merlon)
                objects.append(merlon)

    return objects


# ─── Wooden Door ─────────────────────────────────────────────────

def create_wooden_door():
    """Wooden plank door recessed into the archway."""
    bm = bmesh.new()

    w = DOOR_WIDTH / 2 - 0.01
    h = DOOR_HEIGHT - 0.03
    z = -KEEP_WIDTH / 2 + DOOR_DEPTH * 0.5

    # Main door panel
    v0 = bm.verts.new((-w, 0.005, z))
    v1 = bm.verts.new(( w, 0.005, z))
    v2 = bm.verts.new(( w, h,     z))
    v3 = bm.verts.new((-w, h,     z))
    bm.faces.new([v0, v1, v2, v3])

    # Plank lines (horizontal beams across the door)
    num_planks = 3
    for i in range(num_planks):
        py = h * (i + 1) / (num_planks + 1)
        bw = w - 0.005
        bh = BEAM_WIDTH / 2
        bd = 0.008

        b0 = bm.verts.new((-bw, py - bh, z - bd))
        b1 = bm.verts.new(( bw, py - bh, z - bd))
        b2 = bm.verts.new(( bw, py + bh, z - bd))
        b3 = bm.verts.new((-bw, py + bh, z - bd))
        bm.faces.new([b0, b1, b2, b3])

        # Depth faces for the beam
        b4 = bm.verts.new((-bw, py - bh, z))
        b5 = bm.verts.new(( bw, py - bh, z))
        b6 = bm.verts.new(( bw, py + bh, z))
        b7 = bm.verts.new((-bw, py + bh, z))
        bm.faces.new([b4, b0, b3, b7])  # left
        bm.faces.new([b1, b5, b6, b2])  # right
        bm.faces.new([b7, b3, b2, b6])  # top
        bm.faces.new([b0, b4, b5, b1])  # bottom

    # Iron hinges
    for hy_frac in [0.25, 0.75]:
        py = h * hy_frac
        for side in [-1, 1]:
            hx = side * (w - 0.01)
            hinge_w = 0.015
            hinge_h = 0.008

            h0 = bm.verts.new((hx - hinge_w, py - hinge_h, z - 0.01))
            h1 = bm.verts.new((hx + hinge_w, py - hinge_h, z - 0.01))
            h2 = bm.verts.new((hx + hinge_w, py + hinge_h, z - 0.01))
            h3 = bm.verts.new((hx - hinge_w, py + hinge_h, z - 0.01))
            bm.faces.new([h0, h1, h2, h3])

    bm.normal_update()
    mesh = bpy.data.meshes.new("door_mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = new_object("wooden_door", mesh)
    return obj


# ─── Crystal Spire ───────────────────────────────────────────────

def create_crystal_spire():
    """Glowing crystal on top of the keep — magical/fantasy element."""
    objects = []

    # Crystal base pedestal
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.05,
        depth=0.04,
        vertices=8,
        location=(0, KEEP_HEIGHT + BATTLEMENT_HEIGHT + 0.02, 0)
    )
    pedestal = bpy.context.active_object
    pedestal.name = "crystal_pedestal"
    objects.append(pedestal)

    # Main crystal (elongated octahedron)
    crystal_y = KEEP_HEIGHT + BATTLEMENT_HEIGHT + 0.04 + CRYSTAL_HEIGHT / 2
    bm = bmesh.new()

    r = CRYSTAL_RADIUS
    h = CRYSTAL_HEIGHT / 2

    # Top and bottom apex
    top = bm.verts.new((0, crystal_y + h, 0))
    bot = bm.verts.new((0, crystal_y - h * 0.6, 0))  # shorter bottom

    # Middle ring (6 sides for crystalline look)
    mid_verts = []
    sides = 6
    mid_y = crystal_y + h * 0.1  # slightly above center
    for i in range(sides):
        angle = (2 * math.pi * i) / sides + math.pi / 6  # rotated 30 deg
        # Alternate radius for faceted look
        rad = r if i % 2 == 0 else r * 0.75
        x = rad * math.cos(angle)
        z = rad * math.sin(angle)
        mid_verts.append(bm.verts.new((x, mid_y, z)))

    # Top faces
    for i in range(sides):
        next_i = (i + 1) % sides
        bm.faces.new([top, mid_verts[i], mid_verts[next_i]])

    # Bottom faces
    for i in range(sides):
        next_i = (i + 1) % sides
        bm.faces.new([bot, mid_verts[next_i], mid_verts[i]])

    bm.normal_update()
    mesh = bpy.data.meshes.new("crystal_mesh")
    bm.to_mesh(mesh)
    bm.free()

    crystal_obj = new_object("crystal", mesh)
    objects.append(crystal_obj)

    # Small orbiting crystals
    for i in range(3):
        angle = (2 * math.pi * i) / 3
        ox = 0.07 * math.cos(angle)
        oz = 0.07 * math.sin(angle)
        oy = crystal_y - 0.02

        bpy.ops.mesh.primitive_cone_add(
            radius1=0.012,
            radius2=0.003,
            depth=0.05,
            vertices=5,
            location=(ox, oy, oz)
        )
        small = bpy.context.active_object
        small.name = f"crystal_small_{i}"
        # Tilt outward
        small.rotation_euler = (math.radians(20) * math.cos(angle),
                                 0,
                                 math.radians(20) * math.sin(angle))
        bpy.ops.object.transform_apply(rotation=True)
        objects.append(small)

    return objects


# ─── Decorative Elements ────────────────────────────────────────

def create_window_slit(position, rotation_z=0):
    """Narrow arrow slit window."""
    bm = bmesh.new()

    w = 0.012
    h = 0.06
    d = 0.03
    px, py, pz = position

    # Outer frame (slightly larger)
    fw = w + 0.005
    fh = h + 0.008

    # Simple inset rectangle for the slit
    v0 = bm.verts.new((-fw, -fh, 0))
    v1 = bm.verts.new(( fw, -fh, 0))
    v2 = bm.verts.new(( fw,  fh, 0))
    v3 = bm.verts.new((-fw,  fh, 0))

    v4 = bm.verts.new((-w, -h, -d))
    v5 = bm.verts.new(( w, -h, -d))
    v6 = bm.verts.new(( w,  h, -d))
    v7 = bm.verts.new((-w,  h, -d))

    # Outer ring to inner ring faces (beveled inset look)
    bm.faces.new([v0, v1, v5, v4])  # bottom
    bm.faces.new([v1, v2, v6, v5])  # right
    bm.faces.new([v2, v3, v7, v6])  # top
    bm.faces.new([v3, v0, v4, v7])  # left
    bm.faces.new([v4, v5, v6, v7])  # back (dark interior)

    bm.normal_update()
    mesh = bpy.data.meshes.new("window_slit_mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = new_object("window_slit", mesh)
    obj.location = (px, py, pz)
    obj.rotation_euler.y = rotation_z
    bpy.ops.object.transform_apply(location=True, rotation=True)
    return obj


def create_wall_decorations():
    """Arrow slits and stone trim on the keep walls."""
    objects = []
    hw = KEEP_WIDTH / 2 + 0.002  # just outside the wall surface

    # Arrow slits on each face
    slit_height = KEEP_HEIGHT * 0.55
    slit_positions = [
        # Front face
        ((-0.15, slit_height, -hw), 0),
        (( 0.15, slit_height, -hw), 0),
        # Back face
        ((-0.15, slit_height, hw), math.pi),
        (( 0.15, slit_height, hw), math.pi),
        # Left face
        ((-hw, slit_height, -0.15), -math.pi/2),
        ((-hw, slit_height,  0.15), -math.pi/2),
        # Right face
        ((hw, slit_height, -0.15), math.pi/2),
        ((hw, slit_height,  0.15), math.pi/2),
    ]

    for pos, rot in slit_positions:
        slit = create_window_slit(pos, rot)
        objects.append(slit)

    # Horizontal stone trim band around the keep
    trim_y = KEEP_HEIGHT * 0.65
    trim_h = 0.015
    trim_d = 0.008

    for side in range(4):
        if side == 0:    # front
            pos = (0, trim_y, -hw - trim_d/2)
            scale = (KEEP_WIDTH + 0.02, trim_h, trim_d)
        elif side == 1:  # back
            pos = (0, trim_y, hw + trim_d/2)
            scale = (KEEP_WIDTH + 0.02, trim_h, trim_d)
        elif side == 2:  # left
            pos = (-hw - trim_d/2, trim_y, 0)
            scale = (trim_d, trim_h, KEEP_WIDTH + 0.02)
        else:            # right
            pos = (hw + trim_d/2, trim_y, 0)
            scale = (trim_d, trim_h, KEEP_WIDTH + 0.02)

        bpy.ops.mesh.primitive_cube_add(size=1, location=pos, scale=scale)
        trim = bpy.context.active_object
        trim.name = f"trim_band_{side}"
        bpy.ops.object.transform_apply(scale=True)
        add_bevel(trim, width=0.002, segments=1)
        apply_modifiers(trim)
        objects.append(trim)

    return objects


# ─── Material Creation ───────────────────────────────────────────

def create_stone_material():
    """Procedural weathered stone material for the keep walls."""
    mat = bpy.data.materials.new("stone_material")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (800, 0)

    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (400, 0)
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

    # ── Base Color: Stone with moss ──
    # Voronoi for stone block pattern
    tex_coord = nodes.new('ShaderNodeTexCoord')
    tex_coord.location = (-1200, 200)

    mapping = nodes.new('ShaderNodeMapping')
    mapping.location = (-1000, 200)
    mapping.inputs['Scale'].default_value = (4, 4, 4)
    links.new(tex_coord.outputs['UV'], mapping.inputs['Vector'])

    # Stone color base
    voronoi = nodes.new('ShaderNodeTexVoronoi')
    voronoi.location = (-700, 300)
    voronoi.voronoi_dimensions = '3D'
    voronoi.inputs['Scale'].default_value = 8.0
    voronoi.feature = 'F1'
    links.new(mapping.outputs['Vector'], voronoi.inputs['Vector'])

    # Color ramp for stone colors
    stone_ramp = nodes.new('ShaderNodeValToRGB')
    stone_ramp.location = (-400, 300)
    stone_ramp.color_ramp.elements[0].position = 0.0
    stone_ramp.color_ramp.elements[0].color = (0.18, 0.16, 0.14, 1)  # dark stone
    stone_ramp.color_ramp.elements[1].position = 1.0
    stone_ramp.color_ramp.elements[1].color = (0.35, 0.32, 0.28, 1)  # light stone
    links.new(voronoi.outputs['Distance'], stone_ramp.inputs['Fac'])

    # Noise for moss/weathering patches
    noise = nodes.new('ShaderNodeTexNoise')
    noise.location = (-700, 0)
    noise.inputs['Scale'].default_value = 3.0
    noise.inputs['Detail'].default_value = 6.0
    links.new(mapping.outputs['Vector'], noise.inputs['Vector'])

    moss_ramp = nodes.new('ShaderNodeValToRGB')
    moss_ramp.location = (-400, 0)
    moss_ramp.color_ramp.elements[0].position = 0.45
    moss_ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    moss_ramp.color_ramp.elements[1].position = 0.55
    moss_ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(noise.outputs['Fac'], moss_ramp.inputs['Fac'])

    moss_color = nodes.new('ShaderNodeRGB')
    moss_color.location = (-400, -150)
    moss_color.outputs[0].default_value = (0.12, 0.18, 0.08, 1)  # dark green moss

    mix_moss = nodes.new('ShaderNodeMixRGB')
    mix_moss.location = (-100, 200)
    mix_moss.blend_type = 'MIX'
    links.new(moss_ramp.outputs['Color'], mix_moss.inputs['Fac'])
    links.new(stone_ramp.outputs['Color'], mix_moss.inputs['Color1'])
    links.new(moss_color.outputs['Color'], mix_moss.inputs['Color2'])
    links.new(mix_moss.outputs['Color'], bsdf.inputs['Base Color'])

    # ── Roughness: mostly rough stone with smooth worn edges ──
    rough_noise = nodes.new('ShaderNodeTexNoise')
    rough_noise.location = (-700, -300)
    rough_noise.inputs['Scale'].default_value = 12.0
    rough_noise.inputs['Detail'].default_value = 4.0
    links.new(mapping.outputs['Vector'], rough_noise.inputs['Vector'])

    rough_ramp = nodes.new('ShaderNodeValToRGB')
    rough_ramp.location = (-400, -300)
    rough_ramp.color_ramp.elements[0].position = 0.3
    rough_ramp.color_ramp.elements[0].color = (0.65, 0.65, 0.65, 1)
    rough_ramp.color_ramp.elements[1].position = 0.7
    rough_ramp.color_ramp.elements[1].color = (0.9, 0.9, 0.9, 1)
    links.new(rough_noise.outputs['Fac'], rough_ramp.inputs['Fac'])
    links.new(rough_ramp.outputs['Color'], bsdf.inputs['Roughness'])

    # ── Normal: Stone block edges ──
    bump = nodes.new('ShaderNodeBump')
    bump.location = (100, -200)
    bump.inputs['Strength'].default_value = 0.4
    bump.inputs['Distance'].default_value = 0.02
    links.new(voronoi.outputs['Distance'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])

    # Metallic: stone is not metallic
    bsdf.inputs['Metallic'].default_value = 0.0

    return mat


def create_wood_material():
    """Procedural wood material for the door."""
    mat = bpy.data.materials.new("wood_material")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (600, 0)

    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (300, 0)
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

    tex_coord = nodes.new('ShaderNodeTexCoord')
    tex_coord.location = (-800, 0)

    mapping = nodes.new('ShaderNodeMapping')
    mapping.location = (-600, 0)
    mapping.inputs['Scale'].default_value = (1, 8, 1)  # stretched for wood grain
    links.new(tex_coord.outputs['UV'], mapping.inputs['Vector'])

    # Wood grain via wave texture
    wave = nodes.new('ShaderNodeTexWave')
    wave.location = (-400, 100)
    wave.wave_type = 'BANDS'
    wave.inputs['Scale'].default_value = 3.0
    wave.inputs['Distortion'].default_value = 4.0
    wave.inputs['Detail'].default_value = 3.0
    links.new(mapping.outputs['Vector'], wave.inputs['Vector'])

    wood_ramp = nodes.new('ShaderNodeValToRGB')
    wood_ramp.location = (-100, 100)
    wood_ramp.color_ramp.elements[0].position = 0.3
    wood_ramp.color_ramp.elements[0].color = (0.15, 0.08, 0.04, 1)  # dark wood
    wood_ramp.color_ramp.elements[1].position = 0.7
    wood_ramp.color_ramp.elements[1].color = (0.30, 0.18, 0.10, 1)  # lighter grain
    links.new(wave.outputs['Fac'], wood_ramp.inputs['Fac'])
    links.new(wood_ramp.outputs['Color'], bsdf.inputs['Base Color'])

    bsdf.inputs['Roughness'].default_value = 0.75
    bsdf.inputs['Metallic'].default_value = 0.0

    # Bump from grain
    bump = nodes.new('ShaderNodeBump')
    bump.location = (100, -150)
    bump.inputs['Strength'].default_value = 0.2
    links.new(wave.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])

    return mat


def create_crystal_material():
    """Glowing translucent crystal material."""
    mat = bpy.data.materials.new("crystal_material")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (600, 0)

    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (300, 0)
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

    # Crystal color — magical blue-purple
    bsdf.inputs['Base Color'].default_value = (0.2, 0.5, 0.9, 1)
    bsdf.inputs['Roughness'].default_value = 0.1
    bsdf.inputs['Metallic'].default_value = 0.0

    # Emission for glow
    bsdf.inputs['Emission Color'].default_value = (0.3, 0.6, 1.0, 1)
    bsdf.inputs['Emission Strength'].default_value = 3.0

    # Transmission for translucency
    bsdf.inputs['Transmission Weight'].default_value = 0.6
    bsdf.inputs['IOR'].default_value = 1.45

    return mat


def create_roof_material():
    """Dark slate/shingle roof material."""
    mat = bpy.data.materials.new("roof_material")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (600, 0)

    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (300, 0)
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

    bsdf.inputs['Base Color'].default_value = (0.12, 0.10, 0.14, 1)  # dark slate
    bsdf.inputs['Roughness'].default_value = 0.85
    bsdf.inputs['Metallic'].default_value = 0.0

    # Subtle bump for shingles
    tex_coord = nodes.new('ShaderNodeTexCoord')
    tex_coord.location = (-600, 0)

    mapping = nodes.new('ShaderNodeMapping')
    mapping.location = (-400, 0)
    mapping.inputs['Scale'].default_value = (8, 16, 8)
    links.new(tex_coord.outputs['UV'], mapping.inputs['Vector'])

    noise = nodes.new('ShaderNodeTexNoise')
    noise.location = (-200, -100)
    noise.inputs['Scale'].default_value = 20.0
    noise.inputs['Detail'].default_value = 2.0
    links.new(mapping.outputs['Vector'], noise.inputs['Vector'])

    bump = nodes.new('ShaderNodeBump')
    bump.location = (100, -100)
    bump.inputs['Strength'].default_value = 0.3
    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])

    return mat


# ─── Texture Baking ──────────────────────────────────────────────

def bake_textures(obj, material_name_prefix, size=TEX_SIZE):
    """
    Bake procedural materials to image textures for export.
    Returns dict of baked images.
    """
    print(f"    Baking textures at {size}x{size}...")

    # Store original render engine, switch to Cycles for baking
    original_engine = bpy.context.scene.render.engine
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = 32  # low samples for baking (fast)
    bpy.context.scene.cycles.device = 'CPU'  # safe fallback

    # Try GPU if available
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for device in prefs.devices:
            device.use = True
        bpy.context.scene.cycles.device = 'GPU'
    except:
        pass  # CPU fallback is fine

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    baked = {}

    # For each material on the object, create bake target images
    # and add image texture nodes

    bake_types = {
        'basecolor': ('DIFFUSE', 'sRGB'),
        'normal':    ('NORMAL', 'Non-Color'),
        'roughness': ('ROUGHNESS', 'Non-Color'),
        'ao':        ('AO', 'Non-Color'),
    }

    for map_name, (bake_type, colorspace) in bake_types.items():
        img = bpy.data.images.new(
            f"{material_name_prefix}_{map_name}",
            width=size, height=size, alpha=False
        )
        img.colorspace_settings.name = colorspace
        baked[map_name] = img

        # For each material slot, add an Image Texture node pointing to this image
        for slot in obj.material_slots:
            if slot.material and slot.material.use_nodes:
                tree = slot.material.node_tree
                img_node = tree.nodes.new('ShaderNodeTexImage')
                img_node.image = img
                img_node.name = f"bake_target_{map_name}"
                img_node.location = (1200, 0)
                # Select this node to make it the bake target
                tree.nodes.active = img_node

        # Bake
        try:
            if bake_type == 'DIFFUSE':
                bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'},
                                     use_clear=True, margin=4)
            elif bake_type == 'NORMAL':
                bpy.ops.object.bake(type='NORMAL', use_clear=True, margin=4,
                                     normal_space='TANGENT')
            elif bake_type == 'ROUGHNESS':
                bpy.ops.object.bake(type='ROUGHNESS', use_clear=True, margin=4)
            elif bake_type == 'AO':
                bpy.ops.object.bake(type='AO', use_clear=True, margin=4)
            print(f"      Baked {map_name}")
        except Exception as e:
            print(f"      Bake failed for {map_name}: {e}")

        # Remove temporary bake target nodes
        for slot in obj.material_slots:
            if slot.material and slot.material.use_nodes:
                tree = slot.material.node_tree
                for node in tree.nodes:
                    if node.name == f"bake_target_{map_name}":
                        tree.nodes.remove(node)

    # Pack ORM from separate bakes
    orm_img = pack_orm(baked.get('ao'), baked.get('roughness'), None, size, material_name_prefix)
    baked['orm'] = orm_img

    # Restore render engine
    bpy.context.scene.render.engine = original_engine

    return baked


def pack_orm(ao_img, rough_img, metal_img, size, prefix):
    """Pack AO, Roughness, Metallic into a single ORM image."""
    orm = bpy.data.images.new(f"{prefix}_orm", width=size, height=size, alpha=False)
    orm.colorspace_settings.name = 'Non-Color'

    ao_pixels = list(ao_img.pixels) if ao_img else [1.0, 1.0, 1.0, 1.0] * (size * size)
    rough_pixels = list(rough_img.pixels) if rough_img else [0.7, 0.7, 0.7, 1.0] * (size * size)

    orm_pixels = [0.0] * (size * size * 4)

    for i in range(size * size):
        idx = i * 4
        orm_pixels[idx + 0] = ao_pixels[idx]       # R = AO
        orm_pixels[idx + 1] = rough_pixels[idx]     # G = Roughness
        orm_pixels[idx + 2] = 0.0                    # B = Metallic (stone = 0)
        orm_pixels[idx + 3] = 1.0

    orm.pixels.foreach_set(orm_pixels)
    orm.pack()
    return orm


# ─── Export Material Setup ───────────────────────────────────────

def create_export_material(name, baked_images):
    """
    Create a clean glTF-compatible material using baked textures.
    Replaces procedural materials before export.
    """
    mat = bpy.data.materials.new(f"{name}_export")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (600, 0)

    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (200, 0)
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

    # Base color
    if 'basecolor' in baked_images:
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = baked_images['basecolor']
        tex.location = (-400, 300)
        links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])

    # Normal map
    if 'normal' in baked_images:
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = baked_images['normal']
        tex.location = (-400, -200)

        nmap = nodes.new('ShaderNodeNormalMap')
        nmap.location = (-100, -200)
        links.new(tex.outputs['Color'], nmap.inputs['Color'])
        links.new(nmap.outputs['Normal'], bsdf.inputs['Normal'])

    # ORM packed
    if 'orm' in baked_images:
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = baked_images['orm']
        tex.location = (-400, 50)

        sep = nodes.new('ShaderNodeSeparateColor')
        sep.location = (-100, 50)
        links.new(tex.outputs['Color'], sep.inputs['Color'])
        links.new(sep.outputs[1], bsdf.inputs['Roughness'])    # G = roughness
        links.new(sep.outputs[2], bsdf.inputs['Metallic'])     # B = metallic

    return mat


# ─── Main Assembly ───────────────────────────────────────────────

def main():
    print("=" * 60)
    print("Fantasy HQ Generator")
    print("=" * 60)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    clear_scene()

    # Create materials
    stone_mat = create_stone_material()
    wood_mat = create_wood_material()
    crystal_mat = create_crystal_material()
    roof_mat = create_roof_material()

    all_objects = []

    # ── Build the keep ──
    print("  Building keep body...")
    keep = create_keep_body()
    keep.data.materials.append(stone_mat)
    all_objects.append(keep)

    # ── Doorway ──
    print("  Building doorway...")
    doorway = create_arched_doorway()
    doorway.data.materials.append(stone_mat)
    all_objects.append(doorway)

    # ── Door ──
    print("  Building wooden door...")
    door = create_wooden_door()
    door.data.materials.append(wood_mat)
    all_objects.append(door)

    # ── Corner turrets ──
    print("  Building turrets...")
    hw = KEEP_WIDTH / 2 - 0.02
    turret_positions = [
        (-hw, -hw, "turret_fl"),
        ( hw, -hw, "turret_fr"),
        (-hw,  hw, "turret_bl"),
        ( hw,  hw, "turret_br"),
    ]
    for tx, tz, tname in turret_positions:
        turret_parts = create_turret((tx, tz), tname)
        for part in turret_parts:
            if "roof" in part.name:
                part.data.materials.append(roof_mat)
            else:
                part.data.materials.append(stone_mat)
            all_objects.append(part)

    # ── Keep battlements ──
    print("  Building battlements...")
    battlements = create_keep_battlements()
    for b in battlements:
        b.data.materials.append(stone_mat)
        all_objects.append(b)

    # ── Wall decorations ──
    print("  Building wall details...")
    decorations = create_wall_decorations()
    for d in decorations:
        d.data.materials.append(stone_mat)
        all_objects.append(d)

    # ── Crystal spire ──
    print("  Building crystal spire...")
    crystals = create_crystal_spire()
    for c in crystals:
        if "pedestal" in c.name:
            c.data.materials.append(stone_mat)
        else:
            c.data.materials.append(crystal_mat)
        all_objects.append(c)

    # ── Join everything ──
    print("  Joining objects...")
    bpy.ops.object.select_all(action='DESELECT')
    for obj in all_objects:
        if obj and obj.name in bpy.data.objects:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = all_objects[0]
    bpy.ops.object.join()
    hq = bpy.context.active_object
    hq.name = "fantasy_hq"

    # ── UV Unwrap ──
    print("  UV unwrapping...")
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
    bpy.ops.object.mode_set(mode='OBJECT')

    # ── Set origin to center-bottom ──
    bbox = [hq.matrix_world @ Vector(corner) for corner in hq.bound_box]
    min_z = min(v.z for v in bbox)
    center_x = sum(v.x for v in bbox) / 8
    center_y = sum(v.y for v in bbox) / 8

    for vert in hq.data.vertices:
        vert.co.x -= center_x
        vert.co.y -= center_y
        vert.co.z -= min_z
    hq.location = (0, 0, 0)

    # ── Bake textures ──
    print("  Baking PBR textures (this may take a minute)...")
    baked = bake_textures(hq, "fantasy_hq", TEX_SIZE)

    # ── Replace procedural materials with baked image materials for export ──
    print("  Creating export materials...")
    export_mat = create_export_material("fantasy_hq", baked)

    hq.data.materials.clear()
    hq.data.materials.append(export_mat)

    # ── Export ──
    print("  Exporting...")
    bpy.ops.object.select_all(action='DESELECT')
    hq.select_set(True)
    bpy.context.view_layer.objects.active = hq

    # glTF Binary
    glb_path = os.path.join(OUTPUT_DIR, "fantasy_hq.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_yup=True,
    )
    print(f"  Exported: {glb_path}")

    # USD
    usdc_path = os.path.join(OUTPUT_DIR, "fantasy_hq.usdc")
    try:
        bpy.ops.wm.usd_export(
            filepath=usdc_path,
            selected_objects_only=True,
            export_textures=True,
            generate_preview_surface=True,
        )
        print(f"  Exported: {usdc_path}")
    except Exception as e:
        print(f"  USD export skipped: {e}")

    print("\n" + "=" * 60)
    print("Done! Fantasy HQ exported to:")
    print(f"  {OUTPUT_DIR}/fantasy_hq.glb")
    print(f"  {OUTPUT_DIR}/fantasy_hq.usdc")
    print("=" * 60)


if __name__ == "__main__":
    main()

main()
