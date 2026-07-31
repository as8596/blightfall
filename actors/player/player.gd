class_name Player
extends CharacterBody2D
## The player actor. Movement values from GDD §5.
##
## Deliberately not a singleton and not reachable through one (GDD §12, rule 1):
## nothing looks the player up globally, and everything that needs one is handed
## a reference or finds it through Targeting. That is the difference between
## "add a second player" being a week and being a rewrite.

@export_group("Movement")
## 328 px/s at 1280×720 — the GDD's 82 px/s at 320×180, scaled with the
## resolution so the character still crosses the screen in the same time.
@export var move_speed: float = 328.0
## GDD §5: full speed in 0.08s.
@export var time_to_max_speed: float = 0.08
## Not specified; slightly snappier than acceleration so stops read as crisp.
@export var time_to_stop: float = 0.06

## Sprinting. Holding the dash key after a dash keeps you moving fast and
## empties the pool — which is the first thing in the game that makes stamina
## bind at all. GDD §6 wanted "a rhythm limiter that stops panic-rolling"; the
## dodge cooldown was already doing that job on its own, and the four-point pool
## was decoration (docs/M1-NOTES.md).
@export var sprint_speed_scale: float = 1.55
## Points per second while sprinting. At 4 points and 2.0/s a sprint lasts two
## seconds from full, which is a distance rather than a mode.
@export var sprint_drain: float = 2.0
## Below this, sprinting will not start. Stops a sprint that lasts a footstep.
@export var sprint_minimum: float = 0.6

@export_group("Combat")
## GDD §5: 0.8s i-frames on damage.
@export var damage_invuln_time: float = 0.8
## Control loss on being hit. Short — this game blames the player, not the game.
@export var hurt_stun_time: float = 0.18
@export var hurt_knockback_distance: float = 88.0
@export var combo: PlayerComboData

@export_group("Ranged")
## What a loosed arrow is. Set in `player.tscn`; without it the bow refuses to
## draw rather than drawing and firing nothing.
@export var arrow_scene: PackedScene

@export_group("Haul")
## Dropped where the player falls, carrying whatever they were holding.
@export var haul_cache_scene: PackedScene

@export_group("References")
@export var combo_hitbox_shape_path: NodePath = ^"Hitbox/CollisionShape2D"

@onready var input: InputComponent = $InputComponent
@onready var health: HealthComponent = $HealthComponent
@onready var stamina: StaminaComponent = $StaminaComponent
@onready var knockback: KnockbackComponent = $KnockbackComponent
@onready var flash: FlashComponent = $FlashComponent
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var state_machine: StateMachine = $StateMachine
@onready var visual: Sprite2D = $Visual
@onready var animation: AnimationComponent = $AnimationComponent
@onready var inventory: InventoryComponent = $InventoryComponent
@onready var interactor: InteractorComponent = $Interactor
@onready var items: ItemsComponent = $ItemsComponent
@onready var stats: StatsComponent = $StatsComponent
@onready var experience: ExperienceComponent = $ExperienceComponent
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var weapon_arc: WeaponArc = $WeaponArc

## Last committed facing. Drives hitbox placement and the default dodge
## direction. Starts down because that is where a character faces at rest.
var facing: Vector2 = Vector2.DOWN

## The actor's own motion, kept apart from knockback (see KnockbackComponent).
var motion_velocity: Vector2 = Vector2.ZERO

## Dodge lockout (GDD §5: 0.12s cooldown after recovery).
var dodge_cooldown_remaining: float = 0.0

## Combo continuation, tracked here rather than in the Attack state because the
## window outlives the state it belongs to (see PlayerComboData).
var next_combo_index: int = 0

## How long attack has been held, in seconds, and whether that is now enough.
##
## **The light attack still fires on the press**, unchanged. Charging on the
## press instead — tap for light, hold for heavy — would put the whole charge
## threshold's worth of latency on every ordinary swing, and snappy light
## attacks are worth more than a tidier input scheme. So a press swings, and
## *keeping the button down* winds the heavy up underneath it: the charge is
## something you hold into after a swing, not something you wait through before
## one.
var charge: float = 0.0
var charge_ready: bool = false

