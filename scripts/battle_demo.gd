extends Node2D
## SULEYN v1.13: commander matter sources and independently selected magic books.
## attack animation, HP/MP under units and a scrollable combat journal.
## Gameplay mathematics remain in battle_combat.gd and damage_calculator.gd.

const Hex = preload("res://scripts/hex_math.gd")
const BattleBoard = preload("res://scripts/battle_board.gd")
const BattleTurns = preload("res://scripts/battle_turns.gd")
const BattleUnit = preload("res://scripts/battle_unit.gd")
const BattleCombat = preload("res://scripts/battle_combat.gd")
const BattleAI = preload("res://scripts/battle_ai.gd")
const BattleSetup = preload("res://scripts/battle_setup.gd")
const PreparationUI = preload("res://scripts/battle_preparation_ui.gd")
const AttackPreview = preload("res://scripts/attack_preview.gd")
const FeedbackUI = preload("res://scripts/battle_feedback_ui.gd")
const ResultsUI = preload("res://scripts/battle_results_ui.gd")
const SetupCodec = preload("res://scripts/setup_codec.gd")
const SetupStore = preload("res://scripts/setup_store.gd")
const SetupLibraryUI = preload("res://scripts/setup_library_ui.gd")
const CommanderEditorUI = preload("res://scripts/commander_editor_ui.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const Rules = preload("res://scripts/combat_rules.gd")

const INVALID_CELL = Vector2i(-1, -1)
const ALLY_ID = "ally_1"
const ENEMY_ID = "enemy_1"
const TEAM_ENCOUNTER: int = 4
const ENCOUNTER_COUNT: int = 5
const TEST_FALCON = preload("res://data/monsters/falcon_unit_v14.tres")
const TEST_HELLHOUND = preload("res://data/monsters/hellhound_unit_v14.tres")
const TEST_LICH = preload("res://data/monsters/lich_unit_v14.tres")
const BOARD_ORIGIN = Vector2(106.0, 178.0)
const LOG_POSITION = Vector2(898.0, 554.0)
const LOG_SIZE = Vector2(487.0, 259.0)

const BACKGROUND = Color(0.060, 0.079, 0.112)
const HEX_DARK = Color(0.15, 0.24, 0.26)
const HEX_LIGHT = Color(0.18, 0.28, 0.29)
const HEX_EDGE = Color(0.36, 0.48, 0.49)
const AVAILABLE = Color(0.23, 0.52, 0.44)
const HOVER = Color(0.54, 0.65, 0.79)
const ALLY = Color(0.30, 0.55, 0.91)
const ENEMY = Color(0.84, 0.40, 0.44)
const WHITE = Color(0.93, 0.95, 0.95)
const MUTED = Color(0.64, 0.73, 0.76)
const PATH_COLOR = Color(0.99, 0.82, 0.38)
const ATTACK_COLOR = Color(0.96, 0.43, 0.31)
const HEALTH_COLOR = Color(0.52, 0.93, 0.60)
const MANA_COLOR = Color(0.48, 0.74, 1.0)

@export_range(4, 20, 1) var demo_columns: int = 9
@export_range(3, 14, 1) var demo_rows: int = 7
@export_range(20.0, 55.0, 1.0) var hex_radius: float = 35.0
@export var ally_stats: SuleynUnitStats = preload("res://data/demo_male_lv25.tres")
@export var enemy_stats: SuleynUnitStats = preload("res://data/demo_female_lv25.tres")
@export var enemy_ai_enabled: bool = true
@export var start_in_preparation: bool = false
@export var persist_setups: bool = false
@export var setup_store_path: String = "user://battle_setups.json"
## 0..3 = legacy duels, 4 = team battle. Fixed order is NOT a GDD initiative rule.
var encounter_index: int = TEAM_ENCOUNTER

func encounter_enemy_stats() -> SuleynUnitStats:
    match encounter_index:
        1: return TEST_FALCON
        2: return TEST_HELLHOUND
        3: return TEST_LICH
    return enemy_stats

func switch_encounter() -> void:
    if preparing:
        return
    encounter_index = (encounter_index + 1) % ENCOUNTER_COUNT
    reset_demo()

var preparing: bool = false
var team_setup = null
var preparation_ui = null
var new_battle_button: Button
var feedback_ui = null
var results_ui = null
var results_button: Button
var results_pending: bool = false
var setup_store = null
var library_ui = null
var storage_ready: bool = false
var storage_notice: String = ""
var commander_editor = null
var editing_commander_id: String = ""
var editing_profile_key: String = ""

var board
var turns
var units: Dictionary = {}
var selected_unit_id: String = ""
var inspected_unit_id: String = ""
var roster_order: Array[String] = []
var hovered_cell: Vector2i = INVALID_CELL
var reachable: Dictionary = {}
var battle_over: bool = false
var winner_side: String = ""
var message: String = ""
var casting_mode: bool = false
var special_mode: bool = false
var visual_clock: float = 0.0
const AI_THINK_SECONDS: float = 0.65
var ai_waiting_unit_id: String = ""
var ai_delay_remaining: float = AI_THINK_SECONDS

var journal: RichTextLabel
var animation_time: float = 1.0
const ANIMATION_DURATION: float = 0.44
# Hold a newly stunned unit's turn in view before skipping it.
# This prevents the first skip from disappearing instantaneously after an attack.
const CONCUSSION_PREVIEW_SECONDS: float = 0.95
const CONCUSSION_NOTICE_SECONDS: float = 1.30
var concussion_skip_pending: bool = false
var concussion_preview_time: float = 0.0
var concussion_notice_time: float = 0.0
var concussion_notice_text: String = ""
var animation_attacker: String = ""
var animation_defender: String = ""
var animation_target_position: Vector2 = Vector2.ZERO
var animation_direction: Vector2 = Vector2.RIGHT
var animation_damage: int = 0
var animation_evaded: bool = false
var animation_crit: bool = false
var animation_stunned: bool = false


func _ready() -> void:
    create_journal()
    create_new_battle_button()
    create_battle_feedback()
    if persist_setups:
        initialize_setup_storage(true)
    reset_demo()
    if start_in_preparation:
        open_preparation()


func create_new_battle_button() -> void:
    new_battle_button = Button.new()
    new_battle_button.text = "Новый бой (P)"
    new_battle_button.position = Vector2(1190, 34)
    new_battle_button.size = Vector2(210, 38)
    new_battle_button.pressed.connect(open_preparation)
    add_child(new_battle_button)


func open_preparation() -> void:
    if preparing:
        return
    preparing = true
    results_pending = false
    if is_instance_valid(feedback_ui):
        feedback_ui.hide()
    if is_instance_valid(results_ui):
        results_ui.hide()
    if results_button != null:
        results_button.hide()
    reset_ai_wait()
    clear_selection()
    if journal != null:
        journal.hide()
    if new_battle_button != null:
        new_battle_button.hide()
    if is_instance_valid(preparation_ui):
        preparation_ui.free()
    var draft = team_setup.copy() if team_setup != null else BattleSetup.new(demo_columns, demo_rows)
    draft.enemy_ai_enabled = enemy_ai_enabled
    preparation_ui = PreparationUI.new()
    preparation_ui.configure(draft)
    preparation_ui.deployment_requested.connect(preview_preparation)
    preparation_ui.placement_changed.connect(preview_preparation)
    preparation_ui.selection_changed.connect(_on_preparation_selection)
    preparation_ui.battle_requested.connect(start_prepared_battle)
    preparation_ui.library_requested.connect(open_setup_library)
    preparation_ui.commander_requested.connect(open_commander_editor)
    add_child(preparation_ui)
    if not storage_notice.is_empty():
        preparation_ui.set_status(storage_notice)
    queue_redraw()


func _on_preparation_selection(unit_id: String) -> void:
    selected_unit_id = unit_id
    inspected_unit_id = unit_id
    queue_redraw()


func populate_prepared_team(configuration) -> void:
    board = BattleBoard.new(configuration.columns, configuration.rows)
    for cell in configuration.blocked_cells():
        board.set_blocked(cell, true)
    units.clear()
    roster_order.clear()
    for unit_id in configuration.unit_ids():
        add_combatant(unit_id, configuration.team_for(unit_id),
            configuration.profile_stats(unit_id), configuration.positions[unit_id])


func preview_preparation() -> void:
    if not preparing or not is_instance_valid(preparation_ui):
        return
    var draft = preparation_ui.setup
    if not draft.is_valid():
        return
    encounter_index = TEAM_ENCOUNTER
    populate_prepared_team(draft)
    turns = BattleTurns.new(roster_order)
    selected_unit_id = preparation_ui.selected_unit_id
    inspected_unit_id = selected_unit_id
    animation_time = ANIMATION_DURATION
    animation_attacker = ""
    animation_defender = ""
    concussion_skip_pending = false
    concussion_notice_time = 0.0
    reachable.clear()
    reset_ai_wait()
    queue_redraw()


func start_prepared_battle() -> bool:
    if not preparing or not is_instance_valid(preparation_ui) or preparation_ui.stage != "deployment" or (is_instance_valid(library_ui) and library_ui.visible) or (is_instance_valid(commander_editor) and commander_editor.visible):
        return false
    if not preparation_ui.setup.is_valid():
        message = "Проверьте состав и расстановку: " + "; ".join(preparation_ui.setup.validation_errors())
        preparation_ui.set_status(message)
        return false
    team_setup = preparation_ui.setup.copy()
    enemy_ai_enabled = team_setup.enemy_ai_enabled
    encounter_index = TEAM_ENCOUNTER
    preparing = false
    preparation_ui.hide()
    if journal != null:
        journal.show()
    if new_battle_button != null:
        new_battle_button.show()
    reset_demo()
    if persist_setups:
        if setup_store == null:
            initialize_setup_storage(false)
        var saved: Dictionary = setup_store.save_last(team_setup)
        if not saved.ok:
            storage_notice = "Последний состав не сохранён: " + str(saved.reason)
            message = storage_notice
            log_event(storage_notice, "#ffac96")
        else:
            storage_notice = "Восстановлен последний принятый состав."
    return true


func initialize_setup_storage(restore_last: bool = false) -> Dictionary:
    setup_store = SetupStore.new(setup_store_path)
    var result: Dictionary = setup_store.load_library()
    storage_ready = bool(result.ok)
    if not result.ok:
        storage_notice = str(result.reason)
        return result
    storage_notice = str(result.reason) if result.get("recovered", false) else ""
    if restore_last:
        var previous = setup_store.last_setup()
        if previous != null:
            if previous.columns == demo_columns and previous.rows == demo_rows:
                team_setup = previous.copy()
                enemy_ai_enabled = previous.enemy_ai_enabled
                storage_notice = "Восстановлен последний принятый состав." + (" " + str(result.reason) if result.get("recovered", false) else "")
            else:
                storage_notice = "Последний состав рассчитан на другое поле. Выберите сохранённый состав или новый пример."
    return result


func setup_description(configuration) -> String:
    var lines: PackedStringArray = ["Арена: " + configuration.arena_label()]
    for side in ["ally", "enemy"]:
        var names: PackedStringArray = []
        for slot in range(1, 4):
            var unit_id: String = "%s_%d" % [side, slot]
            if not configuration.is_enabled(unit_id):
                continue
            var key: String = configuration.profile_key(unit_id)
            var name: String = str(PreparationUI.PROFILE_LABELS.get(key, key))
            var stats = configuration.profile_stats(unit_id)
            if stats != null and stats.commander != null:
                name += " (ур. %d)" % stats.commander.level
            names.append(name)
        lines.append(("Синие (%d): " if side == "ally" else "Красные (%d): ") % names.size() + (", ".join(names) if not names.is_empty() else "Пусто"))
    lines.append("Красные: ИИ" if configuration.enemy_ai_enabled else "Обе команды вручную")
    return "\n".join(lines)


func library_slots() -> Array[Dictionary]:
    var slots: Array[Dictionary] = setup_store.list_slots()
    for index in range(slots.size()):
        var stored = setup_store.slot_setup(index)
        if stored != null:
            slots[index]["summary"] = "%d×%d · %s" % [stored.side_count("blue"), stored.side_count("red"), stored.arena_label()] + (" · ИИ красных" if stored.enemy_ai_enabled else " · Вручную")
    return slots


func open_setup_library() -> void:
    if not preparing or not is_instance_valid(preparation_ui):
        return
    if is_instance_valid(commander_editor) and commander_editor.visible:
        return
    if setup_store == null:
        initialize_setup_storage(false)
    if not is_instance_valid(library_ui):
        library_ui = SetupLibraryUI.new()
        library_ui.save_requested.connect(save_library_slot)
        library_ui.load_requested.connect(load_library_slot)
        library_ui.delete_requested.connect(delete_library_slot)
        library_ui.export_requested.connect(export_setup_code)
        library_ui.import_requested.connect(import_setup_code)
        library_ui.close_requested.connect(close_setup_library)
        library_ui.z_index = 60
        add_child(library_ui)
    # GUI hit testing follows sibling order, including after preparation is rebuilt.
    move_child(library_ui, get_child_count() - 1)
    library_ui.configure(library_slots(), setup_description(preparation_ui.setup))
    library_ui.show()
    library_ui.slot_buttons[0].grab_focus()
    if not storage_ready:
        library_ui.set_status(storage_notice, true)


func close_setup_library() -> void:
    if is_instance_valid(library_ui):
        library_ui.hide()


func open_commander_editor(unit_id: String) -> void:
    if not preparing or not is_instance_valid(preparation_ui) or preparation_ui.stage != "roster":
        return
    if (is_instance_valid(library_ui) and library_ui.visible) or (is_instance_valid(commander_editor) and commander_editor.visible):
        return
    var draft = preparation_ui.setup
    if not draft.is_enabled(unit_id):
        return
    var base_stats = BattleSetup.catalog_entry(draft.profile_key(unit_id))
    if base_stats == null or base_stats.commander == null:
        return
    editing_commander_id = unit_id
    editing_profile_key = draft.profile_key(unit_id)
    if not is_instance_valid(commander_editor):
        commander_editor = CommanderEditorUI.new()
        commander_editor.applied.connect(apply_commander_options)
        commander_editor.cancelled.connect(close_commander_editor)
        commander_editor.z_index = 70
        add_child(commander_editor)
    move_child(commander_editor, get_child_count() - 1)
    commander_editor.configure("%s · %s" % [unit_token(unit_id), PreparationUI.PROFILE_LABELS.get(editing_profile_key, editing_profile_key)], base_stats, draft.current_commander_options(unit_id))
    commander_editor.show()
    commander_editor.tab_buttons.stats.grab_focus()


func close_commander_editor() -> void:
    if is_instance_valid(commander_editor):
        commander_editor.hide()
    editing_commander_id = ""
    editing_profile_key = ""


func apply_commander_options(options: Dictionary) -> bool:
    if not preparing or not is_instance_valid(preparation_ui) or not is_instance_valid(commander_editor) or not commander_editor.visible:
        return false
    var draft = preparation_ui.setup
    if not draft.is_enabled(editing_commander_id) or draft.profile_key(editing_commander_id) != editing_profile_key:
        return false
    if not draft.set_commander_options(editing_commander_id, options):
        return false
    close_commander_editor()
    preparation_ui.refresh_setup()
    preparation_ui.set_status("Настройки бойца применены к черновику. Для нового боя нажмите «Далее».")
    queue_redraw()
    return true


func save_library_slot(slot: int, title: String) -> void:
    if not preparing or setup_store == null or not is_instance_valid(library_ui):
        return
    var result: Dictionary = setup_store.save_slot(slot, title, preparation_ui.setup)
    if result.ok:
        library_ui.refresh_slots(library_slots())
    library_ui.set_status("Состав сохранён на этом устройстве." if result.ok else str(result.reason), not result.ok)


func delete_library_slot(slot: int) -> void:
    if not preparing or setup_store == null or not is_instance_valid(library_ui):
        return
    var result: Dictionary = setup_store.delete_slot(slot)
    if result.ok:
        library_ui.refresh_slots(library_slots())
    library_ui.set_status("Сохранённый состав удалён." if result.ok else str(result.reason), not result.ok)


func load_library_slot(slot: int) -> bool:
    if not preparing or setup_store == null:
        return false
    var stored = setup_store.slot_setup(slot)
    if stored == null:
        if is_instance_valid(library_ui):
            library_ui.set_status("В этом слоте пока нет состава.", true)
        return false
    return apply_setup_draft(stored, "Сохранённый состав загружен. Проверьте расстановку и начните бой.")


func apply_setup_draft(configuration, notice: String) -> bool:
    if not preparing or not is_instance_valid(preparation_ui):
        return false
    if not configuration.is_valid() or configuration.columns != demo_columns or configuration.rows != demo_rows:
        if is_instance_valid(library_ui):
            library_ui.set_status("Размер поля состава не совпадает с текущим полем %d×%d." % [demo_columns, demo_rows], true)
        return false
    preparation_ui.configure(configuration.copy())
    preparation_ui.set_status(notice)
    close_setup_library()
    queue_redraw()
    return true


func export_setup_code() -> String:
    if not preparing or not is_instance_valid(preparation_ui):
        return ""
    var result: Dictionary = SetupCodec.encode(preparation_ui.setup)
    if is_instance_valid(library_ui):
        if result.ok:
            library_ui.set_code(result.code)
        library_ui.set_status("Код готов. Скопируйте его для переноса или резервной копии." if result.ok else str(result.reason), not result.ok)
    return str(result.code) if result.ok else ""


func import_setup_code(code: String) -> bool:
    if not preparing or not is_instance_valid(preparation_ui):
        return false
    var result: Dictionary = SetupCodec.decode(code)
    if not result.ok:
        if is_instance_valid(library_ui):
            library_ui.set_status(str(result.reason), true)
        return false
    return apply_setup_draft(result.setup, "Состав из кода загружен. Проверьте расстановку и начните бой.")


func create_battle_feedback() -> void:
    feedback_ui = FeedbackUI.new()
    feedback_ui.mode_requested.connect(set_attack_mode)
    add_child(feedback_ui)
    results_button = Button.new()
    results_button.text = "Итоги боя"
    results_button.position = Vector2(965, 34)
    results_button.size = Vector2(210, 38)
    results_button.pressed.connect(show_battle_results)
    results_button.hide()
    add_child(results_button)


func current_attack_mode() -> String:
    return "magic" if casting_mode else ("special" if special_mode else "basic")


func set_attack_mode(mode: String) -> void:
    if preparing or battle_over or is_ai_turn() or not ["basic", "special", "magic"].has(mode):
        return
    casting_mode = mode == "magic"
    special_mode = mode == "special"
    message = "Режим: %s. Наведите на врага для предпросмотра." % attack_mode_name()
    log_event(message, "#b3d5e5")
    refresh_feedback()
    queue_redraw()


func attack_mode_name() -> String:
    if turns == null or not units.has(turns.active_unit_id()):
        return "атака"
    var actor = units[turns.active_unit_id()]
    if casting_mode:
        return "Магия"
    if special_mode:
        return actor.special_skill.display_name if actor.special_skill != null else "Умение не назначено"
    return "Обычный удар"


func attack_preview_for(target_id: String) -> Dictionary:
    var active: String = turns.active_unit_id() if turns != null else ""
    var preview: Dictionary = AttackPreview.evaluate(board, units, active, target_id, current_attack_mode())
    var blocked: String = ""
    if preparing:
        blocked = "Сначала завершите подготовку боя."
    elif battle_over:
        blocked = "Бой завершён."
    elif is_ai_turn():
        blocked = "Сейчас ходит ИИ. A — перейти к ручному управлению."
    elif concussion_skip_pending or (units.has(active) and units[active].concussion_turns_remaining > 0):
        blocked = "Контузия: дождитесь пропуска собственного хода."
    elif animation_time < ANIMATION_DURATION:
        blocked = "Дождитесь окончания анимации."
    elif selected_unit_id != active:
        blocked = "Сначала выберите активного бойца на поле."
    elif turns != null and not turns.can_act(active):
        blocked = "Действие этого хода уже потрачено."
    if not blocked.is_empty():
        preview.available = false
        preview.reason = blocked
    return preview


func unit_status(unit_id: String) -> String:
    if not units.has(unit_id):
        return ""
    var unit = units[unit_id]
    if not unit.is_alive():
        return "Повержен"
    if unit.concussion_turns_remaining > 0:
        return "Контузия: осталось %d собственных пропуска" % unit.concussion_turns_remaining
    if battle_over:
        return "Выжил"
    return "Ходит сейчас" if turns != null and turns.active_unit_id() == unit_id else "Ожидает своего хода"


func feedback_text() -> String:
    if turns == null or not units.has(turns.active_unit_id()):
        return ""
    var active: String = turns.active_unit_id()
    var actor = units[active]
    var target_id: String = board.unit_at(hovered_cell)
    if target_id.is_empty() and board.contains(hovered_cell) and selected_unit_id == active:
        var movement: Dictionary = movement_preview_for(hovered_cell)
        var distance_text: String = "Шаги по маршруту: %d · Лимит: %d" % [movement.steps, movement.budget] if movement.steps >= 0 else "Лимит перемещения: %d гекс." % movement.budget
        var action_hint: String = "ЛКМ — переместиться. Это расходует действие хода." if movement.available else "Выберите другой гекс или действие."
        return "[b]Маршрут · %s[/b]\n%s\n%s\n%s\nАрена: %s · Крестом отмечены непроходимые гексы." % [unit_label(active), movement.reason, distance_text, action_hint, arena_label()]
    if target_id.is_empty() or not units.has(target_id) or units[target_id].side == actor.side:
        var hint: String = "Выберите активного бойца, затем наведите на врага."
        if is_ai_turn():
            hint = "Ход красных выполняет ИИ; A — ручное управление."
        elif battle_over:
            hint = "Бой завершён. Откройте итоги или начните новый бой."
        elif actor.concussion_turns_remaining > 0:
            hint = unit_status(active) + "."
        var cost: int = actor.spell_mana_cost if casting_mode else (actor.special_skill.mana_cost if special_mode and actor.special_skill != null else 0)
        var minimum: int = maxi(1, actor.special_skill.min_range) if special_mode and actor.special_skill != null else 1
        var maximum: int = maxi(minimum, actor.special_skill.max_range) if special_mode and actor.special_skill != null else 1
        var ability_hint: String = "Дальность %d–%d гекс. · Расход %d MP · В запасе %d MP" % [minimum, maximum, cost, actor.mp]
        if casting_mode and actor.spell_power <= 0:
            ability_hint = "У этого бойца нет атакующего заклинания."
        elif special_mode and actor.special_skill == null:
            ability_hint = "У этого бойца нет дополнительного умения."
        return "[b]%s · %s[/b]\n%s\n%s\nОранжевое кольцо — доступная цель. Серое — атака недоступна.\nЗелёный гекс — движение. Движение расходует действие.\n%s: %s" % [unit_label(active), attack_mode_name(), hint, ability_hint, unit_label(inspected_unit_id), unit_status(inspected_unit_id)]
    var p: Dictionary = attack_preview_for(target_id)
    var status: String = "Доступно: ЛКМ по цели выполнит атаку." if p.available else "Недоступно: " + str(p.reason)
    if str(p.name) == "Атака":
        return "[b]Цель: %s[/b]\n%s" % [unit_label(target_id), status]
    var critical: String = " · Крит %d HP (%.1f%% при попадании)" % [p.critical_damage, p.crit_chance_pct] if p.crit_chance_pct > 0.0 else " · Без критов"
    var text: String = "[b]%s → %s[/b]\n%s\nУрон при попадании: %d HP%s\nПопадание %.1f%% · В среднем %.1f HP за попытку\nРасход %d MP · Дистанция %d / %d–%d · Защита цели %.1f%%" % [p.name, unit_label(target_id), status, p.normal_damage, critical, p.hit_chance_pct, p.expected_damage, p.cost, p.distance, p.min_range, p.max_range, p.defense_pct]
    var effect: String = "без взаимодействия"
    if p.attack_matter != Matter.NEUTRAL and p.defender_matter != Matter.NEUTRAL:
        if p.attack_matter == p.defender_matter:
            effect = "−15% к атаке"
        elif Matter.is_strong_against(p.attack_matter, p.defender_matter):
            effect = "−15 п.п. защиты цели"
    text += "\n%s → %s: %s" % [Matter.matter_name(p.attack_matter), Matter.matter_name(p.defender_matter), effect]
    if p.concussion_chance_pct > 0.0:
        text += "\nКонтузия %.0f%% после несмертельного попадания · %d своих пропуска" % [p.concussion_chance_pct, p.concussion_turns]
    return text


func refresh_feedback() -> void:
    if not is_instance_valid(feedback_ui) or preparing:
        return
    feedback_ui.present(feedback_text(), current_attack_mode(), not battle_over and not is_ai_turn())


func arena_label() -> String:
    if preparing and is_instance_valid(preparation_ui):
        return preparation_ui.setup.arena_label()
    return team_setup.arena_label() if encounter_index == TEAM_ENCOUNTER and team_setup != null else "Открытое поле"


func team_size_caption() -> String:
    if preparing and is_instance_valid(preparation_ui):
        return "%d НА %d" % [preparation_ui.setup.side_count("blue"), preparation_ui.setup.side_count("red")]
    var counts: Dictionary = {"blue": 0, "red": 0}
    for unit_id in roster_order:
        counts[units[unit_id].side] += 1
    return "%d НА %d" % [counts.blue, counts.red]


func movement_preview_for(cell: Vector2i) -> Dictionary:
    var active: String = turns.active_unit_id() if turns != null else ""
    var budget: int = units[active].movement if units.has(active) else 0
    var result: Dictionary = {"available": false, "reason": "", "steps": -1, "budget": budget, "path": []}
    if preparing:
        result.reason = "Сначала завершите подготовку боя."
    elif battle_over:
        result.reason = "Бой завершён."
    elif not units.has(active):
        result.reason = "Нет активного бойца."
    elif is_ai_turn():
        result.reason = "Сейчас ходит ИИ. A — ручное управление."
    elif concussion_skip_pending or units[active].concussion_turns_remaining > 0:
        result.reason = "Контузия: дождитесь пропуска собственного хода."
    elif animation_time < ANIMATION_DURATION:
        result.reason = "Дождитесь окончания анимации."
    elif selected_unit_id != active:
        result.reason = "Сначала выберите активного бойца."
    elif not turns.can_act(active):
        result.reason = "Действие этого хода уже потрачено."
    elif not board.contains(cell):
        result.reason = "Гекс находится за пределами поля."
    elif board.blocked.has(cell):
        result.reason = "Гекс закрыт препятствием. Выберите обход."
    elif cell == board.position_of(active):
        result.steps = 0
        result.reason = "Боец уже находится на этом гексе."
    elif not board.unit_at(cell).is_empty():
        result.reason = "Гекс занят бойцом. Выберите свободный гекс."
    else:
        result.path = board.shortest_path(board.position_of(active), cell, active)
        if result.path.is_empty():
            result.reason = "Свободного пути к этому гексу нет."
        else:
            result.steps = result.path.size() - 1
            result.available = result.steps <= budget
            result.reason = "Маршрут доступен: %d из %d шагов." % [result.steps, budget] if result.available else "До гекса нужно %d шагов, доступно %d. Выберите гекс ближе." % [result.steps, budget]
    return result


func battle_summary() -> Dictionary:
    var teams: Dictionary = {"blue": {"total": 0, "alive": 0, "fallen": 0}, "red": {"total": 0, "alive": 0, "fallen": 0}}
    var rows: Array[Dictionary] = []
    for unit_id in roster_order:
        var unit = units[unit_id]
        teams[unit.side].total += 1
        teams[unit.side]["alive" if unit.is_alive() else "fallen"] += 1
        rows.append({"label": unit_label(unit_id), "side": unit.side, "alive": unit.is_alive(), "hp": unit.hp, "max_hp": unit.max_hp})
    return {"winner_side": winner_side, "rounds": turns.round_number, "teams": teams, "units": rows}


func show_battle_results() -> void:
    if preparing or not battle_over or animation_time < ANIMATION_DURATION:
        return
    if not is_instance_valid(results_ui):
        results_ui = ResultsUI.new()
        results_ui.repeat_requested.connect(reset_demo)
        results_ui.preparation_requested.connect(open_preparation)
        results_ui.review_requested.connect(review_battle)
        results_ui.z_index = 50
        add_child(results_ui)
    results_ui.configure(battle_summary())
    results_ui.show()
    results_pending = false
    if is_instance_valid(feedback_ui):
        feedback_ui.hide()
    if results_button != null:
        results_button.show()


func review_battle() -> void:
    if is_instance_valid(results_ui):
        results_ui.hide()
    if is_instance_valid(feedback_ui):
        feedback_ui.show()
    refresh_feedback()
    queue_redraw()


func create_journal() -> void:
    journal = RichTextLabel.new()
    journal.name = "BattleLog"
    journal.position = LOG_POSITION
    journal.size = LOG_SIZE
    journal.bbcode_enabled = true
    journal.scroll_following = true
    journal.selection_enabled = true
    journal.fit_content = false
    journal.mouse_filter = Control.MOUSE_FILTER_STOP
    journal.add_theme_font_size_override("normal_font_size", 14)
    journal.add_theme_color_override("default_color", WHITE)
    journal.add_theme_color_override("font_selected_color", Color(0.92, 0.95, 1.0))
    journal.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
    add_child(journal)


func log_event(body: String, tint: String = "#dce5e7") -> void:
    if journal == null:
        return
    journal.append_text("[color=%s]%s[/color]\n" % [tint, body])


func reset_demo() -> void:
    results_pending = false
    if is_instance_valid(results_ui):
        results_ui.hide()
    if results_button != null:
        results_button.hide()
    if is_instance_valid(feedback_ui) and not preparing:
        feedback_ui.show()
    board = BattleBoard.new(demo_columns, demo_rows)
    var center_row: int = demo_rows / 2
    units.clear()
    roster_order.clear()
    if encounter_index == TEAM_ENCOUNTER and team_setup != null:
        populate_prepared_team(team_setup)
    elif encounter_index == TEAM_ENCOUNTER:
        # Reuse the v1.4 resources without introducing new balance values.
        var blue_stats: Array[SuleynUnitStats] = [ally_stats, enemy_stats, TEST_FALCON]
        var red_stats: Array[SuleynUnitStats] = [TEST_HELLHOUND, TEST_FALCON, TEST_LICH]
        var row_spacing: int = maxi(1, (demo_rows - 1) / 3)
        for slot in range(3):
            var blue_id: String = "ally_%d" % (slot + 1)
            var red_id: String = "enemy_%d" % (slot + 1)
            add_combatant(blue_id, "blue", blue_stats[slot], Vector2i(1, center_row + (slot - 1) * row_spacing))
            add_combatant(red_id, "red", red_stats[slot], Vector2i(demo_columns - 2, center_row + (slot - 1) * row_spacing))
    else:
        add_combatant(ALLY_ID, "blue", ally_stats, Vector2i(1, center_row))
        add_combatant(ENEMY_ID, "red", encounter_enemy_stats(), Vector2i(demo_columns - 2, center_row))
    turns = BattleTurns.new(roster_order)
    inspected_unit_id = turns.active_unit_id()
    selected_unit_id = ""
    hovered_cell = INVALID_CELL
    reachable.clear()
    battle_over = false
    winner_side = ""
    casting_mode = false
    special_mode = false
    visual_clock = 0.0
    reset_ai_wait()
    animation_stunned = false
    animation_time = ANIMATION_DURATION
    concussion_skip_pending = false
    concussion_preview_time = 0.0
    concussion_notice_time = 0.0
    concussion_notice_text = ""
    animation_attacker = ""
    animation_defender = ""
    message = "Ходит %s. Выберите бойца, затем зелёный гекс или противника." % unit_label(turns.active_unit_id())
    if journal != null:
        journal.clear()
    log_event("═══ НОВЫЙ БОЙ · v1.13 · СЦЕНАРИЙ %d/%d ═══" % [encounter_index + 1, ENCOUNTER_COUNT], "#ffdc86")
    log_event("Тестовая арена: %s. Закрытые гексы непроходимы." % arena_label(), "#b3d5e5")
    log_event("Управление: %s. Одно действие: движение, атака или пропуск." % control_description())
    if encounter_index == TEAM_ENCOUNTER:
        log_event("A — переключить ИИ красной команды и ручное управление.", "#ffda87")
    log_event("Фиксированная тестовая очередь; это не окончательное правило инициативы.", "#ffda87")
    for unit_id in roster_order:
        var unit = units[unit_id]
        log_event("%s · %s · %s · HP %d · MP %d." % [unit_label(unit_id),
            side_label(unit.side), Matter.matter_name(unit.matter), unit.max_hp, unit.max_mp])
    log_event("Монстры v1.4: тестовые параметры, баланс не утверждён. Броня отсутствует.", "#ffda87")
    log_event("T — сценарий; R — рестарт; 1 — удар; 2 — умение; F — магия; Space — пропуск.")
    log_event("Уклонение всех 5–90%; контузия — 2 отдельных пропуска собственных ходов.", "#ffda87")
    queue_redraw()


func add_combatant(unit_id: String, side: String, stats: SuleynUnitStats, cell: Vector2i) -> void:
    if not board.add_unit(unit_id, cell):
        push_error("Не удалось разместить бойца: %s" % unit_id)
        return
    units[unit_id] = make_unit(unit_id, side, stats)
    roster_order.append(unit_id)


func side_label(side: String) -> String:
    return "Синяя команда" if side == "blue" else "Красная команда"


func unit_token(unit_id: String) -> String:
    return unit_id.replace("ally_", "С").replace("enemy_", "К")


func can_perform_action(unit_id: String) -> bool:
    return (not preparing and not battle_over and not concussion_skip_pending
        and animation_time >= ANIMATION_DURATION and units.has(unit_id)
        and units[unit_id].is_alive() and units[unit_id].concussion_turns_remaining <= 0
        and turns.can_act(unit_id))


func ai_controls_unit(unit_id: String) -> bool:
    return (enemy_ai_enabled and encounter_index == TEAM_ENCOUNTER
        and units.has(unit_id) and units[unit_id].side == "red")


func is_ai_turn() -> bool:
    return not preparing and not battle_over and turns != null and ai_controls_unit(turns.active_unit_id())


func can_issue_action(unit_id: String, ai_action: bool = false) -> bool:
    return can_perform_action(unit_id) and ai_controls_unit(unit_id) == ai_action


func control_description() -> String:
    if encounter_index == TEAM_ENCOUNTER and enemy_ai_enabled:
        return "синие — игрок, красные — ИИ"
    return "обе команды вручную"


func reset_ai_wait() -> void:
    ai_waiting_unit_id = ""
    ai_delay_remaining = AI_THINK_SECONDS


func toggle_enemy_ai() -> void:
    if preparing or encounter_index != TEAM_ENCOUNTER:
        return
    enemy_ai_enabled = not enemy_ai_enabled
    reset_ai_wait()
    clear_selection()
    message = "Управление: %s. A — переключить." % control_description()
    log_event(message, "#b3d5e5")
    queue_redraw()


func update_ai(delta: float) -> void:
    if not is_ai_turn() or not can_perform_action(turns.active_unit_id()):
        reset_ai_wait()
        return
    var active: String = turns.active_unit_id()
    if ai_waiting_unit_id != active:
        ai_waiting_unit_id = active
        ai_delay_remaining = AI_THINK_SECONDS
    ai_delay_remaining = maxf(0.0, ai_delay_remaining - maxf(0.0, delta))
    if ai_delay_remaining > 0.0:
        return
    perform_ai_turn()
    reset_ai_wait()


func perform_ai_turn() -> void:
    if not is_ai_turn():
        return
    var active: String = turns.active_unit_id()
    if not can_perform_action(active):
        return
    var decision: Dictionary = BattleAI.choose_action(board, units, active)
    var saved_casting: bool = casting_mode
    var saved_special: bool = special_mode
    log_event("[b]ИИ · %s[/b]" % unit_label(active), "#f7acb0")
    match str(decision.get("kind", "pass")):
        "attack":
            var mode: String = str(decision.get("mode", "basic"))
            casting_mode = mode == "magic"
            special_mode = mode == "special"
            attack_enemy(active, str(decision.get("target_id", "")), -1.0, -1.0, -1.0, true)
        "move":
            move_active_unit(active, decision.get("cell", INVALID_CELL), true)
        _:
            pass_turn(true)
    # AI modes never overwrite the player's chosen mode for the next blue turn.
    casting_mode = saved_casting
    special_mode = saved_special
    # A stale/invalid plan must not leave an automated turn waiting forever.
    if not battle_over and turns.active_unit_id() == active and turns.can_act(active):
        pass_turn(true)
    queue_redraw()


func move_active_unit(unit_id: String, cell: Vector2i, ai_action: bool = false) -> bool:
    if not can_issue_action(unit_id, ai_action):
        return false
    var distances: Dictionary = board.reachable_from(
        board.position_of(unit_id), units[unit_id].movement, unit_id)
    var steps: int = int(distances.get(cell, 0))
    if steps <= 0 or not board.move_unit(unit_id, cell):
        return false
    var round_before: int = turns.round_number
    turns.spend_action(unit_id)
    var regen: int = end_active_turn(unit_id)
    clear_selection()
    message = "%s переместился на %d гекса. Теперь ходит %s." % [
        unit_label(unit_id), steps, unit_label(turns.active_unit_id())]
    log_event("Раунд %d · %s: движение на %d гекса; MP +%d." % [
        round_before, unit_label(unit_id), steps, regen], "#b9d6ec")
    queue_redraw()
    return true


func make_unit(unit_id: String, side: String, stats: SuleynUnitStats):
    var health: int = stats.max_hp
    if stats.commander != null:
        health = stats.commander.max_hp()
    var unit = BattleUnit.new(unit_id, side, health, stats.attack,
        stats.defense, stats.movement, stats.display_name)
    if stats.magic_spell != null:
        unit.spell_power = stats.magic_spell.spell_power
        unit.spell_mana_cost = stats.magic_spell.mana_cost
        if stats.magic_spell.magic_book != null:
            unit.spell_matter = stats.magic_spell.magic_book.matter
    unit.special_skill = stats.special_skill
    if stats.melee_skill != null:
        unit.melee_skill_power = stats.melee_skill.skill_power
        unit.melee_damage_type = stats.melee_skill.damage_type
    else:
        unit.melee_skill_power = stats.attack
    if stats.monster != null and stats.commander == null:
        unit.is_monster = true
        unit.monster_categories = stats.monster.categories
        unit.base_pdef_pct = stats.monster.base_pdef_pct
        unit.base_mdef_pct = stats.monster.base_mdef_pct
        unit.display_name = stats.monster.display_name
        unit.matter = stats.monster.matter
        unit.evasion_pct = Rules.final_evasion(stats.monster.evasion_pct)
        unit.physical_damage_bonus_pct = Rules.cap_percent(stats.monster.physical_damage_bonus_pct)
        unit.crit_chance_pct = Rules.cap_chance(stats.monster.crit_chance_pct)
        unit.max_mp = maxi(0, stats.monster.max_mp)
        unit.mp = unit.max_mp
        if stats.monster.critical_passive != null:
            unit.critical_multiplier = stats.monster.critical_passive.crit_multiplier
    if stats.commander != null:
        if not stats.commander.valid_allocation():
            push_warning("Некорректный бюджет очков: %s" % stats.display_name)
        unit.level = stats.commander.level
        unit.matter = stats.commander.resolved_matter()
        unit.critical_multiplier = stats.commander.critical_multiplier()
        unit.max_mp = stats.commander.max_mp()
        unit.mp = unit.max_mp
        unit.armor = stats.commander.armor_name()
        unit.attributes = stats.commander.primary_stats()
        unit.unspent_points = stats.commander.points_unspent()
        var a: Dictionary = unit.attributes
        unit.physical_damage_bonus_pct = minf(90.0, float(a["STR"]) * 2.0)
        unit.evasion_pct = Rules.final_evasion(float(a["AGI"]) * 0.5 + float(stats.commander.armor_evasion_bonus()))
        unit.crit_chance_pct = clampf(float(a["AGI"]) * 0.5, 0.0, 90.0)
        unit.physical_resistance_pct = 0.0
        unit.base_pdef_pct = 0.0
        unit.base_mdef_pct = 0.0
        unit.armor_pdef_pct = float(stats.commander.armor_pdef_bonus())
        unit.armor_mdef_pct = float(stats.commander.armor_mdef_bonus())
        unit.armor_weapon_bonuses = {
            0: float(stats.commander.armor_weapon_bonus(0)),
            1: float(stats.commander.armor_weapon_bonus(1)),
            2: float(stats.commander.armor_weapon_bonus(2)),
        }
        unit.magic_power_pct = minf(90.0, float(a["INT"]) * 2.0)
        unit.mana_regen_pct = clampf(float(a["WIS"]) * 0.3, 0.0, 90.0)
        unit.magic_resistance_pct = minf(90.0, float(a["WIS"]) * 2.0)
    return unit


func _process(delta: float) -> void:
    if preparing:
        return
    var animation_was_playing: bool = animation_time < ANIMATION_DURATION
    var concussion_was_pending: bool = concussion_skip_pending
    visual_clock += delta
    if animation_time < ANIMATION_DURATION:
        animation_time = minf(ANIMATION_DURATION, animation_time + delta)
        queue_redraw()
    if concussion_notice_time > 0.0:
        concussion_notice_time = maxf(0.0, concussion_notice_time - delta)
        queue_redraw()
    if concussion_skip_pending:
        # Do not spend a skipped turn while the hit animation is still playing.
        # The target keeps BOTH pending skips (and visible stars) until the pause ends.
        if animation_time >= ANIMATION_DURATION:
            concussion_preview_time -= delta
            if concussion_preview_time <= 0.0:
                resolve_one_concussion_skip()
        queue_redraw()
    else:
        for unit_id in units:
            if units[unit_id].is_alive() and units[unit_id].concussion_turns_remaining > 0:
                queue_redraw()  # Rotate stars between the first and second skip.
                break
    # A newly available AI turn starts its own pause on the following frame.
    if not animation_was_playing and not concussion_was_pending:
        update_ai(delta)
    if battle_over and results_pending and animation_time >= ANIMATION_DURATION:
        show_battle_results()
    refresh_feedback()


func _input(event: InputEvent) -> void:
    # Keep hover feedback current even when a journal or button consumes motion.
    if event is InputEventMouseMotion and board != null:
        var cell: Vector2i = cell_under_cursor()
        if cell != hovered_cell:
            hovered_cell = cell
            queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
    if is_instance_valid(commander_editor) and commander_editor.visible:
        if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
            close_commander_editor()
        return
    if is_instance_valid(library_ui) and library_ui.visible:
        if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
            close_setup_library()
        return
    if preparing:
        if event is InputEventMouseMotion:
            hovered_cell = cell_under_cursor()
            queue_redraw()
        elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            preparation_ui.handle_board_click(cell_under_cursor())
        return
    if is_instance_valid(results_ui) and results_ui.visible:
        if event is InputEventKey and event.pressed and not event.echo:
            if event.keycode == KEY_R:
                reset_demo()
            elif event.keycode == KEY_P:
                open_preparation()
            elif event.keycode == KEY_T:
                switch_encounter()
        return
    if event is InputEventMouseMotion:
        var new_hover: Vector2i = cell_under_cursor()
        if new_hover != hovered_cell:
            hovered_cell = new_hover
            queue_redraw()
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            var point: Vector2 = get_local_mouse_position()
            if point.x >= 895 and point.x <= 1393 and point.y >= 172 and point.y < 172 + roster_order.size() * 25:
                inspected_unit_id = roster_order[int((point.y - 172) / 25)]
                queue_redraw()
            else:
                click_cell(cell_under_cursor())
    elif event is InputEventKey:
        if event.pressed and not event.echo:
            if event.keycode == KEY_P:
                open_preparation()
            elif event.keycode == KEY_R:
                reset_demo()
            elif event.keycode == KEY_T:
                switch_encounter()
            elif event.keycode == KEY_A:
                toggle_enemy_ai()
            elif event.keycode == KEY_SPACE:
                pass_turn()
            elif event.keycode == KEY_M:
                debug_spend_mana()
            elif event.keycode == KEY_1 and not is_ai_turn():
                set_attack_mode("basic")
            elif event.keycode == KEY_2 and not is_ai_turn():
                set_attack_mode("special")
            elif event.keycode == KEY_F and not is_ai_turn():
                set_attack_mode("basic" if casting_mode else "magic")


func cell_under_cursor() -> Vector2i:
    var point: Vector2 = get_local_mouse_position() - BOARD_ORIGIN
    var cell: Vector2i = Hex.pixel_to_axial(point, hex_radius)
    if not board.contains(cell):
        return INVALID_CELL
    var center: Vector2 = Hex.axial_to_pixel(cell, hex_radius)
    if not Hex.point_in_hex(point, center, hex_radius):
        return INVALID_CELL
    return cell


func click_cell(cell: Vector2i, ai_action: bool = false) -> void:
    if battle_over or concussion_skip_pending or not board.contains(cell) or animation_time < ANIMATION_DURATION:
        return
    var active: String = turns.active_unit_id()
    var clicked_unit: String = board.unit_at(cell)
    if not clicked_unit.is_empty():
        inspected_unit_id = clicked_unit
    if not can_issue_action(active, ai_action):
        if is_ai_turn():
            message = "Ход красной команды выполняет ИИ. A — ручное управление."
        queue_redraw()
        return
    if clicked_unit == active:
        selected_unit_id = active
        refresh_reachable()
        message = "%s выбран. Зелёный гекс — движение; враг — выбранная атака." % unit_label(active)
    elif not clicked_unit.is_empty():
        if units[clicked_unit].side == units[active].side:
            message = "%s — союзник. Сейчас ходит %s." % [unit_label(clicked_unit), unit_label(active)]
        elif selected_unit_id != active:
            message = "Сначала выберите активного героя: %s." % unit_label(active)
        elif not can_target_with_mode(active, clicked_unit):
            message = str(attack_preview_for(clicked_unit).reason)
        else:
            attack_enemy(active, clicked_unit, -1.0, -1.0, -1.0, ai_action)
    elif selected_unit_id == active:
        var movement: Dictionary = movement_preview_for(cell)
        if not movement.available:
            message = str(movement.reason)
        else:
            if not move_active_unit(active, cell, ai_action):
                message = "Выберите другой свободный гекс или нажмите Space для пропуска."
    else:
        message = "Выберите %s; 1 — удар, 2 — умение, F — магия." % unit_label(active)
    queue_redraw()


func can_target_with_mode(attacker_id: String, defender_id: String) -> bool:
    return bool(AttackPreview.evaluate(board, units, attacker_id, defender_id, current_attack_mode()).available)


func attack_enemy(attacker_id: String, defender_id: String, dodge_roll: float = -1.0,
        crit_roll: float = -1.0, concussion_roll: float = -1.0, ai_action: bool = false) -> void:
    if not can_issue_action(attacker_id, ai_action) or not units.has(defender_id):
        return
    var attack_is_magic: bool = casting_mode
    var attack_is_special: bool = special_mode and not attack_is_magic
    var defender_location: Vector2 = center_of(board.position_of(defender_id))
    var attacker_location: Vector2 = center_of(board.position_of(attacker_id))
    var round_before: int = turns.round_number
    var result: Dictionary = {}
    if attack_is_magic:
        result = BattleCombat.magic_attack(board, units, attacker_id, defender_id)
    elif attack_is_special:
        result = BattleCombat.skill_attack(board, units, attacker_id, defender_id,
            units[attacker_id].special_skill, dodge_roll, crit_roll, concussion_roll)
    else:
        result = BattleCombat.melee_attack(board, units, attacker_id, defender_id, dodge_roll, crit_roll)
    if not result.get("ok", false):
        message = str(result.get("reason", "Атака невозможна."))
        log_event("%s: %s" % [unit_label(attacker_id), message], "#ffac96")
        return

    animation_time = 0.0
    animation_attacker = attacker_id
    animation_defender = defender_id
    animation_direction = (defender_location - attacker_location).normalized()
    animation_target_position = defender_location
    animation_damage = int(result.get("damage", 0))
    animation_evaded = bool(result.get("evaded", false))
    animation_crit = bool(result.get("critical", false))
    animation_stunned = bool(result.get("concussion_applied", false))

    var attacker = units[attacker_id]
    var defender = units[defender_id]
    var attack_name: String = "магия" if attack_is_magic else str(result.get("skill_name", "Обычный удар"))
    var skill_power: int = int(result.get("spell_power", 0)) if attack_is_magic else int(result.get("skill_power", 0))
    var cost: int = int(result.get("spell_cost", 0)) if attack_is_magic else int(result.get("skill_cost", 0))
    log_event("[b]Раунд %d · %s → %s[/b] · %s (сила %d; расход %d MP)" % [
        round_before, unit_label(attacker_id), unit_label(defender_id), attack_name, skill_power, cost], "#ffe7a5")

    if not attack_is_magic:
        var dodge_pct: float = float(result.get("evasion_percent", defender.evasion_pct))
        var logged_dodge_roll: float = float(result.get("dodge_roll", -1.0))
        log_event("  Уклонение: шанс %.1f%%, бросок %.2f." % [dodge_pct, logged_dodge_roll])
        if result["evaded"]:
            log_event("  [b]УКЛОНЕНИЕ![/b] Урон 0; HP %d/%d." % [defender.hp, defender.max_hp], "#86e9c0")
        else:
            log_event("  Крит: шанс %.1f%%, бросок %.2f. PDEF цели %.1f%%." % [
                float(result["critical_percent"]), float(result["crit_roll"]),
                float(result["pdef_percent"])])
            if result["critical"]:
                log_event("  [b]КРИТ ×%.2f![/b]" % float(result["critical_multiplier"]), "#ffbd73")
            if float(result.get("concussion_chance_pct", 0.0)) > 0.0 and not bool(result.get("defeated", false)):
                log_event("  Контузия: шанс %.0f%%, бросок %.2f." % [
                    float(result["concussion_chance_pct"]), float(result["concussion_roll"])])
                if bool(result.get("concussion_applied", false)):
                    log_event("  [b]КОНТУЗИЯ![/b] Цель пропустит 2 своих хода.", "#ffd36e")
    else:
        log_event("  Книга: %s · MDEF цели %.1f%% · критов и уклонений нет." % [
            Matter.matter_name(attacker.spell_matter), float(result["mdef_percent"])])

    turns.spend_action(attacker_id)
    var regen: int = attacker.regenerate_mana_end_turn()
    if not result["evaded"]:
        var overkill_note: String = " (расчёт %d)" % int(result["calculated_damage"]) if int(result["damage"]) != int(result["calculated_damage"]) else ""
        log_event("  Урон: [b]%d HP[/b]%s. У цели осталось %d/%d HP." % [
            int(result["damage"]), overkill_note, defender.hp, defender.max_hp], "#ffb5b5")
    log_event("  %s: MP %d/%d (регенерация +%d)." % [
        unit_label(attacker_id), attacker.mp, attacker.max_mp, regen], "#9dc8ff")

    if result["evaded"]:
        advance_turn(attacker_id)
        message = "%s УВЕРНУЛСЯ от атаки %s!" % [unit_label(defender_id), unit_label(attacker_id)]
    elif result["defeated"]:
        turns.remove_unit(defender_id)
        if not opponents_alive(attacker.side):
            battle_over = true
            winner_side = attacker.side
            results_pending = true
            concussion_skip_pending = false
            message = "%s победила! R — повтор; P — изменить составы." % side_label(winner_side)
            log_event("  [b]ПОБЕДА: %s![/b]" % side_label(winner_side), "#ffe080")
        else:
            advance_turn(attacker_id)
            message = "%s повержен." % unit_label(defender_id)
    else:
        advance_turn(attacker_id)
        var crit_notice: String = " КРИТ!" if result["critical"] else ""
        var stun_notice: String = " КОНТУЗИЯ!" if bool(result.get("concussion_applied", false)) else ""
        message = "%s наносит %d урона %s.%s%s" % [unit_label(attacker_id),
            int(result["damage"]), unit_label(defender_id), crit_notice, stun_notice]
    clear_selection()
    queue_redraw()


func end_active_turn(unit_id: String) -> int:
    if preparing or battle_over or unit_id != turns.active_unit_id() or not units.has(unit_id):
        return 0
    var regenerated: int = units[unit_id].regenerate_mana_end_turn()
    advance_turn(unit_id)
    return regenerated


func advance_turn(previous_id: String) -> void:
    if not preparing and not battle_over and turns.next_turn(previous_id):
        reset_ai_wait()
        inspected_unit_id = turns.active_unit_id()
        prepare_next_concussion_skip()


func prepare_next_concussion_skip() -> void:
    # A concussion skip is a separate, visible turn event. Do not decrement
    # the counter immediately after the attack that inflicted the condition.
    concussion_skip_pending = false
    if battle_over:
        return
    var active: String = turns.active_unit_id()
    if active.is_empty() or not units.has(active):
        return
    var unit = units[active]
    if unit.is_alive() and unit.concussion_turns_remaining > 0:
        concussion_skip_pending = true
        concussion_preview_time = CONCUSSION_PREVIEW_SECONDS
        clear_selection()
        queue_redraw()


func resolve_one_concussion_skip() -> void:
    # Called once per stunned character's turn opportunity, never twice for
    # the same opportunity. Other living units get their turns between skips.
    if preparing or not concussion_skip_pending:
        return
    concussion_skip_pending = false
    concussion_preview_time = 0.0
    if battle_over:
        return
    var active: String = turns.active_unit_id()
    if active.is_empty() or not units.has(active):
        return
    var unit = units[active]
    if not unit.skip_concussed_turn():
        return
    var round_before: int = turns.round_number
    var skip_total: int = maxi(1, unit.concussion_total_turns)
    var skip_number: int = skip_total - unit.concussion_turns_remaining
    var regen: int = unit.regenerate_mana_end_turn()
    concussion_notice_text = "%s: ПРОПУСК %d из %d!" % [unit_label(active), skip_number, skip_total]
    concussion_notice_time = CONCUSSION_NOTICE_SECONDS
    message = "%s пропускает ход %d из %d (контузия). Осталось: %d." % [
        unit_label(active), skip_number, skip_total, unit.concussion_turns_remaining]
    log_event("[b]Раунд %d · %s: ПРОПУСК %d из %d (КОНТУЗИЯ)![/b] Осталось: %d. MP +%d." % [
        round_before, unit_label(active), skip_number, skip_total,
        unit.concussion_turns_remaining, regen], "#ffda87")
    clear_selection()
    advance_turn(active)
    queue_redraw()


func debug_spend_mana() -> void:
    if battle_over or concussion_skip_pending:
        return
    var active: String = turns.active_unit_id()
    if not can_issue_action(active):
        return
    if units[active].spend_mana(20):
        message = "%s потратил 20 MP. Регенерация произойдёт в конце хода." % unit_label(active)
        log_event("%s потратил 20 MP (тест). Осталось %d/%d." % [
            unit_label(active), units[active].mp, units[active].max_mp], "#b0cdf5")
    else:
        message = "Недостаточно MP для тестового расхода."
    queue_redraw()


func opponents_alive(attacker_side: String) -> bool:
    for unit_id in units:
        var unit = units[unit_id]
        if unit.side != attacker_side and unit.is_alive():
            return true
    return false


func pass_turn(ai_action: bool = false) -> void:
    if battle_over or concussion_skip_pending or animation_time < ANIMATION_DURATION:
        return
    var active: String = turns.active_unit_id()
    if not can_issue_action(active, ai_action):
        return
    var round_before: int = turns.round_number
    turns.spend_action(active)
    var regen: int = end_active_turn(active)
    clear_selection()
    message = "%s пропустил ход (MP +%d). Теперь ходит %s." % [
        unit_label(active), regen, unit_label(turns.active_unit_id())]
    log_event("Раунд %d · %s: ПРОПУСК ХОДА (MP +%d)." % [
        round_before, unit_label(active), regen], "#bac7d9")
    queue_redraw()


func clear_selection() -> void:
    selected_unit_id = ""
    reachable.clear()


func unit_label(unit_id: String) -> String:
    if not units.has(unit_id):
        return unit_id
    var unit = units[unit_id]
    var name: String = unit.display_name
    if not unit.is_monster:
        name = "Мужчина" if unit.melee_damage_type == Rules.BLUNT else "Женщина"
    return "%s · %s" % [unit_token(unit_id), name] if encounter_index == TEAM_ENCOUNTER else name


func refresh_reachable() -> void:
    reachable.clear()
    if not preparing and not battle_over and selected_unit_id == turns.active_unit_id():
        reachable = board.reachable_from(
            board.position_of(selected_unit_id), units[selected_unit_id].movement, selected_unit_id)


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, Vector2(1440, 900)), BACKGROUND)
    if preparing and is_instance_valid(preparation_ui) and preparation_ui.stage == "roster":
        return
    draw_rect(Rect2(Vector2(28, 98), Vector2(823, 679)), Color(0.10, 0.14, 0.18), true)
    draw_rect(Rect2(Vector2(879, 98), Vector2(530, 735)), Color(0.12, 0.18, 0.23), true)
    draw_text(Vector2(35, 47), "СУЛЭЙН  /  РАССТАНОВКА" if preparing else "СУЛЭЙН  /  КОМАНДНЫЙ БОЙ", 27, WHITE)
    var encounter_caption: String = team_size_caption() if encounter_index == TEAM_ENCOUNTER else "ДУЭЛЬ"
    var heading: String = "v1.13 · %s · %s · СИНИЕ СЛЕВА, КРАСНЫЕ СПРАВА" % [team_size_caption(), arena_label()] if preparing else "v1.13 · %s · %s · T — СЦЕНАРИЙ %d/5" % [encounter_caption, arena_label(), encounter_index + 1]
    draw_text(Vector2(36, 78), heading, 16, MUTED)

    for r in range(board.rows):
        for q in range(board.columns):
            var cell := Vector2i(q, r)
            var center: Vector2 = center_of(cell)
            var points: PackedVector2Array = hex_vertices(center)
            var fill: Color = HEX_DARK if (q + r) % 2 == 0 else HEX_LIGHT
            if board.blocked.has(cell):
                fill = Color(0.25, 0.25, 0.28)
            elif preparing:
                if preparation_ui.setup.cell_is_deployment("blue", cell):
                    fill = fill.lerp(ALLY, 0.28)
                elif preparation_ui.setup.cell_is_deployment("red", cell):
                    fill = fill.lerp(ENEMY, 0.28)
                var side: String = preparation_ui.setup.team_for(selected_unit_id)
                if preparation_ui.setup.cell_is_deployment(side, cell) and board.unit_at(cell).is_empty():
                    fill = fill.lerp(AVAILABLE, 0.4)
            elif reachable.has(cell) and board.unit_at(cell).is_empty():
                fill = AVAILABLE
            if cell == hovered_cell:
                fill = fill.lerp(HOVER, 0.45)
            draw_colored_polygon(points, fill)
            var outline: PackedVector2Array = points.duplicate()
            outline.append(points[0])
            draw_polyline(outline, HEX_EDGE, 1.4, true)
            if board.blocked.has(cell):
                draw_circle(center, hex_radius * 0.47, Color(0.12, 0.14, 0.18))
                draw_line(center + Vector2(-8, -8), center + Vector2(8, 8), MUTED, 3.0, true)
                draw_line(center + Vector2(-8, 8), center + Vector2(8, -8), MUTED, 3.0, true)

    draw_hover_path()
    for unit_id in roster_order:
        draw_unit(unit_id, ALLY if units[unit_id].side == "blue" else ENEMY)
    if preparing:
        draw_text(Vector2(40, 810), "Выберите бойца на поле или справа, затем свободный гекс своей зоны.", 16, WHITE)
        draw_text(Vector2(40, 839), "Составы и расстановка тестовые. Действия боя начнутся после кнопки «Начать бой».", 14, MUTED)
        draw_text(Vector2(40, 872), "Выбран: %s" % unit_label(selected_unit_id), 16, PATH_COLOR)
        return
    draw_damage_popup()
    draw_concussion_turn_notice()
    draw_sidebar()
    draw_instructions()


