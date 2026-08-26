extends Node3D

const WALK_SPEED := 2.35
const LOOK_SPEED := 1.45
const INTERACT_DISTANCE := 2.25

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D

var hint_panel: ColorRect
var hint_label: Label
var controller_label: Label

var select_panel: ColorRect
var select_title: Label
var select_list: VBoxContainer
var selection_open := false
var selection_index := 0
var selection_games: Array[String] = []

var big_screen_title: Label3D
var big_screen_subtitle: Label3D
var big_screen_info: Label3D

var cabinets: Array[Node3D] = []
var pitch := 0.0
var current_cabinet := -1
var last_focused_cabinet := -1

func _ready() -> void:
    _build_environment()
    _build_hall()
    _build_player()
    _build_cabinets()
    _build_hud()
    _update_controller_status()
    _set_big_screen("ARCADE HALL", "MAME  •  ATARI 7800", "D-Pad: laufen   Rechter Stick: umsehen")

func _physics_process(delta: float) -> void:
    if not selection_open:
        _move_player(delta)
        _look(delta)
        _find_nearest_cabinet()
        _update_hud()
    _handle_actions()

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

    # Large 16:9-style screen on the back wall.
    var screen_border := _mat(Color(0.05, 0.055, 0.075))
    var screen_glow := _mat(Color(0.012, 0.025, 0.055), true, 0.8)
    _box(hall, "BigScreenBorder", Vector3(7.0, 2.45, 0.16), Vector3(0, 1.68, -12.72), screen_border)
    _box(hall, "BigScreen", Vector3(6.65, 2.10, 0.05), Vector3(0, 1.68, -12.61), screen_glow)

    big_screen_title = Label3D.new()
    big_screen_title.text = "ARCADE HALL"
    big_screen_title.font_size = 92
    big_screen_title.position = Vector3(0, 2.10, -12.54)
    big_screen_title.outline_size = 8
    big_screen_title.modulate = Color(0.15, 0.90, 1.0)
    hall.add_child(big_screen_title)

    big_screen_subtitle = Label3D.new()
    big_screen_subtitle.text = "MAME  •  ATARI 7800"
    big_screen_subtitle.font_size = 48
    big_screen_subtitle.position = Vector3(0, 1.55, -12.54)
    big_screen_subtitle.outline_size = 6
    big_screen_subtitle.modulate = Color.WHITE
    hall.add_child(big_screen_subtitle)

    big_screen_info = Label3D.new()
    big_screen_info.text = "D-Pad: laufen   Rechter Stick: umsehen"
    big_screen_info.font_size = 30
    big_screen_info.position = Vector3(0, 1.10, -12.54)
    big_screen_info.outline_size = 5
    big_screen_info.modulate = Color(0.82, 0.86, 0.95)
    hall.add_child(big_screen_info)

func _build_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0, 0.95, 4.0)

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
    camera.fov = 75
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

    controller_label = Label.new()
    controller_label.position = Vector2(20, 16)
    controller_label.add_theme_font_size_override("font_size", 14)
    controller_label.modulate = Color(0.70,0.74,0.82,0.72)
    layer.add_child(controller_label)

    hint_panel = ColorRect.new()
    hint_panel.position = Vector2(420, 612)
    hint_panel.size = Vector2(440, 60)
    hint_panel.color = Color(0.012,0.015,0.026,0.86)
    hint_panel.visible = false
    layer.add_child(hint_panel)

    hint_label = Label.new()
    hint_label.position = Vector2(440, 626)
    hint_label.size = Vector2(400, 32)
    hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint_label.add_theme_font_size_override("font_size", 22)
    hint_label.visible = false
    layer.add_child(hint_label)

    # Big couch-distance game selection overlay.
    select_panel = ColorRect.new()
    select_panel.position = Vector2(180, 110)
    select_panel.size = Vector2(920, 500)
    select_panel.color = Color(0.008,0.011,0.020,0.95)
    select_panel.visible = false
    layer.add_child(select_panel)

    select_title = Label.new()
    select_title.position = Vector2(230, 145)
    select_title.size = Vector2(820, 55)
    select_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    select_title.add_theme_font_size_override("font_size", 34)
    select_title.visible = false
    layer.add_child(select_title)

    select_list = VBoxContainer.new()
    select_list.position = Vector2(300, 225)
    select_list.size = Vector2(680, 310)
    select_list.add_theme_constant_override("separation", 16)
    select_list.visible = false
    layer.add_child(select_list)

