class_name Outfits extends RefCounted
## Humanoid presets for the people of each era: plain everyday dress based on
## what the archaeological and textual record actually shows. The seed varies
## skin tone, build, cloth colour, hair and what the person carries; odd seeds
## give a woman where the preset has one.
##
##   var h := Outfits.make("chola_devotee", 3)        # a Humanoid
##   var cfg := Outfits.cfg("medieval_peasant", 12)   # the Humanoid cfg dictionary
##   for n in Outfits.names(): ...
##
## Extra (non-Humanoid) hint in the cfg: "anim" = looping animate() mode that suits
## the person at rest ("drum", "work"); Npc.work() uses it by default.

const NAMES: Array[String] = [
	"neanderthal",
	"indus_citizen", "indus_trader", "indus_guard",
	"egypt_worker", "egypt_overseer", "egypt_guard", "egypt_priest",
	"chola_devotee", "chola_drummer", "chola_soldier", "chola_artisan", "chola_sailor",
	"medieval_peasant", "medieval_guard", "medieval_knight", "medieval_monk", "medieval_judge", "medieval_noble",
]

## Presets that have women as well as men (odd seeds).
const HAS_WOMEN: Array[String] = ["neanderthal", "indus_citizen", "indus_trader", "egypt_worker", "egypt_priest",
	"chola_devotee", "chola_artisan", "medieval_peasant", "medieval_monk", "medieval_noble"]

const SKIN := {
	"neanderthal": [Color(0.8, 0.63, 0.52), Color(0.72, 0.54, 0.42), Color(0.64, 0.47, 0.36), Color(0.85, 0.7, 0.6)],
	"indus": [Color(0.6, 0.42, 0.3), Color(0.52, 0.36, 0.25), Color(0.45, 0.3, 0.21), Color(0.68, 0.5, 0.37)],
	"egypt": [Color(0.6, 0.42, 0.3), Color(0.52, 0.35, 0.24), Color(0.68, 0.5, 0.37), Color(0.38, 0.26, 0.19)],
	"chola": [Color(0.5, 0.34, 0.23), Color(0.42, 0.28, 0.19), Color(0.35, 0.235, 0.165), Color(0.58, 0.41, 0.29)],
	"medieval": [Color(0.85, 0.69, 0.59), Color(0.79, 0.62, 0.51), Color(0.72, 0.55, 0.44), Color(0.89, 0.75, 0.67), Color(0.6, 0.44, 0.33)],
}

const BLACK_HAIR := Color(0.045, 0.038, 0.034)
const GREY_HAIR := Color(0.5, 0.49, 0.47)
const LINEN := Color(0.85, 0.82, 0.72)
const COTTON := Color(0.82, 0.76, 0.63)
const TAN := Color(0.68, 0.6, 0.46)
const MADDER := Color(0.56, 0.2, 0.15)
const INDIGO := Color(0.17, 0.23, 0.4)
const TURMERIC := Color(0.76, 0.58, 0.2)
const LEAF := Color(0.24, 0.38, 0.24)
const LEATHER := Color(0.3, 0.2, 0.13)
const GOLD := Color(0.95, 0.75, 0.35)
const STEEL := Color(0.5, 0.5, 0.53)


static func names() -> PackedStringArray:
	return PackedStringArray(NAMES)


static func culture(outfit: String) -> String:
	return outfit.get_slice("_", 0)


static func is_female(outfit: String, p_seed := 0) -> bool:
	return HAS_WOMEN.has(outfit) and (p_seed % 2 == 1)


static func make(outfit: String, p_seed := 0) -> Humanoid:
	return Humanoid.create(cfg(outfit, p_seed))


static func _d(c: Color, tex := "acg_fabric") -> Array:
	return Humanoid.dye(c, tex)


static func _pick(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi() % list.size()]


static func _vary(rng: RandomNumberGenerator, c: Color, amount := 0.06) -> Color:
	var k := 1.0 + rng.randf_range(-amount, amount)
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0))


