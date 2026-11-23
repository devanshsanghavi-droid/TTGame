class_name CreatureShapes extends RefCounted
## Species data for CreatureWalker: body cross-sections, leg layout, gait and the
## sculpted head / fur / gear for each animal. Life size at scale 1, facing -Z.
##
## Station format: [z, y, half_width, half_height]; +z is toward the tail.

const IVORY := Color(0.86, 0.8, 0.66)
const HORN := Color(0.2, 0.17, 0.14)
const EYE := Color(0.03, 0.025, 0.02)
const KINDS := ["mammoth", "woolly_rhino", "cave_bear", "sauropod", "elephant", "horse", "ox", "trex"]


static func variant_key(kind: String, o: Dictionary) -> String:
	match kind:
		"elephant":
			return "h%s|%s|%s" % [o.get("howdah", false), o.get("cloth", ""), o.get("trim", "")]
		"horse":
			return "%s|s%s|c%s|%s|%s" % [_coat(o), o.get("saddle", false), o.get("caparison", false), o.get("cloth", ""), o.get("trim", "")]
		"ox":
			return "hump%s|%s" % [o.get("hump", false), _ox_coat(o)]
	return ""


static func _coat(o: Dictionary) -> String:
	return o.get("coat", ["bay", "chestnut", "grey", "black", "bay"][int(o.get("seed", 0)) % 5])


static func _ox_coat(o: Dictionary) -> String:
	return o.get("coat", ["tan", "white", "red"][int(o.get("seed", 0)) % 3])


static func materials(S: Dictionary) -> Dictionary:
	return {
		"hide": CreatureMesh.material(S.tex, S.get("mat", {})),
		"gear": CreatureMesh.material("acg_fabric", {"scale": 5.0, "contrast": 0.9, "normal": 1.2}),
	}


