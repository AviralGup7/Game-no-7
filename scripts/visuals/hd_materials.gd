class_name HdMaterials
extends RefCounted

## Shared "HD material pass" applied to every mounted character/enemy model and
## every arena prop after import. It never downloads or replaces textures: it upgrades
## the existing sampled materials in place (anisotropic filtering, tuned
## roughness/metallic/specular per role) so the approved geometric art reads far more
## realistically under the new HD lighting without touching rigs or animations.
##
## Every surface material is duplicated shallowly (textures stay shared) before any
## property is written; the imported source materials are never mutated.

const FILTER_ANISO := BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

## Per-role material targets: [min_roughness, max_roughness, min_metallic, max_metallic].
const ROLE_TUNING := {
	&"player":    [0.35, 0.60, 0.10, 0.30],
	&"basic":     [0.60, 0.85, 0.00, 0.05],
	&"fast":      [0.60, 0.85, 0.00, 0.05],
	&"heavy":     [0.55, 0.80, 0.05, 0.20],
	&"ranged":    [0.60, 0.85, 0.00, 0.05],
	&"dasher":    [0.70, 0.90, 0.00, 0.05],
	&"splitter":  [0.70, 0.90, 0.00, 0.05],
	&"exploder":  [0.45, 0.75, 0.00, 0.10],
	&"warlord":   [0.40, 0.70, 0.05, 0.25],
}
const DEFAULT_TUNING := [0.45, 0.90, 0.00, 0.30]


## Upgrade every mesh surface under `root`. Safe on any node and on missing art:
## no surfaces or non-standard materials are ever touched.
static func polish(root: Node, role: StringName = &"", preserve_authored_pbr: bool = false) -> void:
	if root == null:
		return
	var tuning: Array = ROLE_TUNING.get(role, DEFAULT_TUNING)
	_walk(root, tuning, preserve_authored_pbr)


static func _walk(node: Node, tuning: Array, preserve_authored_pbr: bool) -> void:
	if node is MeshInstance3D:
		_polish_mesh(node as MeshInstance3D, tuning, preserve_authored_pbr)
	for child in node.get_children():
		_walk(child, tuning, preserve_authored_pbr)


static func _polish_mesh(mi: MeshInstance3D, tuning: Array, preserve_authored_pbr: bool) -> void:
	if mi.mesh == null:
		return
	var surfaces := mi.mesh.get_surface_count()
	for index in range(surfaces):
		var active := mi.get_active_material(index)
		if active == null or not (active is BaseMaterial3D):
			continue
		var source := active as BaseMaterial3D
		var tuned := source.duplicate() as BaseMaterial3D
		if tuned == null:
			continue
		tuned.texture_filter = FILTER_ANISO
		# Authored PBR uses unit factors multiplied by its ORM atlas. Clamping those
		# factors to the old palette-kit range would turn steel into plastic and
		# lower cloth roughness. Only filtering changes on such assets.
		if not preserve_authored_pbr:
			tuned.metallic_specular = clampf(source.metallic_specular, 0.35, 0.6)
			tuned.roughness = clampf(source.roughness, float(tuning[0]), float(tuning[1]))
			tuned.metallic = clampf(source.metallic, float(tuning[2]), float(tuning[3]))
			if tuned.normal_enabled and not tuned.normal_texture == null:
				tuned.normal_scale = clampf(source.normal_scale, 0.8, 1.25)
		mi.set_surface_override_material(index, tuned)
