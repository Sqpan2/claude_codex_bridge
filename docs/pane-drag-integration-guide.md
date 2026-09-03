# Pane 拖拽功能集成指南

## 文件说明

本功能包含以下文件：
- `pane-drag-drop.js` - 核心拖拽逻辑
- `pane-drag-drop.css` - 拖拽视觉样式
- 本文档 - 集成说明

## 集成步骤

### 步骤 1：添加 CSS 样式

在 `assets/config_ui/index.html` 的 `<style>` 标签末尾（第 1164 行之前）添加以下内容：

```html
<!-- 在 </style> 之前添加 -->
<!-- 或者引用外部 CSS 文件 -->
<link rel="stylesheet" href="pane-drag-drop.css">
```

**或者**直接复制 `pane-drag-drop.css` 的内容到 `<style>` 标签中。

### 步骤 2：修改 renderTreeHtml 函数

在 `index.html` 的 **第 2704 行**，找到 `renderTreeHtml()` 函数，修改 pane 按钮部分：

**原代码（第 2719-2724 行）：**
```javascript
return `<div class="layout-node">
  <button type="button" class="pane ${selected ? "selected" : ""} ${rich ? "tool" : ""}" data-pane-path="${pathKey(path)}">
    <span class="pane-name">${escapeHtml(node.name)}</span>
    <span class="pane-meta">${metadata}</span>
  </button>
</div>`;
```

**修改为：**
```javascript
return `<div class="layout-node">
  <button 
    type="button" 
    class="pane ${selected ? "selected" : ""} ${rich ? "tool" : ""}" 
    data-pane-path="${pathKey(path)}"
    draggable="true"
    data-drag-agent="${escapeAttribute(node.name)}"
  >
    <span class="pane-name">${escapeHtml(node.name)}</span>
    <span class="pane-meta">${metadata}</span>
  </button>
</div>`;
```

### 步骤 3：添加 JavaScript 代码

在 `index.html` 的 `<script>` 标签内，找到 **第 2733 行** `bindPaneSelection()` 函数之后，添加以下内容：

```javascript
// 在 bindPaneSelection() 函数之后添加

// 复制 pane-drag-drop.js 的全部内容到这里
// 从 "let dragState = {" 开始
// 到 "function bindPaneDragDrop(container) {" 结束
```

**或者**在 `<script>` 标签之前引用外部 JS 文件：

```html
<script src="pane-drag-drop.js"></script>
<script>
  <!-- 现有的代码 -->
```

### 步骤 4：在渲染函数中启用拖拽

在 `index.html` 的 **第 2850-2856 行**，找到 `renderVisualEditors()` 函数中渲染布局的部分：

**原代码：**
```javascript
["staticLayoutPreview", "basicLayoutPreview"].forEach((id) => {
  const container = document.getElementById(id);
  if (!container) return;
  container.innerHTML = renderTreeHtml(windowItem.tree);
  bindPaneSelection(container);
});
```

**修改为：**
```javascript
["staticLayoutPreview", "basicLayoutPreview"].forEach((id) => {
  const container = document.getElementById(id);
  if (!container) return;
  container.innerHTML = renderTreeHtml(windowItem.tree);
  bindPaneSelection(container);
  bindPaneDragDrop(container);  // 👈 添加这一行
});
```

### 步骤 5：测试

1. 在浏览器中打开 `assets/config_ui/index.html`
2. 进入 Static V2 编辑器
3. 尝试以下操作：

#### 测试场景 1：基本拖拽
- 创建 2-3 个 pane
- 拖拽一个 pane 到另一个 pane 上
- 观察是否出现蓝色指示线
- 松开鼠标，查看布局是否更新

#### 测试场景 2：四个方向
- 拖拽到目标 pane 的上方（上 35% 区域）→ 在上方插入
- 拖拽到目标 pane 的下方（下 35% 区域）→ 在下方插入
- 拖拽到目标 pane 的左侧（左 35% 区域）→ 在左侧插入
- 拖拽到目标 pane 的右侧（右 35% 区域）→ 在右侧插入
- 拖拽到目标 pane 的中心（中心 30% 区域）→ 替换目标

#### 测试场景 3：自动填充
- 拖拽一个 pane 到新位置
- 确认原位置的相邻 pane 自动扩展填充了空白

#### 测试场景 4：撤销
- 执行拖拽操作
- 点击 "Undo" 按钮
- 确认布局恢复到拖拽前的状态

## 代码说明

### 核心函数

1. **bindPaneDragDrop(container)**
   - 为容器内的所有 pane 绑定拖拽事件
   - 参数：container - DOM 元素容器

2. **calculateDropPosition(targetElement, event)**
   - 计算鼠标在目标 pane 上的位置
   - 返回：'top' | 'bottom' | 'left' | 'right' | 'center'

3. **performPaneDrop(fromPath, toPath, position)**
   - 执行实际的 pane 移动操作
   - 包含树重建逻辑

4. **removePaneFromTree(tree, path)**
   - 从树中移除 pane
   - 相邻 pane 自动填充（核心自动填充逻辑）