## Seconds of holding before the heavy is available. Short — this is a beat of
## commitment, not a channel.
const CHARGE_TIME: float = 0.45
var combo_window_remaining: float = 0.0

## Which hand the attack verb comes out of: `Slot.WEAPON` or `Slot.RANGED`.
##
## **Two slots and a toggle, rather than one slot you re-equip.** Both weapons
## are worn at once and the swap is a keypress, because swapping through the
## equipment menu is a thing nobody does with a wolf on them — and a bow you can
## only reach between fights is a bow that never gets used in one.
##
## Tracked on the player rather than in `EquipmentComponent`, because it is not a
## fact about what you are wearing. You are wearing both.
var drawn_slot: ItemData.Slot = ItemData.Slot.WEAPON

var _hitbox_shape: CollisionShape2D
var _spawn_position: Vector2


func _ready() -> void:
	add_to_group(Targeting.TARGET_GROUP)
	add_to_group(SaveGame.GROUP)
	_spawn_position = global_position

	_hitbox_shape = get_node_or_null(combo_hitbox_shape_path) as CollisionShape2D
	if _hitbox_shape != null and _hitbox_shape.shape != null:
		# Unique per instance, so resizing the swing on one player can't resize
		# it on another.
		_hitbox_shape.shape = _hitbox_shape.shape.duplicate()

	hitbox.source = self
	hurtbox.owner_actor = self

	animation.bind(state_machine)
	# Skills outlive the scene; this component does not. Re-push them on every
	# spawn, or a skill taken in the valley is gone the moment you walk into
	# Ambry — the component that knew about it was freed with the level.
	Skills.apply_all(stats)
	health.died.connect(_on_died)
	health.changed.connect(func(current: int, maximum: int) -> void:
		Events.player_health_changed.emit(current, maximum)
		Events.player_stats_changed.emit(stat_block()))
	stamina.changed.connect(func(current: float, maximum: float) -> void:
		Events.player_stamina_changed.emit(current, maximum))
	inventory.changed.connect(func(units: int, limit: int) -> void:
		Events.player_inventory_changed.emit(units, limit)
		Events.player_materials_changed.emit(inventory.contents.duplicate()))
	items.changed.connect(func() -> void:
		Events.player_items_changed.emit(items.items, items.counts)
		# The quiver readout is a fact about the pack, so it moves when the pack
		# does — buying arrows, looting them, dropping them.
		Events.player_weapon_changed.emit(drawn_slot, equipment.item_in(drawn_slot),
			arrows_left()))
	items.refused.connect(func(slot: int) -> void:
		Events.player_item_refused.emit(slot))
	items.selection_changed.connect(func(slot: int) -> void:
		Events.player_hotbar_selected.emit(slot))
	stats.changed.connect(_on_stats_changed)
	experience.changed.connect(func(current: int, need: int, level: int) -> void:
		Events.player_xp_changed.emit(current, need, level))
	experience.leveled.connect(func(level: int) -> void:
		Events.player_leveled.emit(level))
	equipment.changed.connect(func() -> void:
		# Taking off the thing you are holding puts the other hand forward. Left
		# alone, `drawn_slot` would go on naming an empty slot and every click
		# would do nothing with no explanation.
		if equipment.item_in(drawn_slot) == null:
			drawn_slot = ItemData.Slot.WEAPON
		Events.player_equipment_changed.emit(equipment.worn)
		Events.player_weapon_changed.emit(drawn_slot, equipment.item_in(drawn_slot),
			arrows_left())
		# Worn gear writes stats, so the sheet has to be re-read after it moves.
		Events.player_stats_changed.emit(stat_block()))
	hurtbox.hit_taken.connect(_on_hit_taken)
	# `EnemyData.xp_value` has been sitting there unread since M1. This is what
	# reads it — off the bus rather than off a reference, because the enemy has
	# no business knowing a player exists (GDD §12 rule 1).
	Events.enemy_died.connect(_on_enemy_died)

	state_machine.start()
	# Deferred: a listener added later in the same frame — the HUD, on scene
	# load — would miss values emitted during `_ready`, and then show zero hearts
	# until the player first took damage.
	_broadcast_state.call_deferred()


