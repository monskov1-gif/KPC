class_name RankBadge
extends Control
## Круглый значок ранга: мягкий круг цвета ранга с буквой.

var rank := "D"


static func make(p_rank: String, side := 64.0) -> RankBadge:
	var b := RankBadge.new()
	b.rank = p_rank
	b.custom_minimum_size = Vector2(side, side)
	b.size_flags_horizontal = Control.SIZE_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	var rad := minf(size.x, size.y) / 2.0
	var col := UiTheme.rank_color(rank)
	draw_circle(c, rad, Color(col, 0.25))
	draw_circle(c, rad * 0.8, col)
	var font := get_theme_default_font()
	var fs := int(rad * 1.0)
	var ts := font.get_string_size(rank, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, c + Vector2(-ts.x / 2.0, ts.y * 0.32), rank, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)
