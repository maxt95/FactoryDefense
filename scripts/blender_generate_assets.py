"""
Blender Asset Generator for Factory Defense
=============================================
Generates PBR-ready 3D assets matching the whitebox catalog dimensions,
with procedural textures, and exports as .glb and .usdz.

Usage:
    1. Open Blender (4.0+)
    2. Go to Scripting workspace (top tab)
    3. Click "Open" and select this file
    4. Click "Run Script" (or Alt+P)
    5. Assets export to the project's Assets/Models/ directory

Or run headless from terminal:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/blender_generate_assets.py
"""

import bpy
import bmesh
import os
import math
import random
from mathutils import Vector, Matrix

# ─── Configuration ────────────────────────────────────────────────

# Output directory — hardcoded to your project path.
# __file__ is unreliable inside Blender's text editor.
PROJECT_DIR = "/Users/maxconrad/Workspace/factory-defense"
OUTPUT_DIR = os.path.join(PROJECT_DIR, "Assets", "Models")

# Texture resolution (256x256 per PRD for standard structures)
TEX_SIZE = 256

# Which assets to generate (comment out any you don't want)
ASSETS_TO_GENERATE = [
    "storage",
    "wall",
    "turret_mount",
    "miner",
    "smelter",
    "assembler",
    "ammo_module",
    "power_plant",
    "conveyor",
    "hq",
]

# ─── Color Palettes ──────────────────────────────────────────────
# sRGB colors for base color textures (matching WhiteboxColors.swift)

PALETTE = {
    "storage":      {"body": (0.45, 0.48, 0.52), "accent": (0.55, 0.50, 0.40)},
    "wall":         {"body": (0.50, 0.52, 0.54), "accent": (0.40, 0.42, 0.44)},
    "turret_mount": {"body": (0.35, 0.38, 0.42), "accent": (0.60, 0.30, 0.25)},
    "miner":        {"body": (0.55, 0.52, 0.35), "accent": (0.40, 0.40, 0.40)},
    "smelter":      {"body": (0.50, 0.35, 0.25), "accent": (0.30, 0.30, 0.30)},
    "assembler":    {"body": (0.35, 0.45, 0.55), "accent": (0.50, 0.50, 0.50)},
    "ammo_module":  {"body": (0.45, 0.40, 0.35), "accent": (0.60, 0.55, 0.30)},
    "power_plant":  {"body": (0.40, 0.50, 0.35), "accent": (0.65, 0.60, 0.20)},
    "conveyor":     {"body": (0.50, 0.50, 0.50), "accent": (0.60, 0.55, 0.30)},
    "hq":           {"body": (0.30, 0.40, 0.55), "accent": (0.70, 0.65, 0.40)},
}

# ─── Asset Geometry Definitions ───────────────────────────────────
# Matches WhiteboxAssetCatalog.swift dimensions exactly.
# Each asset = list of (half_extents, offset) box/cylinder primitives.
# half_extents: (x, y, z), offset: (x, y, z) where y=0 is ground.

ASSET_GEOMETRY = {
    "storage": [
        {"type": "box", "half": (0.45, 0.20, 0.45), "offset": (0, 0.20, 0)},
        {"type": "box", "half": (0.18, 0.08, 0.18), "offset": (0, 0.45, 0)},
    ],
    "wall": [
        {"type": "box", "half": (0.45, 0.50, 0.45), "offset": (0, 0.50, 0)},
    ],
    "turret_mount": [
        {"type": "box", "half": (0.45, 0.10, 0.45), "offset": (0, 0.10, 0)},
        {"type": "box", "half": (0.15, 0.25, 0.15), "offset": (0, 0.30, 0)},  # offset includes base height
        {"type": "box", "half": (0.25, 0.10, 0.25), "offset": (0, 0.60, 0)},
    ],
    "miner": [
        {"type": "box",      "half": (0.40, 0.20, 0.40), "offset": (0, 0.20, 0)},
        {"type": "cylinder", "radius": 0.10, "height": 0.30, "offset": (0, 0.55, 0)},
    ],
    "smelter": [
        {"type": "box", "half": (0.40, 0.30, 0.40), "offset": (0, 0.30, 0)},
        {"type": "box", "half": (0.08, 0.25, 0.08), "offset": (0.20, 0.85, -0.15)},  # chimney
    ],
    "assembler": [
        {"type": "box", "half": (0.45, 0.25, 0.45), "offset": (0, 0.25, 0)},
        {"type": "box", "half": (0.14, 0.14, 0.14), "offset": (-0.18, 0.64, 0)},
        {"type": "box", "half": (0.14, 0.14, 0.14), "offset": (0.18, 0.64, 0)},
    ],
    "ammo_module": [
        {"type": "box", "half": (0.35, 0.30, 0.35), "offset": (0, 0.30, 0)},
        {"type": "box", "half": (0.10, 0.10, 0.22), "offset": (0.30, 0.44, 0)},
    ],
    "power_plant": [
        {"type": "box", "half": (0.40, 0.40, 0.40), "offset": (0, 0.40, 0)},
        {"type": "box", "half": (0.16, 0.20, 0.16), "offset": (0, 0.96, 0)},
    ],
    "conveyor": [
        {"type": "box", "half": (0.45, 0.05, 0.45), "offset": (0, 0.05, 0)},
        {"type": "box", "half": (0.10, 0.02, 0.10), "offset": (0.24, 0.12, 0)},
    ],
    "hq": [
        {"type": "box", "half": (0.45, 0.45, 0.45), "offset": (0, 0.45, 0)},
        {"type": "box", "half": (0.16, 0.16, 0.16), "offset": (0, 1.06, 0)},
    ],
}


