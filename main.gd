extends Node3D

const WALK_SPEED := 2.45
const LOOK_SPEED := 1.55
const INTERACT_DISTANCE := 2.25
const HALL_HALF_WIDTH := 4.8
const HALL_FRONT_Z := 5.8
const HALL_BACK_Z := -12.8

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var hint_panel: ColorRect
var hint_label: Label
var controller_label: Label

var cabinets: Array[Node3D] = []
var pitch := 0.0
var current_cabinet := -1

func _ready() -> void:
    _build_environment()
    _build_hall()
    _build_player()
    _build_cabinets()
    _build_hud()
    _update_controller_status()

func _physics_process(delta: float) -> void:
    _move_player(delta)
    _look(delta)
    _find_nearest_cabinet()
    _update_hud()
    _handle_actions()

func _mat(color: Color, emission := false, energy := 1.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.6
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
    env.background_color = Color(0.004, 0.005, 0.01)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.16, 0.18, 0.26)
    env.ambient_light_energy = 0.38
    world_env.environment = env
    add_child(world_env)

    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-55, -25, 0)
    key.light_energy = 0.35
    add_child(key)

func _build_hall() -> void:
    var hall := Node3D.new()
    hall.name = "Hall"
    add_child(hall)

    var floor_mat := _mat(Color(0.035, 0.04, 0.055))
    var wall_mat := _mat(Color(0.025, 0.03, 0.045))
    var ceiling_mat := _mat(Color(0.018, 0.02, 0.03))

    _box(hall, "Floor", Vector3(10.0, 0.20, 19.0), Vector3(0, -0.10, -3.5), floor_mat, true)
    _box(hall, "Ceiling", Vector3(10.0, 0.18, 19.0), Vector3(0, 3.20, -3.5), ceiling_mat)
    _box(hall, "LeftWall", Vector3(0.18, 3.4, 19.0), Vector3(-5.0, 1.6, -3.5), wall_mat, true)
    _box(hall, "RightWall", Vector3(0.18, 3.4, 19.0), Vector3(5.0, 1.6, -3.5), wall_mat, true)
    _box(hall, "BackWall", Vector3(10.0, 3.4, 0.18), Vector3(0, 1.6, -13.0), wall_mat, true)
    _box(hall, "FrontWall", Vector3(10.0, 3.4, 0.18), Vector3(0, 1.6, 6.0), wall_mat, true)

    # Center runner / carpet strip to make the aisle read more like an arcade.
    _box(hall, "CarpetRunner", Vector3(2.6, 0.025, 17.4), Vector3(0, 0.015, -3.5), _mat(Color(0.055, 0.025, 0.075)))

    # Ceiling neon strips.
    var cyan := _mat(Color(0.08, 0.72, 0.95), true, 2.4)
    var magenta := _mat(Color(0.95, 0.08, 0.55), true, 2.1)

    for z in [-10.5, -6.5, -2.5, 1.5, 5.0]:
        _box(hall, "NeonCyan", Vector3(2.8, 0.035, 0.07), Vector3(-1.65, 3.08, z), cyan)
        _box(hall, "NeonMagenta", Vector3(2.8, 0.035, 0.07), Vector3(1.65, 3.08, z), magenta)

    # Rear sign
    var sign := Label3D.new()
    sign.text = "ARCADE HALL"
    sign.font_size = 96
    sign.position = Vector3(0, 2.55, -12.78)
    sign.outline_size = 8
    sign.modulate = Color(0.15, 0.85, 1.0)
    hall.add_child(sign)

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
    # Rows face the central aisle.
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

    var body_mat := _mat(Color(0.028,0.032,0.046))
    var side_mat := _mat(Color(0.09,0.105,0.14))
    var trim_mat := _mat(Color(0.16,0.18,0.23))
    var screen_mat := _mat(Color(0.07,0.78,0.95), true, 2.3) if system == "MAME" else _mat(Color(0.95,0.16,0.06), true, 2.2)

    # Slightly taller and deeper proportions.
    _box(cab, "Body", Vector3(1.28, 2.48, 0.82), Vector3(0,1.24,0), body_mat, true)
    _box(cab, "Top", Vector3(1.40, 0.38, 0.90), Vector3(0,2.29,-0.01), side_mat)
    _box(cab, "LowerFront", Vector3(1.08, 0.82, 0.05), Vector3(0,0.56,0.435), trim_mat)
    _box(cab, "Screen", Vector3(0.90, 0.66, 0.045), Vector3(0,1.60,0.438), screen_mat)
    _box(cab, "Controls", Vector3(1.08, 0.12, 0.46), Vector3(0,1.11,0.56), side_mat)

    # Joystick
    _box(cab, "Stick", Vector3(0.08,0.20,0.08), Vector3(-0.25,1.24,0.63), trim_mat)
    var ball := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.07
    sphere.height = 0.14
    ball.mesh = sphere
    ball.position = Vector3(-0.25,1.36,0.63)
    ball.material_override = screen_mat
    cab.add_child(ball)

    # Two buttons
    for x in [0.14, 0.32]:
        var btn := MeshInstance3D.new()
        var cyl := CylinderMesh.new()
        cyl.top_radius = 0.055
        cyl.bottom_radius = 0.055
        cyl.height = 0.035
        btn.mesh = cyl
        btn.rotation_degrees.x = 90
        btn.position = Vector3(x,1.20,0.67)
        btn.material_override = screen_mat
        cab.add_child(btn)

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

    hint_panel = ColorRect.new()
    hint_panel.position = Vector2(415, 610)
    hint_panel.size = Vector2(450, 64)
    hint_panel.color = Color(0.015,0.018,0.03,0.82)
    hint_panel.visible = false
    layer.add_child(hint_panel)

    hint_label = Label.new()
    hint_label.position = Vector2(440, 626)
    hint_label.size = Vector2(400, 34)
    hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint_label.add_theme_font_size_override("font_size", 22)
    hint_label.visible = false
    layer.add_child(hint_label)

    controller_label = Label.new()
    controller_label.position = Vector2(22, 18)
    controller_label.add_theme_font_size_override("font_size", 14)
    controller_label.modulate = Color(0.72,0.75,0.82,0.72)
    layer.add_child(controller_label)

    var crosshair := Label.new()
    crosshair.text = "•"
    crosshair.position = Vector2(635, 345)
    crosshair.add_theme_font_size_override("font_size", 24)
    crosshair.modulate = Color(1,1,1,0.45)
    layer.add_child(crosshair)

func _move_player(delta: float) -> void:
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

func _update_hud() -> void:
    if current_cabinet >= 0:
        var cab := cabinets[current_cabinet]
        hint_panel.visible = true
        hint_label.visible = true
        hint_label.text = "X  –  %s spielen" % str(cab.get_meta("title"))
    else:
        hint_panel.visible = false
        hint_label.visible = false

func _update_controller_status() -> void:
    var pads := Input.get_connected_joypads()
    if pads.is_empty():
        controller_label.text = "Kein Gamecontroller erkannt"
    else:
        var names: Array[String] = []
        for id in pads:
            names.append(Input.get_joy_name(id))
        controller_label.text = ", ".join(names)

func _handle_actions() -> void:
    if Input.is_action_just_pressed("interact") and current_cabinet >= 0:
        var cab := cabinets[current_cabinet]
        hint_label.text = "%s – Emulator folgt in v0.3" % str(cab.get_meta("title"))

    if Input.is_action_just_pressed("back"):
        hint_panel.visible = false
        hint_label.visible = false