## Wind the heavy up while the button is down, and let go of it when it is not.
##
## Lives on the player rather than in a state, because the hold spans states:
## you press during Move, swing through Attack, and are still holding when it
## drops you back into Idle. A charge owned by any one of those would be reset
## by the transition out of it.
func _tick_charge(delta: float) -> void:
	if combo == null or combo.heavy == null:
		return
	# Not while the bow is out. The hold means something else there — it is the
	# draw — and a charge quietly winding up underneath it would fire a heavy
	# swing the instant the player swapped back to the sword.
	if drawn_slot == ItemData.Slot.RANGED:
		charge = 0.0
		charge_ready = false
		return
	if input.intent.attack_held and health.is_alive():
		charge += delta
		if not charge_ready and charge >= CHARGE_TIME:
			charge_ready = true
			Sfx.play(&"ui_select", -12.0)
			if flash != null:
				flash.flash(0.18)
		return
	charge = 0.0
	charge_ready = false


## Whether a released hold should become a heavy swing rather than nothing.
func consume_heavy() -> bool:
	if not charge_ready or input.intent.attack_held:
		return false
	charge = 0.0
	charge_ready = false
	return true


# ------------------------------------------------------------------- the bow

## The bow, if one is worn and it is the thing in hand. Null otherwise, which is
## the single question every caller actually wants answered: *does attack shoot?*
func drawn_bow() -> ItemData:
	if drawn_slot != ItemData.Slot.RANGED:
		return null
	var item := equipment.item_in(ItemData.Slot.RANGED)
	return item if item != null and item.is_ranged() else null


## Swap which weapon the attack verb comes out of.
##
## Refuses when the slot it would swap to is empty, and says so by returning
## false — a toggle that silently puts an empty hand forward would make the next
## click do nothing for a reason the player cannot see.
func toggle_weapon() -> bool:
	var wanted: ItemData.Slot = ItemData.Slot.RANGED \
		if drawn_slot == ItemData.Slot.WEAPON else ItemData.Slot.WEAPON
	if equipment.item_in(wanted) == null:
		Sfx.play(&"ui_deny", -6.0)
		return false
	drawn_slot = wanted
	# The wind-up belongs to whatever was in hand a moment ago. Carrying it
	# across the swap would let you charge a heavy and loose it as an arrow.
	charge = 0.0
	charge_ready = false
	next_combo_index = 0
	combo_window_remaining = 0.0
	Sfx.play(&"ui_select", -6.0)
	Events.player_weapon_changed.emit(drawn_slot, equipment.item_in(drawn_slot), arrows_left())
	return true


## How many arrows the drawn bow could fire. Zero when there is no bow.
func arrows_left() -> int:
	var bow := drawn_bow()
	if bow == null:
		return 0
	return items.count_of(bow.ranged.ammo_id)


## Take one arrow out of the pack. False when there were none, which is what
## stops the draw state before it starts.
func spend_arrow() -> bool:
	var bow := drawn_bow()
	if bow == null:
		return false
	if not items.take(bow.ranged.ammo_id, 1):
		return false
	Events.player_weapon_changed.emit(drawn_slot, bow, arrows_left())
	return true


## Push current values onto the bus for anything that has just started listening.
func _broadcast_state() -> void:
	Events.player_health_changed.emit(health.current, health.max_health)
	Events.player_stamina_changed.emit(stamina.current, stamina.max_stamina)
	Events.player_inventory_changed.emit(inventory.total(), inventory.capacity)
	Events.player_materials_changed.emit(inventory.contents.duplicate())
	Events.player_items_changed.emit(items.items, items.counts)
	Events.player_hotbar_selected.emit(items.selected)
	Events.player_stats_changed.emit(stat_block())
	Events.player_xp_changed.emit(experience.current, experience.needed(), experience.level)
	Events.player_equipment_changed.emit(equipment.worn)
	Events.player_weapon_changed.emit(drawn_slot, equipment.item_in(drawn_slot), arrows_left())


func _on_enemy_died(enemy: Node) -> void:
	var data: EnemyData = enemy.get("data") if enemy != null else null
	if data != null:
		experience.grant(data.xp_value)


