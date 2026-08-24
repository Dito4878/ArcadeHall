extends Node3D

const WALK_SPEED := 2.35
const LOOK_SPEED := 1.65
const LOOK_DEADZONE := 0.30
const INTERACT_DISTANCE := 2.35

const ROM_ROOTS := [
    "/storage/emulated/0/ArcadeHall/roms",
    "/sdcard/ArcadeHall/roms"
]

const RETROARCH_PACKAGES := [
    "com.retroarch.aarch64",
    "com.retroarch"
]

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D

var hint_panel: ColorRect
var hint_label: Label
var controller_label: Label

var select_backdrop: ColorRect
var select_title: Label
var select_system: Label
var select_status: Label
var select_list: VBoxContainer

var selection_open := false
var selection_index := 0
var selection_games: Array[Dictionary] = []

var big_screen_title: Label3D
var big_screen_subtitle: Label3D
var big_screen_info: Label3D

var cabinets: Array[Node3D] = []
var pitch := 0.0
var current_cabinet := -1
var last_focused_cabinet := -1

func _ready() -> void:
    # SAFE startup: no Android permission dialog and no forced window-mode
    # before the 3D scene has been created.
    _build_environment()
    _build_hall()
    _build_player()
    _build_cabinets()
    _build_hud()
    _update_controller_status()
    _set_big_screen("ARCADE HALL", "MAME  •  ATARI 7800", "Steuerkreuz: laufen   Rechter Stick: umsehen")


func _physics_process(delta: float) -> void:
    if not selection_open:
        _move_player(delta)
        _look_with_raw_right_stick(delta)
        _find_nearest_cabinet()
        _update_hud()
    _handle_actions()

func _filtered_axis(value: float) -> float:
    var a := abs(value)
    if a <= LOOK_DEADZONE:
        return 0.0
    return sign(value) * ((a - LOOK_DEADZONE) / (1.0 - LOOK_DEADZONE))

func _look_with_raw_right_stick(delta: float) -> void:
    # Read the right stick directly. This avoids the old action-map bug
    # where looking up could leave the opposite direction unresponsive.
    var pads := Input.get_connected_joypads()
    if pads.is_empty():
        return

    var pad_id: int = pads[0]
    var lx := _filtered_axis(Input.get_joy_axis(pad_id, 2))
    var ly := _filtered_axis(Input.get_joy_axis(pad_id, 3))

    head.rotation.y -= lx * LOOK_SPEED * delta

    # Android/PS5: right-stick up is negative Y, down is positive Y.
    # Positive camera X looks upward in Godot.
    pitch = clamp(pitch - ly * LOOK_SPEED * delta, deg_to_rad(-55.0), deg_to_rad(55.0))
    camera.rotation.x = pitch

func _mat(color: Color, emission := false, energy := 1.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.58
    if emission:
        m.emission_enabled = true
        m.emission = color
        m.emission_energy_multiplier = energy
    return m

func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, material: Material, collision := false) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = name
    var mesh := BoxMesh.new()
    mesh.size = size
    mi.mesh = mesh
    mi.position = pos
    mi.material_override = material
    parent.add_child(mi)

    if collision:
        var body := StaticBody3D.new()
        var shape := CollisionShape3D.new()
        var box_shape := BoxShape3D.new()
        box_shape.size = size
        shape.shape = box_shape
        body.position = pos
        body.add_child(shape)
        parent.add_child(body)

    return mi

func _build_environment() -> void:
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.003, 0.004, 0.008)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.15, 0.18, 0.28)
    env.ambient_light_energy = 0.40
    world_env.environment = env
    add_child(world_env)

    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-55, -25, 0)
    key.light_energy = 0.32
    add_child(key)

