extends Node3D

const WALK_SPEED := 3.2
const LOOK_SPEED := 1.8
const INTERACT_DISTANCE := 2.4
const CABINET_COUNT := 6

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var hud_label: Label
var hint_label: Label
var controller_label: Label
var cabinets: Array[Node3D] = []
var pitch := 0.0
var current_cabinet := -1

func _ready() -> void:
    _build_environment()
    _build_hall()
    _build_player()
    _build_hud()
    _build_cabinets()
    _update_controller_status()

func _physics_process(delta: float) -> void:
    _move_player(delta)
    _look(delta)
    _find_nearest_cabinet()
    _update_hud()
    _handle_actions()

func _build_environment() -> void:
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.01, 0.012, 0.018)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.28, 0.32, 0.42)
    env.ambient_light_energy = 0.7
    world_env.environment = env
    add_child(world_env)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -25, 0)
    light.light_energy = 1.0
    add_child(light)

func _mat(color: Color, emission := false) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.65
    if emission:
        m.emission_enabled = true
        m.emission = color
        m.emission_energy_multiplier = 1.8
    return m

func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, material: Material, collision := false) -> MeshInstance3D:
    var mesh_i := MeshInstance3D.new()
    mesh_i.name = name
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_i.mesh = mesh
    mesh_i.position = pos
    mesh_i.material_override = material
    parent.add_child(mesh_i)

    if collision:
        var body := StaticBody3D.new()
        var shape := CollisionShape3D.new()
        var box_shape := BoxShape3D.new()
        box_shape.size = size
        shape.shape = box_shape
        body.position = pos
        body.add_child(shape)
        parent.add_child(body)
    return mesh_i

func _build_hall() -> void:
    var hall := Node3D.new()
    hall.name = "Hall"
    add_child(hall)

    _box(hall, "Floor", Vector3(18, 0.25, 22), Vector3(0, -0.125, -2), _mat(Color(0.075,0.08,0.095)), true)
    _box(hall, "Ceiling", Vector3(18, 0.2, 22), Vector3(0, 4.2, -2), _mat(Color(0.04,0.04,0.055)))
    _box(hall, "BackWall", Vector3(18, 4.3, 0.25), Vector3(0, 2.05, -13), _mat(Color(0.07,0.065,0.09)), true)
    _box(hall, "FrontWall", Vector3(18, 4.3, 0.25), Vector3(0, 2.05, 9), _mat(Color(0.05,0.05,0.065)), true)
    _box(hall, "LeftWall", Vector3(0.25, 4.3, 22), Vector3(-9, 2.05, -2), _mat(Color(0.065,0.055,0.08)), true)
    _box(hall, "RightWall", Vector3(0.25, 4.3, 22), Vector3(9, 2.05, -2), _mat(Color(0.055,0.065,0.085)), true)

    # Simple ceiling light strips.
    for z in [-10.0, -5.0, 0.0, 5.0]:
        _box(hall, "Strip", Vector3(8.0, 0.04, 0.10), Vector3(0, 4.05, z), _mat(Color(0.45,0.58,0.9), true))

func _build_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0, 1.0, 5.0)

    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.75
    collision.shape = capsule
    player.add_child(collision)

    head = Node3D.new()
    head.name = "Head"
    head.position = Vector3(0, 0.65, 0)
    player.add_child(head)

    camera = Camera3D.new()
    camera.name = "Camera"
    camera.current = true
    camera.fov = 72
    head.add_child(camera)

    add_child(player)

func _build_cabinets() -> void:
    var defs = [
        {"name":"MAME 1", "system":"MAME", "pos":Vector3(-6.6,0,-8.8), "rot":0.0},
        {"name":"MAME 2", "system":"MAME", "pos":Vector3(-2.2,0,-8.8), "rot":0.0},
        {"name":"MAME 3", "system":"MAME", "pos":Vector3(2.2,0,-8.8), "rot":0.0},
        {"name":"MAME 4", "system":"MAME", "pos":Vector3(6.6,0,-8.8), "rot":0.0},
        {"name":"ATARI 1", "system":"ATARI 7800", "pos":Vector3(-7.2,0,-2.0), "rot":90.0},
        {"name":"ATARI 2", "system":"ATARI 7800", "pos":Vector3(7.2,0,-2.0), "rot":-90.0},
    ]

    for d in defs:
        var cab := _make_cabinet(d["name"], d["system"])
        cab.position = d["pos"]
        cab.rotation_degrees.y = d["rot"]
        add_child(cab)
        cabinets.append(cab)