# ─── Utility Functions ────────────────────────────────────────────

def clear_scene():
    """Remove all objects, meshes, materials, and images from the scene."""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    for block in [bpy.data.meshes, bpy.data.materials, bpy.data.images]:
        for item in block:
            if not item.users:
                block.remove(item)


def create_box(half_extents, offset):
    """Create a box mesh at the given offset with the given half-extents."""
    hx, hy, hz = half_extents
    ox, oy, oz = offset

    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=(ox, oz, oy),  # Blender Z-up → game Y-up
        scale=(hx * 2, hz * 2, hy * 2)  # Blender (X, Y, Z) with Z-up
    )
    obj = bpy.context.active_object
    # Apply scale so mesh data is correct for UV unwrap
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Add a small bevel for better lighting response
    bevel = obj.modifiers.new(name="Bevel", type='BEVEL')
    bevel.width = 0.01
    bevel.segments = 1
    bevel.limit_method = 'ANGLE'
    bevel.angle_limit = math.radians(60)
    bpy.ops.object.modifier_apply(modifier="Bevel")

    return obj


def create_cylinder(radius, height, offset, segments=10):
    """Create a cylinder mesh at the given offset."""
    ox, oy, oz = offset

    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius,
        depth=height,
        vertices=segments,
        location=(ox, oz, oy),  # Blender Z-up
    )
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def join_objects(objects):
    """Join multiple objects into one."""
    if len(objects) <= 1:
        return objects[0] if objects else None

    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return bpy.context.active_object


def smart_uv_unwrap(obj):
    """UV unwrap the object using Smart UV Project."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')


def set_origin_to_bottom_center(obj):
    """Set the object origin to the center-bottom of its bounding box."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Get the bounding box in world space
    bbox = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    min_z = min(v.z for v in bbox)
    center_x = sum(v.x for v in bbox) / 8
    center_y = sum(v.y for v in bbox) / 8

    # Move geometry so origin is at center-bottom
    offset = Vector((-center_x, -center_y, -min_z))
    mesh = obj.data
    for vert in mesh.vertices:
        vert.co += offset

    # Move object to compensate
    obj.location.x += center_x
    obj.location.y += center_y
    obj.location.z += min_z

    # Now set location to world origin
    obj.location = (0, 0, 0)


# ─── Texture Generation ──────────────────────────────────────────

def create_base_color_texture(name, body_color, accent_color, size=TEX_SIZE):
    """
    Generate a base color texture with two-tone pattern.
    Body color for main surfaces, accent for edges/details.
    """
    img = bpy.data.images.new(f"{name}_basecolor", width=size, height=size, alpha=False)
    img.colorspace_settings.name = 'sRGB'

    pixels = [0.0] * (size * size * 4)

    random.seed(hash(name))  # deterministic per asset

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4

            # Create subtle variation and panel lines
            noise = random.uniform(-0.03, 0.03)

            # Panel line pattern (darker lines at regular intervals)
            is_panel_line = (x % 32 < 2) or (y % 32 < 2)

            # Top portion uses accent color (lid/top detail)
            use_accent = y > size * 0.7

            if use_accent:
                r, g, b = accent_color
            else:
                r, g, b = body_color

            if is_panel_line:
                darken = 0.85
                r *= darken
                g *= darken
                b *= darken

            # Add noise for texture
            r = max(0, min(1, r + noise))
            g = max(0, min(1, g + noise))
            b = max(0, min(1, b + noise))

            pixels[idx + 0] = r
            pixels[idx + 1] = g
            pixels[idx + 2] = b
            pixels[idx + 3] = 1.0

    img.pixels.foreach_set(pixels)
    img.pack()
    return img


