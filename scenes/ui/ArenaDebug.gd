extends CanvasLayer

## 밸런싱 아레나 디버그 패널 — Testplay 에 붙는다. F1 로 토글.
## 탭 구성: 환경(무적/배속/삭제/모드선택) · 스폰(수량 지정) · 스탯(직접 주입, 카드창 없음) · PC튜닝.
## process_mode = ALWAYS — 배속/일시정지와 무관하게 항상 동작.
## 스탯 주입/라이브 튜닝은 검은 카드 화면 없이 즉시 적용 — 게임 화면 유지한 채 수치만 바꾼다.

const _GameConfigScript := preload("res://scripts/managers/GameConfig.gd")

var _player: Node
var _exp: Node
var _host: Node          # Testplay — arena_spawn(kind, count) 호출용

var _panel: PanelContainer
var _readout: Label
var _god_btn: Button
var _mode_label: Label
var _spawn_count: SpinBox
var _stats_label: Label
var _wave_btn: Button

var _t: float = 0.0
var _tracked: Dictionary = {}   # enemy_ref -> {t, name, counted}
var _last_ttk: float = -1.0
var _last_ttk_name: String = ""
var _kills: int = 0
var _ttk_sum: float = 0.0


## Testplay 가 _player + _exp_system + self(host) 를 넘겨 연결.
func setup(player: Node, exp_system: Node, host: Node = null) -> void:
	_player = player if player != null else get_tree().get_first_node_in_group("player")
	_exp = exp_system
	_host = host
	if _panel == null:
		_build()
	_sync_god_btn()
	_sync_mode_label()


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # 씬 떠날 때 배속 원복.


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F1:
		if _panel != null:
			_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_track_ttk(delta)
	_refresh_readout()
	_refresh_stats()


# ── TTK 추적 — 적 등장 시 스폰시각 기록, _dead 되는 순간 TTK 계산(게임시간) ──
func _track_ttk(delta: float) -> void:
	_t += delta
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not _tracked.has(e):
			_tracked[e] = {"t": _t, "name": _enemy_name(e), "counted": false}
	var to_erase: Array = []
	for e in _tracked.keys():
		var info: Dictionary = _tracked[e]
		var dead: bool = not is_instance_valid(e) or ("_dead" in e and e._dead)
		if dead and not info["counted"]:
			info["counted"] = true
			_last_ttk = _t - float(info["t"])
			_last_ttk_name = String(info["name"])
			_kills += 1
			_ttk_sum += _last_ttk
		if not is_instance_valid(e):
			to_erase.append(e)
	for e in to_erase:
		_tracked.erase(e)


func _enemy_name(e: Node) -> String:
	if e.is_in_group("boss"): return "보스"
	if e.is_in_group("sorcerers"): return "주술사"
	if e.is_in_group("elites"): return "엘리트"
	if "behavior" in e and int(e.behavior) == 2: return "슬래머"
	if e.is_in_group("ranged_enemies"): return "궁수"
	if e.is_in_group("leapers"): return "리퍼"
	return "잡몹"


func _alive_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not ("_dead" in e and e._dead):
			n += 1
	return n


func _refresh_readout() -> void:
	if _readout == null:
		return
	var lv := 1
	if _exp != null and is_instance_valid(_exp) and "level" in _exp:
		lv = int(_exp.level)
	var ap := 1
	if _player != null and is_instance_valid(_player) and "attack_power" in _player:
		ap = int(_player.attack_power)
	var god := false
	if _player != null and is_instance_valid(_player) and "god_mode" in _player:
		god = bool(_player.god_mode)
	var avg := (_ttk_sum / float(_kills)) if _kills > 0 else 0.0
	_readout.text = "생존 %d | 레벨 %d | 공격력 %d | 배속 %.2fx | 무적 %s\n최근 TTK %.2fs (%s) · 처치 %d · 평균 %.2fs" % [
		_alive_count(), lv, ap, Engine.time_scale, ("ON" if god else "OFF"),
		maxf(_last_ttk, 0.0), _last_ttk_name, _kills, avg]
	if _host != null and is_instance_valid(_host) and _host.has_method("arena_wave_info"):
		_readout.text += "\n" + String(_host.call("arena_wave_info"))


