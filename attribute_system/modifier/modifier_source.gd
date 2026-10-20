class_name ModifierSource extends RefCounted
## 一次修改的"来源": 一件装备 / 一个 buff / 一个天赋 / 一次即时结算
##
## ★ 来源不直接改数值, 只负责"提交自己要贡献哪些修改器",
##   由 AttributeSheet 统一入账、统一撤销(这样才有可追踪 / 可回放 / 可网络同步)
## ★ instant = true 时, 修改会被直接折算进 base_value 并且不保留任何记录,
##   适合"当前生命值"这类一次性生效的改动
var source_id: StringName = &"" ## 唯一标识, 也是批量撤销的钥匙
var display_name: String = ""
var modifiers: Array[AttributeModifier] = []
var tags: Array[StringName] = []
var instant: bool = false ## 即时生效: 不留记录
var stackable: bool = false ## 是否可叠层
var stack_count: int = 1 ## 叠层层数(每层都会完整贡献一遍 modifiers)
var duration: float = 0.0 ## 持续时间, 0 = 永久
var remaining_time: float = 0.0 ## 运行时剩余时间
var enabled: bool = true

func _init(source_id_: StringName = &"") -> void:
	source_id = source_id_

## 快捷构造: 单条修改器的来源
static func create(source_id_: StringName, target_id: StringName, op: AttributeModifier.Op, value: float, bucket: StringName = &"default", instant_: bool = false) -> ModifierSource:
	var source := ModifierSource.new(source_id_)
	source.modifiers.append(AttributeModifier.create(target_id, op, value, bucket))
	source.instant = instant_
	return source

## 链式追加一条修改器(用于一个来源同时影响多个属性的情况)
func add_modifier(modifier: AttributeModifier) -> ModifierSource:
	if modifier:
		modifiers.append(modifier)
	return self

## 按指定属性的某个桶追加一条修改器
func add(target_id: StringName, op: AttributeModifier.Op, value: float, bucket: StringName = &"default") -> ModifierSource:
	return add_modifier(AttributeModifier.create(target_id, op, value, bucket))

## 深拷贝: 同一个来源模板被多次施加时互不干扰
func clone() -> ModifierSource:
	var copy := ModifierSource.new(source_id)
	copy.display_name = display_name
	copy.tags.assign(tags)
	copy.instant = instant
	copy.stackable = stackable
	copy.stack_count = stack_count
	copy.duration = duration
	copy.remaining_time = remaining_time
	copy.enabled = enabled
	for modifier: AttributeModifier in modifiers:
		copy.modifiers.append(modifier.clone())
	return copy

func is_timed() -> bool:
	return duration > 0.0

func is_expired() -> bool:
	return is_timed() and remaining_time <= 0.0

func tick(delta: float) -> void:
	if is_timed():
		remaining_time -= delta

func describe() -> String:
	var lines := PackedStringArray()
	var instant_mark: String = " [即时]" if instant else ""
	var stack_mark: String = ""
	if stack_count > 1:
		stack_mark = " x%d" % stack_count
	lines.append("来源 %s%s%s" % [source_id, instant_mark, stack_mark])
	for modifier: AttributeModifier in modifiers:
		lines.append("  " + modifier.describe())
	return "\n".join(lines)
