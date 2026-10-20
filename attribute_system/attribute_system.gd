@tool
class_name AttributeSystem extends Node
## 每个实体一个的"属性系统门面"节点
##
## ★ 一个实体(玩家 / 敌人 / 生物)在自己的场景树里挂一个 AttributeSystem,
##   它只持有该实体唯一的一张 AttributeSheet; 它不是单例, 也不管理其它实体.
## ★ 属性定义(AttributeDefinition)仍然是可共享的只读 Resource:
##   玩家和敌人可以引用同一批 .tres 定义, 但各自的裸值 / 来源 / 缓存完全独立,
##   因为运行时状态都在本节点自己的 AttributeSheet 里.
## ★ 定义统一收在 AttributeSet 里; 同一份 AttributeSet 的求值计划只编译一次,
##   所有引用它的实体共享同一个 EvaluationPlan.
##
## 职责: 装配定义 -> 编译求值计划 -> 建立本实体的属性表 -> 转发调用 -> 合成事件
## 不负责: 计算(AttributeEvaluator) / 桶规则(BucketSpec) / 状态(AttributeSheet + AttributeSlot)
## 配置在编辑器中完成, 运行期将定义视为不可变: 计划只在加载时编译一次.
##
## 用法:
##   var system := $AttributeSystem
##   system.apply_source(ModifierSource.create(&"weapon", &"attack", AttributeModifier.Op.ADD, 2.0, &"flat"))
##   print(system.get_value(&"attack"))
signal on_sheet_ready(sheet: AttributeSheet)
signal on_attribute_changed(attribute_id: StringName, old_value: float, new_value: float)
signal on_source_applied(source_id: StringName)
signal on_source_removed(source_id: StringName)

## 本实体唯一的属性表(首次使用前会自动建立)
var sheet: AttributeSheet

@export var attribute_set: AttributeSet ## 本实体的属性配置集(各实体可共享同一份资源)
@export var auto_refresh: bool = true: ## 变更后是否立即重算并广播(关掉则读取时才惰性重算)
	set(value):
		auto_refresh = value
		if sheet:
			sheet.auto_refresh = value

var plan: EvaluationPlan ## 共享的求值计划(只读)
var evaluator: AttributeEvaluator ## 共享的求值器(无实体状态)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_ready()

# ---------------------------------------------------------------- 定义与计划

## 加载期准备一次: 取得(或编译)共享计划 -> 建立本实体的属性表
func _compile() -> void:
	if not attribute_set:
		push_error("[AttributeSystem] 未配置 AttributeSet: %s" % get_path())
		plan = EvaluationPlan.new()
		var empty: Array[AttributeDefinition] = []
		plan.compile(empty)
		evaluator = AttributeEvaluator.new(plan)
		_create_sheet()
		return
	plan = attribute_set.get_plan()
	evaluator = attribute_set.get_evaluator()
	_create_sheet()

## 校验当前配置, 不创建任何运行时状态
## 编辑器里会通过 _get_configuration_warnings() 显示在节点警告中
func validate_configuration() -> PackedStringArray:
	if not attribute_set:
		return PackedStringArray(["没有配置 AttributeSet"])
	return attribute_set.validate()

func _get_configuration_warnings() -> PackedStringArray:
	return validate_configuration()

func has_definition(attribute_id: StringName) -> bool:
	return attribute_set != null and attribute_set.has_definition(attribute_id)

func get_definition(attribute_id: StringName) -> AttributeDefinition:
	return attribute_set.get_definition(attribute_id) if attribute_set else null

func get_definition_ids() -> Array[StringName]:
	if not attribute_set:
		return []
	return attribute_set.get_definition_ids()

## 打印当前求值计划(拓扑顺序 + 依赖边 + 编译期错误)
func describe_plan() -> String:
	_ensure_ready()
	return plan.describe()

# ---------------------------------------------------------------- 属性表

## 取本实体的属性表(需要完整控制权时使用: 手动批量、连接细粒度事件、调试等)
func get_sheet() -> AttributeSheet:
	_ensure_ready()
	return sheet

func has_attribute(attribute_id: StringName) -> bool:
	_ensure_ready()
	return sheet.has(attribute_id)

func get_attribute_ids() -> Array[StringName]:
	_ensure_ready()
	return sheet.get_attribute_ids()

# ---------------------------------------------------------------- 转发接口

func get_value(attribute_id: StringName) -> float:
	_ensure_ready()
	return sheet.get_value(attribute_id)

func get_base_value(attribute_id: StringName) -> float:
	_ensure_ready()
	return sheet.get_base_value(attribute_id)

func set_base_value(attribute_id: StringName, value: float) -> void:
	_ensure_ready()
	sheet.set_base_value(attribute_id, value)

func apply_source(source: ModifierSource) -> bool:
	_ensure_ready()
	return sheet.apply_source(source)

func remove_source(source_id: StringName) -> bool:
	_ensure_ready()
	return sheet.remove_source(source_id)

func has_source(source_id: StringName) -> bool:
	_ensure_ready()
	return sheet.has_source(source_id)

func get_source(source_id: StringName) -> ModifierSource:
	_ensure_ready()
	return sheet.get_source(source_id)

func set_source_stack(source_id: StringName, count: int) -> bool:
	_ensure_ready()
	return sheet.set_source_stack(source_id, count)

func set_modifier_value(source_id: StringName, modifier_uid: StringName, value: float) -> bool:
	_ensure_ready()
	return sheet.set_modifier_value(source_id, modifier_uid, value)

func tick(delta: float) -> void:
	_ensure_ready()
	sheet.tick(delta)

func begin_batch() -> void:
	_ensure_ready()
	sheet.begin_batch()

func end_batch() -> void:
	_ensure_ready()
	sheet.end_batch()

func snapshot() -> Dictionary:
	_ensure_ready()
	return sheet.snapshot()

func restore(data: Dictionary) -> void:
	_ensure_ready()
	sheet.restore(data)

## 打印本实体的属性现场(调试用)
func dump() -> String:
	_ensure_ready()
	return "实体 %s\n%s" % [get_path(), sheet.dump()]

# ---------------------------------------------------------------- 内部

## 允许在 _ready 之前或 inspector 装配完成后被调用: 首次使用会自动编译并建表
func _ensure_ready() -> void:
	if not sheet:
		_compile()

func _create_sheet() -> void:
	sheet = AttributeSheet.new(plan, evaluator, auto_refresh)
	sheet.on_value_changed.connect(_on_sheet_value_changed)
	sheet.on_source_applied.connect(_on_sheet_source_applied)
	sheet.on_source_removed.connect(_on_sheet_source_removed)
	on_sheet_ready.emit(sheet)

func _on_sheet_value_changed(attribute_id: StringName, old_value: float, new_value: float) -> void:
	on_attribute_changed.emit(attribute_id, old_value, new_value)

func _on_sheet_source_applied(source_id: StringName) -> void:
	on_source_applied.emit(source_id)

func _on_sheet_source_removed(source_id: StringName) -> void:
	on_source_removed.emit(source_id)