func draw_hover_path() -> void:
    if preparing or battle_over or selected_unit_id != turns.active_unit_id():
        return
    var preview: Dictionary = movement_preview_for(hovered_cell)
    var path: Array = preview.path
    if path.size() < 2:
        return
    for i in range(1, path.size()):
        draw_line(center_of(path[i - 1]), center_of(path[i]), PATH_COLOR if i <= preview.budget else MUTED.darkened(0.25), 4.0, true)
    var at: Vector2 = center_of(hovered_cell) + Vector2(-22, -26)
    draw_rect(Rect2(at, Vector2(48, 21)), BACKGROUND, true)
    draw_text(at + Vector2(5, 16), "%d/%d" % [preview.steps, preview.budget], 14, PATH_COLOR if preview.available else MUTED)


func draw_unit(unit_id: String, fill: Color) -> void:
    if not units.has(unit_id) or not units[unit_id].is_alive():
        return
    var cell: Vector2i = board.position_of(unit_id)
    if not board.contains(cell):
        return
    var center: Vector2 = center_of(cell)
    if selected_unit_id == unit_id:
        draw_arc(center, hex_radius * 0.88, 0.0, TAU, 48, PATH_COLOR, 3.0, true)
    if not preparing and not battle_over and turns.active_unit_id() == unit_id:
        draw_arc(center, hex_radius * 0.98, 0.0, TAU, 48, PATH_COLOR, 2.0, true)
    if not preparing and not battle_over and selected_unit_id == turns.active_unit_id() and selected_unit_id != unit_id:
        if units[selected_unit_id].side != units[unit_id].side:
            var target_preview: Dictionary = attack_preview_for(unit_id)
            draw_arc(center, hex_radius * 1.06, 0.0, TAU, 48, ATTACK_COLOR if target_preview.available else MUTED.darkened(0.25), 3.0 if target_preview.available else 1.0, true)

    draw_arc(center, hex_radius * 0.78, 0.0, TAU, 48, fill, 3.0, true)
    if encounter_index == TEAM_ENCOUNTER:
        draw_text(center + Vector2(-9, -39), unit_token(unit_id), 12, fill.lightened(0.3))
    var phase: float = animation_time / ANIMATION_DURATION
    var lunge: float = 0.0
    var shake: float = 0.0
    if animation_time < ANIMATION_DURATION:
        if unit_id == animation_attacker:
            lunge = sin(PI * phase) * 15.0
        elif unit_id == animation_defender and not animation_evaded:
            shake = sin(phase * PI * 8.0) * 3.5 * (1.0 - phase)
        elif unit_id == animation_defender and animation_evaded:
            lunge = -sin(PI * phase) * 10.0
    var animated_center: Vector2 = center + animation_direction * (lunge + shake)
    if units[unit_id].is_monster:
        draw_monster_figurine(animated_center, units[unit_id].monster_categories, units[unit_id].matter)
    else:
        draw_hero_figurine(animated_center, units[unit_id].melee_damage_type == Rules.BLUNT, fill)
    draw_vitals(center, units[unit_id])
    if units[unit_id].concussion_turns_remaining > 0:
        draw_concussion_stars(animated_center, units[unit_id].concussion_turns_remaining)