def create_normal_texture(name, size=TEX_SIZE):
    """
    Generate a normal map with subtle surface detail.
    Flat normal = (0.5, 0.5, 1.0) in tangent space.
    Adds slight panel/rivet detail.
    """
    img = bpy.data.images.new(f"{name}_normal", width=size, height=size, alpha=False)
    img.colorspace_settings.name = 'Non-Color'

    pixels = [0.0] * (size * size * 4)

    random.seed(hash(name) + 1)

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4

            # Base flat normal
            nx, ny, nz = 0.5, 0.5, 1.0

            # Panel line bumps (slight indentation at seams)
            near_panel_x = (x % 32) < 3 or (x % 32) > 29
            near_panel_y = (y % 32) < 3 or (y % 32) > 29

            if near_panel_x:
                nx += 0.08 if (x % 32) < 3 else -0.08
            if near_panel_y:
                ny += 0.08 if (y % 32) < 3 else -0.08

            # Rivet bumps (small circular bumps in grid)
            rivet_spacing = 64
            rivet_x = x % rivet_spacing
            rivet_y = y % rivet_spacing
            rivet_dist = math.sqrt((rivet_x - rivet_spacing / 2) ** 2 + (rivet_y - rivet_spacing / 2) ** 2)
            if rivet_dist < 4:
                strength = 0.12 * (1 - rivet_dist / 4)
                dx = (rivet_x - rivet_spacing / 2) / max(rivet_dist, 0.1)
                dy = (rivet_y - rivet_spacing / 2) / max(rivet_dist, 0.1)
                nx += dx * strength
                ny += dy * strength

            # Subtle surface noise
            noise = random.uniform(-0.015, 0.015)
            nx += noise
            ny += noise

            # Clamp to valid range
            nx = max(0, min(1, nx))
            ny = max(0, min(1, ny))
            nz = max(0, min(1, nz))

            pixels[idx + 0] = nx
            pixels[idx + 1] = ny
            pixels[idx + 2] = nz
            pixels[idx + 3] = 1.0

    img.pixels.foreach_set(pixels)
    img.pack()
    return img


def create_orm_texture(name, base_roughness=0.65, base_metallic=0.0, size=TEX_SIZE):
    """
    Generate ORM packed texture.
    R = Ambient Occlusion (1.0 = no occlusion)
    G = Roughness
    B = Metallic
    """
    img = bpy.data.images.new(f"{name}_orm", width=size, height=size, alpha=False)
    img.colorspace_settings.name = 'Non-Color'

    pixels = [0.0] * (size * size * 4)

    random.seed(hash(name) + 2)

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4

            # AO: darken at panel lines (seams collect dirt/shadow)
            ao = 1.0
            near_panel = ((x % 32) < 2) or ((y % 32) < 2)
            if near_panel:
                ao = 0.7

            # Roughness: slight variation across surface
            roughness = base_roughness + random.uniform(-0.08, 0.08)
            # Panel lines are slightly rougher
            if near_panel:
                roughness += 0.1
            roughness = max(0.1, min(1.0, roughness))

            # Metallic: use base value with slight variation
            metallic = base_metallic + random.uniform(-0.02, 0.02)
            metallic = max(0.0, min(1.0, metallic))

            pixels[idx + 0] = ao
            pixels[idx + 1] = roughness
            pixels[idx + 2] = metallic
            pixels[idx + 3] = 1.0

    img.pixels.foreach_set(pixels)
    img.pack()
    return img


# ─── Material Setup ──────────────────────────────────────────────

def create_pbr_material(name, basecolor_img, normal_img, orm_img):
    """
    Create a Principled BSDF material with PBR textures connected.
    This ensures the material exports correctly to glTF.
    """
    mat = bpy.data.materials.new(name=f"{name}_material")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    # Clear default nodes
    for node in nodes:
        nodes.remove(node)

    # Output node
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (600, 0)

    # Principled BSDF
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (200, 0)
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

    # ── Base Color Texture ──
    basecolor_tex = nodes.new('ShaderNodeTexImage')
    basecolor_tex.image = basecolor_img
    basecolor_tex.location = (-400, 300)
    links.new(basecolor_tex.outputs['Color'], bsdf.inputs['Base Color'])

    # ── Normal Map ──
    normal_tex = nodes.new('ShaderNodeTexImage')
    normal_tex.image = normal_img
    normal_tex.location = (-400, -200)

    normal_map = nodes.new('ShaderNodeNormalMap')
    normal_map.location = (-100, -200)
    normal_map.inputs['Strength'].default_value = 1.0

    links.new(normal_tex.outputs['Color'], normal_map.inputs['Color'])
    links.new(normal_map.outputs['Normal'], bsdf.inputs['Normal'])

    # ── ORM Packed Texture ──
    orm_tex = nodes.new('ShaderNodeTexImage')
    orm_tex.image = orm_img
    orm_tex.location = (-400, 50)

    # Separate RGB to route channels
    separate = nodes.new('ShaderNodeSeparateColor')
    separate.location = (-100, 50)
    links.new(orm_tex.outputs['Color'], separate.inputs['Color'])

    # R → (AO — not directly connected in Principled BSDF, but exports in glTF)
    # G → Roughness
    links.new(separate.outputs[1], bsdf.inputs['Roughness'])
    # B → Metallic
    links.new(separate.outputs[2], bsdf.inputs['Metallic'])

    return mat


