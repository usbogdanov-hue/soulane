extends SceneTree
## Durable, isolated plain-data library checks. Never uses production save path.
const Store = preload("res://scripts/setup_store.gd")
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")

var checks: int = 0
var failures: int = 0
var base: String


func _initialize() -> void:
    base = "user://tests/store_v110_%d" % Time.get_ticks_usec()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
    test_roundtrip_and_independence()
    test_validation_and_failed_write()
    test_corruption_and_recovery()
    test_library_schema()
    _cleanup(base)
    if failures == 0:
        print("SULEYN setup store v1.10: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN setup store v1.10: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED setup store v1.10: " + description)


func _path(name: String) -> String:
    return base + "/" + name + ".json"


func _write(path: String, text: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    assert(file != null)
    file.store_string(text)
    file.close()


func _text(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    assert(file != null)
    var text: String = file.get_as_text()
    file.close()
    return text


func _same(left, right) -> bool:
    return left != null and right != null and Codec.encode(left).code == Codec.encode(right).code


func test_roundtrip_and_independence() -> void:
    var path: String = _path("roundtrip")
    var store = Store.new(path)
    check(store.load_library().ok, "missing library is an empty successful load")
    check(store.list_slots().size() == 3 and store.last_setup() == null, "empty library has three slots and no accepted setup")
    for row in store.list_slots():
        check(not row.occupied and row.name.is_empty(), "empty slot metadata is explicit")
    check(store.slot_setup(-1) == null and store.slot_setup(3) == null and store.slot_setup(0) == null, "unknown or empty slot has no setup")
    var first = Setup.new()
    first.set_arena("gates")
    first.set_profile("ally_1", "lich")
    first.place_unit("ally_1", Vector2i(0, 0))
    first.enemy_ai_enabled = false
    check(store.save_slot(0, "  Проходы  ", first).ok, "valid first preset writes")
    check(FileAccess.file_exists(path), "first save creates local file")
    check(store.list_slots()[0].name == "Проходы", "slot name trims surrounding spaces")
    check(_same(store.slot_setup(0), first), "saved preset preserves arena profiles positions and AI")
    first.set_profile("ally_1", "male")
    check(store.slot_setup(0).profile_key("ally_1") == "lich", "saved state does not alias source draft")
    var retrieved = store.slot_setup(0)
    retrieved.set_arena("pillars")
    retrieved.positions.clear()
    check(store.slot_setup(0).arena_key == "gates" and store.slot_setup(0).is_valid(), "retrieved setup is an independent copy")
    var metadata: Array[Dictionary] = store.list_slots()
    metadata[0].name = "Changed"
    metadata.clear()
    check(store.list_slots()[0].name == "Проходы", "slot metadata is also copied")
    var last = Setup.new()
    last.set_arena("pillars")
    check(store.save_last(last).ok, "accepted setup writes without replacing named slots")
    check(FileAccess.file_exists(path + ".bak"), "second commit retains a prior library backup")
    check(_same(store.last_setup(), last) and store.list_slots()[0].occupied, "accepted and named setups are independent")
    var reload = Store.new(path)
    check(reload.load_library().ok, "fresh store reads saved JSON numbers")
    check(_same(reload.last_setup(), last) and reload.slot_setup(0).profile_key("ally_1") == "lich", "fresh instance restores all saved fields")
    var accepted_copy = reload.last_setup()
    accepted_copy.enemy_ai_enabled = false
    check(reload.last_setup().enemy_ai_enabled, "accepted setup getter returns copy")
    for index in [1, 2]:
        check(reload.save_slot(index, "Слот %d" % index, last).ok, "all three slots independently save")
    check(reload.delete_slot(1).ok, "deleting occupied slot commits")
    check(not reload.list_slots()[1].occupied and reload.list_slots()[0].occupied and reload.list_slots()[2].occupied, "delete changes only chosen slot")
    check(_same(reload.last_setup(), last), "deleting slot preserves last accepted setup")
    var deleted_reload = Store.new(path)
    check(deleted_reload.load_library().ok and not deleted_reload.list_slots()[1].occupied, "deleted slot remains empty after fresh load")
    check(not deleted_reload.delete_slot(1).ok and not deleted_reload.delete_slot(3).ok, "empty and out-of-range delete are rejected")


func test_validation_and_failed_write() -> void:
    var path: String = _path("failures")
    var store = Store.new(path)
    var setup = Setup.new()
    check(store.save_slot(0, "Original", setup).ok, "save lazily loads missing library")
    var original: String = _text(path)
    for name in ["", "   ", "A".repeat(33), "Bad\nName", "Bad\tName", "Bad" + String.chr(127)]:
        check(not store.save_slot(1, name, setup).ok, "invalid name rejected")
    for index in [-1, 3, 100]:
        check(not store.save_slot(index, "Valid", setup).ok, "invalid slot index rejected")
    var corrupted = setup.copy()
    corrupted.profile_keys["ally_1"] = "resource://untrusted"
    check(not store.save_slot(1, "Bad setup", corrupted).ok and not store.save_last(corrupted).ok, "invalid model cannot enter either saved field")
    check(_text(path) == original and not store.list_slots()[1].occupied and store.last_setup() == null, "validation failure changes neither disk nor memory")
    DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
    var wanted = Setup.new()
    wanted.set_arena("gates")
    check(not store.save_slot(0, "Replacement", wanted).ok, "temp-file write failure reported")
    check(_text(path) == original and store.list_slots()[0].name == "Original" and store.slot_setup(0).arena_key == "open", "failed write preserves previous file and in-memory state")
    check(not store.save_last(wanted).ok and store.last_setup() == null, "accepted setup is not committed after failed persistence")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
    check(store.save_slot(0, "Recovered write", wanted).ok, "write works after external I/O problem clears")
    var missing_parent = Store.new(base + "/missing/subdir/library.json")
    check(not missing_parent.save_last(setup).ok and missing_parent.last_setup() == null, "missing parent directory is a non-mutating write error")
    seed(20261113)
    var expected_roll: int = randi()
    seed(20261113)
    store.list_slots()
    store.slot_setup(0)
    store.last_setup()
    check(randi() == expected_roll, "library reads do not consume global combat RNG")


func test_corruption_and_recovery() -> void:
    var path: String = _path("recovery")
    var store = Store.new(path)
    var setup = Setup.new()
    setup.set_arena("gates")
    check(store.save_slot(0, "First", setup).ok, "recovery fixture first commit")
    setup.set_arena("pillars")
    check(store.save_last(setup).ok, "recovery fixture second commit creates valid backup")
    var old_backup: String = _text(path + ".bak")
    _write(path, "{broken")
    var recovered = Store.new(path)
    var loaded: Dictionary = recovered.load_library()
    check(loaded.ok and loaded.recovered and not loaded.reason.is_empty(), "bad main recovers a valid backup with notice")
    check(recovered.slot_setup(0).arena_key == "gates" and recovered.last_setup() == null, "recovery restores prior complete transaction")
    check(_text(path) == "{broken" and _text(path + ".bak") == old_backup, "recovery read does not overwrite either file")
    check(recovered.save_last(setup).ok, "recovered library can commit valid new data")
    check(_text(path + ".bak") == old_backup, "corrupt main never replaces valid backup")
    var verified = Store.new(path)
    check(verified.load_library().ok and verified.last_setup().arena_key == "pillars", "next read uses repaired valid main")
    _write(path, "Damaged while game was running")
    var intact_backup: String = _text(path + ".bak")
    check(not verified.save_last(setup).ok, "corruption after a successful load also blocks overwrite")
    check(_text(path) == "Damaged while game was running" and _text(path + ".bak") == intact_backup, "late corruption cannot replace intact backup")
    var locked_path: String = _path("locked")
    _write(locked_path, "Unrecognized original data")
    var locked = Store.new(locked_path)
    check(not locked.load_library().ok, "unknown main without valid backup reports read error")
    check(not locked.save_last(setup).ok and not locked.save_slot(0, "Must not overwrite", setup).ok, "autosave and explicit save cannot clobber unknown library")
    check(_text(locked_path) == "Unrecognized original data" and not FileAccess.file_exists(locked_path + ".tmp"), "locked library leaves original bytes and no partial write")
    _write(locked_path + ".bak", "Also broken")
    check(not locked.load_library().ok and not locked.save_last(setup).ok, "invalid backup does not unlock corrupt library")
    _write(locked_path, old_backup)
    check(locked.load_library().ok and locked.save_last(setup).ok, "valid repaired file explicitly reloads and unlocks library")
    var absent_path: String = _path("missing_main")
    _write(absent_path + ".bak", old_backup)
    var backup_only = Store.new(absent_path)
    check(backup_only.load_library().recovered and backup_only.slot_setup(0).arena_key == "gates", "backup also restores missing main")


func test_library_schema() -> void:
    var setup = Setup.new()
    var valid: Dictionary = {"format": "suleyn.library", "version": 1,
        "last_setup": Codec.encode(setup).data, "slots": [null, null, null]}
    var variants: Array = [null, [], {}, {"format": "other", "version": 1, "last_setup": null, "slots": [null, null, null]}]
    var bad: Dictionary = valid.duplicate(true)
    bad.version = 1.5
    variants.append(bad)
    bad = valid.duplicate(true)
    bad.slots = [null, null]
    variants.append(bad)
    bad = valid.duplicate(true)
    bad.last_setup = {"path": "res://data/demo_male_lv25.tres"}
    variants.append(bad)
    bad = valid.duplicate(true)
    bad.slots[0] = {"name": "Bad", "setup": Codec.encode(setup).data, "extra": true}
    variants.append(bad)
    bad = valid.duplicate(true)
    bad.slots[1] = {"name": 123, "setup": Codec.encode(setup).data}
    variants.append(bad)
    bad = valid.duplicate(true)
    bad.extra = true
    variants.append(bad)
    bad = valid.duplicate(true)
    bad.slots[2] = {"name": "Bad", "setup": {}}
    variants.append(bad)
    for index in range(variants.size()):
        var path: String = _path("schema_%d" % index)
        var text: String = JSON.stringify(variants[index])
        _write(path, text)
        var store = Store.new(path)
        check(not store.load_library().ok and store.last_setup() == null, "invalid library rejected as whole before exposing partial fields %d" % index)
        check(not store.save_last(setup).ok and _text(path) == text, "invalid library stays intact when autosave requested %d" % index)
    var oversized_path: String = _path("oversized")
    _write(oversized_path, " ".repeat(Store.MAX_FILE_BYTES + 1))
    var oversized = Store.new(oversized_path)
    check(not oversized.load_library().ok and not oversized.save_last(setup).ok, "oversized file refused before parsing or replacement")


func _cleanup(path: String) -> void:
    var directory := DirAccess.open(path)
    if directory == null:
        return
    directory.list_dir_begin()
    var entry: String = directory.get_next()
    while not entry.is_empty():
        var child: String = path + "/" + entry
        if directory.current_is_dir():
            _cleanup(child)
        else:
            DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
        entry = directory.get_next()
    directory.list_dir_end()
    directory = null
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