static func shape(kind: String, o: Dictionary) -> Dictionary:
	var S := {}
	match kind:
		"mammoth":
			S = {
				"tex": "thatch_roof_angled", "mat": {"scale": 0.75, "contrast": 1.15, "rim": 0.3, "normal": 1.3},
				"col": [Color(0.3, 0.185, 0.115), Color(0.2, 0.125, 0.085), Color(0.37, 0.24, 0.15)],
				"body": [[1.8, 1.85, 0.5, 0.62], [1.25, 1.93, 0.84, 0.94], [0.5, 2.0, 0.98, 1.06], [-0.3, 2.1, 1.02, 1.14], [-0.95, 2.26, 0.98, 1.2], [-1.5, 2.32, 0.78, 1.0]],
				"neck": [[-1.62, 2.52, 0.64, 0.76], [-1.95, 2.68, 0.56, 0.64], [-2.25, 2.8, 0.5, 0.56]],
				"tail": [[1.9, 2.0, 0.12, 0.12], [2.06, 1.72, 0.08, 0.08], [2.12, 1.42, 0.05, 0.05]],
				"front": {"x": 0.52, "hip": Vector2(-1.05, 1.9), "knee": Vector2(-1.12, 1.0), "ankle": Vector2(-1.05, 0.2), "r": [0.4, 0.34, 0.27, 0.25, 0.25], "foot": "pad", "foot_r": 0.3},
				"hind": {"x": 0.5, "hip": Vector2(1.2, 1.65), "knee": Vector2(1.05, 0.9), "ankle": Vector2(1.25, 0.2), "r": [0.44, 0.36, 0.27, 0.24, 0.24], "foot": "pad", "foot_r": 0.28},
				"stride": 2.6, "duty": 0.72, "lift": 0.28, "bob": 0.035, "roll": 0.022, "sway": 0.05, "toe_pitch": 0.35,
				"speed": 1.5, "turn": 0.5, "accel": 0.7, "weight": 0.8, "half_len": 1.3, "max_yaw": 0.7,
				"neck_sim": {"rigid": true},
				"tail_sim": {"stiff": 40.0, "tip": 18.0, "damp": 4.0, "yaw": Vector3(0.14, 1.3, 0.8), "walk": 0.6},
				"trunk_sim": {"stiff": 34.0, "tip": 12.0, "damp": 4.5, "yaw": Vector3(0.045, 0.8, 0.7), "pitch": Vector3(0.04, 0.55, 0.8), "walk": 1.6},
				"collider": [1.9, 3.1, 4.4, -0.3], "aabb": AABB(Vector3(-2.2, -0.3, -5.6), Vector3(4.4, 4.6, 8.4)), "threat": true,
			}
		"elephant":
			S = {
				"tex": "mud_cracked_dry_03", "mat": {"scale": 2.3, "contrast": 0.4, "normal": 1.1, "rough": 1.05},
				"col": [Color(0.37, 0.34, 0.32), Color(0.45, 0.4, 0.37), Color(0.3, 0.28, 0.27)],
				"body": [[1.62, 1.8, 0.5, 0.58], [1.1, 1.92, 0.8, 0.83], [0.4, 2.02, 0.92, 0.9], [-0.4, 2.0, 0.92, 0.9], [-1.0, 1.94, 0.85, 0.87], [-1.42, 1.92, 0.66, 0.74]],
				"neck": [[-1.5, 2.08, 0.56, 0.62], [-1.78, 2.2, 0.5, 0.55], [-2.02, 2.32, 0.46, 0.5]],
				"tail": [[1.7, 2.0, 0.09, 0.09], [1.86, 1.65, 0.06, 0.06], [1.92, 1.25, 0.045, 0.045], [1.94, 0.9, 0.035, 0.035]],
				"front": {"x": 0.47, "hip": Vector2(-0.98, 1.6), "knee": Vector2(-1.04, 0.84), "ankle": Vector2(-0.98, 0.17), "r": [0.34, 0.29, 0.23, 0.215, 0.215], "foot": "pad", "foot_r": 0.25},
				"hind": {"x": 0.46, "hip": Vector2(1.12, 1.48), "knee": Vector2(0.98, 0.78), "ankle": Vector2(1.16, 0.17), "r": [0.38, 0.31, 0.23, 0.205, 0.205], "foot": "pad", "foot_r": 0.235},
				"stride": 2.3, "duty": 0.72, "lift": 0.24, "bob": 0.03, "roll": 0.02, "sway": 0.045, "toe_pitch": 0.35,
				"speed": 1.4, "turn": 0.55, "accel": 0.7, "weight": 0.7, "half_len": 1.15, "max_yaw": 0.7,
				"neck_sim": {"rigid": true},
				"tail_sim": {"stiff": 40.0, "tip": 16.0, "damp": 4.0, "yaw": Vector3(0.16, 1.5, 0.8), "walk": 0.5},
				"trunk_sim": {"stiff": 34.0, "tip": 12.0, "damp": 4.5, "yaw": Vector3(0.05, 0.8, 0.7), "pitch": Vector3(0.045, 0.6, 0.8), "walk": 1.5},
				"collider": [1.8, 2.8, 3.9, -0.25], "aabb": AABB(Vector3(-2.2, -0.3, -4.6), Vector3(4.4, 5.6, 7.2)), "threat": true,
			}
		"woolly_rhino":
			S = {
				"tex": "thatch_roof_angled", "mat": {"scale": 1.0, "contrast": 1.0, "rim": 0.25, "normal": 1.2},
				"col": [Color(0.4, 0.29, 0.18), Color(0.3, 0.21, 0.14), Color(0.46, 0.34, 0.21)],
				"body": [[1.3, 1.22, 0.42, 0.46], [0.9, 1.26, 0.64, 0.6], [0.2, 1.24, 0.72, 0.64], [-0.4, 1.32, 0.72, 0.72], [-0.85, 1.46, 0.66, 0.78], [-1.22, 1.34, 0.52, 0.62]],
				"neck": [[-1.32, 1.26, 0.48, 0.56], [-1.56, 1.12, 0.42, 0.47], [-1.76, 1.0, 0.36, 0.39]],
				"tail": [[1.36, 1.36, 0.07, 0.07], [1.5, 1.1, 0.05, 0.05], [1.54, 0.86, 0.035, 0.035]],
				"front": {"x": 0.44, "hip": Vector2(-0.84, 1.16), "knee": Vector2(-0.9, 0.62), "ankle": Vector2(-0.84, 0.16), "r": [0.31, 0.26, 0.2, 0.18, 0.18], "foot": "pad", "foot_r": 0.2},
				"hind": {"x": 0.44, "hip": Vector2(0.9, 1.1), "knee": Vector2(0.78, 0.6), "ankle": Vector2(0.94, 0.16), "r": [0.34, 0.28, 0.2, 0.175, 0.175], "foot": "pad", "foot_r": 0.195},
				"stride": 1.7, "duty": 0.68, "lift": 0.18, "bob": 0.025, "roll": 0.02, "sway": 0.03, "toe_pitch": 0.4,
				"speed": 1.5, "turn": 0.7, "accel": 0.9, "weight": 0.55, "half_len": 1.1, "max_yaw": 0.6,
				"neck_sim": {"rigid": true},
				"tail_sim": {"stiff": 50.0, "tip": 24.0, "damp": 5.0, "yaw": Vector3(0.2, 2.0, 0.8)},
				"collider": [1.5, 2.0, 3.5, -0.3], "aabb": AABB(Vector3(-1.6, -0.3, -4.0), Vector3(3.2, 3.2, 6.4)), "threat": true,
			}
		"cave_bear":
			S = {
				"tex": "thatch_roof_angled", "mat": {"scale": 1.5, "contrast": 0.95, "rim": 0.35, "normal": 1.1},
				"col": [Color(0.3, 0.2, 0.12), Color(0.24, 0.16, 0.1), Color(0.36, 0.25, 0.15)],
				"body": [[1.1, 0.9, 0.38, 0.46], [0.6, 0.95, 0.58, 0.58], [0.0, 0.96, 0.63, 0.6], [-0.5, 1.03, 0.62, 0.68], [-0.95, 1.06, 0.5, 0.6]],
				"neck": [[-1.06, 1.1, 0.42, 0.44], [-1.28, 1.08, 0.36, 0.37], [-1.48, 1.05, 0.31, 0.31]],
				"tail": [[1.15, 1.02, 0.09, 0.09], [1.3, 0.92, 0.06, 0.06]],
				"front": {"x": 0.36, "hip": Vector2(-0.75, 0.86), "knee": Vector2(-0.8, 0.46), "ankle": Vector2(-0.74, 0.11), "r": [0.24, 0.2, 0.16, 0.145, 0.14], "foot": "paw", "foot_r": 0.15, "foot_dz": -0.04},
				"hind": {"x": 0.34, "hip": Vector2(0.8, 0.82), "knee": Vector2(0.66, 0.44), "ankle": Vector2(0.86, 0.11), "r": [0.27, 0.22, 0.16, 0.14, 0.135], "foot": "paw", "foot_r": 0.15, "foot_dz": -0.06},
				"stride": 1.5, "duty": 0.66, "lift": 0.16, "bob": 0.03, "roll": 0.035, "sway": 0.04, "toe_pitch": 0.6,
				"speed": 1.4, "turn": 0.9, "accel": 1.2, "weight": 0.4, "half_len": 0.85, "max_yaw": 0.9, "hears": true,
				"neck_sim": {"rigid": true},
				"tail_sim": {"rigid": true},
				"collider": [1.2, 1.5, 2.6, -0.2], "aabb": AABB(Vector3(-1.2, -0.3, -2.6), Vector3(2.4, 2.4, 4.4)), "threat": true,
			}
		"sauropod":
			var neck: Array = []
			for i in 10:
				var t := i / 9.0
				neck.append([lerpf(-2.9, -10.2, t), lerpf(4.35, 9.3, t) + sin(t * PI) * 0.35, lerpf(0.78, 0.27, pow(t, 0.7)), lerpf(0.86, 0.27, pow(t, 0.7))])
			var tail: Array = []
			for i in 11:
				var t := i / 10.0
				tail.append([lerpf(3.0, 13.6, t), lerpf(4.05, 1.5, pow(t, 0.8)) + sin(t * PI) * 0.5, lerpf(0.78, 0.05, pow(t, 0.75)), lerpf(0.86, 0.05, pow(t, 0.75))])
			S = {
				"tex": "dry_ground_01", "mat": {"scale": 0.4, "contrast": 0.8, "normal": 1.5, "rough": 1.05},
				"col": [Color(0.4, 0.37, 0.29), Color(0.6, 0.55, 0.43), Color(0.27, 0.27, 0.22)],
				"body": [[2.85, 4.02, 0.92, 1.0], [2.0, 3.95, 1.26, 1.36], [0.8, 3.85, 1.46, 1.56], [-0.6, 3.85, 1.4, 1.5], [-1.8, 3.96, 1.16, 1.26], [-2.5, 4.12, 0.9, 1.0]],
				"neck": neck, "tail": tail, "sides": 18,
				"front": {"x": 0.95, "hip": Vector2(-1.9, 3.3), "knee": Vector2(-2.0, 1.75), "ankle": Vector2(-1.9, 0.32), "r": [0.64, 0.54, 0.45, 0.43, 0.43], "foot": "pad", "foot_r": 0.48, "top_up": 0.3},
				"hind": {"x": 1.02, "hip": Vector2(2.1, 3.3), "knee": Vector2(1.92, 1.75), "ankle": Vector2(2.1, 0.32), "r": [0.72, 0.56, 0.47, 0.44, 0.44], "foot": "pad", "foot_r": 0.5, "top_up": 0.3},
				"stride": 5.2, "duty": 0.74, "lift": 0.45, "bob": 0.06, "roll": 0.015, "sway": 0.1, "toe_pitch": 0.3,
				"speed": 1.7, "turn": 0.22, "accel": 0.5, "weight": 1.0, "half_len": 2.2, "max_yaw": 0.9, "head_share": 0.25,
				"neck_sim": {"stiff": 26.0, "tip": 14.0, "damp": 4.5, "yaw": Vector3(0.012, 0.33, 0.5), "pitch": Vector3(0.007, 0.27, 0.45)},
				"tail_sim": {"stiff": 22.0, "tip": 7.0, "damp": 3.2, "yaw": Vector3(0.035, 0.5, 0.55), "walk": 1.4},
				"collider": [2.9, 5.2, 6.4, 0.0], "aabb": AABB(Vector3(-5, -0.5, -13), Vector3(10, 12.5, 28)), "threat": true,
			}
		"horse":
			var coat := _coat(o)
			var cols := {
				"bay": [Color(0.34, 0.17, 0.085), Color(0.3, 0.16, 0.085), Color(0.3, 0.15, 0.075)],
				"chestnut": [Color(0.46, 0.24, 0.11), Color(0.5, 0.29, 0.15), Color(0.42, 0.21, 0.1)],
				"grey": [Color(0.62, 0.6, 0.57), Color(0.72, 0.7, 0.67), Color(0.52, 0.51, 0.49)],
				"black": [Color(0.085, 0.075, 0.07), Color(0.1, 0.09, 0.085), Color(0.07, 0.065, 0.06)],
			}
			S = {
				"tex": "thatch_roof_angled", "mat": {"scale": 2.6, "contrast": 0.45, "normal": 0.5, "rough": 0.8, "rim": 0.15},
				"col": cols.get(coat, cols.bay), "coat": coat,
				"body": [[0.98, 1.2, 0.22, 0.27], [0.72, 1.2, 0.31, 0.36], [0.2, 1.13, 0.33, 0.36], [-0.3, 1.11, 0.34, 0.38], [-0.64, 1.18, 0.3, 0.4], [-0.84, 1.22, 0.24, 0.35]],
				"neck": [[-0.84, 1.32, 0.2, 0.33], [-1.0, 1.52, 0.165, 0.27], [-1.14, 1.72, 0.135, 0.215], [-1.25, 1.9, 0.115, 0.17]],
				"front": {"x": 0.17, "hip": Vector2(-0.62, 1.0), "knee": Vector2(-0.65, 0.56), "ankle": Vector2(-0.61, 0.15), "r": [0.14, 0.11, 0.068, 0.05, 0.054], "foot": "hoof", "foot_r": 0.075, "foot_dz": -0.05, "top_up": 0.25},
				"hind": {"x": 0.17, "hip": Vector2(0.7, 1.05), "knee": Vector2(0.9, 0.6), "ankle": Vector2(0.83, 0.15), "r": [Vector2(0.16, 0.22), Vector2(0.115, 0.15), 0.07, 0.05, 0.054], "foot": "hoof", "foot_r": 0.075, "foot_dz": -0.05, "bend": -1.0, "top_up": 0.3},
				"stride": 1.9, "duty": 0.64, "lift": 0.2, "bob": 0.03, "roll": 0.015, "sway": 0.015, "toe_pitch": 1.1,
				"speed": 1.6, "turn": 1.0, "accel": 1.6, "weight": 0.3, "half_len": 0.7, "max_yaw": 0.9, "trot_speed": 2.6,
				"neck_sim": {"rigid": true},
				"hairtail_sim": {"stiff": 30.0, "tip": 10.0, "damp": 3.5, "yaw": Vector3(0.1, 1.6, 0.8), "walk": 0.8},
				"collider": [0.8, 1.7, 2.3, -0.2], "aabb": AABB(Vector3(-1.2, -0.3, -2.4), Vector3(2.4, 3.2, 4.2)),
			}
		"ox":
			var coat := _ox_coat(o)
			var cols := {
				"tan": [Color(0.55, 0.42, 0.29), Color(0.66, 0.56, 0.44), Color(0.46, 0.34, 0.23)],
				"white": [Color(0.74, 0.71, 0.66), Color(0.8, 0.78, 0.74), Color(0.6, 0.58, 0.54)],
				"red": [Color(0.42, 0.22, 0.12), Color(0.48, 0.3, 0.19), Color(0.36, 0.18, 0.1)],
			}
			S = {
				"tex": "thatch_roof_angled", "mat": {"scale": 2.4, "contrast": 0.5, "normal": 0.6, "rough": 0.85, "rim": 0.15},
				"col": cols.get(coat, cols.tan), "coat": coat,
				"body": [[1.02, 1.08, 0.26, 0.32], [0.72, 1.05, 0.4, 0.45], [0.1, 0.99, 0.47, 0.51], [-0.42, 0.99, 0.46, 0.53], [-0.76, 1.08 + (0.07 if o.get("hump", false) else 0.0), 0.38, 0.52 + (0.13 if o.get("hump", false) else 0.0)], [-1.0, 1.1, 0.29, 0.42]],
				"neck": [[-1.04, 1.14, 0.26, 0.38], [-1.24, 1.16, 0.215, 0.29], [-1.4, 1.17, 0.18, 0.215]],
				"tail": [[1.08, 1.25, 0.045, 0.045], [1.2, 0.95, 0.03, 0.03], [1.23, 0.65, 0.025, 0.025], [1.23, 0.4, 0.02, 0.02]],
				"front": {"x": 0.21, "hip": Vector2(-0.76, 0.86), "knee": Vector2(-0.79, 0.47), "ankle": Vector2(-0.75, 0.13), "r": [0.16, 0.125, 0.078, 0.06, 0.062], "foot": "hoof", "foot_r": 0.085, "foot_dz": -0.04, "top_up": 0.25},
				"hind": {"x": 0.21, "hip": Vector2(0.78, 0.92), "knee": Vector2(0.94, 0.52), "ankle": Vector2(0.88, 0.13), "r": [Vector2(0.17, 0.23), Vector2(0.12, 0.16), 0.078, 0.06, 0.062], "foot": "hoof", "foot_r": 0.075, "foot_dz": -0.04, "bend": -1.0, "top_up": 0.3},
				"stride": 1.6, "duty": 0.68, "lift": 0.14, "bob": 0.02, "roll": 0.02, "sway": 0.02, "toe_pitch": 0.9,
				"speed": 1.0, "turn": 0.8, "accel": 1.0, "weight": 0.3, "half_len": 0.8, "max_yaw": 0.8,
				"neck_sim": {"rigid": true},
				"tail_sim": {"stiff": 40.0, "tip": 14.0, "damp": 4.0, "yaw": Vector3(0.2, 1.8, 0.8)},
				"collider": [0.95, 1.5, 2.5, -0.2], "aabb": AABB(Vector3(-1.2, -0.3, -2.4), Vector3(2.4, 2.6, 4.2)),
			}
		"trex":
			var tail: Array = []
			for i in 9:
				var t := i / 8.0
				tail.append([lerpf(1.5, 7.8, t), 3.46 - sin(t * PI) * 0.12 - t * 0.25, lerpf(0.6, 0.05, pow(t, 0.8)), lerpf(0.8, 0.06, pow(t, 0.8))])
			S = {
				"tex": "dry_ground_01", "mat": {"scale": 0.75, "contrast": 0.9, "normal": 1.6, "rough": 1.0},
				"col": [Color(0.36, 0.31, 0.2), Color(0.64, 0.57, 0.42), Color(0.2, 0.18, 0.13)],
				"body": [[1.2, 3.45, 0.64, 0.84], [0.3, 3.38, 0.9, 1.16], [-0.8, 3.3, 0.98, 1.3], [-1.9, 3.38, 0.9, 1.16], [-2.8, 3.58, 0.68, 0.9]],
				"neck": [[-3.1, 3.82, 0.56, 0.74], [-3.5, 4.1, 0.52, 0.66], [-3.82, 4.32, 0.5, 0.6], [-4.05, 4.46, 0.48, 0.56]],
				"tail": tail, "sides": 18,
				"hind": {"x": 0.62, "hip": Vector2(0.25, 3.2), "knee": Vector2(-0.8, 2.25), "ankle": Vector2(0.4, 1.22), "r": [Vector2(0.46, 0.8), Vector2(0.44, 0.7), Vector2(0.38, 0.54), Vector2(0.32, 0.46), Vector2(0.26, 0.35)], "foot": "theropod", "foot_r": 0.24, "foot_dz": -0.62, "toe_len": 0.95, "top_up": 0.25},
				"stride": 5.6, "duty": 0.62, "lift": 0.75, "bob": 0.09, "roll": 0.03, "sway": 0.16, "toe_pitch": 0.9,
				"speed": 2.4, "turn": 0.55, "accel": 1.2, "weight": 1.0, "half_len": 2.0, "max_yaw": 1.0, "head_share": 0.5, "hears": true,
				"neck_sim": {"stiff": 70.0, "tip": 50.0, "damp": 7.0},
				"tail_sim": {"stiff": 30.0, "tip": 10.0, "damp": 3.5, "yaw": Vector3(0.03, 0.6, 0.6), "walk": 2.2},
				"collider": [1.7, 4.2, 5.6, -0.8], "aabb": AABB(Vector3(-3, -0.5, -7), Vector3(6, 6.5, 15.5)), "threat": true,
			}
	S["kind"] = kind
	return S