func _move_player(delta: float) -> void:
    # Movement actions contain D-pad only; left stick is intentionally unused.
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

func _look(delta: float) -> void:
    var lx := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
    var ly := Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
    head.rotation.y -= lx * LOOK_SPEED * delta
    pitch = clamp(pitch - ly * LOOK_SPEED * delta, deg_to_rad(-42), deg_to_rad(42))
    camera.rotation.x = pitch

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
            _set_big_screen(
                str(cab.get_meta("title")),
                str(cab.get_meta("system")),
                "X drücken für Spielauswahl"
            )
        else:
            _set_big_screen("ARCADE HALL", "MAME  •  ATARI 7800", "D-Pad: laufen   Rechter Stick: umsehen")

func _update_hud() -> void:
    if current_cabinet >= 0:
        hint_panel.visible = true
        hint_label.visible = true
        hint_label.text = "X  –  Spielauswahl"
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

func _games_for_system(system: String) -> Array[String]:
    if system == "MAME":
        return ["Pac-Man", "Donkey Kong", "Galaga", "Bubble Bobble"]
    return ["Donkey Kong", "Centipede", "Asteroids", "Joust"]

func _open_selection() -> void:
    if current_cabinet < 0:
        return

    var cab := cabinets[current_cabinet]
    selection_games = _games_for_system(str(cab.get_meta("system")))
    selection_index = 0
    selection_open = true

    select_panel.visible = true
    select_title.visible = true
    select_list.visible = true
    hint_panel.visible = false
    hint_label.visible = false

    select_title.text = "%s – SPIELAUSWAHL" % str(cab.get_meta("system"))
    _refresh_selection()

func _refresh_selection() -> void:
    for child in select_list.get_children():
        child.queue_free()

    for i in range(selection_games.size()):
        var row := Label.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        row.add_theme_font_size_override("font_size", 30 if i == selection_index else 24)
        row.text = ("▶  " if i == selection_index else "    ") + selection_games[i]
        row.modulate = Color.WHITE if i == selection_index else Color(0.68,0.72,0.80)
        select_list.add_child(row)

    if not selection_games.is_empty():
        _set_big_screen(selection_games[selection_index], "VORSCHAU", "X = starten   Kreis = zurück")

func _close_selection() -> void:
    selection_open = false
    select_panel.visible = false
    select_title.visible = false
    select_list.visible = false
    if current_cabinet >= 0:
        var cab := cabinets[current_cabinet]
        _set_big_screen(str(cab.get_meta("title")), str(cab.get_meta("system")), "X drücken für Spielauswahl")

func _handle_actions() -> void:
    if selection_open:
        if Input.is_action_just_pressed("move_forward"):
            selection_index = max(0, selection_index - 1)
            _refresh_selection()
        elif Input.is_action_just_pressed("move_back"):
            selection_index = min(selection_games.size() - 1, selection_index + 1)
            _refresh_selection()
        elif Input.is_action_just_pressed("interact"):
            _set_big_screen(selection_games[selection_index], "START", "Emulator-Anbindung folgt als nächster Schritt")
        elif Input.is_action_just_pressed("back"):
            _close_selection()
        return

    if Input.is_action_just_pressed("interact") and current_cabinet >= 0:
        _open_selection()

    if Input.is_action_just_pressed("back"):
        hint_panel.visible = false
        hint_label.visible = false