func draw_hero_figurine(center: Vector2, heavy_male: bool, team_color: Color) -> void:
    # Drawn entirely with Godot primitives, no external textures or fonts.
    # Looking right: heavy man with mace. Looking left: light woman with spear.
    var face: float = 1.0 if heavy_male else -1.0
    var dark: Color = Color(0.13, 0.19, 0.23)
    var skin: Color = Color(0.95, 0.73, 0.59)
    var local: Vector2 = center + Vector2(0, -10)
    draw_circle(center + Vector2(0, 13), 13.0, Color(0.02, 0.05, 0.07, 0.55))
    draw_rect(Rect2(local + Vector2(-10, 10), Vector2(8, 13)), dark)
    draw_rect(Rect2(local + Vector2(3, 10), Vector2(8, 13)), dark)
    draw_rect(Rect2(local + Vector2(-11, 16), Vector2(10, 6)), Color(0.25, 0.27, 0.30))
    draw_rect(Rect2(local + Vector2(3, 16), Vector2(10, 6)), Color(0.25, 0.27, 0.30))
    # torso armor
    var torso: PackedVector2Array = PackedVector2Array([
        local + Vector2(-14, -4), local + Vector2(14, -4),
        local + Vector2(12, 14), local + Vector2(-12, 14)])
    draw_colored_polygon(torso, Color(0.66, 0.72, 0.81) if heavy_male else team_color)
    draw_line(local + Vector2(-10, 5), local + Vector2(10, 5),
        Color(0.29, 0.34, 0.41) if heavy_male else Color(0.95, 0.76, 0.39), 3.0)
    draw_rect(Rect2(local + Vector2(-16, -3), Vector2(5, 15)),
        Color(0.50, 0.56, 0.67) if heavy_male else skin)
    draw_rect(Rect2(local + Vector2(11, -3), Vector2(5, 15)),
        Color(0.50, 0.56, 0.67) if heavy_male else skin)
    draw_circle(local + Vector2(0, -15), 10.5, skin)
    if heavy_male:
        draw_rect(Rect2(local + Vector2(-11, -24), Vector2(22, 8)), Color(0.66, 0.73, 0.81))
        draw_rect(Rect2(local + Vector2(-9, -19), Vector2(18, 4)), Color(0.38, 0.45, 0.54))
        draw_line(local + Vector2(0, -19), local + Vector2(0, -12), dark, 2.0)
        # mace, raised to the right
        draw_line(local + Vector2(face * 13, 3), local + Vector2(face * 25, -17), Color(0.65, 0.47, 0.27), 4.0)
        draw_circle(local + Vector2(face * 27, -19), 7.0, Color(0.72, 0.76, 0.81))
        draw_line(local + Vector2(face * 23, -22), local + Vector2(face * 31, -22), dark, 2.0)
    else:
        # ponytail, leather light armor and a long spear
        draw_circle(local + Vector2(8, -17), 8.0, Color(0.43, 0.20, 0.17))
        draw_rect(Rect2(local + Vector2(-9, -26), Vector2(18, 7)), Color(0.49, 0.26, 0.19))
        draw_line(local + Vector2(face * 8, 7), local + Vector2(face * 32, -16), Color(0.66, 0.45, 0.22), 3.0)
        var tip := PackedVector2Array([
            local + Vector2(face * 32, -24),
            local + Vector2(face * 27, -12),
            local + Vector2(face * 38, -18)])
        draw_colored_polygon(tip, Color(0.84, 0.88, 0.90))
    # colored waist stripe makes team differentiation obvious.
    draw_line(local + Vector2(-10, 12), local + Vector2(10, 12), team_color, 3.0)