func _build_hall() -> void:
    var hall := Node3D.new()
    hall.name = "Hall"
    add_child(hall)

    var floor_mat := _mat(Color(0.025, 0.03, 0.045))
    var wall_mat := _mat(Color(0.018, 0.022, 0.035))
    var ceiling_mat := _mat(Color(0.012, 0.014, 0.022))

    _box(hall, "Floor", Vector3(10.0, 0.20, 19.0), Vector3(0, -0.10, -3.5), floor_mat, true)
    _box(hall, "Ceiling", Vector3(10.0, 0.18, 19.0), Vector3(0, 3.20, -3.5), ceiling_mat)
    _box(hall, "LeftWall", Vector3(0.18, 3.4, 19.0), Vector3(-5.0, 1.6, -3.5), wall_mat, true)
    _box(hall, "RightWall", Vector3(0.18, 3.4, 19.0), Vector3(5.0, 1.6, -3.5), wall_mat, true)
    _box(hall, "BackWall", Vector3(10.0, 3.4, 0.18), Vector3(0, 1.6, -13.0), wall_mat, true)
    _box(hall, "FrontWall", Vector3(10.0, 3.4, 0.18), Vector3(0, 1.6, 6.0), wall_mat, true)

    _box(hall, "CarpetRunner", Vector3(2.6, 0.025, 17.4), Vector3(0, 0.015, -3.5), _mat(Color(0.05, 0.018, 0.072)))

    var cyan := _mat(Color(0.06, 0.68, 0.95), true, 2.3)
    var magenta := _mat(Color(0.95, 0.05, 0.48), true, 2.1)
    for z in [-10.5, -6.5, -2.5, 1.5, 5.0]:
        _box(hall, "NeonCyan", Vector3(2.8, 0.035, 0.07), Vector3(-1.65, 3.08, z), cyan)
        _box(hall, "NeonMagenta", Vector3(2.8, 0.035, 0.07), Vector3(1.65, 3.08, z), magenta)

    # The physical wall screen is deliberately almost wall-filling.
    var screen_border := _mat(Color(0.05, 0.055, 0.075))
    var screen_glow := _mat(Color(0.010, 0.025, 0.060), true, 1.0)
    _box(hall, "BigScreenBorder", Vector3(9.1, 3.05, 0.16), Vector3(0, 1.62, -12.72), screen_border)
    _box(hall, "BigScreen", Vector3(8.75, 2.72, 0.05), Vector3(0, 1.62, -12.61), screen_glow)

    big_screen_title = Label3D.new()
    big_screen_title.text = "ARCADE HALL"
    big_screen_title.font_size = 120
    big_screen_title.position = Vector3(0, 2.12, -12.54)
    big_screen_title.outline_size = 10
    big_screen_title.modulate = Color(0.15, 0.90, 1.0)
    hall.add_child(big_screen_title)

    big_screen_subtitle = Label3D.new()
    big_screen_subtitle.text = "MAME  •  ATARI 7800"
    big_screen_subtitle.font_size = 62
    big_screen_subtitle.position = Vector3(0, 1.48, -12.54)
    big_screen_subtitle.outline_size = 7
    big_screen_subtitle.modulate = Color.WHITE
    hall.add_child(big_screen_subtitle)

    big_screen_info = Label3D.new()
    big_screen_info.text = "Steuerkreuz: laufen   Rechter Stick: umsehen"
    big_screen_info.font_size = 38
    big_screen_info.position = Vector3(0, 0.92, -12.54)
    big_screen_info.outline_size = 6
    big_screen_info.modulate = Color(0.82, 0.86, 0.95)
    hall.add_child(big_screen_info)

func _build_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0, 0.95, 3.8)

    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.32
    capsule.height = 1.72
    collision.shape = capsule
    player.add_child(collision)

    head = Node3D.new()
    head.name = "Head"
    head.position = Vector3(0, 0.58, 0)
    player.add_child(head)

    camera = Camera3D.new()
    camera.name = "Camera"
    camera.current = true
    camera.fov = 76
    camera.near = 0.08
    head.add_child(camera)

    add_child(player)

func _build_cabinets() -> void:
    var defs = [
        {"title":"MAME 1", "system":"MAME", "pos":Vector3(-3.55,0,-8.8), "rot":90.0},
        {"title":"MAME 2", "system":"MAME", "pos":Vector3(-3.55,0,-5.3), "rot":90.0},
        {"title":"MAME 3", "system":"MAME", "pos":Vector3(-3.55,0,-1.8), "rot":90.0},
        {"title":"MAME 4", "system":"MAME", "pos":Vector3(-3.55,0,1.7), "rot":90.0},
        {"title":"ATARI 1", "system":"ATARI 7800", "pos":Vector3(3.55,0,-6.7), "rot":-90.0},
        {"title":"ATARI 2", "system":"ATARI 7800", "pos":Vector3(3.55,0,-2.8), "rot":-90.0},
    ]

    for d in defs:
        var cab := _make_cabinet(d["title"], d["system"])
        cab.position = d["pos"]
        cab.rotation_degrees.y = d["rot"]
        add_child(cab)
        cabinets.append(cab)