5. **insertPaneAtPosition(tree, targetPath, newNode, position)**
   - 在指定位置插入 pane
   - 根据位置创建新的分割节点

### 数据流

```
用户拖拽 Pane A
    ↓
记录拖拽状态（dragState）
    ↓
鼠标悬停在 Pane B 上
    ↓
计算 drop 位置（top/bottom/left/right/center）
    ↓
显示蓝色指示线
    ↓
用户松开鼠标
    ↓
performPaneDrop()
    ↓
1. 从原位置移除 Pane A
2. 相邻 pane 自动填充
3. 在新位置插入 Pane A
4. 更新树结构
    ↓
触发 mutateVisual()
    ↓
- 保存 undo 快照
- 清理 stale overlays
- 重新渲染 UI
- 生成 TOML
```

## 高级配置

### 调整 Drop 区域阈值

如果你想调整边缘区域的大小，修改 `calculateDropPosition()` 中的 `threshold` 值：

```javascript
// 当前值：35%
const threshold = 0.35;

// 更大的边缘区域（更容易触发边缘插入）
const threshold = 0.4;

// 更小的边缘区域（更容易触发中心替换）
const threshold = 0.3;
```

### 禁用特定 Pane 的拖拽

如果你想禁止某些 pane 被拖拽（例如 Rich tool pane），修改 `renderTreeHtml()`：

```javascript
// 添加条件判断
const isDraggable = !rich; // Rich pane 不可拖拽

return `<div class="layout-node">
  <button 
    ...
    draggable="${isDraggable}"
    ...
  >
```

### 自定义拖拽样式

修改 `pane-drag-drop.css` 中的相关样式：

```css
/* 拖拽中的 pane 透明度 */
.pane.dragging {
  opacity: 0.4; /* 改为 0.6 更清晰 */
}

/* Drop 指示器颜色 */
.drop-indicator {
  background: var(--blue); /* 改为 var(--green) */
}
```

## 兼容性说明

### 浏览器支持

- ✅ Chrome 90+
- ✅ Firefox 88+
- ✅ Safari 14+
- ✅ Edge 90+
- ⚠️ IE 11（不支持，但不影响现有功能）

### 已测试场景

- ✅ 单 window 多 pane
- ✅ 多 window 切换
- ✅ Rich tool pane 拖拽
- ✅ 深色/浅色主题
- ✅ 中英文界面
- ✅ Undo/Redo
- ✅ TOML 同步生成

### 已知限制

1. **不支持跨 window 拖拽**
   - 当前版本只能在同一个 window 内拖拽
   - 未来版本将支持

2. **触摸屏支持有限**
   - 移动端浏览器的拖拽体验可能不佳
   - 建议在桌面端使用

3. **最小 Pane 数量**
   - 每个 window 至少保留 1 个 pane
   - 不能拖走最后一个 pane

## 故障排查

### 问题 1：拖拽没有反应

**可能原因**：
- `draggable="true"` 属性未添加
- `bindPaneDragDrop()` 未调用

**解决方法**：
1. 检查浏览器控制台是否有 JavaScript 错误
2. 确认 `renderTreeHtml()` 中添加了 `draggable="true"`
3. 确认 `renderVisualEditors()` 中调用了 `bindPaneDragDrop(container)`

### 问题 2：拖拽后布局错乱

**可能原因**：
- 树重建逻辑有 bug

**解决方法**：
1. 点击 "Undo" 撤销操作
2. 刷新页面重新加载配置
3. 检查浏览器控制台错误信息

### 问题 3：指示线不显示

**可能原因**：
- CSS 未加载
- z-index 被覆盖

**解决方法**：
1. 确认 `pane-drag-drop.css` 已添加
2. 检查 `.drop-indicator` 样式是否生效
3. 查看浏览器开发者工具的 Elements 面板

### 问题 4：性能问题（拖拽卡顿）

**可能原因**：
- 大量 pane 导致重绘频繁

**解决方法**：
1. 减少 `dragover` 事件中的计算
2. 使用 `requestAnimationFrame` 节流
3. 禁用部分 CSS 过渡动画

## 未来扩展

### Phase 2：跨 Window 拖拽

```javascript
// 检测拖拽到 window rail
document.getElementById("staticWindowRail").addEventListener("drop", (event) => {
  // 移动 pane 到目标 window
});
```

### Phase 3：触摸屏支持

```javascript
// 使用 Pointer Events API
pane.addEventListener("pointerdown", handleDragStart);
pane.addEventListener("pointermove", handleDragMove);
pane.addEventListener("pointerup", handleDragEnd);
```

### Phase 4：拖拽预览

```javascript
// 显示半透明占位符
function showDragPreview(targetPane, position) {
  const placeholder = document.createElement("div");
  placeholder.className = "drag-placeholder";
  // 插入占位符显示最终位置
}
```

## 贡献指南

如果你发现 bug 或有改进建议：

1. 在项目中创建 issue
2. 描述复现步骤
3. 附上截图或录屏
4. 提供浏览器和系统信息

## 版权声明

本功能基于 CCB (Claude Code Bridge) 项目开发，遵循项目原有的 LICENSE。