func draw_monster_figurine(center: Vector2, categories: int, material: int) -> void:
    # Test-only primitive silhouettes: winged bird, quadruped, undead spellcaster.
    var body_color: Color = Color(0.58, 0.76, 0.83) if material == Matter.WIND else (
        Color(0.86, 0.40, 0.28) if material == Matter.FIRE else Color(0.56, 0.42, 0.73))
    draw_circle(center + Vector2(0, 15), 13.0, Color(0.02, 0.05, 0.07, 0.55))
    if (categories & Rules.FLYING) != 0:
        var left_wing: PackedVector2Array = PackedVector2Array([
            center + Vector2(-5, -5), center + Vector2(-36, -23),
            center + Vector2(-25, 5), center + Vector2(-7, 9)])
        var right_wing: PackedVector2Array = PackedVector2Array([
            center + Vector2(5, -5), center + Vector2(36, -23),
            center + Vector2(25, 5), center + Vector2(7, 9)])
        draw_colored_polygon(left_wing, body_color)
        draw_colored_polygon(right_wing, body_color)
        draw_circle(center + Vector2(0, -6), 12.0, body_color)
        draw_circle(center + Vector2(0, -18), 7.0, body_color.lightened(0.2))
        draw_colored_polygon(PackedVector2Array([center + Vector2(-3, -18),
            center + Vector2(4, -18), center + Vector2(1, -10)]), Color(1, 0.75, 0.22))
    elif (categories & Rules.MAGICAL_UNDEAD) != 0:
        draw_colored_polygon(PackedVector2Array([center + Vector2(0, -30),
            center + Vector2(-18, 20), center + Vector2(18, 20)]), body_color)
        draw_circle(center + Vector2(0, -15), 11.0, Color(0.16, 0.14, 0.23))
        draw_circle(center + Vector2(-4, -16), 2.0, Color(0.53, 0.96, 0.97))
        draw_circle(center + Vector2(4, -16), 2.0, Color(0.53, 0.96, 0.97))
        draw_line(center + Vector2(20, 19), center + Vector2(22, -26), Color(0.84, 0.76, 0.60), 4.0)
    else:
        draw_circle(center + Vector2(-2, -6), 16.0, body_color)
        draw_circle(center + Vector2(12, -17), 10.0, body_color)
        draw_line(center + Vector2(-12, 0), center + Vector2(-18, 18), body_color.darkened(0.2), 5.0)
        draw_line(center + Vector2(9, 0), center + Vector2(15, 18), body_color.darkened(0.2), 5.0)
        draw_circle(center + Vector2(15, -19), 2.5, Color(0.96, 0.88, 0.27))