func _make_cabinet(title: String, system: String) -> Node3D:
    var cab := Node3D.new()
    cab.name = title
    cab.set_meta("system", system)
    cab.set_meta("title", title)

    var body_mat := _mat(Color(0.025,0.028,0.04))
    var side_mat := _mat(Color(0.09,0.10,0.14))
    var trim_mat := _mat(Color(0.16,0.18,0.23))
    var screen_mat := _mat(Color(0.05,0.75,0.95), true, 2.3) if system == "MAME" else _mat(Color(0.95,0.15,0.05), true, 2.2)

    _box(cab, "Body", Vector3(1.28, 2.48, 0.82), Vector3(0,1.24,0), body_mat, true)
    _box(cab, "Top", Vector3(1.40, 0.38, 0.90), Vector3(0,2.29,-0.01), side_mat)
    _box(cab, "LowerFront", Vector3(1.08, 0.82, 0.05), Vector3(0,0.56,0.435), trim_mat)
    _box(cab, "Screen", Vector3(0.90, 0.66, 0.045), Vector3(0,1.60,0.438), screen_mat)
    _box(cab, "Controls", Vector3(1.08, 0.12, 0.46), Vector3(0,1.11,0.56), side_mat)

    var marquee := Label3D.new()
    marquee.text = title
    marquee.font_size = 52
    marquee.position = Vector3(0,2.31,0.47)
    marquee.outline_size = 7
    marquee.modulate = Color.WHITE
    cab.add_child(marquee)

    var sys_label := Label3D.new()
    sys_label.text = system
    sys_label.font_size = 26
    sys_label.position = Vector3(0,0.58,0.47)
    sys_label.outline_size = 5
    sys_label.modulate = Color(0.82,0.86,0.95)
    cab.add_child(sys_label)

    return cab

func _build_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    # Root Control fills the whole TV. All UI uses anchors instead of a
    # fixed 1280x720 centered box.
    var root_ui := Control.new()
    root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layer.add_child(root_ui)

    controller_label = Label.new()
    controller_label.position = Vector2(28, 22)
    controller_label.add_theme_font_size_override("font_size", 22)
    controller_label.modulate = Color(0.70,0.74,0.82,0.72)
    root_ui.add_child(controller_label)

    hint_panel = ColorRect.new()
    hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    hint_panel.position = Vector2(-310, -104)
    hint_panel.size = Vector2(620, 72)
    hint_panel.color = Color(0.012,0.015,0.026,0.88)
    hint_panel.visible = false
    root_ui.add_child(hint_panel)

    hint_label = Label.new()
    hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    hint_label.position = Vector2(-285, -91)
    hint_label.size = Vector2(570, 46)
    hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint_label.add_theme_font_size_override("font_size", 30)
    hint_label.visible = false
    root_ui.add_child(hint_label)

    # Full-TV game selection overlay.
    select_backdrop = ColorRect.new()
    select_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    select_backdrop.color = Color(0.005,0.007,0.013,0.97)
    select_backdrop.visible = false
    root_ui.add_child(select_backdrop)

    select_title = Label.new()
    select_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
    select_title.position = Vector2(100, 78)
    select_title.size = Vector2(-200, 90)
    select_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    select_title.add_theme_font_size_override("font_size", 58)
    select_title.visible = false
    root_ui.add_child(select_title)

    select_system = Label.new()
    select_system.set_anchors_preset(Control.PRESET_TOP_WIDE)
    select_system.position = Vector2(100, 164)
    select_system.size = Vector2(-200, 60)
    select_system.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    select_system.add_theme_font_size_override("font_size", 34)
    select_system.modulate = Color(0.25, 0.84, 1.0)
    select_system.visible = false
    root_ui.add_child(select_system)

    select_list = VBoxContainer.new()
    select_list.set_anchors_preset(Control.PRESET_CENTER)
    select_list.position = Vector2(-560, -250)
    select_list.size = Vector2(1120, 510)
    select_list.add_theme_constant_override("separation", 20)
    select_list.visible = false
    root_ui.add_child(select_list)

    select_status = Label.new()
    select_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    select_status.position = Vector2(100, -135)
    select_status.size = Vector2(-200, 90)
    select_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    select_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    select_status.add_theme_font_size_override("font_size", 28)
    select_status.modulate = Color(0.82,0.85,0.92)
    select_status.visible = false
    root_ui.add_child(select_status)

