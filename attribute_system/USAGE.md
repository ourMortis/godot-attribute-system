# 属性系统使用说明

本文档面向实际使用：如何配置属性、如何在运行时读写、如何处理装备 / buff / 即时效果，以及常见问题的排查方式。

架构与类的职责见 [ARCHITECTURE.md](ARCHITECTURE.md)。

---

## 1. 概念速览

| 概念 | 作用 | 谁来配置 |
| --- | --- | --- |
| `AttributeSet` | 一份属性配置集，包含所有定义，并缓存编译好的求值计划 | 编辑器 / 工具脚本 |
| `AttributeDefinition` | 单个属性：id、默认裸值、桶、依赖、公式、钳制、取整 | 编辑器 |
| `BucketSpec` | 一个桶（加法区 / 乘区 / 覆盖区） | 编辑器 |
| `AttributeDependency` | "我的基础值依赖谁、系数多少" | 编辑器 |
| `AttributeFormula` | 可选的计算策略，为空时按桶顺序折叠 | 编辑器 |
| `AttributeSystem` | 每个实体一个的门面节点 | 场景树 |
| `AttributeSheet` | 该实体的运行时属性表（裸值、来源、缓存） | 运行时自动创建 |
| `ModifierSource` | 一次修改的来源（装备 / buff / 即时结算） | 运行时 |

---

## 2. 最小接入步骤

### 2.1 在实体场景里挂节点

给实体（玩家 / 敌人 / 生物）加一个 `Node`，挂上 `attribute_system.gd`：

```
Player (Node2D)
└── AttributeSystem (Node)
```

每个实体一个 `AttributeSystem`，不要做成全局单例。

### 2.2 创建属性定义

在文件系统里新建资源，类型选 `AttributeDefinition`，为每个属性设置：

- `id`：唯一标识，代码和依赖都用它（例如 `attack`）
- `display_name`：显示名
- `default_base`：裸值默认值
- `buckets`：有序桶列表（顺序就是计算顺序）
- `dependencies`：派生依赖（可选）
- `formula`：计算策略（可选）
- `persist`：是否写入存档（派生属性一般设为 `false`）

### 2.3 创建配置集

新建一个 `AttributeSet` 资源，把上面的定义拖进 `definitions` 数组。

同一个 `AttributeSet` 可以被多个实体共享；求值计划只会编译一次。

### 2.4 把配置集挂到节点上

在 `AttributeSystem` 节点的检查器里把 `attribute_set` 指向刚创建的配置集。

也可以在场景里直接内联一个 `AttributeSet` 子资源。

### 2.5 运行

场景加载时 `AttributeSystem` 会自动：

1. 通过 `AttributeSet` 取得（必要时编译并缓存）`EvaluationPlan`
2. 取得共享的 `AttributeEvaluator`
3. 为本实体建立唯一的 `AttributeSheet`
4. 计算一次初始值

之后就可以通过 API 或 `get_sheet()` 使用了。

---

## 3. 配置示例

下面这套配置与演示场景 `scene/unit.tscn` 一致。

| 属性 | default_base | 桶（按顺序） | 依赖 | persist |
| --- | --- | --- | --- | --- |
| `strength` | 10 | `flat(ADD)` | — | true |
| `attack` | 2 | `flat(ADD)`, `more(MULTIPLY)` | `strength × 2` | false |
| `max_health` | 100 | `flat(ADD)`, `increased(MULTIPLY_ONE_PLUS)` | — | true |
| `health` | 100 | `flat(ADD)` | — | true |

桶的语义：

| `combine` | 并入方式 | 用途 |
| --- | --- | --- |
| `ADD` | `当前值 + Σ` | 平坦加法，例如 +50 攻击力 |
| `MULTIPLY` | `当前值 × Π` | 独立乘区，例如每个 +10% 各自相乘 |
| `MULTIPLY_ONE_PLUS` | `当前值 × (1 + Σ)` | 百分比加算区（多个 +10% 合并成 +20%） |
| `OVERRIDE` | `当前值 = 桶内值` | 覆盖区，直接指定最终值 |

桶内的单条修改按 `ADD` / `MUL` / `OVERRIDE` 聚合；名字必须与修改器的 `bucket` 一致。

### 数值推演

1. `strength` 裸值 10，护符提供 `+5` → `strength = 15`
2. `attack.effective_base = 2 + 2 × 15 = 32`
3. 武器提供 `flat +5`，附魔提供 `more ×1.1`
4. `attack = (32 + 5) × 1.1 = 40.7`
5. 卸下护符 → `strength = 10` → `attack = (2 + 20 + 5) × 1.1 = 29.7`

---

## 4. 运行时使用

### 4.1 读取与永久修改

```gdscript
var system: AttributeSystem = $AttributeSystem

# 读取当前值（含依赖、修改器、钳制、取整）
var attack := system.get_value(&"attack")

# 读取裸值（不含修改器与派生贡献）
var base := system.get_base_value(&"strength")

# 修改裸值：升级加点、初始化等永久改动
system.set_base_value(&"strength", 20.0)
```

需要更细粒度的控制（手动批量、连接表级信号、调试）时取表：