func draw_concussion_stars(center: Vector2, remaining: int) -> void:
    # Procedurally animated five-point stars, no image assets required.
    var drift: float = visual_clock * 2.6
    for i in range(3):
        var orbit: float = drift + float(i) * TAU / 3.0
        var star_center: Vector2 = center + Vector2(
            cos(orbit) * 19.0, -49.0 + sin(orbit) * 4.0)
        draw_five_point_star(star_center, 6.0, drift * 0.5 + float(i), Color(1.0, 0.86, 0.29))
    draw_text(center + Vector2(-36, -62), "КОНТУЗИЯ ×%d" % remaining, 11, PATH_COLOR)


func draw_concussion_turn_notice() -> void:
    if not concussion_skip_pending and concussion_notice_time <= 0.0:
        return
    var text_line: String = concussion_notice_text
    if concussion_skip_pending:
        var active: String = turns.active_unit_id()
        if units.has(active):
            var unit = units[active]
            var total: int = maxi(1, unit.concussion_total_turns)
            var current: int = total - unit.concussion_turns_remaining + 1
            text_line = "%s КОНТУЖЕН: пропуск %d из %d" % [unit_label(active), current, total]
    draw_rect(Rect2(Vector2(120, 105), Vector2(690, 47)), Color(0.30, 0.21, 0.08, 0.95), true)
    draw_rect(Rect2(Vector2(120, 105), Vector2(690, 47)), PATH_COLOR, false, 2.0)
    draw_text(Vector2(137, 135), text_line, 20, PATH_COLOR)