## PC 현재 적용 스탯(읽기 전용) — 카드/튜닝 반영된 최종 실효값.
func _refresh_stats() -> void:
	if _stats_label == null or _player == null or not is_instance_valid(_player):
		return
	var p = _player
	var d = (p.data if "data" in p and p.data != null else null)
	var lines: Array = []
	if p.has_method("get_hp") and p.has_method("get_max_hp"):
		lines.append("HP  %d / %d" % [int(p.call("get_hp")), int(p.call("get_max_hp"))])
	lines.append("공격력  %d" % (int(p.attack_power) if "attack_power" in p else 1))
	if d != null:
		if "move_speed" in d:
			lines.append("이동 속도  %.2f" % d.move_speed)
		if "instant_slash_distance" in d:
			lines.append("일섬 사거리  %.1f" % d.instant_slash_distance)
		if "slash_width" in d:
			lines.append("일섬 폭  %.2f" % d.slash_width)
		if "evade_max_stacks" in d and p.has_method("get_evade_stacks"):
			lines.append("회피 스택  %d / %d" % [int(p.call("get_evade_stacks")), d.evade_max_stacks])
		if "evade_refill_time" in d:
			var rm: float = (p.evade_refill_mult if "evade_refill_mult" in p else 1.0)
			lines.append("회피충전  %.2fs (×%.2f)" % [d.evade_refill_time * rm, rm])
	if "shield_charges" in p and int(p.shield_charges) > 0:
		lines.append("보호막  %d" % int(p.shield_charges))
	_stats_label.text = "\n".join(lines)


# ── 환경 액션 ──
func _toggle_god() -> void:
	if _player != null and "god_mode" in _player:
		_player.god_mode = not _player.god_mode
	_sync_god_btn()

func _sync_god_btn() -> void:
	if _god_btn != null and _player != null and is_instance_valid(_player) and "god_mode" in _player:
		_god_btn.text = "무적: " + ("ON" if _player.god_mode else "OFF")
		_god_btn.modulate = Color(0.55, 1.0, 0.55) if _player.god_mode else Color(1, 1, 1)

func _set_time_scale(v: float) -> void:
	Engine.time_scale = clampf(v, 0.05, 4.0)

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	_tracked.clear()


# ── 웨이브 선택 (GameConfig 세팅 + 씬 리로드. 컨트롤은 일섬 단일) ──
func _set_mode(wave: int) -> void:
	_GameConfigScript.wave_preset = wave
	_GameConfigScript.contact_damage_enabled = false
	_GameConfigScript.charge_zoom_enabled = true
	var tree := get_tree()
	if tree != null:
		tree.reload_current_scene()

func _sync_mode_label() -> void:
	if _mode_label == null:
		return
	var wave: int = _GameConfigScript.wave_preset
	var nm := "일섬 (기본 웨이브)"
	if wave == 1:
		nm = "근접 몹 일섬"
	elif wave == 2:
		nm = "원거리 몹 일섬"
	_mode_label.text = "현재 웨이브: " + nm


# ── 스폰 (수량 지정 → host.arena_spawn) ──
func _do_spawn(kind: String) -> void:
	if _host != null and is_instance_valid(_host) and _host.has_method("arena_spawn"):
		var n: int = int(_spawn_count.value) if _spawn_count != null else 1
		_host.call("arena_spawn", kind, n)

## 웨이브 시작/정지 토글 — Testplay 의 WaveManager 를 켜고 끈다(chapter_1 곡선 자동 스폰).
func _toggle_wave() -> void:
	if _host == null or not is_instance_valid(_host) or not _host.has_method("toggle_wave"):
		return
	var running: bool = bool(_host.call("toggle_wave"))
	if _wave_btn != null:
		_wave_btn.text = "■ 웨이브 정지" if running else "▶ 웨이브 시작"
		_wave_btn.modulate = Color(1.0, 0.6, 0.6) if running else Color(0.6, 1.0, 0.6)

func _wave_jump(secs: float) -> void:
	if _host != null and is_instance_valid(_host) and _host.has_method("arena_wave_jump"):
		_host.call("arena_wave_jump", secs)