# ─── Asset Generation ────────────────────────────────────────────

def generate_asset(asset_name):
    """Generate a complete asset with geometry, UVs, textures, and material."""
    print(f"  Generating: {asset_name}")

    geometry_def = ASSET_GEOMETRY.get(asset_name)
    if not geometry_def:
        print(f"    No geometry definition for {asset_name}, skipping.")
        return None

    colors = PALETTE.get(asset_name, {"body": (0.5, 0.5, 0.5), "accent": (0.4, 0.4, 0.4)})

    # ── Create geometry ──
    objects = []
    for prim in geometry_def:
        if prim["type"] == "box":
            obj = create_box(prim["half"], prim["offset"])
            objects.append(obj)
        elif prim["type"] == "cylinder":
            obj = create_cylinder(prim["radius"], prim["height"], prim["offset"])
            objects.append(obj)

    if not objects:
        return None

    # Join all primitives into one object
    asset_obj = join_objects(objects)
    asset_obj.name = asset_name

    # Set origin to center-bottom
    set_origin_to_bottom_center(asset_obj)

    # UV unwrap
    smart_uv_unwrap(asset_obj)

    # ── Generate textures ──
    is_metallic = asset_name in ["wall", "turret_mount", "conveyor"]
    base_roughness = 0.5 if is_metallic else 0.65
    base_metallic = 0.8 if is_metallic else 0.0

    basecolor_img = create_base_color_texture(asset_name, colors["body"], colors["accent"])
    normal_img = create_normal_texture(asset_name)
    orm_img = create_orm_texture(asset_name, base_roughness=base_roughness, base_metallic=base_metallic)

    # ── Create and assign material ──
    material = create_pbr_material(asset_name, basecolor_img, normal_img, orm_img)
    asset_obj.data.materials.clear()
    asset_obj.data.materials.append(material)

    return asset_obj


def export_asset(obj, asset_name):
    """Export a single asset as .glb and .usdz."""
    # Select only this object
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    # ── Export glTF Binary (.glb) ──
    glb_path = os.path.join(OUTPUT_DIR, f"{asset_name}.glb")
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
    print(f"    Exported: {glb_path}")

    # ── Export USD (.usdc) ──
    # Note: Blender exports .usdc (crate format). You can convert to .usdz
    # with Reality Converter, or your engine can load .usdc directly via Model I/O.
    usdc_path = os.path.join(OUTPUT_DIR, f"{asset_name}.usdc")
    try:
        bpy.ops.wm.usd_export(
            filepath=usdc_path,
            selected_objects_only=True,
            export_textures=True,
            generate_preview_surface=True,
            export_normals=True,
            export_materials=True,
        )
        print(f"    Exported: {usdc_path}")
    except Exception as e:
        print(f"    USD export skipped ({e}). Use Reality Converter to convert .glb → .usdz")


# ─── Main ─────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("Factory Defense Asset Generator")
    print("=" * 60)

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Output directory: {OUTPUT_DIR}")

    for asset_name in ASSETS_TO_GENERATE:
        print(f"\n--- {asset_name} ---")

        # Clear scene for each asset (clean export)
        clear_scene()

        # Generate the asset
        obj = generate_asset(asset_name)
        if obj is None:
            print(f"  Failed to generate {asset_name}")
            continue

        # Export
        export_asset(obj, asset_name)

    # Final cleanup
    clear_scene()

    print("\n" + "=" * 60)
    print("Done! Assets exported to:")
    print(f"  {OUTPUT_DIR}")
    print("")
    print("Next steps:")
    print("  1. .glb files are ready for GLTFKit2 or web preview")
    print("  2. .usdc files load directly via ModelIOMeshLibrary")
    print("  3. For .usdz: open .glb in Reality Converter → Export")
    print("=" * 60)


if __name__ == "__main__":
    main()

# Run when executed inside Blender's text editor
main()
