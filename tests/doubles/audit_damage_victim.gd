class_name AuditDamageVictim
extends Damageable
var health := HealthComponent.new()

func _ready() -> void:
	add_child(health)
	health.reset(100.0)
	add_to_group("enemies")
	health.damaged.connect(_on_damaged)

func _on_damaged(result: DamageResult) -> void:
	EventBus.enemy_damaged.emit(self, result)

func apply_damage(payload: DamagePayload) -> DamageResult:
	return health.take_damage(payload)

func is_alive() -> bool:
	return not health.is_dead()

func get_health_fraction() -> float:
	return health.get_health_ratio()
