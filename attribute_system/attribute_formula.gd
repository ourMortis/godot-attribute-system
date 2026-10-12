class_name AttributeFormula extends Resource
## 仅存储属性的计算策略
## 通过 calculate 接口使用
## 配合 AttributeModifier 的 tag 成员可实现复杂运算规则


## 先加后乘 有 SET 则直接返回
func calculate(base_value: float, modifiers: Array[AttributeModifier]) -> float:
	var mul_value: float = 1
	var added_value: float = base_value
	for modifier: AttributeModifier in modifiers:
		match modifier.type:
			AttributeModifier.ModifierType.ADD:
				added_value += modifier.value
				continue
			AttributeModifier.ModifierType.MUL:
				mul_value *= modifier.value
				continue
			AttributeModifier.ModifierType.SET:
				return modifier.value
	return added_value * mul_value
