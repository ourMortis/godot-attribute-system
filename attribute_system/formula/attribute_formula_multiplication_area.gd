class_name AttributeFormulaMultiplicationArea extends AttributeFormula
## 所有桶一律按"乘区"处理: 最终值 = 基础值 * 桶1 * 桶2 * ...
##
## 与 AttributeFormulaNormal 的区别:
##   Normal 听桶的 combine 声明(加法 / 百分比 / 乘法 / 覆盖);
##   本策略忽略 combine, 只要桶里有修改器就乘上去.
## 等价写法: 把桶全部声明成 combine = MULTIPLY, 然后用 Normal.
## 注意: 使用本策略时桶应当声明为 MULTIPLY(聚合起点为 1), 否则加法桶的起点 0 会把结果乘成 0.
func calculate(effective_base: float, buckets: Array[BucketSpec], bucket_values: Dictionary[StringName, float]) -> float:
	var result: float = effective_base
	for bucket: BucketSpec in buckets:
		if bucket and bucket_values.has(bucket.bucket_name):
			result *= bucket_values[bucket.bucket_name]
	return result