## Push the village's contributions into the components that own the numbers.
## Health raises its ceiling before anything reads it, for the same ordering
## reason the save system has a test for: lowering a max first would clamp away
## containers the player earned.
func _on_stats_changed() -> void:
	health.set_max_health(stats.value(StatsComponent.MAX_HEALTH), false)
	inventory.capacity = stats.value(StatsComponent.CARRY)
	move_speed = float(stats.value(StatsComponent.MOVE_SPEED))
	stamina.max_stamina = stats.base_max_stamina + float(stats.bonus(StatsComponent.STAMINA))
	var faster := stats.regen_speed()
	stamina.regen_delay = stats.base_regen_delay / faster
	stamina.full_regen_time = stats.base_regen_time / faster
	Events.player_stats_changed.emit(stat_block())
	Events.player_inventory_changed.emit(inventory.total(), inventory.capacity)


## The character sheet, as data. Read off the live components and the combo
## resource rather than kept as a second copy — a sheet that can disagree with
## the game is worse than no sheet.
func stat_block() -> Dictionary:
	var dodge := state_machine.get_node_or_null("Dodge")
	var strike := "-"
	if combo != null and combo.length() > 0:
		var steps: Array[String] = []
		for i in combo.length():
			steps.append(str(combo.step(i).damage))
		strike = " / ".join(steps)
	return {
		"health": health.current,
		"max_health": health.max_health,
		"max_stamina": stamina.max_stamina,
		"capacity": inventory.capacity,
		"move_speed": move_speed,
		"damage": strike,
		"damage_bonus": stats.bonus(StatsComponent.DAMAGE),
		"reach_bonus": stats.bonus(StatsComponent.REACH),
		"granted_by": stats.sources(),
		"dodge_distance": dodge.distance if dodge != null else 0.0,
		"regen_delay": stamina.regen_delay,
		"regen_time": stamina.full_regen_time,
	}


func _process(delta: float) -> void:
	dodge_cooldown_remaining = maxf(dodge_cooldown_remaining - delta, 0.0)
	if combo_window_remaining > 0.0:
		combo_window_remaining = maxf(combo_window_remaining - delta, 0.0)
		if combo_window_remaining == 0.0:
			next_combo_index = 0

	_tick_charge(delta)
	_try_swap()
	_try_interact()
	_try_hotbar()


## The weapon toggle. Allowed from standing, walking and the recovery of a swing
## — the same places the hotbar is — but never mid-draw or mid-roll, where the
## thing in your hands is already committed to something.
func _try_swap() -> void:
	if not (state_machine.is_in(&"Idle") or state_machine.is_in(&"Move")):
		return
	if not input.consume_swap():
		return
	@warning_ignore("return_value_discarded")
	toggle_weapon()


## Interacting is handled here rather than in a state, because it is not a state
## the player enters — nothing about the character changes, the world just
## responds. Gated to standing and walking: mid-swing and mid-roll you have
## already committed to something else, and a door that opens out of a dodge
## would make dodging near a building unusable.
func _try_interact() -> void:
	if not (state_machine.is_in(&"Idle") or state_machine.is_in(&"Move")):
		return
	if not input.consume_interact():
		return
	if not interactor.try_interact():
		# Nothing in range. The press is spent either way — holding a stale
		# interact that fires the moment you walk up to a door is worse than
		# dropping it.
		pass


## Same gating as interacting: standing or walking only. Eating out of a dodge
## would make the i-frames a free window to heal in, which is a different game.
func _try_hotbar() -> void:
	if not (state_machine.is_in(&"Idle") or state_machine.is_in(&"Move")):
		return
	# Numbers and the wheel *select*; the tool verb uses. Skimming the bar must
	# never eat anything on the way past.
	var slot := input.hotbar_pressed()
	if slot >= 0:
		items.select(slot)
	items.cycle(input.take_hotbar_scroll())
	if input.consume_tool():
		@warning_ignore("return_value_discarded")
		items.use_selected(self)


## Accelerate toward `desired` and move. Knockback rides on top rather than
## being blended in, so a hit still moves you during a full-speed run.
func apply_motion(delta: float, desired: Vector2) -> void:
	var rate := move_speed / maxf(time_to_max_speed, 0.0001)
	if desired == Vector2.ZERO:
		rate = move_speed / maxf(time_to_stop, 0.0001)
	motion_velocity = motion_velocity.move_toward(desired, rate * delta)
	_move()


