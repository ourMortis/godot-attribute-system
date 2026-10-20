extends Node2D
## 属性系统演示脚本
##
## 需要在 Unit/AttributeSystem 节点上装配好这些定义(细节见 attribute_system/ARCHITECTURE.md 第 6 节):
##   strength   : buckets = [ flat(ADD) ]                                default_base = 10
##   attack     : buckets = [ flat(ADD), more(MULTIPLY) ]                default_base = 2
##                dependencies = [ { source = strength, coefficient = 2 } ]
##   max_health : buckets = [ flat(ADD), increased(MULTIPLY_ONE_PLUS) ]  default_base = 100
##   health     : buckets = [ flat(ADD) ]                                default_base = 100
##
## 按键:
##   1 -> 装备武器(给 attack 挂一条 +2 的持续来源, 可叠层)
##   2 -> 卸下武器(按来源整体撤销)
##   3 -> 戴上力量护符(只改 strength, 因为依赖关系 attack 会跟着变)
##   4 -> 摘下力量护符

const SOURCE_WEAPON := &"weapon"
const SOURCE_AMULET := &"amulet"

@onready var attribute_system: AttributeSystem = $AttributeSystem

func _ready() -> void:
	attribute_system.on_attribute_changed.connect(_on_value_changed)
	print("初始状态:")
	print(attribute_system.dump())
	print(attribute_system.describe_plan())

## 一次性的永久改动: 直接折算进裸值, 不留记录
func apply_instant_damage(amount: float) -> void:
	_sheet().apply_source(ModifierSource.create(&"hit", &"health", AttributeModifier.Op.ADD, -amount, &"flat", true))

## 一批修改合并成一次刷新: 换整套装备时用, 避免中途分别触发事件
func equip_loadout() -> void:
	var sheet := _sheet()
	sheet.begin_batch()
	sheet.apply_source(ModifierSource.create(SOURCE_WEAPON, &"attack", AttributeModifier.Op.ADD, 2.0, &"flat"))
	sheet.apply_source(ModifierSource.create(SOURCE_AMULET, &"strength", AttributeModifier.Op.ADD, 5.0, &"flat"))
	sheet.apply_source(ModifierSource.create(&"ring", &"max_health", AttributeModifier.Op.ADD, 0.1, &"increased"))
	sheet.end_batch()

func _sheet() -> AttributeSheet:
	return attribute_system.get_sheet()

func _on_value_changed(attribute_id: StringName, old_value: float, new_value: float) -> void:
	print("  %12s: %8.2f -> %8.2f" % [attribute_id, old_value, new_value])

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("1"):
		equip_weapon()
	elif event.is_action_pressed("2"):
		unequip_weapon()
	elif event.is_action_pressed("3"):
		equip_amulet()
	elif event.is_action_pressed("4"):
		unequip_amulet()

func equip_weapon() -> void:
	# 持续来源: attack +2(flat 桶). stackable = true 时再按一次会叠一层, 变成 +4
	var weapon := ModifierSource.create(SOURCE_WEAPON, &"attack", AttributeModifier.Op.ADD, 2.0, &"flat")
	weapon.stackable = true
	_sheet().apply_source(weapon)
	print("装备武器 -> attack = %.2f" % _sheet().get_value(&"attack"))

func unequip_weapon() -> void:
	_sheet().remove_source(SOURCE_WEAPON)
	print("卸下武器 -> attack = %.2f" % _sheet().get_value(&"attack"))

func equip_amulet() -> void:
	# 派生属性演示: 护符只动 strength, attack 由依赖(2 + strength × 2)自动跟上
	var amulet := ModifierSource.new(SOURCE_AMULET)
	amulet.add(&"strength", AttributeModifier.Op.ADD, 5.0, &"flat")
	_sheet().apply_source(amulet)
	print("戴上护符 -> strength = %.2f, attack = %.2f" % [_sheet().get_value(&"strength"), _sheet().get_value(&"attack")])

func unequip_amulet() -> void:
	_sheet().remove_source(SOURCE_AMULET)
	print("摘下护符 -> strength = %.2f, attack = %.2f" % [_sheet().get_value(&"strength"), _sheet().get_value(&"attack")])
