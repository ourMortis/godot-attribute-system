@tool
class_name BucketSpec extends Resource
## 一个"桶"(阶段 / 乘区)的规格说明
##
## 桶是 "修改器 -> 数值" 之间的第一层组织:
## 同一个桶里的修改器先聚合成一个数, 再按 combine 声明的方式并入当前值.
## AttributeDefinition.buckets 里的数组顺序 = 实际的计算顺序.
##
## 桶内的聚合规则统一由 AttributeModifier.apply() 决定: ADD 累加 / MUL 累乘 / OVERRIDE 覆盖
##
## 常见搭配:
##   平坦加法区   { combine = ADD }               -> 当前值 + Σ
##   百分比加算区 { combine = MULTIPLY_ONE_PLUS } -> 当前值 * (1 + Σ)   (类似 PoE 的 increased)
##   独立乘区     { combine = MULTIPLY }          -> 当前值 * Π         (类似 PoE 的 more)
##   覆盖区       { combine = OVERRIDE }          -> 当前值 = 桶内值
enum Combine {
	ADD,               ## 桶内聚合结果 加到 当前值上: current + Σ
	MULTIPLY,          ## 桶内聚合结果 乘到 当前值上: current * Π
	MULTIPLY_ONE_PLUS, ## 桶内聚合结果加一后 乘到当前值上: current * (1 + Σ)
	OVERRIDE,          ## 桶内聚合结果 直接替换当前值: current = 桶内值
}

@export var bucket_name: StringName = &"default" ## 唯一名, 与 AttributeModifier.bucket 对应
@export var combine: Combine = Combine.ADD ## 这个桶以何种方式并入当前值
@export var description: String = "" ## 备注, 仅供编辑器阅读

## 桶内聚合的起点: 加法/百分比/覆盖桶从 0 起算, 乘法桶从 1 起算
func seed_value() -> float:
	return 1.0 if combine == Combine.MULTIPLY else 0.0

## 把这个桶的聚合结果并入当前值
func combine_value(current: float, accumulated: float) -> float:
	match combine:
		Combine.ADD:
			return current + accumulated
		Combine.MULTIPLY:
			return current * accumulated
		Combine.MULTIPLY_ONE_PLUS:
			return current * (1.0 + accumulated)
		Combine.OVERRIDE:
			return accumulated
	return current

## 默认流水线: 严格按 buckets 的顺序, 逐个桶折叠进 effective_base
## 没有修改器参与过的桶不会出现在 bucket_values 里, 于是不会影响结果(空的覆盖区不会把值清成 0)
static func fold_all(effective_base: float, buckets: Array[BucketSpec], bucket_values: Dictionary[StringName, float]) -> float:
	var result: float = effective_base
	for bucket: BucketSpec in buckets:
		if bucket and bucket_values.has(bucket.bucket_name):
			result = bucket.combine_value(result, bucket_values[bucket.bucket_name])
	return result
