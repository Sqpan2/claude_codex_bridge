# Pane 拖拽布局设计文档

## 功能概述

为 CCB 添加拖拽式 pane 布局功能，允许用户通过鼠标拖拽 pane 到新位置，系统自动重新计算布局并填充空白。

## 当前架构分析

### 现有布局系统

1. **布局引擎**：`lib/terminal_runtime/layouts.py`
   - 基于 tmux 的 split-window 命令
   - 支持固定的布局模式（2/3/4 个 pane）
   - 百分比驱动的分割逻辑

2. **Pane 操作**：`lib/terminal_runtime/tmux_panes_runtime/actions.py`
   - `split_pane()`: 分割创建新 pane
   - 支持方向：left/right/top/bottom
   - 支持百分比调整

3. **鼠标支持**：`config/tmux-ccb.conf`
   - 已启用 `set -g mouse on`
   - 原生支持鼠标拖拽调整大小
   - 但不支持拖拽移动

## 技术挑战

### 1. tmux 限制

tmux 本身**不支持**原生的 pane 拖拽移动功能。tmux 的鼠标支持仅限于：
- 点击切换 pane
- 拖拽 border 调整大小
- 滚动浏览历史

### 2. 布局重建

要实现拖拽效果，需要：
1. 检测鼠标拖拽事件
2. 确定目标位置
3. **销毁当前布局**
4. **重建新布局**（按新的排列顺序）
5. **恢复 pane 内容**（可能需要 tmux respawn-pane 或保存/恢复会话）

## 设计方案

### 方案 A：基于 tmux 鼠标绑定的伪拖拽

**原理**：
- 绑定 tmux 鼠标点击事件到 pane 标题栏
- 显示可移动目标位置的视觉提示
- 用户点击目标位置完成"拖拽"
- 重建布局

**优点**：
- 不需要复杂的拖拽检测
- 可以完全在 tmux 内实现

**缺点**：
- 不是真正的拖拽体验
- 需要两次点击（选择源 + 选择目标）

**实现步骤**：
1. 扩展 `sidebar_click.py` 的逻辑
2. 添加 pane 选择模式
3. 在选择模式下显示目标位置
4. 触发布局重建

### 方案 B：布局配置 UI + 应用

**原理**：
- 提供一个独立的布局配置界面（TUI 或 Web）
- 用户在配置界面中拖拽 pane
- 生成新的布局配置
- 应用到 tmux session

**优点**：
- 真正的拖拽体验
- 可以预览布局变化
- 更直观的 UI

**缺点**：
- 需要额外的 UI 组件
- 与主 tmux 界面分离

**实现步骤**：
1. 创建布局编辑器（Python TUI 或简单的 HTML5）
2. 实现拖拽逻辑（使用 urwid/textual 或 web 前端）
3. 生成布局描述 DSL
4. 应用布局到 tmux

### 方案 C：基于 tmux 快捷键的快速重排

**原理**：
- 定义一组快捷键用于 pane 移动
- 例如：`Prefix + <` = 向左移动，`Prefix + >` = 向右移动
- 实时重建布局

**优点**：
- 实现简单
- 键盘友好
- 不依赖鼠标

**缺点**：
- 不是拖拽
- 学习曲线

### 方案 D：完整的布局状态机 + 智能重排

**原理**：
1. 维护布局状态树（当前每个 pane 的位置和大小）
2. 提供 API：`move_pane(pane_id, target_position, direction)`
3. 使用算法计算最优布局
4. 通过以下步骤重建：
   - 保存每个 pane 的内容和状态
   - 销毁所有非 root pane
   - 按新布局重新分割
   - 使用 `tmux respawn-pane` 恢复进程

**优点**：
- 最灵活
- 可以支持任意布局转换
- 可以保留 pane 会话

**缺点**：
- 实现复杂
- 可能有短暂的闪烁
- 需要处理状态保存/恢复

## 推荐方案

### **方案 B + 方案 C 混合**

**阶段 1：快速实现（方案 C）**
- 添加键盘快捷键实现 pane 位置交换
- 例如：
  - `Prefix + Ctrl+h/j/k/l`: 与相邻 pane 交换位置
  - `Prefix + Shift+1/2/3/4`: 移动到第 N 个位置

**阶段 2：增强体验（方案 B）**
- 添加一个 TUI 布局配置界面
- 使用 Python `textual` 或 `rich` 实现
- 提供可视化拖拽

**阶段 3：集成优化（方案 D）**
- 实现完整的布局状态管理
- 智能填充算法
- 平滑的 pane 迁移

## 实现计划

### Phase 1: 核心基础设施（1-2 天）