## Bypass acceleration. The dodge drives its own speed curve.
func set_motion(desired: Vector2) -> void:
	motion_velocity = desired
	_move()


func _move() -> void:
	velocity = motion_velocity + knockback.velocity
	move_and_slide()


## Walk velocity for the current input, scaled (attacks move at 25% / 0%).
func desired_walk_velocity(speed_scale: float = 1.0) -> Vector2:
	return input.intent.move * move_speed * speed_scale


## Where the cursor is, as a unit vector from the character.
##
## Attacks aim here through a full 360° while walking stays 8-directional. Those
## are different jobs: movement wants to feel like a grid, and a swing wants to
## go where you pointed. The body sprite still picks the nearest of its four
## directions from this, which is what keeps a four-way sprite sheet honest
## against a 360° swing.
## Set to aim without a pointer or a pad — a cutscene, a scripted swing, a test
## driving the character with no mouse in the window.
var aim_override: Vector2 = Vector2.ZERO


func aim_direction() -> Vector2:
	if aim_override != Vector2.ZERO:
		return aim_override.normalized()
	# A pad aims with the right stick; a mouse aims with the cursor. Whichever
	# was touched last wins, which is the only rule that survives someone
	# picking up a controller mid-session.
	if input.intent.aim_stick != Vector2.ZERO:
		return input.intent.aim_stick.normalized()
	var target := WorldView.mouse_world_position(self)
	var offset := target - global_position
	return offset.normalized() if offset.length_squared() > 1.0 else facing


## Face the cursor, without snapping to eight.
func face_aim() -> void:
	facing = aim_direction()


