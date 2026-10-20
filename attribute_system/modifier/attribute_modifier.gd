class_name AttributeModifier extends Resource
## 一条"修改记录": 来自哪个来源(source), 把哪个属性(target)的哪个桶(bucket)改了多少(value)
##
## ★ 它只描述数据, 不做计算.
##   桶内聚合与最终求值分别由 BucketSpec / AttributeFormula / AttributeEvaluator 负责,
##   但"一条修改如何作用到数值上"的规则都收敛在 apply() 这一个静态方法里.
enum Op {
	ADD,      ## 加算: current + amount
	MUL,      ## 乘算: current * amount
	OVERRIDE, ## 覆盖: amount
}

@export var modifier_uid: StringName = &"" ## 可选: 用于在来源内部单独定位这条修改
@export var op: Op = Op.ADD
@export var bucket: StringName = &"default" ## 必须与目标属性的某个 BucketSpec.bucket_name 一致
@export var value: float = 0.0
@export var target_id: StringName = &"" ## 作用于哪个属性
@export var source_id: StringName = &"" ## 由 ModifierSource 统一填写, 便于按来源批量撤销
@export var tags: Array[StringName] = [] ## 供 AttributeDefinition.accept_tags 过滤

## 唯一的"把一条修改作用到数值上"的入口
##   桶内聚合: apply(桶内累计值, op, value)
##   即时效果: apply(base_value, op, value)
static func apply(current: float, op: Op, amount: float) -> float:
	match op:
		Op.ADD:
			return current + amount
		Op.MUL:
			return current * amount
		Op.OVERRIDE:
			return amount
	return current

## 快捷构造
static func create(target_id_: StringName, op_: Op, value_: float, bucket_: StringName = &"default", modifier_uid_: StringName = &"") -> AttributeModifier:
	var modifier := AttributeModifier.new()
	modifier.target_id = target_id_
	modifier.op = op_
	modifier.value = value_
	modifier.bucket = bucket_
	modifier.modifier_uid = modifier_uid_
	return modifier

## 深拷贝: 入账时使用, 保证同一份修改记录不会在多个实体/多个来源之间共享
func clone() -> AttributeModifier:
	return duplicate(true) as AttributeModifier

func op_name() -> String:
	match op:
		Op.ADD:
			return "ADD"
		Op.MUL:
			return "MUL"
		Op.OVERRIDE:
			return "OVERRIDE"
	return "?"

func describe() -> String:
	return "%s -> %s[%s] %s %s" % [source_id, target_id, bucket, op_name(), value]