# ---------------------------------------------------------------------- feet
static func foot(cm: CreatureMesh, L: Dictionary, ankle: Vector3, sole: Vector3, sgn: float, b: int, S: Dictionary) -> void:
	var fr: float = L.get("foot_r", 0.2)
	var col: Array = S.col
	match String(L.get("foot", "pad")):
		"pad":
			cm.shade(col[0], col[1], col[0])
			cm.loft([ankle.lerp(sole, 0.3), ankle.lerp(sole, 0.75), sole + Vector3(0, 0.015, 0)], [fr * 0.88, fr, fr * 1.04], b, 10, Vector3.BACK)
			cm.paint(IVORY.darkened(0.25), 0.5, 0.7)
			for a: float in [-0.75, -0.25, 0.25, 0.75]:
				cm.ellipsoid(Vector3(fr * 0.21, fr * 0.2, fr * 0.13), sole + Vector3(sin(a) * fr * 0.92, fr * 0.2, -cos(a) * fr * 0.98), b, 1)
		"hoof":
			cm.paint(Color(0.1, 0.085, 0.07), 0.4, 0.5)
			cm.loft([ankle.lerp(sole, 0.45), sole + Vector3(0, 0.04, -0.01), sole], [fr * 0.72, fr, fr * 1.06], b, 8, Vector3.BACK)
		"paw":
			cm.shade(col[0].darkened(0.15), col[1], col[0].darkened(0.15))
			cm.ellipsoid(Vector3(fr, fr * 0.6, fr * 1.45), sole + Vector3(0, fr * 0.55, -fr * 0.4), b)
			cm.paint(Color(0.16, 0.13, 0.1), 0.2, 0.45)
			for k in 4:
				var cx := (k - 1.5) * fr * 0.48
				var c0 := sole + Vector3(cx, fr * 0.5, -fr * 1.6)
				cm.horn([c0, c0 + Vector3(0, -0.01, -fr * 0.4), c0 + Vector3(0, -fr * 0.4, -fr * 0.7)], fr * 0.14, b, 5)
		"theropod":
			var ball := sole + Vector3(0, fr * 0.95, 0.08)
			cm.shade(col[0], col[1], col[0])
			var r4: Vector2 = L.r[4]
			cm.loft([ankle + Vector3(0, 0.1, 0), ankle.lerp(ball, 0.5), ball], [r4 * 0.92, r4 * 0.96, Vector2(fr * 1.2, fr * 1.2)], b, 10, Vector3.BACK)
			var tl: float = L.get("toe_len", 0.8)
			for a: float in [-0.5, 0.0, 0.5]:
				var dir := Vector3(sin(a + sgn * 0.08), 0, -cos(a))
				var tip := ball + dir * tl * (1.0 if a == 0.0 else 0.82) + Vector3(0, -fr * 0.55, 0)
				cm.shade(col[0], col[1], col[0])
				cm.loft([ball - dir * 0.1, ball.lerp(tip, 0.5) + Vector3(0, 0.03, 0), tip], [fr * 0.95, fr * 0.72, fr * 0.55], b, 7)
				cm.paint(HORN, 0.2, 0.4)
				cm.horn([tip - dir * 0.06, tip + dir * 0.16 + Vector3(0, 0.02, 0), tip + dir * 0.3 + Vector3(0, -fr * 0.42, 0)], fr * 0.48, b, 6)
			var back := ball + Vector3(-sgn * 0.12, 0.12, 0.3)
			cm.paint(HORN, 0.2, 0.4)
			cm.horn([ball + Vector3(0, 0.1, 0.1), back, back + Vector3(0, -0.14, 0.12)], fr * 0.4, b, 5)


