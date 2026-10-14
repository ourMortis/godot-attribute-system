class_name AttributeFormulaNormal extends AttributeFormula
## 先加后乘 有SET操作直接返回

func calculate(value: float, modifiers: Array[AttributeModifier]) -> float:
	var mul_value: float = 1
	var added_value: float = value
	for modifier: AttributeModifier in modifiers:
		match modifier.type:
			AttributeModifier.ModifierType.ADD:
				added_value += modifier.value
			AttributeModifier.ModifierType.MUL:
				mul_value *= modifier.value
			AttributeModifier.ModifierType.SET:
				return modifier.value
	return added_value * mul_value