static func cfg(outfit: String, p_seed := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(outfit) + p_seed * 7919 + 17
	var cult := culture(outfit)
	var f := is_female(outfit, p_seed)
	var skins: Array = SKIN.get(cult, SKIN.medieval)
	var c := {
		"skin": skins[((p_seed >> 1) + rng.randi() % 2) % skins.size()],
		"female": f, "face": true, "shape": true, "merge": true,
		"height": rng.randf_range(1.54, 1.64) if f else rng.randf_range(1.65, 1.77),
		"bulk": rng.randf_range(0.9, 0.99) if f else rng.randf_range(0.95, 1.08),
		"hair": BLACK_HAIR if rng.randf() > 0.14 else GREY_HAIR,
	}
	match outfit:
		"neanderthal": _neanderthal(c, rng, f)
		"indus_citizen", "indus_trader", "indus_guard": _indus(c, rng, f, outfit)
		"egypt_worker", "egypt_overseer", "egypt_guard", "egypt_priest": _egypt(c, rng, f, outfit)
		"chola_devotee", "chola_drummer", "chola_soldier", "chola_artisan", "chola_sailor": _chola(c, rng, f, outfit)
		_: _medieval(c, rng, f, outfit)
	return c


# ---------------------------------------------------------------- Pleistocene
## Hide wraps and fur, stocky build, heavy brow. Hair and skin varied: the
## genetic evidence points to a range that includes pale skin and red hair.
static func _neanderthal(c: Dictionary, rng: RandomNumberGenerator, f: bool) -> void:
	c.height = rng.randf_range(1.52, 1.58) if f else rng.randf_range(1.62, 1.68)
	c.bulk = rng.randf_range(1.1, 1.16) if f else rng.randf_range(1.18, 1.26)
	c.brow = true
	c.hair = _pick(rng, [Color(0.16, 0.1, 0.07), Color(0.26, 0.16, 0.1), Color(0.42, 0.2, 0.1), Color(0.1, 0.08, 0.06)])
	c.head = "long_hair"
	var hide: Array = _d(_vary(rng, _pick(rng, [Color(0.4, 0.27, 0.18), Color(0.33, 0.23, 0.16), Color(0.47, 0.34, 0.23)])), "fabric_leather_02")
	c.bottom = hide
	c.skirt = rng.randf_range(0.44, 0.54)
	c.skirt_flare = 0.6
	c.belt = _d(Color(0.25, 0.17, 0.11), "fabric_leather_02")
	c.shoe = Color(0.75, 0.62, 0.5)
	if not f and rng.randf() < 0.35:
		c.bare_chest = true
		c.drape = hide
	else:
		c.top = hide
		c.sleeves = "none"
	if rng.randf() < 0.7:
		c.cowl = _d(_pick(rng, [Color(0.34, 0.26, 0.19), Color(0.45, 0.38, 0.3), Color(0.24, 0.19, 0.15)]), "thatch_roof_angled")
		c.cowl_ragged = true
	if f:
		c.prop = _pick(rng, ["", "sack", "staff"])
	else:
		c.beard = true
		c.prop = _pick(rng, ["spear", "spear", ""])


# --------------------------------------------------------------- Mohenjo-daro
## c. 2500 BCE: draped cotton (undyed, madder red, indigo), a wrap over the left
## shoulder, fillet headbands and hair buns, carnelian beads, shell bangles.
static func _indus(c: Dictionary, rng: RandomNumberGenerator, f: bool, outfit: String) -> void:
	c.barefoot = true
	c.skirt_flare = 0.45
	var wrap: Array = _d(_vary(rng, _pick(rng, [COTTON, COTTON, TAN, Color(0.74, 0.66, 0.5)])))
	var robe: Array = _d(_vary(rng, _pick(rng, [COTTON, MADDER, TAN, INDIGO, Color(0.66, 0.3, 0.2)])))
	c.bottom = wrap
	if f:
		c.top = wrap
		c.sleeves = "none"
		c.skirt = rng.randf_range(0.6, 0.72)
		c.drape = robe
		c.head = _pick(rng, ["bun", "bun", "braid"])
		c.necklace = Color(0.62, 0.17, 0.1)
		c.bangles = Color(0.9, 0.88, 0.8)
		c.bangles_metal = false
	else:
		c.bare_chest = true
		c.skirt = rng.randf_range(0.5, 0.6)
		c.head = "headband"
		c.head_color = _pick(rng, [Color(0.8, 0.62, 0.25), COTTON, MADDER])
		c.short_beard = rng.randf() < 0.55
		if rng.randf() < 0.6:
			c.necklace = Color(0.62, 0.17, 0.1)
	match outfit:
		"indus_citizen":
			if not f:
				c.drape = robe
				c.drape_arm = true
		"indus_trader":
			if f:
				c.prop = _pick(rng, ["head_basket", "pot"])
			else:
				c.drape = robe
				c.drape_arm = true
				c.head = "turban"
				c.head_color = Humanoid.tint_for("rough_linen", _vary(rng, COTTON))
				c.props = [_pick(rng, ["staff", "sack"])]
		"indus_guard":
			c.skirt = 0.48
			c.belt = _d(LEATHER, "fabric_leather_02")
			c.band = _d(LEATHER, "fabric_leather_02")
			c.armband = Color(0.85, 0.5, 0.35)
			c.prop = "spear"
			c.short_beard = true


# ----------------------------------------------------------------------- Giza
## Old Kingdom: white linen kilts and bare chests for working men, linen sheath
## dresses for women, cropped hair, shaved heads or short wigs, mostly barefoot.
static func _egypt(c: Dictionary, rng: RandomNumberGenerator, f: bool, outfit: String) -> void:
	c.barefoot = true
	c.hair = BLACK_HAIR
	var linen: Array = _d(_vary(rng, LINEN, 0.05))
	c.bottom = linen
	c.skirt_flare = 0.5
	if f:
		c.top = linen
		c.sleeves = "none"
		c.skirt = rng.randf_range(0.8, 0.86)
		c.skirt_flare = 0.35
		c.head = "wig"
	else:
		c.bare_chest = true
		c.skirt = 0.44
		c.belt = _d(Color(0.78, 0.74, 0.64))
	match outfit:
		"egypt_worker":
			if f:
				c.prop = _pick(rng, ["head_basket", "", "pot"])
			else:
				c.head = _pick(rng, ["shaved", "hair", "headcloth", "hair"])
				c.head_color = LINEN
				c.skirt = rng.randf_range(0.38, 0.46)
				c.prop = _pick(rng, ["", "head_basket", "hammer", ""])
		"egypt_overseer":
			c.skirt = 0.62
			c.skirt_flare = 0.6
			c.head = "wig"
			c.collar = Color(0.2, 0.5, 0.55)
			c.prop = "staff"
		"egypt_guard":
			c.head = "hair"
			c.band = _d(LEATHER, "fabric_leather_02")
			c.prop = "spear"
			c.shield = "hide"
			c.shield_color = _pick(rng, [Color(0.72, 0.6, 0.46), Color(0.5, 0.36, 0.25), Color(0.8, 0.74, 0.64)])
		"egypt_priest":
			if f:
				c.collar = Color(0.2, 0.5, 0.55)
			else:
				c.head = "shaved"
				c.skirt = 0.8
				c.skirt_flare = 0.4
				c.band = linen
				c.prop = "scroll"


# ------------------------------------------------------------------ Thanjavur
## c. 1010 CE Tamil country: white cotton veshti with a woven border and a bare
## chest or folded upper cloth for men, a draped sari for women, hair in a knot,
## flowers in the hair, modest gold.
static func _chola(c: Dictionary, rng: RandomNumberGenerator, f: bool, outfit: String) -> void:
	c.barefoot = true
	c.hair = BLACK_HAIR if rng.randf() > 0.1 else GREY_HAIR
	c.skirt_flare = 0.42
	var white: Array = _d(_vary(rng, Color(0.86, 0.82, 0.7), 0.04))
	var border: Color = _pick(rng, [MADDER, TURMERIC, LEAF, Color(0.45, 0.14, 0.2)])
	if f:
		var sari_c: Color = _vary(rng, _pick(rng, [MADDER, TURMERIC, LEAF, INDIGO, Color(0.45, 0.14, 0.2), Color(0.8, 0.45, 0.2)]))
		c.top = _d(_pick(rng, [Color(0.3, 0.14, 0.12), Color(0.2, 0.25, 0.2), Color(0.6, 0.48, 0.25)]))
		c.sleeves = "none"
		c.skirt = 0.86
		c.skirt_flare = 0.45
		c.bottom = _d(sari_c)
		c.drape = _d(sari_c)
		c.drape_style = "sari"
		c.skirt_border = Color(0.8, 0.62, 0.22) if sari_c.r < 0.7 else MADDER
		c.head = "bun"
		if rng.randf() < 0.7:
			c.flowers = Color(0.92, 0.9, 0.82)
		c.bangles = GOLD
		c.necklace = Color(0.82, 0.62, 0.22)
	else:
		c.bare_chest = true
		c.bottom = white
		c.skirt = 0.78
		c.skirt_border = border
		c.head = "topknot"
	match outfit:
		"chola_devotee":
			if not f:
				if rng.randf() < 0.65:
					c.drape = _d(_vary(rng, _pick(rng, [Color(0.86, 0.82, 0.7), TURMERIC, Color(0.8, 0.45, 0.2)])))
					c.drape_style = "stole"
				if rng.randf() < 0.5:
					c.necklace = Color(0.33, 0.19, 0.12)
		"chola_drummer":
			c.skirt = 0.62
			c.props = ["drum"]
			c.band = _d(LEATHER, "fabric_leather_02")
			c.anim = "drum"
			c.head = _pick(rng, ["topknot", "headcloth"])
			c.head_color = Color(0.86, 0.82, 0.7)
		"chola_soldier":
			c.skirt = 0.46
			c.skirt_flare = 0.55
			c.belt = _d(_pick(rng, [MADDER, Color(0.45, 0.14, 0.2)]))
			c.band = _d(LEATHER, "fabric_leather_02")
			c.armband = GOLD
			c.props = ["sword"]
			c.prop = _pick(rng, ["spear", "spear", ""])
			c.shield = "round"
			c.shield_color = _pick(rng, [Color(0.28, 0.19, 0.13), Color(0.4, 0.14, 0.1)])
		"chola_artisan":
			if f:
				c.skirt = 0.8
				c.erase("flowers")
				c.prop = _pick(rng, ["head_basket", ""])
			else:
				c.skirt = 0.5
				c.head = _pick(rng, ["headcloth", "topknot"])
				c.head_color = Color(0.86, 0.82, 0.7)
				c.prop = "hammer"
				c.anim = "work"
		"chola_sailor":
			c.skirt = 0.42
			c.skirt_flare = 0.6
			c.erase("skirt_border")
			c.bottom = _d(_vary(rng, _pick(rng, [INDIGO, COTTON, TAN])))
			c.belt = _d(COTTON)
			if rng.randf() < 0.5:
				c.head = "turban"
				c.head_color = Humanoid.tint_for("rough_linen", _pick(rng, [COTTON, MADDER, Color(0.86, 0.82, 0.7)]))
			else:
				c.head = "headcloth"
				c.head_color = _pick(rng, [COTTON, MADDER])
			c.prop = _pick(rng, ["oar", "", "oar"])


# ------------------------------------------------------------- 13th c. Europe
## Wool tunics over hose for men, long kirtles and linen veils for women;
## undyed, russet, woad blue and weld green for working people, brighter cloth
## for the rich. Mail and a surcoat for the knight, a habit for the religious.
static func _medieval(c: Dictionary, rng: RandomNumberGenerator, f: bool, outfit: String) -> void:
	c.hair = _pick(rng, [Color(0.2, 0.13, 0.08), Color(0.32, 0.21, 0.12), Color(0.55, 0.42, 0.24), Color(0.08, 0.06, 0.05), Color(0.4, 0.18, 0.09), GREY_HAIR])
	c.shoe = Color(0.75, 0.62, 0.5)
	var wool: Color = _vary(rng, _pick(rng, [Color(0.48, 0.29, 0.19), Color(0.58, 0.53, 0.43), Color(0.28, 0.35, 0.47), Color(0.33, 0.4, 0.24), Color(0.38, 0.31, 0.24), Color(0.5, 0.42, 0.2)]))
	var rich: Color = _pick(rng, [Color(0.55, 0.1, 0.1), Color(0.14, 0.2, 0.45), Color(0.16, 0.36, 0.2), Color(0.42, 0.12, 0.3), Color(0.72, 0.55, 0.14)])
	var hose: Array = _d(_pick(rng, [Color(0.42, 0.37, 0.3), Color(0.28, 0.26, 0.23), Color(0.36, 0.25, 0.18)]))
	var white_coif := Color(0.84, 0.81, 0.73)
	c.sleeves = "long"
	c.bottom = hose
	c.belt = _d(LEATHER, "fabric_leather_02")
	match outfit:
		"medieval_peasant":
			c.top = _d(wool)
			if f:
				c.bottom = _d(wool)
				c.skirt = 0.88
				c.skirt_flare = 0.6
				c.head = "veil"
				c.head_color = Color(0.84, 0.81, 0.73)
				c.prop = _pick(rng, ["", "sack", ""])
			else:
				c.tunic = rng.randf_range(0.46, 0.56)
				c.head = _pick(rng, ["linen_coif", "straw_hat", "hood", "hair"])
				c.head_color = white_coif
				if c.head == "hood":
					c.cowl = _d(wool * Color(0.8, 0.8, 0.8))
				c.short_beard = rng.randf() < 0.5
				c.prop = _pick(rng, ["", "hoe", "sack", "staff"])
		"medieval_guard":
			c.top = _d(_vary(rng, _pick(rng, [Color(0.62, 0.55, 0.4), Color(0.5, 0.44, 0.33), Color(0.45, 0.2, 0.15)])))
			c.tunic = 0.48
			c.head = "kettle_helm"
			c.head_color = STEEL
			c.prop = "spear"
			c.shield = _pick(rng, ["kite", "round"])
			c.shield_color = _pick(rng, [Color(0.5, 0.12, 0.1), Color(0.15, 0.22, 0.42), Color(0.7, 0.62, 0.3)])
			if rng.randf() < 0.5:
				c.props = ["sword"]
			c.short_beard = rng.randf() < 0.5
		"medieval_knight":
			c.mail = true
			c.top = _d(rich if rng.randf() < 0.8 else Color(0.84, 0.81, 0.74))
			c.tunic = 0.64
			c.bottom = _d(Color(0.2, 0.2, 0.22))
			c.head = "great_helm" if rng.randf() < 0.5 else "mail_coif"
			c.head_color = STEEL
			c.props = ["sword"]
			c.shield = "kite"
			c.shield_color = rich
			c.shoe = Color(0.35, 0.35, 0.38)
			c.bulk = maxf(c.bulk, 1.02)
		"medieval_monk":
			var habit: Color = _pick(rng, [Color(0.12, 0.11, 0.1), Color(0.4, 0.33, 0.26), Color(0.78, 0.74, 0.66), Color(0.3, 0.26, 0.22)])
			c.top = _d(habit)
			c.bottom = _d(habit)
			c.skirt = 0.88
			c.skirt_flare = 0.5
			c.cowl = _d(habit * Color(0.92, 0.92, 0.92))
			c.belt = _d(Color(0.74, 0.67, 0.5))
			if f:
				c.head = "veil"
				c.head_color = Color(0.12, 0.11, 0.1)
				c.wimple_color = Color(0.86, 0.84, 0.78)
			else:
				c.head = "tonsure"
				c.prop = _pick(rng, ["", "staff", ""])
		"medieval_judge":
			var robe: Color = _pick(rng, [Color(0.52, 0.1, 0.1), Color(0.15, 0.19, 0.38), Color(0.38, 0.12, 0.24)])
			c.top = _d(robe)
			c.bottom = _d(robe)
			c.skirt = 0.88
			c.skirt_flare = 0.55
			c.cowl = _d(Color(0.8, 0.78, 0.73))
			c.head = "linen_coif"
			c.head_color = white_coif
			c.prop = "scroll"
			c.shoe = Color(0.4, 0.33, 0.28)
			c.hair = GREY_HAIR if rng.randf() < 0.6 else c.hair
			c.short_beard = rng.randf() < 0.4
		_:
			c.top = _d(rich)
			var second: Color = _pick(rng, [Color(0.2, 0.18, 0.3), Color(0.5, 0.36, 0.14), Color(0.3, 0.12, 0.12), Color(0.2, 0.3, 0.22)])
			c.cloak = _d(second)
			c.belt = _d(Color(0.6, 0.45, 0.2), "fabric_leather_02")
			if f:
				c.bottom = _d(rich)
				c.skirt = 0.9
				c.skirt_flare = 0.75
				c.head = _pick(rng, ["veil", "circlet", "braid"])
				c.head_color = Color(0.86, 0.84, 0.78) if c.head == "veil" else GOLD
			else:
				c.tunic = 0.74
				c.skirt_flare = 0.7
				c.bottom = _d(second)
				c.head = _pick(rng, ["circlet", "linen_coif", "hair"])
				c.head_color = GOLD if c.head == "circlet" else second
				if rng.randf() < 0.5:
					c.props = ["sword"]
				c.short_beard = rng.randf() < 0.4
