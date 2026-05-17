class_name InfiniteGround
extends Node3D

## Vampire-Survivors-style "infinite" ground plane: one oversized
## PlaneMesh that follows the PC each frame, with a world-space grid
## shader so the PC's motion is visually unambiguous.
##
## Why this design (vs. a real chunk grid):
##   For a flat single-biome arena, one PC-following plane + a shader
##   that draws lines from WORLD position is visually identical to a
##   N×N chunk grid but with one draw call instead of N² and zero
##   chunk-bookkeeping. A real chunk system only starts paying off
##   when per-cell decoration / biome logic shows up — when that
##   arrives, replace this class with a ChunkManager that pools
##   InfiniteGround-like cells.
##
## Why a GRID shader instead of a Perlin noise texture:
##   We started with NoiseTexture2D + triplanar UVs. The math worked
##   (pattern was anchored to world position, mesh followed the PC) but
##   Perlin is a smooth gradient — at the camera's zoom, every visible
##   ground pixel ended up nearly the same color and the player read it
##   as "not moving". Hard grid lines give a discrete reference: a 4-
##   unit cell line that crosses the screen IS unambiguous motion.

@export var target_path: NodePath
## XZ size of the visible / colliding ground plane. 100×100 is plenty
## for any reasonable camera FOV.
@export var ground_size: float = 100.0
@export var ground_color: Color = Color(0.34, 0.45, 0.28)
## Color used for the grid lines. Default = a darker shade of ground_color
## (computed in _build_material when this stays at its sentinel alpha=0).
@export var line_color: Color = Color(0, 0, 0, 0)
## World units per grid cell. 4 = a fresh line every ~half a step.
@export var cell_size: float = 4.0
## Fraction of a cell the line occupies (0..1). 0.04 = subtle hairline.
@export var line_width: float = 0.04
@export var ground_roughness: float = 0.95

var _target: Node3D
var _ground: StaticBody3D
var _visual: MeshInstance3D
var _collider: CollisionShape3D

const _GRID_SHADER_CODE: String = """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec4 base_color : source_color;
uniform vec4 line_color : source_color;
uniform float cell_size = 4.0;
uniform float line_width = 0.04;
uniform float roughness_in = 0.95;

varying vec3 world_xz;

void vertex() {
	// World-space XZ — independent of mesh/node transform, so when the
	// ground follows the PC the grid stays anchored to the world.
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = fract(world_xz.xz / cell_size);
	float lx = step(cell.x, line_width) + step(1.0 - line_width, cell.x);
	float ly = step(cell.y, line_width) + step(1.0 - line_width, cell.y);
	float on_line = clamp(lx + ly, 0.0, 1.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, on_line);
	ROUGHNESS = roughness_in;
}
"""

func _ready() -> void:
	# Detach from parent transform so we drive position ourselves.
	top_level = true
	_target = get_node_or_null(target_path) as Node3D
	_build()
	_sync_to_target()

func _process(_delta: float) -> void:
	_sync_to_target()

func _physics_process(_delta: float) -> void:
	# Sync on the physics tick too so the collider follows the PC
	# without ever lagging a render frame.
	_sync_to_target()

func _sync_to_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var p := _target.global_position
	global_position = Vector3(p.x, 0.0, p.z)

## External override — useful when target isn't set via NodePath at
## load time (Main / Testplay spawn the PC then hand us its ref).
func set_target(t: Node3D) -> void:
	_target = t
	_sync_to_target()

func _build() -> void:
	_ground = StaticBody3D.new()
	_ground.name = "GroundBody"
	_ground.collision_layer = 1
	_ground.collision_mask = 0
	add_child(_ground)

	var pm := PlaneMesh.new()
	pm.size = Vector2(ground_size, ground_size)
	# Subdivide so the world-position varying interpolates smoothly across
	# the plane; without subdivisions a huge plane's vertex world_xz only
	# has 4 sample points and the fract() in the shader can show banding.
	pm.subdivide_width = 16
	pm.subdivide_depth = 16
	_visual = MeshInstance3D.new()
	_visual.name = "GroundVisual"
	_visual.mesh = pm
	_visual.material_override = _build_material()
	_ground.add_child(_visual)

	_collider = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(ground_size, 0.2, ground_size)
	_collider.shape = bs
	_collider.transform.origin = Vector3(0.0, -0.1, 0.0)
	_ground.add_child(_collider)

func _build_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = _GRID_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("base_color", ground_color)
	# Auto-derive line color from ground_color if the user left the
	# sentinel (alpha=0). 0.6× albedo reads as a soft darker line —
	# present but not "debug-grid" loud.
	var lc: Color = line_color
	if lc.a <= 0.0:
		lc = Color(ground_color.r * 0.6, ground_color.g * 0.6,
				ground_color.b * 0.6, 1.0)
	mat.set_shader_parameter("line_color", lc)
	mat.set_shader_parameter("cell_size", cell_size)
	mat.set_shader_parameter("line_width", line_width)
	mat.set_shader_parameter("roughness_in", ground_roughness)
	return mat
