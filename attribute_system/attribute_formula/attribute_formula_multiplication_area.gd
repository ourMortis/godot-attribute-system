class_name AttributeFormulaMultiplicationArea extends AttributeFormula
## 一个包含多个乘区的计算公式
## 最终值 = 基础值  * (乘区1) * (乘区2) * ... * (乘区x)
## 使用tag给AttributeModifier分类 以便判断修改器应该算在哪个乘区里

## 给这个数组添加元素 数组大小就是乘区个数
## modifier的tag成员应当被限制在 [1, zones.size()-1] 
@export var zones: PackedFloat64Array = [];


func calculate(value: float, modifiers: Array[AttributeModifier]) -> float:
	zones.fill(1.0)
	var result: float = value
	for modifier: AttributeModifier in modifiers:
		if modifier.tag < zones.size():
			match modifier.type:
				AttributeModifier.ModifierType.ADD:
					zones[modifier.tag] += modifier.value
				AttributeModifier.ModifierType.MUL:
					zones[modifier.tag] *= modifier.value
				AttributeModifier.ModifierType.SET:
					zones[modifier.tag] = modifier.value
	for zone_value in zones:
		result *= zone_value
	return result