#### 1.1 布局状态管理
```python
# lib/terminal_runtime/layout_state.py

@dataclass
class PaneState:
    pane_id: str
    agent_name: str
    position: int  # 在布局中的逻辑位置
    width_percent: int
    height_percent: int
    process_info: dict  # 用于 respawn

@dataclass
class LayoutState:
    window_name: str
    panes: list[PaneState]
    layout_type: str  # 'grid', 'horizontal', 'vertical'
    
    def swap_panes(self, idx1: int, idx2: int) -> 'LayoutState':
        """交换两个 pane 的位置"""
        ...
    
    def move_pane(self, from_idx: int, to_idx: int) -> 'LayoutState':
        """移动 pane 到新位置"""
        ...
```

#### 1.2 布局重建引擎
```python
# lib/terminal_runtime/layout_rebuilder.py

def rebuild_layout(
    backend: TmuxLayoutBackend,
    old_state: LayoutState,
    new_state: LayoutState,
    preserve_sessions: bool = True
) -> LayoutResult:
    """
    重建布局：
    1. 记录每个 pane 的会话信息
    2. 销毁非 root pane
    3. 按新顺序重新分割
    4. 恢复会话（如果 preserve_sessions=True）
    """
    ...
```

### Phase 2: 交互接口（2-3 天）

#### 2.1 键盘快捷键
```bash
# config/tmux-ccb.conf 添加：

# Swap pane with adjacent pane
bind-key C-h run-shell "ccb __layout-swap --direction left"
bind-key C-j run-shell "ccb __layout-swap --direction down"
bind-key C-k run-shell "ccb __layout-swap --direction up"
bind-key C-l run-shell "ccb __layout-swap --direction right"

# Move pane to position
bind-key ! run-shell "ccb __layout-move --position 1"
bind-key @ run-shell "ccb __layout-move --position 2"
bind-key '#' run-shell "ccb __layout-move --position 3"
bind-key '$' run-shell "ccb __layout-move --position 4"
```

#### 2.2 CLI 命令处理
```python
# lib/cli/layout_move.py

def handle_layout_swap(direction: str):
    """处理相邻 pane 交换"""
    ...

def handle_layout_move(position: int):
    """处理移动到指定位置"""
    ...
```

### Phase 3: 可视化编辑器（3-5 天）

#### 3.1 TUI 布局编辑器
使用 `textual` 实现交互式布局编辑器：

```python
# lib/cli/layout_editor.py

from textual.app import App
from textual.widgets import Static

class PaneWidget(Static):
    """可拖拽的 pane 组件"""
    
class LayoutEditorApp(App):
    """布局编辑器 TUI"""
    
    def on_mount(self):
        # 加载当前布局
        ...
    
    def on_drag_start(self, event):
        # 开始拖拽
        ...
    
    def on_drag_end(self, event):
        # 完成拖拽，重建布局
        ...
```

启动方式：
```bash
ccb layout edit --window main
```

### Phase 4: 智能填充（2-3 天）

#### 4.1 布局算法
```python
# lib/terminal_runtime/layout_algorithm.py

def calculate_optimal_layout(
    panes: list[PaneState],
    window_size: tuple[int, int]
) -> LayoutTree:
    """
    计算最优布局：
    - 尽量保持 pane 大小均匀
    - 最小化分割次数
    - 考虑 pane 的逻辑顺序
    """
    ...
```

## 依赖和注意事项

### 依赖项
- 现有：tmux 3.0+
- 新增：
  - `textual` (TUI 框架) - 仅用于可视化编辑器
  - 无其他外部依赖

### 限制和权衡

1. **会话恢复**：
   - 某些 pane 状态可能无法完美恢复
   - 建议提示用户保存工作

2. **性能**：
   - 布局重建可能需要 100-500ms
   - 对于 4+ panes 可能有短暂闪烁

3. **兼容性**：
   - 需要保持与现有布局配置的兼容
   - 旧版本的配置文件应该继续工作

## 测试计划

### 单元测试
- `test_layout_state.py`: 状态管理
- `test_layout_rebuilder.py`: 布局重建逻辑
- `test_layout_algorithm.py`: 布局计算算法

### 集成测试
- `test_layout_swap_integration.py`: 完整的交换流程
- `test_layout_editor_integration.py`: TUI 编辑器

### 手动测试场景
1. 2-pane 布局交换
2. 4-pane 复杂布局重排
3. 跨 window 移动（未来扩展）
4. 大小调整与拖拽结合

## 未来扩展

1. **跨 window 移动**：将 pane 拖到另一个 window
2. **布局模板**：预定义常用布局
3. **布局历史**：撤销/重做布局变更
4. **动画过渡**：平滑的布局变化动画（如果 tmux 支持）
5. **Web 配置界面**：通过浏览器配置布局

## 参考资料

- tmux 手册：`man tmux`
- CCB 现有布局实现：`lib/terminal_runtime/layouts.py`
- Sidebar 交互实现：`lib/cli/sidebar_click.py`
- Textual 文档：https://textual.textualize.io/