# ── 스탯 직접 주입 (검은 카드 화면 없이 즉시) ──
func _level_up_direct() -> void:
	if _exp == null or not is_instance_valid(_exp):
		return
	_exp.level += 1   # 카드 화면 없이 레벨만 +1 (몬스터 HP 스케일링이 이 레벨을 읽음)
	if _exp.has_signal("exp_changed") and "current_exp" in _exp and "threshold" in _exp:
		_exp.exp_changed.emit(_exp.current_exp, _exp.threshold)

func _attack_up() -> void:
	if _player != null and "attack_power" in _player:
		_player.attack_power += 1

func _refill_evade() -> void:
	if _player != null and is_instance_valid(_player) and _player.has_method("refill_evade"):
		_player.call("refill_evade")

## 도깨비(또는 임의) 은혜 장착 — 중복이면 스킵, 아니면 uniq 등급으로 즉시 등록.
func _equip_boon(id: String) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method("add_boon"):
		return
	var owned = _player.get("active_boons")
	if owned is Array:
		for b in owned:
			if b is Dictionary and String(b.get("id", "")) == id:
				return  # 이미 장착 — 중복 누적 방지.
	_player.call("add_boon", id, "uniq")

func _set_pc_float(field: String, v: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if field == "attack_power":
		_player.attack_power = int(round(v))
	elif field == "evade_refill_mult":
		_player.evade_refill_mult = v
	elif "data" in _player and _player.data != null and field in _player.data:
		_player.data.set(field, v)


# ── UI 빌드 ──
func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.94)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(12, 48)
	_panel.custom_minimum_size = Vector2(346, 0)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_panel.add_child(vb)
	vb.add_child(_title("⚔ 밸런싱 아레나  (F1 토글)"))
	_readout = _info("")
	vb.add_child(_readout)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(328, 452)
	vb.add_child(tabs)

	# 환경 탭
	var t_env := _tab("환경")
	tabs.add_child(t_env)
	_god_btn = _btn("무적: OFF", _toggle_god)
	t_env.add_child(_god_btn)
	t_env.add_child(_slider("시간 배속", 0.2, 3.0, 1.0, 0.05, func(v): _set_time_scale(v)))
	t_env.add_child(_btn("적 전체 삭제", _clear_enemies))
	t_env.add_child(HSeparator.new())
	t_env.add_child(_title("웨이브 구성"))
	_mode_label = _info("")
	t_env.add_child(_mode_label)
	t_env.add_child(_btn("기본 일섬 웨이브", func(): _set_mode(0)))
	t_env.add_child(_btn("근접 몬스터 일섬", func(): _set_mode(1)))
	t_env.add_child(_btn("원거리 몬스터 일섬", func(): _set_mode(2)))

	# 스폰 탭
	var t_spawn := _tab("스폰")
	tabs.add_child(t_spawn)
	_wave_btn = _btn("▶ 웨이브 시작", _toggle_wave)
	_wave_btn.modulate = Color(0.6, 1.0, 0.6)
	t_spawn.add_child(_wave_btn)
	t_spawn.add_child(_btn("웨이브 +30초 점프", func(): _wave_jump(30.0)))
	t_spawn.add_child(HSeparator.new())
	t_spawn.add_child(_spin_row("수량", 1, 50, 3))
	t_spawn.add_child(HSeparator.new())
	t_spawn.add_child(_spawn_btn("잡몹", "mob"))
	t_spawn.add_child(_spawn_btn("리퍼", "leaper"))
	t_spawn.add_child(_spawn_btn("슬래머", "slammer"))
	t_spawn.add_child(_spawn_btn("궁수 (원거리)", "ranged"))
	t_spawn.add_child(_spawn_btn("주술사", "sorcerer"))
	t_spawn.add_child(_spawn_btn("★엘리트 (원거리)", "star_elite"))
	t_spawn.add_child(_spawn_btn("엘리트 1 (폭발)", "elite1"))
	t_spawn.add_child(_spawn_btn("엘리트 2 (보너스)", "elite2"))
	t_spawn.add_child(_spawn_btn("엘리트 3 (불릿타임)", "elite3"))
	t_spawn.add_child(_spawn_btn("엘리트 4 (보호막)", "elite4"))
	t_spawn.add_child(_spawn_btn("보스 1", "boss1"))
	t_spawn.add_child(_spawn_btn("보스 2", "boss2"))
	t_spawn.add_child(_spawn_btn("보스 3", "boss3"))

	# 스탯 탭 — 검은 카드 화면 없이 즉시 주입
	var t_stat := _tab("스탯")
	tabs.add_child(t_stat)
	t_stat.add_child(_btn("레벨 +1 (몬스터 강화)", _level_up_direct))
	t_stat.add_child(_btn("공격력 +1", _attack_up))
	t_stat.add_child(_btn("회피 가득", _refill_evade))

	# 도깨비 은혜 장착(능동 FX 테스트) — 유일(uniq) 등급 즉시 장착.
	t_stat.add_child(_title("도깨비 은혜 장착 (uniq)"))
	t_stat.add_child(_btn("도깨비불 일섬 (혼불 유도)", func(): _equip_boon("dokebi_foxfire")))
	t_stat.add_child(_btn("옮겨붙는 도깨비불 (연쇄)", func(): _equip_boon("dokebi_chain")))
	t_stat.add_child(_btn("방망이 한방 (강타)", func(): _equip_boon("dokebi_smash")))
	t_stat.add_child(_btn("방망이 난타 (추가 부채)", func(): _equip_boon("dokebi_extrafan")))
	t_stat.add_child(_btn("난장도깨비패 (분신)", func(): _equip_boon("dokebi_clone")))
	t_stat.add_child(_btn("뚝딱 금 나와라 (금화)", func(): _equip_boon("dokebi_gold")))
	t_stat.add_child(_btn("도깨비 금줄 (점화존)", func(): _equip_boon("dokebi_ignite")))

	# 현재 스탯 탭 — 읽기 전용(튜닝 반영된 최종 적용값)
	var t_cur := _tab("현재")
	tabs.add_child(t_cur)
	t_cur.add_child(_title("PC 현재 적용 스탯"))
	_stats_label = _info("")
	t_cur.add_child(_stats_label)

	# PC 튜닝 탭 — 라이브 슬라이더
	var t_pc := _tab("튜닝")
	tabs.add_child(t_pc)
	var pd = (_player.data if _player != null and "data" in _player and _player.data != null else null)
	t_pc.add_child(_slider("이동 속도", 1.0, 12.0, (pd.move_speed if pd else 4.0), 0.1, func(v): _set_pc_float("move_speed", v)))
	t_pc.add_child(_slider("공격력", 1, 10, float(_player.attack_power if _player != null and "attack_power" in _player else 1), 1, func(v): _set_pc_float("attack_power", v)))
	t_pc.add_child(_slider("일섬 사거리", 3.0, 20.0, (pd.instant_slash_distance if pd else 11.0), 0.5, func(v): _set_pc_float("instant_slash_distance", v)))
	t_pc.add_child(_slider("회피충전 배수", 0.3, 1.5, float(_player.evade_refill_mult if _player != null and "evade_refill_mult" in _player else 1.0), 0.05, func(v): _set_pc_float("evade_refill_mult", v)))