func draw_five_point_star(at: Vector2, radius: float, turn: float, fill: Color) -> void:
    var star := PackedVector2Array()
    for point_index in range(10):
        var direction: float = -PI / 2.0 + turn + float(point_index) * PI / 5.0
        var size: float = radius if point_index % 2 == 0 else radius * 0.43
        star.append(at + Vector2(cos(direction), sin(direction)) * size)
    draw_colored_polygon(star, fill)


func draw_vitals(center: Vector2, unit) -> void:
    var rect: Rect2 = Rect2(center + Vector2(-35, 23), Vector2(70, 27))
    draw_rect(rect, Color(0.055, 0.092, 0.14, 0.93), true)
    draw_rect(rect, Color(0.49, 0.56, 0.63, 0.73), false, 1.0)
    draw_text(center + Vector2(-30, 34), "HP %d/%d" % [unit.hp, unit.max_hp], 10, HEALTH_COLOR)
    draw_text(center + Vector2(-30, 46), "MP %d/%d" % [unit.mp, unit.max_mp], 10, MANA_COLOR)


func draw_damage_popup() -> void:
    if animation_time >= ANIMATION_DURATION:
        return
    var phase: float = animation_time / ANIMATION_DURATION
    var at: Vector2 = animation_target_position + Vector2(-39, -48 - 20 * phase)
    var txt: String = "УКЛОН!" if animation_evaded else ("КРИТ -%d" % animation_damage if animation_crit else "-%d HP" % animation_damage)
    draw_rect(Rect2(at + Vector2(-3, -18), Vector2(122, 24)), Color(0.03, 0.05, 0.07, 0.85), true)
    draw_text(at, txt, 18, HEALTH_COLOR if animation_evaded else (PATH_COLOR if animation_crit else Color(1.0, 0.57, 0.54)))
    if animation_stunned:
        draw_text(at + Vector2(0, -21), "КОНТУЗИЯ!", 13, PATH_COLOR)