# ------------------------------------------------------------------- helpers
## Body section at z -> Vector3(y, half_width, half_height), interpolated the same
## way as the lofted surface (Catmull-Rom through the stations).
static func body_at(S: Dictionary, z: float) -> Vector3:
	var st: Array = S.body
	var n := st.size()
	if z >= st[0][0]:
		return Vector3(st[0][1], st[0][2], st[0][3])
	for i in n - 1:
		var a: Array = st[i]
		var b: Array = st[i + 1]
		if z <= a[0] and z >= b[0]:
			var t: float = (a[0] - z) / maxf(a[0] - b[0], 0.0001)
			var p0: Array = st[maxi(i - 1, 0)]
			var p3: Array = st[mini(i + 2, n - 1)]
			var v1 := Vector3(a[1], a[2], a[3])
			var v2 := Vector3(b[1], b[2], b[3])
			var c := v1.cubic_interpolate(v2, Vector3(p0[1], p0[2], p0[3]), Vector3(p3[1], p3[2], p3[3]), t)
			var lin := v1.lerp(v2, t)
			return Vector3(c.x, maxf(c.y, lin.y), maxf(c.z, lin.z))
	var l: Array = st[n - 1]
	return Vector3(l[1], l[2], l[3])


static func eyes(cm: CreatureMesh, b: int, at: Vector3, dx: float, r: float) -> void:
	cm.paint(EYE, 0.0, 0.12)
	for sgn: float in [-1.0, 1.0]:
		cm.ellipsoid(Vector3(r * 0.7, r, r), at + Vector3(dx * sgn, 0, 0), b, 1)


