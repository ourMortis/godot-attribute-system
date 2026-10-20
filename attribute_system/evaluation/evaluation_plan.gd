class_name EvaluationPlan extends Resource
## 加载期编译出来的"求值计划"
##
## ★ 只读、无运行时状态, 编译一次后所有实体共享
## ★ 属性之间的依赖在这里被固定成一条无环的顺序(order), 运行期只按数组顺序跑
## ★ 环必须在编译期被发现: 成环的属性会退到队尾(不参与依赖计算)并记入 errors
var definitions: Array[AttributeDefinition] = [] ## 参与编译的定义(保持声明顺序)
var order: Array[StringName] = [] ## 求值顺序(拓扑序)
var index_of: Dictionary[StringName, int] = {} ## id -> order 下标
var depends_on: Dictionary[StringName, Array] = {} ## id -> 它依赖的 id
var dependents_of: Dictionary[StringName, Array] = {} ## 反向边: id -> 依赖它的 id, 用于脏传播
var errors: PackedStringArray = PackedStringArray() ## 编译期发现的问题

## 编译: 建图 -> 拓扑排序 -> 环检测
func compile(definition_list: Array[AttributeDefinition]) -> PackedStringArray:
	definitions.assign(definition_list)
	order.clear()
	index_of.clear()
	depends_on.clear()
	dependents_of.clear()
	errors.clear()

	var by_id: Dictionary[StringName, AttributeDefinition] = {}
	for definition: AttributeDefinition in definitions:
		if not definition:
			errors.append("定义列表里存在 null")
		elif definition.id == &"":
			errors.append("存在没有 id 的属性定义")
		elif by_id.has(definition.id):
			errors.append("属性 id 重复: %s" % definition.id)
		else:
			by_id[definition.id] = definition
			for message: String in definition.validate():
				errors.append("[%s] %s" % [definition.id, message])

	# 建图: source -> [target...], 同时统计入度
	var in_degree: Dictionary[StringName, int] = {}
	var edges: Dictionary[StringName, Array] = {}
	for definition: AttributeDefinition in definitions:
		if by_id.has(definition.id):
			in_degree[definition.id] = 0
	for definition: AttributeDefinition in definitions:
		if not by_id.has(definition.id):
			continue
		var required: Array[StringName] = []
		for dependency: AttributeDependency in definition.dependencies:
			if not dependency or not dependency.enabled:
				continue
			if dependency.source_id == definition.id:
				errors.append("[%s] 属性依赖了自己: %s" % [definition.id, dependency.source_id])
				continue
			if not by_id.has(dependency.source_id):
				if not dependency.optional:
					errors.append("[%s] 依赖的属性不存在: %s" % [definition.id, dependency.source_id])
				continue
			required.append(dependency.source_id)
			in_degree[definition.id] = in_degree[definition.id] + 1
			if not edges.has(dependency.source_id):
				edges[dependency.source_id] = []
			edges[dependency.source_id].append(definition.id)
		depends_on[definition.id] = required

	# Kahn 拓扑排序, 无依赖者按声明顺序入队, 结果稳定可复现
	var queue: Array[StringName] = []
	for definition: AttributeDefinition in definitions:
		if by_id.has(definition.id) and in_degree.get(definition.id, 0) == 0:
			queue.append(definition.id)
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		if index_of.has(current):
			continue
		index_of[current] = order.size()
		order.append(current)
		for target: StringName in edges.get(current, []):
			in_degree[target] = in_degree[target] - 1
			if in_degree[target] <= 0:
				queue.append(target)

	# 还有没排进去的, 说明成环
	if order.size() < by_id.size():
		var cycled := PackedStringArray()
		for definition: AttributeDefinition in definitions:
			if by_id.has(definition.id) and not index_of.has(definition.id):
				index_of[definition.id] = order.size()
				order.append(definition.id)
				cycled.append(String(definition.id))
		errors.append("属性依赖存在环, 以下属性不参与依赖计算: %s" % ", ".join(cycled))

	# 反向表, 供调试 / 展示 / 将来的脏传播优化使用
	for id: StringName in depends_on:
		for source_id: StringName in depends_on[id]:
			if not dependents_of.has(source_id):
				dependents_of[source_id] = []
			dependents_of[source_id].append(id)

	return errors

func has(id: StringName) -> bool:
	return index_of.has(id)

func size() -> int:
	return order.size()

func get_definition(id: StringName) -> AttributeDefinition:
	for definition: AttributeDefinition in definitions:
		if definition and definition.id == id:
			return definition
	return null

func describe() -> String:
	var lines := PackedStringArray()
	var names := PackedStringArray()
	for id: StringName in order:
		names.append(String(id))
	lines.append("求值顺序: %s" % ", ".join(names))
	for id: StringName in depends_on:
		var deps: Array = depends_on[id]
		if deps.is_empty():
			continue
		var dep_names := PackedStringArray()
		for source_id: StringName in deps:
			dep_names.append(String(source_id))
		lines.append("  %s <- %s" % [id, ", ".join(dep_names)])
	for error: String in errors:
		lines.append("  [错误] %s" % error)
	return "\n".join(lines)
