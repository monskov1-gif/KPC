class_name HudSheets
extends RefCounted
## Окна игрового интерфейса в «облаке» Sheet: события, сумка, профиль игрока (с альбомом снимков).
## Логика — в сервисах сессии (EventService, ResourceInventory, PlayerProfile); здесь только показ и кнопки.

const RES_ICON := {"wish_ticket": ["ticket", Color("b58be0")], "coins": ["coin", Color("d8b36e")],
	"star_dust": ["dust", Color("e79ab8")], "fabric_velvet": ["fabric", Color("b4789a")],
	"thread_silk": ["thread", Color("9fb4d8")]}


static func res_icon(id: String, size := 22.0) -> IconView:
	var r: Array = RES_ICON.get(id, ["sparkle", UiTheme.GOLD])
	return UiTheme.icon(r[0], size, r[1])


## Награда — ряд «фишек»: иконка ресурса и количество.
static func reward_row(reward: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for id in reward:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiTheme.pill(Color(1, 1, 1, 0.75), 4))
		var c := HBoxContainer.new()
		c.add_child(res_icon(str(id), 20))
		c.add_child(UiTheme.tag("×%d" % int(reward[id]), 15))
		chip.add_child(c)
		h.add_child(chip)
	return h


static func _card(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UiTheme.cloud(Color(1, 0.99, 0.98, 0.92), 20, 14)
	st.border_width_left = 6
	st.border_color = accent
	p.add_theme_stylebox_override("panel", st)
	return p


static func _wrap(text: String, size := 15, color := UiTheme.TEXT_DIM) -> Label:
	var l := UiTheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# ---------- события ----------

## play(challenge_id) — открыть гардероб с испытанием события.
static func open_events(sheet: Sheet, play: Callable, on_claim: Callable) -> void:
	var s := Game.session
	var day := EventService.today()
	sheet.clear()
	var evs := s.events.all_events().duplicate()
	# идущие — сверху, будущие — ниже
	evs.sort_custom(func(a, b): return int(s.events.is_active(a, day)) > int(s.events.is_active(b, day)))
	for e in evs:
		sheet.content.add_child(_event_card(sheet, e, day, play, on_claim))
	sheet.open("События", "calendar")


static func _event_card(sheet: Sheet, e: Dictionary, day: int, play: Callable, on_claim: Callable) -> Control:
	var s := Game.session
	var accent := Color(str(e.get("accent", "#d8b36e")))
	var card := _card(accent)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	var medal := PanelContainer.new()
	medal.add_theme_stylebox_override("panel", UiTheme.box(accent.lightened(0.55), 999, 10))
	medal.add_child(UiTheme.icon(str(e.get("icon", "sparkle")), 40, accent.darkened(0.35)))
	medal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(medal)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	v.add_child(UiTheme.title(tr_or(str(e.get("title_key", "")), str(e.id)), 21))
	v.add_child(_wrap(tr_or(str(e.get("description_key", "")), "")))
	var active := s.events.is_active(e, day)
	var left := s.events.days_left(e, day)
	var when := ""
	if e.get("kind", "") == "daily":
		when = "Каждый день · дней подряд: %d" % s.events.streak()
	elif active:
		when = "Идёт · осталось %s" % _days(left)
	else:
		when = "Начнётся через %s" % _days(-left)
	v.add_child(UiTheme.tag(when, 14, UiTheme.GOLD_DEEP if active else UiTheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(reward_row(e.get("reward", {})))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var cid := str(e.get("challenge_id", ""))
	var res := s.rewards.result(cid)
	if cid != "" and str(res.get("best_rank", "")) != "":
		row.add_child(RankBadge.make(str(res.best_rank), 40))
	var cleared := bool(res.get("cleared", false))
	if s.events.claimed(e, day):
		row.add_child(UiTheme.tag("✓ Награда получена", 15, UiTheme.OK))
	elif s.events.can_claim(e, day, cleared):
		row.add_child(UiTheme.primary(UiTheme.button("Забрать", func():
			var r := s.claim_event(str(e.id), day)
			if r.ok:
				Audio.ui("ui_reward")
				on_claim.call(r.reward)
			open_events(sheet, play, on_claim))))
	elif active and cid != "":
		row.add_child(UiTheme.primary(UiTheme.button("Участвовать", func(): play.call(cid))))
	v.add_child(row)
	if not active:
		card.modulate = Color(1, 1, 1, 0.7)
	return card


static func _days(n: int) -> String:
	n = maxi(1, n)
	var w := "дней"
	if n % 10 == 1 and n % 100 != 11:
		w = "день"
	elif n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		w = "дня"
	return "%d %s" % [n, w]


static func tr_or(key: String, fallback: String) -> String:
	if key == "":
		return fallback
	var t := TranslationServer.translate(key)
	return fallback if t == key and fallback != "" else str(t)


# ---------- сумка ----------

static func open_inventory(sheet: Sheet, open_wardrobe: Callable) -> void:
	var s := Game.session
	sheet.clear()
	var c := sheet.content
	c.add_child(UiTheme.title("Валюта и материалы", 20))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for id in ["wish_ticket", "coins", "star_dust", "fabric_velvet", "thread_silk"]:
		if not s.resources.is_known(id):
			continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.cloud(Color(1, 0.99, 0.98, 0.9), 18, 10))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := res_icon(id, 40)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var n := UiTheme.title(str(s.resources.amount(id)), 20)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		var l := UiTheme.tag(tr_or(str(s.resources.definition(id).get("name_key", "")), id), 13, UiTheme.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
		card.add_child(v)
		grid.add_child(card)
	c.add_child(grid)
	c.add_child(UiTheme.title("Одежда и лица", 20))
	var counts := {}
	var totals := {}
	for it in s.catalog.all_items():
		if not s.characters.has_character("kot_child") or not it.compatible_character_ids.has("kot_child") \
				or it.compatible_character_ids.size() > 1:
			totals[it.slot] = int(totals.get(it.slot, 0)) + 1
			if s.inventory.owns(it.id):
				counts[it.slot] = int(counts.get(it.slot, 0)) + 1
	var list := GridContainer.new()
	list.columns = 2
	list.add_theme_constant_override("h_separation", 18)
	for slot in s.config.slots:
		if not totals.has(slot):
			continue
		var h := HBoxContainer.new()
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(UiTheme.icon(slot, 26, UiTheme.GOLD_DEEP))
		var name := UiTheme.label(tr_or("slot." + slot, slot), 16)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name)
		h.add_child(UiTheme.tag("%d / %d" % [int(counts.get(slot, 0)), int(totals[slot])], 15, UiTheme.TEXT_DIM))
		list.add_child(h)
	c.add_child(list)
	var b := UiTheme.secondary(UiTheme.button("Открыть гардероб", open_wardrobe))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.add_child(b)
	sheet.open("Сумка", "bag")


# ---------- профиль ----------

static func open_profile(sheet: Sheet, hero_id: String, on_changed: Callable) -> void:
	var s := Game.session
	var stats := s.profile_stats()
	var lv := PlayerProfile.level_of(PlayerProfile.xp_from(stats))
	sheet.clear()
	var c := sheet.content
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var av := AvatarView.new()
	av.custom_minimum_size = Vector2(104, 104)
	if s.characters.has_character(hero_id):
		av.hair = s.characters.placeholder_color(hero_id)
	av.cat_ears = hero_id.begins_with("kot")
	av.active = true
	head.add_child(av)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := LineEdit.new()
	name.text = s.profile.player_name
	name.placeholder_text = s.profile.display_name()
	name.max_length = PlayerProfile.NAME_MAX
	name.custom_minimum_size.y = 44
	var commit := func(_t = ""):
		s.profile.set_player_name(name.text)
		Game.save_game()
		on_changed.call()
	name.text_submitted.connect(commit)
	name.focus_exited.connect(commit)
	v.add_child(name)
	var id_text := str(s.profile.uid)
	v.add_child(UiTheme.tag("ID %s %s %s" % [id_text.substr(0, 3), id_text.substr(3, 3), id_text.substr(6)], 14,
		UiTheme.TEXT_DIM))
	var lr := HBoxContainer.new()
	lr.add_child(UiTheme.title("Ур. %d" % lv.level, 22, UiTheme.GOLD_DEEP))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.value = lv.progress * 100.0
	bar.custom_minimum_size = Vector2(160, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UiTheme.box(Color(0.9, 0.84, 0.82, 0.8), 6, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.GOLD, 6, 0))
	lr.add_child(bar)
	v.add_child(lr)
	v.add_child(UiTheme.tag("Опыт: %d / %d" % [lv.xp, lv.to], 13, UiTheme.TEXT_DIM))
	head.add_child(v)
	c.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	var t := int(s.profile.play_seconds)
	var rows := [
		["hanger", "Вещей в гардеробе", "%d / %d" % [stats.item, stats.items_total]],
		["person", "Персонажей", "%d / %d" % [stats.characters, stats.characters_total]],
		["trophy", "Испытаний пройдено", str(stats.challenge)],
		["star", "Лучший ранг", str(stats.best_rank) if str(stats.best_rank) != "" else "—"],
		["gacha", "Молитв", str(stats.pull)],
		["calendar", "Наград событий", str(stats.event)],
		["camera", "Снимков в альбоме", str(stats.photo)],
		["steps", "Время в игре", "%d ч %02d мин" % [t / 3600, (t / 60) % 60]],
	]
	for r in rows:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", UiTheme.cloud(Color(1, 0.99, 0.98, 0.85), 16, 10))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_child(UiTheme.icon(r[0], 24, UiTheme.GOLD_DEEP))
		var l := UiTheme.label(r[1], 15, UiTheme.TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UiTheme.title(r[2], 17))
		cell.add_child(h)
		grid.add_child(cell)
	c.add_child(grid)
	c.add_child(UiTheme.title("Альбом", 20))
	if s.profile.photos.is_empty():
		c.add_child(_wrap("Снимков пока нет — нажмите кнопку с фотоаппаратом во время прогулки."))
	else:
		var album := GridContainer.new()
		album.columns = 3
		album.add_theme_constant_override("h_separation", 8)
		album.add_theme_constant_override("v_separation", 8)
		var shown := 0
		for i in range(s.profile.photos.size() - 1, -1, -1):
			var tex := PhotoAlbum.thumbnail(s.profile.photos[i], 200)
			if tex == null:
				continue
			var b := Button.new()
			b.flat = true
			b.icon = tex
			b.expand_icon = true
			b.custom_minimum_size = Vector2(150, 84)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var path: String = s.profile.photos[i]
			b.pressed.connect(func(): _show_photo(sheet, path, hero_id, on_changed))
			album.add_child(b)
			shown += 1
			if shown >= 12:
				break
		c.add_child(album)
	sheet.open(s.profile.display_name(), "person")


static func _show_photo(sheet: Sheet, path: String, hero_id: String, on_changed: Callable) -> void:
	sheet.clear()
	var tr := TextureRect.new()
	tr.texture = PhotoAlbum.thumbnail(path, 960)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(0, 340)
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.content.add_child(tr)
	sheet.add_footer(UiTheme.secondary(UiTheme.button("Назад", func(): open_profile(sheet, hero_id, on_changed))))
	sheet.open("Снимок", "camera")