## Fringe of hanging fur along the flanks and belly.
static func shag(cm: CreatureMesh, S: Dictionary, b: int, z0: float, z1: float, n: int, angles: Array, length: float, radius: float, seed_i := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	for row in angles.size():
		var ang: float = angles[row]
		for i in n:
			var z := lerpf(z0, z1, (i + rng.randf() * 0.7) / n)
			var sec := body_at(S, z)
			for sgn: float in [-1.0, 1.0]:
				var at := Vector3(cos(ang) * sec.y * sgn, sec.x - sin(ang) * sec.z, z)
				var dir := Vector3(sgn * 0.12 * cos(ang), -1.0, rng.randf_range(-0.12, 0.12)).normalized()
				cm.tuft(at - dir * radius * 0.4, dir, length * rng.randf_range(0.7, 1.15), radius * rng.randf_range(0.8, 1.2), b)


## Curtain of hair hanging from the flank at `ang` radians below horizontal, with a
## ragged hem of long and short locks. Two-sided sheet, both flanks.
static func fringe(cm: CreatureMesh, S: Dictionary, b: int, z0: float, z1: float, ang: float, length: float, n: int, flare := 0.05, seed_i := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for sgn: float in [-1.0, 1.0]:
		var base := verts.size()
		for i in n + 1:
			var z := lerpf(z0, z1, float(i) / n)
			var sec := body_at(S, z)
			var top := Vector3(cos(ang) * sec.y * 0.99 * sgn, sec.x - sin(ang) * sec.z * 0.99, z)
			var li := length * (rng.randf_range(0.75, 1.15) if i % 2 == 0 else rng.randf_range(0.3, 0.7))
			verts.append(top)
			verts.append(top + Vector3(sgn * (flare + cos(ang) * 0.06), -li, rng.randf_range(-0.04, 0.04)))
		for i in n:
			var a := base + i * 2
			idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var bones: Array = []
	for _i in verts.size():
		bones.append(b)
	cm.sheet(verts, idx, bones)


## Cloth laid over the back between z0 and z1, hanging to hem_y. Two-sided.
static func drape(cm: CreatureMesh, S: Dictionary, b: int, z0: float, z1: float, hem_y: float, inflate := 0.03, arc := 1.75, nz := 8, min_hx := 0.0) -> void:
	var na := 9
	var cols := na + 2
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for iz in nz + 1:
		var z := lerpf(z0, z1, float(iz) / nz)
		var sec := body_at(S, z)
		var hx := maxf(sin(arc) * (sec.y + inflate) * 1.04, min_hx) + sin(iz * 1.9) * 0.02
		verts.append(Vector3(-hx, hem_y + sin(iz * 2.3) * 0.015, z))
		for ia in na:
			var th := lerpf(-arc, arc, float(ia) / (na - 1))
			verts.append(Vector3(sin(th) * (sec.y + inflate), sec.x + cos(th) * (sec.z + inflate), z))
		verts.append(Vector3(hx, hem_y + sin(iz * 2.3 + 1.0) * 0.015, z))
	for iz in nz:
		for ic in cols - 1:
			var a := iz * cols + ic
			idx.append_array([a, a + 1, a + cols + 1, a, a + cols + 1, a + cols])
	var bones: Array = []
	for _i in verts.size():
		bones.append(b)
	cm.sheet(verts, idx, bones)


static func _trunk(cm: CreatureMesh, rig: Dictionary, ho: Vector3, y_tip: float, r0: float) -> void:
	var st: Array = []
	var n := 8
	var top := ho + Vector3(0, -0.3, -0.6)
	for i in n:
		var t := float(i) / (n - 1)
		var y := lerpf(top.y, y_tip, t)
		var z := top.z - sin(t * PI * 0.8) * 0.26 + t * 0.12
		st.append([Vector3(0, y, z), lerpf(r0, r0 * 0.36, pow(t, 0.85))])
	CreatureWalker.add_chain(cm, rig, "trunk", st, rig.head, "head", 10, 2)


# -------------------------------------------------------------------- detail
static func detail(cm: CreatureMesh, rig: Dictionary, S: Dictionary, o: Dictionary) -> void:
	match String(S.kind):
		"mammoth": _mammoth(cm, rig, S)
		"elephant": _elephant(cm, rig, S, o)
		"woolly_rhino": _rhino(cm, rig, S)
		"cave_bear": _bear(cm, rig, S)
		"sauropod": _sauropod(cm, rig, S)
		"horse": _horse(cm, rig, S, o)
		"ox": _ox(cm, rig, S, o)
		"trex": _trex(cm, rig, S)


static func _mammoth(cm: CreatureMesh, rig: Dictionary, S: Dictionary) -> void:
	var ho: Vector3 = rig.head_origin
	var hb: int = rig.head
	var bb: int = rig.body
	var col: Array = S.col
	# high domed skull with a top-knot, cheeks running into the trunk
	cm.ellipsoid(Vector3(0.5, 0.64, 0.56), ho + Vector3(0, 0.2, -0.18), hb)
	cm.ellipsoid(Vector3(0.32, 0.26, 0.32), ho + Vector3(0, 0.76, -0.12), hb)
	cm.ellipsoid(Vector3(0.4, 0.46, 0.4), ho + Vector3(0, -0.22, -0.42), hb)
	for sgn: float in [-1.0, 1.0]:
		cm.ellipsoid(Vector3(0.06, 0.24, 0.17), Transform3D(Basis(Vector3.UP, -0.5 * sgn), ho + Vector3(0.5 * sgn, 0.12, 0.04)), hb, 1)
		cm.ellipsoid(Vector3(0.36, 0.62, 0.52), Vector3(0.6 * sgn, 1.95, -1.0), bb)
		cm.ellipsoid(Vector3(0.36, 0.6, 0.52), Vector3(0.56 * sgn, 1.7, 1.22), bb)
	_trunk(cm, rig, ho, 0.28, 0.25)
	cm.paint(IVORY, 0.25, 0.5)
	for sgn: float in [-1.0, 1.0]:
		cm.horn([ho + Vector3(0.3 * sgn, -0.4, -0.5), ho + Vector3(0.42 * sgn, -1.1, -0.85), ho + Vector3(0.6 * sgn, -1.5, -1.45),
			ho + Vector3(0.68 * sgn, -1.46, -2.05), ho + Vector3(0.52 * sgn, -1.05, -2.5), ho + Vector3(0.28 * sgn, -0.55, -2.7)], 0.115, hb, 9, 0.028)
	eyes(cm, hb, ho + Vector3(0, 0.05, -0.56), 0.36, 0.045)
	# shaggy coat: three overlapping curtains down each flank, belly fringe, leg skirts
	cm.shade(col[0].darkened(0.12), col[1], col[0])
	fringe(cm, S, bb, 1.7, -1.45, 0.2, 0.75, 64, 0.07, 3)
	cm.shade(col[0], col[1], col[0])
	fringe(cm, S, bb, 1.65, -1.4, 0.62, 0.8, 58, 0.04, 4)
	cm.shade(col[1].lerp(col[0], 0.5), col[1], col[1])
	fringe(cm, S, bb, 1.55, -1.35, 1.08, 0.66, 50, 0.0, 5)
	for sgn: float in [-1.0, 1.0]:
		for k in 6:
			var a := k * 1.05
			cm.tuft(Vector3(0.52 * sgn + cos(a) * 0.3, 1.5, -1.05 + sin(a) * 0.3), Vector3.DOWN, 0.5, 0.13, bb)
			cm.tuft(Vector3(0.5 * sgn + cos(a) * 0.3, 1.3, 1.2 + sin(a) * 0.3), Vector3.DOWN, 0.45, 0.13, bb)
		cm.tuft(ho + Vector3(0.3 * sgn, -0.45, -0.2), Vector3.DOWN, 0.5, 0.13, hb)
	cm.tuft(ho + Vector3(0, 0.9, -0.14), Vector3(0, -0.3, -1).normalized(), 0.36, 0.17, hb)
	cm.tuft(Vector3(0, 1.45, 2.12), Vector3.DOWN, 0.4, 0.08, rig.tail_b[rig.tail_b.size() - 1])


static func _elephant(cm: CreatureMesh, rig: Dictionary, S: Dictionary, o: Dictionary) -> void:
	var ho: Vector3 = rig.head_origin
	var hb: int = rig.head
	var bb: int = rig.body
	var col: Array = S.col
	cm.ellipsoid(Vector3(0.46, 0.52, 0.5), ho + Vector3(0, 0.1, -0.16), hb)
	cm.ellipsoid(Vector3(0.36, 0.42, 0.38), ho + Vector3(0, -0.24, -0.4), hb)
	for sgn: float in [-1.0, 1.0]:
		cm.ellipsoid(Vector3(0.2, 0.15, 0.24), ho + Vector3(0.12 * sgn, 0.47, -0.16), hb)
		cm.ellipsoid(Vector3(0.3, 0.52, 0.44), Vector3(0.5 * sgn, 1.7, -0.95), bb)
		cm.ellipsoid(Vector3(0.3, 0.5, 0.44), Vector3(0.48 * sgn, 1.52, 1.1), bb)
		# ear: a flap hinged along its front edge
		var eo := ho + Vector3(0.43 * sgn, 0.15, -0.02)
		var eb := cm.bone("ear%s" % ("L" if sgn < 0.0 else "R"), eo)
		cm.shade(col[0], col[1].lerp(Color(0.5, 0.36, 0.33), 0.4), col[0])
		cm.ellipsoid(Vector3(0.05, 0.5, 0.42), Transform3D(Basis(Vector3.UP, -0.42 * sgn) * Basis(Vector3.RIGHT, 0.15), eo + Vector3(0.14 * sgn, -0.14, 0.34)), eb)
		rig.ears.append([eb, eo, sgn])
		cm.shade(col[0], col[1], col[2])
	_trunk(cm, rig, ho, 0.2, 0.22)
	cm.paint(IVORY, 0.25, 0.5)
	for sgn: float in [-1.0, 1.0]:
		cm.horn([ho + Vector3(0.24 * sgn, -0.42, -0.5), ho + Vector3(0.32 * sgn, -0.85, -0.82), ho + Vector3(0.38 * sgn, -1.0, -1.25), ho + Vector3(0.34 * sgn, -0.9, -1.6)], 0.075, hb, 8, 0.02)
	eyes(cm, hb, ho + Vector3(0, 0.0, -0.52), 0.33, 0.04)
	cm.shade(col[2].darkened(0.3), null, null)
	cm.tuft(Vector3(0, 0.95, 1.94), Vector3.DOWN, 0.4, 0.07, rig.tail_b[rig.tail_b.size() - 1])
	rig.seat = Vector3(0, 2.86, -1.2)
	if o.get("howdah", false):
		var cloth: Color = o.get("cloth", Color(0.5, 0.09, 0.08))
		var trim: Color = o.get("trim", Color(0.78, 0.58, 0.2))
		cm.surface("gear")
		cm.paint(cloth, 1.0, 1.0)
		drape(cm, S, bb, 1.22, -1.05, 1.15, 0.07, 1.8, 10, 1.0)
		cm.paint(trim, 1.0, 0.8)
		drape(cm, S, bb, 1.3, 1.19, 1.08, 0.085, 1.8, 1, 1.02)
		drape(cm, S, bb, -1.02, -1.13, 1.08, 0.085, 1.8, 1, 1.02)
		# howdah: timber platform with rails, pole and pennant
		var top := 2.9
		cm.paint(Color(0.36, 0.24, 0.14), 1.0, 0.9)
		cm.box(Vector3(1.5, 0.14, 1.7), Vector3(0, top + 0.05, 0.1), bb)
		for sx: float in [-0.7, 0.7]:
			for sz: float in [-0.7, 0.9]:
				cm.box(Vector3(0.08, 0.6, 0.08), Vector3(sx, top + 0.4, sz), bb)
			cm.box(Vector3(0.06, 0.07, 1.68), Vector3(sx, top + 0.68, 0.1), bb)
			cm.box(Vector3(0.05, 0.3, 1.6), Vector3(sx, top + 0.3, 0.1), bb)
		for sz: float in [-0.7, 0.9]:
			cm.box(Vector3(1.4, 0.07, 0.06), Vector3(0, top + 0.68, sz), bb)
			cm.box(Vector3(1.4, 0.3, 0.05), Vector3(0, top + 0.3, sz), bb)
		cm.box(Vector3(0.05, 2.2, 0.05), Vector3(0.66, top + 1.5, 0.92), bb)
		cm.paint(cloth.lerp(trim, 0.15), 1.0, 1.0)
		var fx := 0.66
		var fy := top + 2.5
		cm.sheet(PackedVector3Array([Vector3(fx, fy, 0.95), Vector3(fx, fy - 0.6, 0.95), Vector3(fx + 0.04, fy - 0.2, 1.6), Vector3(fx - 0.05, fy - 0.36, 2.15)]),
			PackedInt32Array([0, 1, 2, 1, 3, 2]), [bb, bb, bb, bb])
		rig.seat = Vector3(0, top + 0.12, 0.2)
		cm.surface("hide")


static func _rhino(cm: CreatureMesh, rig: Dictionary, S: Dictionary) -> void:
	var ho: Vector3 = rig.head_origin
	var hb: int = rig.head
	var bb: int = rig.body
	var col: Array = S.col
	# long, deep head carried low; wide square lip
	cm.loft([ho + Vector3(0, 0.03, 0.14), ho + Vector3(0, -0.03, -0.22), ho + Vector3(0, -0.1, -0.52), ho + Vector3(0, -0.17, -0.8), ho + Vector3(0, -0.2, -0.92)],
		[Vector2(0.33, 0.36), Vector2(0.29, 0.32), Vector2(0.22, 0.25), Vector2(0.2, 0.2), Vector2(0.14, 0.12)], hb, 12)
	for sgn: float in [-1.0, 1.0]:
		cm.loft([ho + Vector3(0.22 * sgn, 0.26, 0.08), ho + Vector3(0.27 * sgn, 0.46, 0.12), ho + Vector3(0.29 * sgn, 0.58, 0.14)], [Vector2(0.075, 0.045), Vector2(0.07, 0.04), 0.01], hb, 6, Vector3.BACK)
		cm.ellipsoid(Vector3(0.27, 0.46, 0.38), Vector3(0.48 * sgn, 1.24, -0.84), bb)
		cm.ellipsoid(Vector3(0.29, 0.46, 0.4), Vector3(0.46 * sgn, 1.18, 0.88), bb)
	cm.paint(Color(0.24, 0.2, 0.16), 0.6, 0.6)
	cm.horn([ho + Vector3(0, -0.06, -0.78), ho + Vector3(0, 0.24, -0.93), ho + Vector3(0, 0.58, -0.98), ho + Vector3(0, 0.9, -0.9)], 0.135, hb, 9, 0.02)
	cm.horn([ho + Vector3(0, 0.06, -0.45), ho + Vector3(0, 0.24, -0.49), ho + Vector3(0, 0.36, -0.49)], 0.1, hb, 8, 0.02)
	eyes(cm, hb, ho + Vector3(0, 0.02, -0.36), 0.265, 0.03)
	cm.shade(col[0].darkened(0.1), col[1], col[0])
	fringe(cm, S, bb, 1.3, -1.25, 0.4, 0.34, 56, 0.05, 5)
	cm.shade(col[1].lerp(col[0], 0.5), col[1], col[1])
	fringe(cm, S, bb, 1.25, -1.2, 1.0, 0.3, 48, 0.0, 6)
	cm.tuft(ho + Vector3(0, -0.34, -0.1), Vector3.DOWN, 0.26, 0.14, hb)


static func _bear(cm: CreatureMesh, rig: Dictionary, S: Dictionary) -> void:
	var ho: Vector3 = rig.head_origin
	var hb: int = rig.head
	var bb: int = rig.body
	var col: Array = S.col
	cm.ellipsoid(Vector3(0.29, 0.27, 0.31), ho + Vector3(0, 0.05, -0.12), hb)
	cm.shade(col[0].lerp(Color(0.5, 0.38, 0.24), 0.5), null, null)
	cm.loft([ho + Vector3(0, 0.02, -0.28), ho + Vector3(0, -0.02, -0.5), ho + Vector3(0, -0.04, -0.66)], [Vector2(0.17, 0.14), Vector2(0.13, 0.1), Vector2(0.1, 0.075)], hb, 10)
	var jo := ho + Vector3(0, -0.08, -0.2)
	var jb := cm.bone("jaw", jo)
	rig.jaw = jb
	rig.jaw_origin = jo
	cm.loft([jo + Vector3(0, -0.02, 0.0), jo + Vector3(0, -0.06, -0.26), jo + Vector3(0, -0.05, -0.43)], [Vector2(0.15, 0.07), Vector2(0.11, 0.055), Vector2(0.08, 0.04)], jb, 8)
	cm.paint(Color(0.05, 0.04, 0.04), 0.1, 0.3)
	cm.ellipsoid(Vector3(0.055, 0.04, 0.04), ho + Vector3(0, 0.0, -0.69), hb, 1)
	cm.shade(col[0], col[1], col[2])
	for sgn: float in [-1.0, 1.0]:
		cm.ellipsoid(Vector3(0.085, 0.09, 0.04), ho + Vector3(0.2 * sgn, 0.27, -0.04), hb, 1)
		cm.ellipsoid(Vector3(0.24, 0.38, 0.3), Vector3(0.42 * sgn, 0.95, -0.72), bb)
		cm.ellipsoid(Vector3(0.26, 0.4, 0.34), Vector3(0.4 * sgn, 0.9, 0.76), bb)
	eyes(cm, hb, ho + Vector3(0, 0.1, -0.37), 0.125, 0.026)
	cm.paint(IVORY, 0.1, 0.5)
	for sgn: float in [-1.0, 1.0]:
		cm.horn([ho + Vector3(0.06 * sgn, -0.06, -0.62), ho + Vector3(0.06 * sgn, -0.16, -0.62)], 0.022, hb, 5)
		cm.horn([jo + Vector3(0.05 * sgn, -0.02, -0.4), jo + Vector3(0.05 * sgn, 0.06, -0.4)], 0.02, jb, 5)
	cm.shade(col[1], col[1], col[1])
	fringe(cm, S, bb, 1.0, -0.9, 0.95, 0.2, 44, 0.0, 4)
	cm.tuft(ho + Vector3(0, -0.2, 0.1), Vector3.DOWN, 0.22, 0.2, bb)


static func _sauropod(cm: CreatureMesh, rig: Dictionary, S: Dictionary) -> void:
	var ho: Vector3 = rig.head_origin
	var hb: int = rig.head
	var bb: int = rig.body
	cm.loft([ho + Vector3(0, 0.02, 0.2), ho + Vector3(0, 0.04, -0.2), ho + Vector3(0, -0.02, -0.62), ho + Vector3(0, -0.1, -0.98), ho + Vector3(0, -0.14, -1.12)],
		[Vector2(0.28, 0.27), Vector2(0.33, 0.29), Vector2(0.31, 0.22), Vector2(0.25, 0.15), Vector2(0.14, 0.08)], hb, 12)
	cm.ellipsoid(Vector3(0.12, 0.1, 0.2), ho + Vector3(0, 0.26, -0.36), hb, 1)
	for sgn: float in [-1.0, 1.0]:
		cm.ellipsoid(Vector3(0.62, 1.2, 1.0), Vector3(1.0 * sgn, 3.5, 2.05), bb)
		cm.ellipsoid(Vector3(0.52, 1.1, 0.85), Vector3(0.98 * sgn, 3.5, -1.9), bb)
	eyes(cm, hb, ho + Vector3(0, 0.1, -0.3), 0.29, 0.05)


static func _horse(cm: CreatureMesh, rig: Dictionary, S: Dictionary, o: Dictionary) -> void:
	var ho: Vector3 = rig.head_origin
	var hb: int = rig.head
	var bb: int = rig.body
	var coat: String = S.coat
	var hair := Color(0.05, 0.045, 0.04)
	if coat == "chestnut":
		hair = Color(0.4, 0.2, 0.09)
	elif coat == "grey":
		hair = Color(0.8, 0.78, 0.74)
	# head hangs from the poll at about 50 degrees: deep jowl, straight profile, soft muzzle
	cm.loft([ho + Vector3(0, 0.07, 0.07), ho + Vector3(0, -0.08, -0.1), ho + Vector3(0, -0.28, -0.25), ho + Vector3(0, -0.45, -0.38), ho + Vector3(0, -0.53, -0.44)],
		[Vector2(0.1, 0.12), Vector2(0.105, 0.155), Vector2(0.088, 0.12), Vector2(0.076, 0.092), Vector2(0.066, 0.07)], hb, 10)
	cm.ellipsoid(Vector3(0.095, 0.13, 0.1), ho + Vector3(0, -0.2, -0.06), hb, 1)
	for sgn: float in [-1.0, 1.0]:
		cm.loft([ho + Vector3(0.06 * sgn, 0.1, 0.04), ho + Vector3(0.075 * sgn, 0.2, 0.02), ho + Vector3(0.08 * sgn, 0.27, 0.0)], [Vector2(0.035, 0.02), Vector2(0.03, 0.018), 0.006], hb, 6, Vector3.BACK)
		cm.ellipsoid(Vector3(0.12, 0.27, 0.24), Vector3(0.2 * sgn, 1.12, -0.6), bb)
		cm.ellipsoid(Vector3(0.13, 0.31, 0.3), Vector3(0.19 * sgn, 1.18, 0.66), bb)
	eyes(cm, hb, ho + Vector3(0, -0.07, -0.13), 0.098, 0.022)
	cm.paint(Color(0.07, 0.06, 0.055), 0.2, 0.5)
	cm.ellipsoid(Vector3(0.06, 0.05, 0.04), ho + Vector3(0, -0.54, -0.45), hb, 1)
	# mane along the crest, forelock, hair tail
	cm.shade(hair, null, null, 1.0, 0.85)
	var nb: Array = rig.neck_b
	var neck: Array = S.neck
	var mp: Array = []
	var mr: Array = []
	var ms: Array = []
	var crest := Vector3(0, 0.6, 0.8)
	for i in neck.size():
		var st: Array = neck[i]
		mp.append(Vector3(0, st[1], st[0]) + crest * (float(st[3]) - 0.01))
		mr.append(Vector2(0.03, 0.075))
		ms.append(CreatureMesh.chain_weight(nb, bb, hb, float(i)))
	mp.append(ho + Vector3(0, 0.16, 0.0))
	mr.append(Vector2(0.025, 0.04))
	ms.append(hb)
	cm.loft(mp, mr, ms, 6, crest)
	cm.tuft(ho + Vector3(0, 0.15, -0.03), Vector3(0, -0.75, -0.65).normalized(), 0.2, 0.05, hb)
	CreatureWalker.add_chain(cm, rig, "hairtail", [[Vector3(0, 1.38, 0.98), 0.05], [Vector3(0, 1.32, 1.14), 0.085], [Vector3(0, 1.02, 1.24), 0.1],
		[Vector3(0, 0.72, 1.26), 0.09], [Vector3(0, 0.44, 1.25), 0.04]], bb, "body", 8, 2)
	rig.seat = Vector3(0, 1.5, -0.12)
	var saddle: bool = o.get("saddle", false) or o.get("caparison", false)
	if saddle:
		var cloth: Color = o.get("cloth", Color(0.5, 0.09, 0.08))
		var trim: Color = o.get("trim", Color(0.82, 0.7, 0.3))
		cm.surface("gear")
		if o.get("caparison", false):
			cm.paint(cloth, 1.0, 1.0)
			drape(cm, S, bb, 0.98, -0.84, 0.62, 0.045, 1.9, 9, 0.4)
			cm.paint(trim, 1.0, 0.85)
			drape(cm, S, bb, 1.03, 0.97, 0.58, 0.055, 1.9, 1, 0.41)
			drape(cm, S, bb, -0.83, -0.89, 0.58, 0.055, 1.9, 1, 0.41)
			# chest panel
			cm.paint(cloth, 1.0, 1.0)
			cm.sheet(PackedVector3Array([Vector3(-0.4, 1.42, -0.86), Vector3(0.4, 1.42, -0.86), Vector3(-0.42, 0.62, -0.9), Vector3(0.42, 0.62, -0.9), Vector3(0, 1.0, -1.04)]),
				PackedInt32Array([0, 4, 1, 0, 2, 4, 2, 3, 4, 3, 1, 4]), [bb, bb, bb, bb, bb])
		else:
			cm.paint(cloth, 1.0, 1.0)
			drape(cm, S, bb, 0.36, -0.42, 0.92, 0.03, 1.7, 4)
		# saddle: seat, pommel, cantle, girth, stirrups
		cm.paint(Color(0.3, 0.17, 0.09), 1.0, 0.7)
		cm.ellipsoid(Vector3(0.24, 0.07, 0.3), Vector3(0, 1.52, -0.1), bb)
		cm.ellipsoid(Vector3(0.16, 0.13, 0.06), Vector3(0, 1.58, -0.4), bb, 1)
		cm.ellipsoid(Vector3(0.2, 0.15, 0.06), Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 1.6, 0.2)), bb, 1)
		for sgn: float in [-1.0, 1.0]:
			cm.box(Vector3(0.015, 0.5, 0.03), Vector3(0.42 * sgn, 1.02, -0.2), bb)
			cm.box(Vector3(0.05, 0.03, 0.12), Vector3(0.43 * sgn, 0.76, -0.2), bb)
		# bridle: noseband, cheek straps, reins to the saddle
		cm.paint(Color(0.2, 0.12, 0.07), 1.0, 0.7)
		cm.loft([ho + Vector3(0.095, -0.38, -0.31), ho + Vector3(0, -0.31, -0.37), ho + Vector3(-0.095, -0.38, -0.31), ho + Vector3(0, -0.46, -0.26), ho + Vector3(0.095, -0.38, -0.31)], [0.012], hb, 4)
		for sgn: float in [-1.0, 1.0]:
			cm.loft([ho + Vector3(0.095 * sgn, -0.38, -0.31), ho + Vector3(0.11 * sgn, -0.1, -0.06), ho + Vector3(0.06 * sgn, 0.1, 0.06)], [0.01], hb, 4)
		cm.surface("hide")