func _make_cabinet(title: String, system: String) -> Node3D:
    var cab := Node3D.new()
    cab.name = title
    cab.set_meta("system", system)
    cab.set_meta("title", title)

    var dark := _mat(Color(0.055,0.06,0.075))
    var trim := _mat(Color(0.16,0.18,0.24))
    var screen_mat := _mat(Color(0.06,0.55,0.78), true) if system == "MAME" else _mat(Color(0.82,0.18,0.09), true)

    _box(cab, "Body", Vector3(1.15, 2.35, 0.75), Vector3(0,1.175,0), dark, true)
    _box(cab, "Top", Vector3(1.25, 0.35, 0.82), Vector3(0,2.18,-0.02), trim)
    _box(cab, "Screen", Vector3(0.86, 0.65, 0.035), Vector3(0,1.55,0.393), screen_mat)
    _box(cab, "Controls", Vector3(1.0, 0.12, 0.40), Vector3(0,1.08,0.54), trim)

    var marquee := Label3D.new()
    marquee.text = title
    marquee.font_size = 42
    marquee.position = Vector3(0,2.20,0.43)
    marquee.outline_size = 6
    marquee.modulate = Color.WHITE
    cab.add_child(marquee)

    var sys_label := Label3D.new()
    sys_label.text = system
    sys_label.font_size = 24
    sys_label.position = Vector3(0,0.58,0.40)
    sys_label.outline_size = 4
    cab.add_child(sys_label)

    return cab

func _build_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    var panel := ColorRect.new()
    panel.position = Vector2(22, 18)
    panel.size = Vector2(470, 118)
    panel.color = Color(0.02,0.025,0.04,0.78)
    layer.add_child(panel)

    hud_label = Label.new()
    hud_label.position = Vector2(42, 32)
    hud_label.text = "ARCADE HALL v0.1"
    hud_label.add_theme_font_size_override("font_size", 24)
    layer.add_child(hud_label)

    hint_label = Label.new()
    hint_label.position = Vector2(42, 70)
    hint_label.text = "L-Stick: laufen   R-Stick: umsehen   X: wählen"
    hint_label.add_theme_font_size_override("font_size", 18)
    layer.add_child(hint_label)

    controller_label = Label.new()
    controller_label.position = Vector2(42, 102)
    controller_label.add_theme_font_size_override("font_size", 16)
    layer.add_child(controller_label)

    var crosshair := Label.new()
    crosshair.text = "+"
    crosshair.position = Vector2(632, 347)
    crosshair.add_theme_font_size_override("font_size", 28)
    layer.add_child(crosshair)

func _move_player(delta: float) -> void:
    var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var basis := Basis(Vector3.UP, head.rotation.y)
    var dir := (basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()
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
    pitch = clamp(pitch - ly * LOOK_SPEED * delta, deg_to_rad(-55), deg_to_rad(55))
    camera.rotation.x = pitch

func _find_nearest_cabinet() -> void:
    current_cabinet = -1
    var best := INTERACT_DISTANCE
    for i in cabinets.size():
        var d := player.global_position.distance_to(cabinets[i].global_position)
        if d < best:
            best = d
            current_cabinet = i

func _update_hud() -> void:
    if current_cabinet >= 0:
        var cab := cabinets[current_cabinet]
        hint_label.text = "X drücken: %s  [%s]" % [cab.get_meta("title"), cab.get_meta("system")]
    else:
        hint_label.text = "L-Stick: laufen   R-Stick: 360° umsehen   X: Automat"

func _update_controller_status() -> void:
    var pads := Input.get_connected_joypads()
    if pads.is_empty():
        controller_label.text = "Controller: keiner erkannt | Fire-TV-Fernbedienung/Keyboard möglich"
    else:
        var names: Array[String] = []
        for id in pads:
            names.append(Input.get_joy_name(id))
        controller_label.text = "Controller: " + ", ".join(names)

func _handle_actions() -> void:
    if Input.is_action_just_pressed("interact") and current_cabinet >= 0:
        var cab := cabinets[current_cabinet]
        hud_label.text = "AUSGEWÄHLT: %s" % cab.get_meta("title")
        hint_label.text = "Emulator-Start kommt in v0.2"
    if Input.is_action_just_pressed("back"):
        hud_label.text = "ARCADE HALL v0.1"
        hint_label.text = "Zurück – Halle bleibt aktiv"