```gdscript
var sheet := system.get_sheet()
```

### 4.2 持续效果（装备 / buff）

```gdscript
# 给 attack 的 flat 桶 +2
system.apply_source(
	ModifierSource.create(&"weapon", &"attack", AttributeModifier.Op.ADD, 2.0, &"flat")
)

# 整体撤销：source_id 是钥匙
system.remove_source(&"weapon")
```

一个来源可以同时影响多个属性：

```gdscript
var boost := ModifierSource.new(&"blessing")
boost.add(&"attack", AttributeModifier.Op.ADD, 5.0, &"flat")
boost.add(&"max_health", AttributeModifier.Op.ADD, 0.1, &"increased")
system.apply_source(boost)
```

### 4.3 叠层

```gdscript
var poison := ModifierSource.create(&"poison", &"health", AttributeModifier.Op.ADD, -5.0, &"flat")
poison.stackable = true

system.apply_source(poison) # 1 层
system.apply_source(poison) # 2 层

system.set_source_stack(&"poison", 5) # 直接设为 5 层
system.set_source_stack(&"poison", 0) # 0 层 = 撤销
```

不可叠层的来源用同一个 `source_id` 再次施加时，会按"刷新覆盖"处理，而不是叠加。

### 4.4 修改来源内某条修改器

给修改器设置 `modifier_uid`，之后可以单独改数值（会按当前层数重新入账）：

```gdscript
var buff := ModifierSource.new(&"rage")
buff.add_modifier(
	AttributeModifier.create(&"attack", AttributeModifier.Op.ADD, 10.0, &"flat", &"rage_atk")
)
system.apply_source(buff)

system.set_modifier_value(&"rage", &"rage_atk", 15.0)
```

### 4.5 限时效果

```gdscript
var haste := ModifierSource.create(&"haste", &"attack", AttributeModifier.Op.MUL, 1.2, &"more")
haste.duration = 3.0
system.apply_source(haste)
```

需要在每帧推进计时：

```gdscript
func _process(delta: float) -> void:
	attribute_system.tick(delta)
```

到期后来源会被整体撤销。

### 4.6 即时效果

`instant = true` 的效果会直接写进裸值，不保留来源记录，适合伤害、治疗、一次性消耗：

```gdscript
# 当前生命值 -25
system.apply_source(
	ModifierSource.create(&"hit", &"health", AttributeModifier.Op.ADD, -25.0, &"flat", true)
)

# 当前生命值减半
system.apply_source(
	ModifierSource.create(&"halve", &"health", AttributeModifier.Op.MUL, 0.5, &"flat", true)
)
```

即时效果不做撤销，也没有 `has_source()` 记录。

### 4.7 批量事务

一次穿多件装备、一次结算多个效果时使用批量，避免中途广播中间值：

```gdscript
system.begin_batch()

system.apply_source(ModifierSource.create(&"weapon", &"attack", AttributeModifier.Op.ADD, 2.0, &"flat"))
system.apply_source(ModifierSource.create(&"amulet", &"strength", AttributeModifier.Op.ADD, 5.0, &"flat"))
system.apply_source(ModifierSource.create(&"ring", &"max_health", AttributeModifier.Op.ADD, 0.1, &"increased"))

system.end_batch()
```

批内只累积变更，`end_batch()` 时统一重算并只广播一轮事件。

---

## 5. 事件

### 5.1 系统级事件

```gdscript
system.on_attribute_changed.connect(
	func(attribute_id, old_value, new_value):
		print("%s: %.2f -> %.2f" % [attribute_id, old_value, new_value])
)
system.on_source_applied.connect(func(source_id): print("apply ", source_id))
system.on_source_removed.connect(func(source_id): print("remove ", source_id))
system.on_sheet_ready.connect(func(sheet): print("sheet ready"))
```

### 5.2 表级事件

需要绕过系统转发时，直接连到表上：

```gdscript
var sheet := system.get_sheet()
sheet.on_value_changed.connect(_on_value_changed)
```

系统级事件适合 UI 和业务逻辑；表级事件适合高频路径或需要更细控制的地方。

### 5.3 事件行为

- 只有数值真正变化时才触发（浮点按近似相等判断）。
- 依赖链会按顺序触发：先被依赖的属性，再依赖它的属性。
- 批量事务内不会触发，`end_batch()` 后统一触发。
- 信号是同步的；监听者里的重活会阻塞本次改值。

---

## 6. 存档

```gdscript
var data := system.snapshot()
system.restore(data)
```

`snapshot()` 只导出 `persist = true` 属性的 `base_value`：

- 派生属性不需要存档（可由定义与来源重新算出）
- 缓存、事件不会入档
- 当前实现不保存活跃来源；如果 buff 需要跨存档，需要额外扩展

---

## 7. 调试与校验

```gdscript
# 打印本实体所有属性与来源
print(system.dump())

# 打印求值顺序与依赖边
print(system.describe_plan())

# 校验配置（不创建运行时状态）
var errors := system.validate_configuration()
```

编辑器里不需要运行项目：`AttributeSystem` 是 `@tool` 脚本，会在节点上显示配置警告：

