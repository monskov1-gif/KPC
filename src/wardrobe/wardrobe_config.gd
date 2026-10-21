class_name WardrobeConfig
extends RefCounted
## Справочники системы одежды и общие коэффициенты (data/wardrobe/config.json).

var attributes: Array[String] = []
var slots: Array[String] = []
var categories: Dictionary = {}          # category -> Array[slot]
var rarities: Array[String] = []
var style_tags: Array[String] = []
var color_tags: Array[String] = []
var material_tags: Array[String] = []
var body_types: Array[String] = []
var theme_levels: Dictionary = {}        # level -> multiplier
var severity_q: Dictionary = {}          # severity -> Q
var combination_method := "strictest"
var combination_floor := 0.1
var theme_ignored_q := 0.1
var theme_matching_levels: Array[String] = []
var default_rank_thresholds: Dictionary = {}
var rank_order: Array[String] = []
var duplicate_policy: Dictionary = {}
var attribute_min := 0
var attribute_max := 100


static func from_dict(d: Dictionary) -> WardrobeConfig:
	var c := WardrobeConfig.new()
	c.attributes = DataLoader.to_string_array(d.get("attributes", []))
	c.slots = DataLoader.to_string_array(d.get("slots", []))
	c.categories = d.get("categories", {})
	c.rarities = DataLoader.to_string_array(d.get("rarities", []))
	c.style_tags = DataLoader.to_string_array(d.get("style_tags", []))
	c.color_tags = DataLoader.to_string_array(d.get("color_tags", []))
	c.material_tags = DataLoader.to_string_array(d.get("material_tags", []))
	c.body_types = DataLoader.to_string_array(d.get("body_types", []))
	c.theme_levels = d.get("theme_levels", {})
	c.severity_q = d.get("requirement_severity_q", {})
	var comb: Dictionary = d.get("requirement_combination", {})
	c.combination_method = comb.get("method", "strictest")
	c.combination_floor = float(comb.get("floor", 0.1))
	var ti: Dictionary = d.get("theme_ignored", {})
	c.theme_ignored_q = float(ti.get("q", 0.1))
	c.theme_matching_levels = DataLoader.to_string_array(ti.get("matching_levels", ["perfect", "good"]))
	c.default_rank_thresholds = d.get("default_rank_thresholds", {})
	c.rank_order = DataLoader.to_string_array(d.get("rank_order", ["D", "C", "B", "A", "S"]))
	c.duplicate_policy = d.get("duplicate_policy", {})
	var scale: Dictionary = d.get("attribute_scale", {})
	c.attribute_min = int(scale.get("min", 0))
	c.attribute_max = int(scale.get("max", 100))
	return c


func rank_index(rank: String) -> int:
	return rank_order.find(rank)