func draw_sidebar() -> void:
    var active: String = turns.active_unit_id()
    draw_text(Vector2(899, 126), "РАУНД %d" % turns.round_number, 18, PATH_COLOR)
    if battle_over:
        draw_text(Vector2(1050, 126), "ПОБЕДА: %s" % side_label(winner_side), 16, PATH_COLOR)
    else:
        var turn_caption: String = "ПРОПУСК: %s" if concussion_skip_pending else ("ИИ: %s" if is_ai_turn() else "ХОДИТ: %s")
        draw_text(Vector2(1050, 126), turn_caption % unit_label(active), 16, PATH_COLOR if concussion_skip_pending else WHITE)
    var queue_tokens: PackedStringArray = []
    for offset in range(turns.turn_order.size()):
        var index: int = (turns.turn_index + offset) % turns.turn_order.size()
        queue_tokens.append(unit_token(turns.turn_order[index]))
    var queue_caption: String = "БОЙ ЗАВЕРШЁН" if battle_over else "ОЧЕРЕДЬ: " + " → ".join(queue_tokens)
    draw_text(Vector2(900, 154), queue_caption, 15, MUTED)
    for slot in range(roster_order.size()):
        var unit_id: String = roster_order[slot]
        var unit = units[unit_id]
        var y: float = 190.0 + slot * 25.0
        var fill: Color = ALLY if unit.side == "blue" else ENEMY
        if inspected_unit_id == unit_id:
            draw_rect(Rect2(Vector2(895, y - 18), Vector2(498, 25)), Color(0.19, 0.26, 0.32))
        draw_circle(Vector2(907, y - 5), 5.0, fill if unit.is_alive() else MUTED)
        var state: String = "ПОВЕРЖЕН" if not unit.is_alive() else ("КОНТ. %d" % unit.concussion_turns_remaining if unit.concussion_turns_remaining > 0 else "")
        var marker: String = "» " if unit_id == active and not battle_over else ""
        draw_text(Vector2(920, y), marker + unit_label(unit_id), 14, WHITE if unit.is_alive() else MUTED)
        draw_text(Vector2(1130, y), "HP %d  MP %d  %s" % [unit.hp, unit.mp, state], 13, fill.lightened(0.3))
    draw_text(Vector2(900, 341), "ПАРАМЕТРЫ · клик по бойцу или строке списка", 13, MUTED)
    var detail_id: String = inspected_unit_id if units.has(inspected_unit_id) else active
    if units.has(detail_id):
        draw_commander_row(detail_id, ALLY if units[detail_id].side == "blue" else ENEMY, 371)
    draw_rect(Rect2(Vector2(893, 531), Vector2(503, 294)), Color(0.055, 0.090, 0.13), true)
    var detail_status: String = unit_status(detail_id)
    var matter_caption: String = ""
    if units.has(detail_id):
        var detail = units[detail_id]
        matter_caption = "Боец: %s · Магия: %s" % [Matter.matter_name(detail.matter), Matter.matter_name(detail.spell_matter) if detail.spell_power > 0 else "—"]
    draw_text(Vector2(901, 513), detail_status if units.has(detail_id) and units[detail_id].concussion_turns_remaining > 0 else matter_caption, 14, PATH_COLOR)
    draw_text(Vector2(903, 548), "ЖУРНАЛ БОЯ  /  MP, КРИТЫ, КОНТУЗИЯ", 15, PATH_COLOR)