- 没有配置 `AttributeSet`
- 配置集为空
- 属性 id 重复
- 依赖的属性不存在
- 依赖成环

---

## 8. 常见玩法配方

### 8.1 派生属性

`attack` 依赖 `strength`：

```
AttributeDependency:
  source_id  = strength
  coefficient = 2
```

改变 `strength` 后 `attack` 会自动重算并广播事件。

### 8.2 装备

每件装备对应一个固定 `source_id`（如 `"sword"`），穿上 = `apply_source`，脱下 = `remove_source("sword")`。

同一件装备再次施加：

- `stackable = false`：刷新覆盖
- `stackable = true`：叠层

### 8.3 多乘区属性

```
attack 的桶：[flat(ADD), increased(MULTIPLY_ONE_PLUS), more1(MULTIPLY), more2(MULTIPLY)]
```

- 多个 `increased` 修改器先求和，再一次性乘
- 每个 `more` 桶独立相乘

也可以直接用 `AttributeFormulaMultiplicationArea`：它会忽略桶的 `combine`，把每个桶都当乘区。

### 8.4 覆盖区

需要"某个效果直接把值设为固定值"时，给属性加一个 `OVERRIDE` 桶，并让修改器使用 `AttributeModifier.Op.OVERRIDE`：

```gdscript
ModifierSource.create(&"freeze", &"attack", AttributeModifier.Op.OVERRIDE, 0.0, &"set")
```

### 8.5 钳制与取整

在 `AttributeDefinition` 上设置：

- `clamp_enabled` + `clamp_min` / `clamp_max`
- `rounding`：`NONE` / `ROUND` / `FLOOR` / `CEIL`

适合生命值下限、整数显示、固定步长等。

### 8.6 多个实体共享配置

玩家和敌人可以引用同一份 `AttributeSet`：

```gdscript
player_system.attribute_set = shared_set
enemy_system.attribute_set = shared_set
```

它们共享同一个求值计划和求值器，但各自的裸值、来源、缓存完全独立。

---

## 9. 完整示例脚本

```gdscript
extends Node2D

@onready var attribute_system: AttributeSystem = $AttributeSystem

func _ready() -> void:
	attribute_system.on_attribute_changed.connect(_on_attribute_changed)
	print("初始状态:")
	print(attribute_system.dump())

func _process(delta: float) -> void:
	attribute_system.tick(delta)

func _on_attribute_changed(attribute_id: StringName, old_value: float, new_value: float) -> void:
	print("  %12s: %8.2f -> %8.2f" % [attribute_id, old_value, new_value])

func equip_amulet() -> void:
	attribute_system.apply_source(
		ModifierSource.create(&"amulet", &"strength", AttributeModifier.Op.ADD, 5.0, &"flat")
	)

func unequip_amulet() -> void:
	attribute_system.remove_source(&"amulet")

func equip_weapon() -> void:
	var weapon := ModifierSource.create(&"weapon", &"attack", AttributeModifier.Op.ADD, 2.0, &"flat")
	weapon.stackable = true
	attribute_system.apply_source(weapon)

func unequip_weapon() -> void:
	attribute_system.remove_source(&"weapon")

func take_damage(amount: float) -> void:
	attribute_system.apply_source(
		ModifierSource.create(&"hit", &"health", AttributeModifier.Op.ADD, -amount, &"flat", true)
	)
```

---

## 10. 常见问题

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| 修改器完全没有效果 | `bucket` 名字与定义中的桶名不一致 | 检查 `BucketSpec.bucket_name` 与 `AttributeModifier.bucket` |
| 属性值是 0 或明显不对 | 乘区桶的起点/`combine` 配错 | 加法区用 `ADD`，独立乘区用 `MULTIPLY` |
| 派生属性不更新 | 依赖的 `source_id` 写错，或 `enabled = false` | 在编辑器里看节点警告，或打印 `describe_plan()` |
| 加载时报依赖缺失 | 依赖的属性没有加入 `AttributeSet` | 补定义，或把依赖设为 `optional = true` |
| 加载时报成环 | A 依赖 B、B 又依赖 A | 拆分属性或去掉反向依赖 |
| 想修改属性却没有接口 | 运行期不支持增删定义 | 修改 `AttributeSet` 资源后重新加载场景或游戏 |
| UI 收到过多事件 | 每个属性变化都单独广播 | 用 `begin_batch()` / `end_batch()` 合并，或直接连表并做节流 |
| 存档后 buff 消失 | `snapshot()` 只保存裸值 | 需要保留 buff 时自行扩展来源持久化 |

---

## 11. 性能建议

- 用 `begin_batch()` / `end_batch()` 合并成套修改。
- 优先共享 `AttributeSet`，让同一套定义只编译一次计划。
- 高频 UI 可以监听 `sheet.on_value_changed` 并做节流，或直接读缓存值。
- 不要每帧重建 `ModifierSource`；装备/buff 应保持稳定来源并在数值变化时用 `set_modifier_value()`。
- 属性变更会沿依赖向下传播，只重算受影响的部分；保持依赖链简短有助于降低单次修改成本。