static func _ox(cm: CreatureMesh, rig: Dictionary, S: Dictionary, _o: Dictionary) -> void:
	var ho: Vector3 = rig.head_origin
	var hb: int = rig.head
	var bb: int = rig.body
	var col: Array = S.col
	# broad forehead, head carried low
	cm.loft([ho + Vector3(0, 0.05, 0.1), ho + Vector3(0, -0.05, -0.12), ho + Vector3(0, -0.24, -0.32), ho + Vector3(0, -0.38, -0.44), ho + Vector3(0, -0.43, -0.49)],
		[Vector2(0.16, 0.17), Vector2(0.16, 0.18), Vector2(0.13, 0.135), Vector2(0.115, 0.1), Vector2(0.09, 0.07)], hb, 10)
	# dewlap: thin fold of skin under the neck and brisket
	cm.loft([Vector3(0, 0.72, -0.72), Vector3(0, 0.66, -0.95), Vector3(0, 0.78, -1.2), Vector3(0, 0.95, -1.36)], [Vector2(0.06, 0.12), Vector2(0.05, 0.16), Vector2(0.045, 0.14), Vector2(0.03, 0.06)], bb, 6)
	for sgn: float in [-1.0, 1.0]:
		cm.ellipsoid(Vector3(0.11, 0.05, 0.055), Transform3D(Basis(Vector3.BACK, 0.25 * sgn), ho + Vector3(0.21 * sgn, 0.02, 0.06)), hb, 1)
		cm.ellipsoid(Vector3(0.15, 0.27, 0.24), Vector3(0.26 * sgn, 0.98, -0.72), bb)
		cm.ellipsoid(Vector3(0.17, 0.3, 0.28), Vector3(0.24 * sgn, 1.02, 0.74), bb)
	cm.paint(Color(0.62, 0.58, 0.48), 0.4, 0.55)
	for sgn: float in [-1.0, 1.0]:
		cm.horn([ho + Vector3(0.1 * sgn, 0.12, 0.04), ho + Vector3(0.3 * sgn, 0.18, 0.02), ho + Vector3(0.42 * sgn, 0.34, -0.04), ho + Vector3(0.4 * sgn, 0.52, -0.1)], 0.045, hb, 7, 0.01)
	eyes(cm, hb, ho + Vector3(0, -0.03, -0.17), 0.14, 0.024)
	cm.paint(Color(0.12, 0.1, 0.09), 0.3, 0.5)
	cm.ellipsoid(Vector3(0.075, 0.055, 0.04), ho + Vector3(0, -0.43, -0.5), hb, 1)
	cm.shade(col[2].darkened(0.5), null, null)
	cm.tuft(Vector3(0, 0.45, 1.23), Vector3.DOWN, 0.28, 0.055, rig.tail_b[rig.tail_b.size() - 1])
	rig.seat = Vector3(0, 1.5, -0.1)