func draw_commander_row(unit_id: String, fill: Color, y: float) -> void:
    var u = units[unit_id]
    if u.is_monster:
        draw_monster_row(unit_id, fill, y)
        return
    var a: Dictionary = u.attributes
    var name: String = unit_label(unit_id)
    var weapon: String = Rules.damage_type_name(u.melee_damage_type)
    draw_rect(Rect2(Vector2(895, y - 22), Vector2(498, 141)), Color(0.18, 0.24, 0.29), true)
    draw_circle(Vector2(910, y - 5), 8.0, fill)
    draw_text(Vector2(926, y), "%s  ·  %d уровень" % [name, u.level], 18, WHITE)
    draw_text(Vector2(902, y + 22), "%s | %s | сила умения %d" % [u.armor, weapon, u.melee_skill_power], 14, MUTED)
    draw_text(Vector2(902, y + 43), "HP %d/%d     MP %d/%d" % [u.hp, u.max_hp, u.mp, u.max_mp], 16, WHITE)
    draw_text(Vector2(902, y + 63), "STR %d   AGI %d   WIS %d   INT %d" % [
        int(a.get("STR", 0)), int(a.get("AGI", 0)), int(a.get("WIS", 0)), int(a.get("INT", 0))], 15, WHITE)
    draw_text(Vector2(902, y + 83), "Физ. бонус +%.0f%%   Уклонение %.1f%%   Крит %.1f%%" % [
        u.physical_damage_bonus_pct, u.final_evasion_pct(), u.crit_chance_pct], 14, PATH_COLOR)
    var incoming_type: int = units[turns.active_unit_id()].melee_damage_type if not turns.active_unit_id().is_empty() else Rules.BLUNT
    draw_text(Vector2(902, y + 104), "PDEF против %s: %.0f%%  |  MDEF: %.0f%%  |  КРИТ ×%.1f" % [
        Rules.damage_type_name(incoming_type).to_lower(),
        u.physical_defense_pct(incoming_type), u.magic_defense_pct(), u.critical_multiplier], 13, WHITE)
    if u.special_skill != null:
        var ability: SuleynAttackSkill = u.special_skill
        draw_text(Vector2(902, y + 116), "2: %s · %d MP · %d–%d гекс.  %s" % [
            ability.display_name, ability.mana_cost, ability.min_range, ability.max_range,
            "КОНТУЗИЯ %d ход." % u.concussion_turns_remaining if u.concussion_turns_remaining > 0 else ""], 12, PATH_COLOR)


func draw_monster_row(unit_id: String, fill: Color, y: float) -> void:
    var u = units[unit_id]
    draw_rect(Rect2(Vector2(895, y - 22), Vector2(498, 141)), Color(0.18, 0.24, 0.29), true)
    draw_circle(Vector2(910, y - 5), 8.0, fill)
    draw_text(Vector2(926, y), unit_label(unit_id), 18, WHITE)
    draw_text(Vector2(902, y + 22), "МОНСТР · %s · %s" % [
        Matter.matter_name(u.matter), Rules.damage_type_name(u.melee_damage_type)], 14, MUTED)
    draw_text(Vector2(902, y + 43), "HP %d/%d    MP %d/%d    Уклонение %.1f%%" % [
        u.hp, u.max_hp, u.mp, u.max_mp, u.final_evasion_pct()], 14, WHITE)
    draw_text(Vector2(902, y + 63), "Base PDEF %.0f%% · Base MDEF %.0f%% · Без брони" % [
        u.base_pdef_pct, u.base_mdef_pct], 14, WHITE)
    draw_text(Vector2(902, y + 84), "PDEF колющее %.0f%%, рубящее %.0f%%, дробящее %.0f%%" % [
        u.physical_defense_pct(Rules.PIERCING), u.physical_defense_pct(Rules.SLASHING),
        u.physical_defense_pct(Rules.BLUNT)], 13, PATH_COLOR)
    draw_text(Vector2(902, y + 105), "Крит %.1f%% ×%.1f · сила удара %d · MP+%.1f%%" % [
        u.crit_chance_pct, u.critical_multiplier, u.melee_skill_power, u.mana_regen_pct], 13, MUTED)


func draw_instructions() -> void:
    draw_text(Vector2(40, 810), "ЛКМ: активный боец → зелёный гекс / оранжевая цель. Одно действие.", 16, WHITE)
    var ai_hint: String = "   A — ИИ" if encounter_index == TEAM_ENCOUNTER else ""
    draw_text(Vector2(40, 839), "1 — удар   2 — умение   F — магия   Space — пропуск   R — сброс   T — сценарий" + ai_hint, 15, MUTED)
    draw_text(Vector2(40, 872), message, 16, PATH_COLOR)


func center_of(cell: Vector2i) -> Vector2:
    return BOARD_ORIGIN + Hex.axial_to_pixel(cell, hex_radius)


func hex_vertices(center: Vector2) -> PackedVector2Array:
    var vertices := PackedVector2Array()
    for i in range(6):
        var angle: float = deg_to_rad(-90.0 + 60.0 * float(i))
        vertices.append(center + Vector2(cos(angle), sin(angle)) * hex_radius)
    return vertices


func draw_text(at: Vector2, value: String, font_size: int, color: Color) -> void:
    draw_string(ThemeDB.fallback_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