func _tab(tab_name: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.name = tab_name
	vb.add_theme_constant_override("separation", 4)
	return vb

func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(1, 0.92, 0.5))
	l.add_theme_font_size_override("font_size", 14)
	return l

func _info(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
	l.add_theme_font_size_override("font_size", 12)
	return l

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(300, 26)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b

func _spawn_btn(label_text: String, kind: String) -> Button:
	return _btn(label_text, func(): _do_spawn(kind))

func _spin_row(label_text: String, mn: int, mx: int, val: int) -> Control:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(80, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	hb.add_child(lbl)
	var sp := SpinBox.new()
	sp.min_value = mn
	sp.max_value = mx
	sp.step = 1
	sp.value = val
	sp.custom_minimum_size = Vector2(110, 0)
	hb.add_child(sp)
	_spawn_count = sp
	return hb

func _slider(label_text: String, mn: float, mx: float, val: float, step: float, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(100, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	hb.add_child(lbl)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value = val
	hb.add_child(s)
	var vlbl := Label.new()
	vlbl.custom_minimum_size = Vector2(44, 0)
	vlbl.text = ("%.2f" % val) if step < 1.0 else str(int(val))
	vlbl.add_theme_font_size_override("font_size", 12)
	hb.add_child(vlbl)
	s.value_changed.connect(func(v):
		vlbl.text = ("%.2f" % v) if step < 1.0 else str(int(v))
		cb.call(v))
	return hb