func _move_player(delta: float) -> void:
    # D-pad only. Left stick is deliberately not read anywhere.
    var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var forward_basis := Basis(Vector3.UP, head.rotation.y)
    var dir := (forward_basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()

    player.velocity.x = dir.x * WALK_SPEED
    player.velocity.z = dir.z * WALK_SPEED

    if not player.is_on_floor():
        player.velocity.y -= 18.0 * delta
    else:
        player.velocity.y = 0.0

    player.move_and_slide()

func _find_nearest_cabinet() -> void:
    current_cabinet = -1
    var best := INTERACT_DISTANCE

    for i in range(cabinets.size()):
        var d := player.global_position.distance_to(cabinets[i].global_position)
        if d < best:
            best = d
            current_cabinet = i

    if current_cabinet != last_focused_cabinet:
        last_focused_cabinet = current_cabinet
        if current_cabinet >= 0:
            var cab := cabinets[current_cabinet]
            _set_big_screen(str(cab.get_meta("title")), str(cab.get_meta("system")), "X = Spielauswahl")
        else:
            _set_big_screen("ARCADE HALL", "MAME  •  ATARI 7800", "Steuerkreuz: laufen   Rechter Stick: umsehen")

func _update_hud() -> void:
    if current_cabinet >= 0:
        hint_panel.visible = true
        hint_label.visible = true
        hint_label.text = "X  –  SPIELE"
    else:
        hint_panel.visible = false
        hint_label.visible = false

func _set_big_screen(title: String, subtitle: String, info: String) -> void:
    if big_screen_title:
        big_screen_title.text = title
        big_screen_subtitle.text = subtitle
        big_screen_info.text = info

func _update_controller_status() -> void:
    var pads := Input.get_connected_joypads()
    if pads.is_empty():
        controller_label.text = "Kein Gamecontroller erkannt"
    else:
        var names: Array[String] = []
        for id in pads:
            names.append(Input.get_joy_name(id))
        controller_label.text = ", ".join(names)

func _system_subdir(system: String) -> String:
    return "mame" if system == "MAME" else "atari7800"

func _valid_rom_extension(system: String, filename: String) -> bool:
    var ext := filename.get_extension().to_lower()
    if system == "MAME":
        return ext in ["zip", "7z"]
    return ext in ["a78", "bin", "rom", "zip"]

func _scan_roms(system: String) -> Array[Dictionary]:
    var found: Array[Dictionary] = []
    var subdir := _system_subdir(system)

    for root in ROM_ROOTS:
        var path := root.path_join(subdir)
        var dir := DirAccess.open(path)
        if dir == null:
            continue

        dir.list_dir_begin()
        while true:
            var name := dir.get_next()
            if name == "":
                break
            if dir.current_is_dir():
                continue
            if _valid_rom_extension(system, name):
                found.append({
                    "name": name.get_basename(),
                    "path": path.path_join(name),
                    "system": system
                })
        dir.list_dir_end()

        if not found.is_empty():
            break

    found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
    )
    return found

func _open_selection() -> void:
    if current_cabinet < 0:
        return

    var cab := cabinets[current_cabinet]
    var system := str(cab.get_meta("system"))
    selection_games = _scan_roms(system)
    selection_index = 0
    selection_open = true

    select_backdrop.visible = true
    select_title.visible = true
    select_system.visible = true
    select_list.visible = true
    select_status.visible = true

    hint_panel.visible = false
    hint_label.visible = false

    select_title.text = "SPIELAUSWAHL"
    select_system.text = system

    if selection_games.is_empty():
        select_status.text = "Keine ROMs gefunden oder Speicherzugriff fehlt.\nOrdner: /storage/emulated/0/ArcadeHall/roms/%s/" % _system_subdir(system)
    else:
        select_status.text = "Steuerkreuz ↑/↓ = wählen    X = starten    Kreis = zurück"

    _refresh_selection()