func face(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		facing = direction.normalized()


## Point the combo hitbox along `facing` and load one hit's numbers into it.
func configure_hitbox(step: ComboStepData) -> void:
	hitbox.rotation = facing.angle()
	# The combo's frame data plus what you are carrying and what the town has
	# rebuilt. Both bonuses were being *computed* and shown on the character
	# sheet and neither reached the hitbox, so a forge and a sword were both
	# decoration — the numbers moved and nothing died faster.
	hitbox.damage = maxi(step.damage + stats.bonus(StatsComponent.DAMAGE), 1)
	hitbox.knockback_distance = step.knockback_distance
	hitbox.hitstop = step.hitstop
	hitbox.screen_shake = step.screen_shake
	hitbox.impact_sfx = step.impact_sfx
	if _hitbox_shape != null:
		var rect := _hitbox_shape.shape as RectangleShape2D
		# Reach scales the box the same way it scales the drawn arc, or the
		# picture and the thing that can hurt you stop agreeing — which is the
		# one promise `WeaponArc` exists to keep.
		var reach := reach_scale()
		if rect != null:
			rect.size = step.hitbox_size * reach
		_hitbox_shape.position = Vector2(step.hitbox_offset * reach, 0.0)


## How much further than shipped the swing goes, as a multiplier.
func reach_scale() -> float:
	return 1.0 + float(stats.bonus(StatsComponent.REACH)) / 100.0


## True while the dash key is held, there is fuel, and the player is moving.
## Sprinting is a *continuation* of the dash rather than its own verb: you
## commit by tapping, and keeping your thumb down keeps the commitment.
var sprinting: bool = false


func update_sprint(delta: float) -> bool:
	var wants := input.intent.dodge_held and input.intent.move != Vector2.ZERO
	if not wants:
		sprinting = false
		return false
	# Starting costs more than continuing, so a pool scraping the bottom does
	# not flicker in and out of a sprint every frame.
	if not sprinting and stamina.current < sprint_minimum:
		return false
	if not stamina.spend(sprint_drain * delta):
		sprinting = false
		return false
	sprinting = true
	return true


func can_dodge() -> bool:
	return dodge_cooldown_remaining <= 0.0 and stamina.can_spend(1.0)


func is_alive() -> bool:
	return health.is_alive()


## Consulted by Targeting — a dying player stops being a valid target so
## enemies don't keep lunging at a corpse.
func is_targetable() -> bool:
	return health.is_alive()


func _on_hit_taken(hitbox_hit: Hitbox) -> void:
	if not health.is_alive():
		return
	hurtbox.start_damage_iframes(damage_invuln_time)
	flash.flash()
	Sfx.play(&"player_hurt")
	Events.screen_shake_requested.emit(8.0, 0.2)
	HitStop.freeze(0.08)
	if state_machine.has_state(&"Hurt"):
		state_machine.transition_to(&"Hurt", {"source": hitbox_hit.source})


func _on_died() -> void:
	_drop_haul()
	Events.player_died.emit(self)
	state_machine.transition_to(&"Dead")


## Leave the haul where the player fell (GDD §15 A4). Nothing is destroyed —
## it waits, and it is the reason turning back early is ever the right call.
func _drop_haul() -> void:
	if inventory.total() <= 0 or haul_cache_scene == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	HaulCache.drop(get_tree(), haul_cache_scene, parent, global_position, inventory.take_all())


# ------------------------------------------------------------------ saving
#
# Three methods and a group membership — see systems/save/save_game.gd. Adding
# tools, heart shards or whetstones later means extending `save_data` and
# `load_data`, and touching nothing else.

func save_id() -> StringName:
	return &"player"


func save_data() -> Dictionary:
	return {
		"position": SaveGame.write_vector2(global_position),
		"facing": SaveGame.write_vector2(facing),
		"health": health.current,
		"max_health": health.max_health,
		"max_stamina": stamina.max_stamina,
		"inventory": inventory.save_data(),
		"items": items.save_data(),
		"experience": experience.save_data(),
		"equipment": equipment.save_data(),
		"drawn_slot": int(drawn_slot),
	}


func load_data(data: Dictionary) -> void:
	global_position = SaveGame.read_vector2(data, "position", global_position)
	facing = SaveGame.read_vector2(data, "facing", facing)

	# Order matters: raise the ceiling before restoring current, or a save with
	# more heart containers than the default clamps down to the default.
	health.set_max_health(SaveGame.read_int(data, "max_health", health.max_health), false)
	# ...and tell the stat sheet, or the next thing that touches stats will
	# recompute health off the *shipped* base and take the extra containers
	# straight back off again.
	stats.set_base(StatsComponent.MAX_HEALTH,
		health.max_health - stats.bonus(StatsComponent.MAX_HEALTH))
	health.current = clampi(SaveGame.read_int(data, "health", health.current), 0, health.max_health)
	health.changed.emit(health.current, health.max_health)

	stamina.max_stamina = SaveGame.read_float(data, "max_stamina", stamina.max_stamina)
	stamina.refill()

	var carried: Variant = data.get("inventory")
	if carried is Dictionary:
		inventory.load_data(carried)

	var earned: Variant = data.get("experience")
	if earned is Dictionary:
		experience.load_data(earned)

	var worn: Variant = data.get("equipment")
	if worn is Dictionary:
		equipment.load_data(worn, Items.all())

	# After the equipment, so a save that had the bow out can be checked against
	# what actually got restored — and falls back to the sword if it did not.
	drawn_slot = SaveGame.read_int(data, "drawn_slot", int(ItemData.Slot.WEAPON)) as ItemData.Slot
	if not ItemData.HAND_SLOTS.has(drawn_slot) or equipment.item_in(drawn_slot) == null:
		drawn_slot = ItemData.Slot.WEAPON

	# Whatever the player was doing when they saved, they are standing still now.
	motion_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	knockback.clear()
	hurtbox.clear_iframes()
	input.clear_buffers()
	next_combo_index = 0
	combo_window_remaining = 0.0
	dodge_cooldown_remaining = 0.0
	charge = 0.0
	charge_ready = false
	if health.is_alive():
		hurtbox.disabled = false
		input.enabled = true
		flash.clear()
		state_machine.transition_to(&"Idle")
	else:
		state_machine.transition_to(&"Dead")


## Debug respawn (F5 in the prototype room).
func respawn() -> void:
	global_position = _spawn_position
	motion_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	knockback.clear()
	health.reset()
	stamina.refill()
	hurtbox.clear_iframes()
	hurtbox.disabled = false
	flash.clear()
	input.enabled = true
	input.clear_buffers()
	next_combo_index = 0
	combo_window_remaining = 0.0
	dodge_cooldown_remaining = 0.0
	state_machine.transition_to(&"Idle")