static func _trex(cm: CreatureMesh, rig: Dictionary, S: Dictionary) -> void:
	var ho: Vector3 = rig.head_origin
	var hb: int = rig.head
	var bb: int = rig.body
	var col: Array = S.col
	var k := 1.28                      # head scale
	# skull: deep at the back, narrowing to a blunt snout
	cm.loft([ho + Vector3(0, 0.02, 0.3) * k, ho + Vector3(0, 0.08, -0.15) * k, ho + Vector3(0, 0.06, -0.6) * k, ho + Vector3(0, -0.02, -1.05) * k, ho + Vector3(0, -0.08, -1.45) * k, ho + Vector3(0, -0.12, -1.6) * k],
		[Vector2(0.4, 0.42) * k, Vector2(0.44, 0.44) * k, Vector2(0.4, 0.38) * k, Vector2(0.3, 0.3) * k, Vector2(0.25, 0.22) * k, Vector2(0.17, 0.13) * k], hb, 14)
	for sgn: float in [-1.0, 1.0]:
		cm.ellipsoid(Vector3(0.09, 0.07, 0.3) * k, ho + Vector3(0.29 * sgn, 0.37, -0.42) * k, hb, 1)
		cm.ellipsoid(Vector3(0.2, 0.26, 0.26) * k, ho + Vector3(0.3 * sgn, -0.05, -0.08) * k, hb, 1)
	var jo := ho + Vector3(0, -0.18, 0.0) * k
	var jb := cm.bone("jaw", jo)
	rig.jaw = jb
	rig.jaw_origin = jo
	cm.shade(col[0].lerp(col[1], 0.5), col[1], col[0])
	cm.loft([jo + Vector3(0, -0.06, 0.12) * k, jo + Vector3(0, -0.2, -0.4) * k, jo + Vector3(0, -0.2, -1.0) * k, jo + Vector3(0, -0.14, -1.46) * k],
		[Vector2(0.38, 0.16) * k, Vector2(0.34, 0.15) * k, Vector2(0.24, 0.12) * k, Vector2(0.14, 0.07) * k], jb, 12)
	cm.paint(Color(0.32, 0.1, 0.09), 0.3, 0.35)
	cm.ellipsoid(Vector3(0.2, 0.06, 0.6) * k, jo + Vector3(0, -0.07, -0.7) * k, jb, 1)
	cm.ellipsoid(Vector3(0.24, 0.06, 0.6) * k, ho + Vector3(0, -0.2, -0.75) * k, hb, 1)
	cm.paint(IVORY, 0.1, 0.45)
	for i in 9:
		var t := i / 8.0
		var z := lerpf(-0.35, -1.5, t)
		var hw := lerpf(0.36, 0.13, pow(t, 1.4))
		var tl := (0.085 - absf(t - 0.4) * 0.05) * (0.7 + 0.6 * absf(sin(i * 2.7)))
		for sgn: float in [-1.0, 1.0]:
			var up := ho + Vector3(hw * sgn, -0.2 - t * 0.07, z) * k
			cm.horn([up + Vector3(0, 0.05, 0) * k, up + Vector3(0, -tl, 0.02) * k], 0.03 * k, hb, 5)
			if i < 8:
				var lo := jo + Vector3((hw - 0.05) * sgn, -0.08, z - 0.06) * k
				cm.horn([lo + Vector3(0, -0.04, 0) * k, lo + Vector3(0, tl * 0.7, 0.02) * k], 0.024 * k, jb, 5)
	eyes(cm, hb, ho + Vector3(0, 0.27, -0.48) * k, 0.34 * k, 0.055)
	# arms: small, two-fingered, tucked in
	for sgn: float in [-1.0, 1.0]:
		cm.shade(col[0], col[1], col[0])
		var sh := Vector3(0.62 * sgn, 2.9, -2.5)
		var el := Vector3(0.7 * sgn, 2.42, -2.4)
		var hd := Vector3(0.62 * sgn, 2.22, -2.84)
		cm.loft([sh + Vector3(-0.1 * sgn, 0.15, 0), sh, el, hd], [0.15, 0.14, 0.11, 0.075], bb, 7)
		cm.paint(HORN, 0.2, 0.4)
		for j in 2:
			var c0 := hd + Vector3((j - 0.5) * 0.09, 0, -0.02)
			cm.horn([c0, c0 + Vector3(0, -0.06, -0.15), c0 + Vector3(0, -0.22, -0.2)], 0.045, bb, 5)
	# thigh and calf muscle, carried by the leg bones
	cm.shade(col[0], col[1], col[2])
	for leg: Dictionary in rig.legs:
		var hip: Vector3 = leg.hip
		var kn: Vector3 = hip + (leg.d_up as Vector3) * float(leg.l1)
		cm.ellipsoid(Vector3(0.44, 0.95, 0.8), Transform3D(Basis(Vector3.RIGHT, -0.75), hip.lerp(kn, 0.38) + Vector3(signf(hip.x) * 0.06, 0, 0.1)), leg.b_up)
		cm.ellipsoid(Vector3(0.3, 0.62, 0.42), Transform3D(Basis(Vector3.RIGHT, 0.8), kn + (leg.d_lo as Vector3) * 0.5 + Vector3(0, 0, 0.12)), leg.b_lo)