func _refresh_selection() -> void:
    for child in select_list.get_children():
        child.queue_free()

    if selection_games.is_empty():
        var empty := Label.new()
        empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        empty.add_theme_font_size_override("font_size", 42)
        empty.text = "KEINE SPIELE GEFUNDEN"
        empty.modulate = Color(1.0,0.55,0.40)
        select_list.add_child(empty)
        return

    var start := max(0, selection_index - 4)
    var end := min(selection_games.size(), start + 9)
    if end - start < 9:
        start = max(0, end - 9)

    for i in range(start, end):
        var row := Label.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        row.add_theme_font_size_override("font_size", 48 if i == selection_index else 38)
        row.text = ("▶  " if i == selection_index else "    ") + str(selection_games[i]["name"])
        row.modulate = Color.WHITE if i == selection_index else Color(0.58,0.63,0.72)
        select_list.add_child(row)

    _set_big_screen(
        str(selection_games[selection_index]["name"]),
        str(selection_games[selection_index]["system"]),
        "X = START"
    )

func _close_selection() -> void:
    selection_open = false
    select_backdrop.visible = false
    select_title.visible = false
    select_system.visible = false
    select_list.visible = false
    select_status.visible = false

    if current_cabinet >= 0:
        var cab := cabinets[current_cabinet]
        _set_big_screen(str(cab.get_meta("title")), str(cab.get_meta("system")), "X = Spielauswahl")

func _core_filename(system: String) -> String:
    # v0.4 uses these two RetroArch cores deliberately.
    return "mame2003_plus_libretro_android.so" if system == "MAME" else "prosystem_libretro_android.so"

func _launch_retroarch(game: Dictionary) -> bool:
    if not OS.has_feature("android"):
        select_status.text = "Spielstart funktioniert nur auf Android / Fire TV."
        return false

    var runtime = Engine.get_singleton("AndroidRuntime")
    if runtime == null:
        select_status.text = "AndroidRuntime nicht verfügbar."
        return false

    var activity = runtime.getActivity()
    var Intent = JavaClassWrapper.wrap("android.content.Intent")
    var ComponentName = JavaClassWrapper.wrap("android.content.ComponentName")

    for package_name in RETROARCH_PACKAGES:
        var intent = Intent.Intent()
        var component = ComponentName.ComponentName(
            package_name,
            "com.retroarch.browser.retroactivity.RetroActivityFuture"
        )
        intent.setComponent(component)

        var core_path := "/data/data/%s/cores/%s" % [package_name, _core_filename(str(game["system"]))]
        var config_path := "/storage/emulated/0/Android/data/%s/files/retroarch.cfg" % package_name

        intent.putExtra("ROM", str(game["path"]))
        intent.putExtra("LIBRETRO", core_path)
        intent.putExtra("CONFIGFILE", config_path)
        intent.putExtra("DATADIR", "/data/data/%s" % package_name)
        intent.putExtra("SDCARD", "/storage/emulated/0")
        intent.putExtra("EXTERNAL", "/storage/emulated/0/Android/data/%s/files" % package_name)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)

        activity.startActivity(intent)
        var exception = JavaClassWrapper.get_exception()
        if exception == null:
            select_status.text = "Starte %s …" % str(game["name"])
            return true

    select_status.text = "RetroArch wurde nicht gefunden.\nInstalliere RetroArch und die passenden Cores."
    return false

func _handle_actions() -> void:
    if selection_open:
        if Input.is_action_just_pressed("move_forward") and not selection_games.is_empty():
            selection_index = max(0, selection_index - 1)
            _refresh_selection()

        elif Input.is_action_just_pressed("move_back") and not selection_games.is_empty():
            selection_index = min(selection_games.size() - 1, selection_index + 1)
            _refresh_selection()

        elif Input.is_action_just_pressed("interact") and not selection_games.is_empty():
            _launch_retroarch(selection_games[selection_index])

        elif Input.is_action_just_pressed("back"):
            _close_selection()
        return

    if Input.is_action_just_pressed("interact") and current_cabinet >= 0:
        _open_selection()

    if Input.is_action_just_pressed("back"):
        hint_panel.visible = false
        hint_label.visible = false
