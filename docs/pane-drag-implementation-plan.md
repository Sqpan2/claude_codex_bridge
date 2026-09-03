# Pane 拖拽功能实现方案

## 当前架构分析

### 现有 Config UI 功能
位置：`assets/config_ui/index.html`

**已有功能**：
1. ✅ 可视化布局编辑器（二叉树结构）
2. ✅ 点击选择 pane
3. ✅ 左右拆分 / 上下拆分
4. ✅ 删除 pane（相邻 pane 自动填充）
5. ✅ Window 切换和管理
6. ✅ 实时预览布局

**当前交互方式**：
- 点击 pane → 选中
- 点击工具栏按钮 → 操作（拆分/删除）
- 删除后 → 相邻 pane **自动扩展填充空白** ✅

**数据结构**：
```javascript
// visualState.windows[i].tree 是一个二叉树
{
  kind: "horizontal" | "vertical" | "leaf",
  left: {...},   // 子节点
  right: {...},  // 子节点
  name: "agent1",
  provider: "codex"
}
```

## 需求分析

你希望添加：
1. **拖拽 pane 到不同位置**
2. **拖拽后其他 pane 自动填充空白**

**好消息**：
- ✅ 自动填充功能已经存在（删除 pane 时实现了）
- ✅ 二叉树结构支持任意重排
- ✅ UI 框架完整

**需要添加**：
- 拖拽交互逻辑
- Drop zone 视觉提示
- 拖拽后的树重建逻辑

## 技术方案

### 方案：HTML5 Drag and Drop API

在现有 UI 基础上添加原生拖拽支持。

#### 优点
- ✅ 原生 API，无需外部库
- ✅ 与现有代码完美集成
- ✅ 支持视觉反馈（拖拽预览）
- ✅ 浏览器优化性能

#### 实现步骤

### 1. 添加拖拽属性到 Pane 元素

**修改位置**：`renderTreeHtml()` 函数（第 2704 行）

```javascript
function renderTreeHtml(node, path = []) {
  if (node.kind !== "leaf") {
    return `<div class="layout-node branch ${node.kind}">
      ${renderTreeHtml(node.left, [...path, "left"])}
      ${renderTreeHtml(node.right, [...path, "right"])}
    </div>`;
  }
  const selected = pathKey(path) === pathKey(selectedPanePath);
  const rich = !node.provider || node.name === "rich";
  const overlay = rich ? {} : overlayFor(node.name);
  const metadata = rich
    ? `<span>${t("notAskTarget")}</span>`
    : `<span>${escapeHtml(node.provider)}</span>
       <span>${node.workspace_mode === "worktree" ? "worktree" : "inplace"}</span>
       ${overlay.role ? `<span>${escapeHtml(overlay.role)}</span>` : ""}`;
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
}
```

### 2. 添加拖拽 CSS 样式

**修改位置**：`<style>` 区域（第 8-1164 行）

```css
/* 拖拽相关样式 */
.pane {
  cursor: move;
  transition: all 0.15s ease;
  user-select: none;
}

.pane.dragging {
  opacity: 0.5;
  cursor: grabbing;
}

.pane.drag-over {
  border-color: var(--blue);
  box-shadow: inset 0 0 0 2px var(--blue);
  background: var(--blue-soft);
}

.layout-node {
  position: relative;
}

.drop-indicator {
  position: absolute;
  background: var(--blue);
  opacity: 0.6;
  z-index: 10;
  pointer-events: none;
  transition: all 0.15s ease;
}

.drop-indicator.vertical {
  height: 3px;
  width: 100%;
  left: 0;
}

.drop-indicator.horizontal {
  width: 3px;
  height: 100%;
  top: 0;
}

.drop-indicator.top {
  top: 0;
}

.drop-indicator.bottom {
  bottom: 0;
}

.drop-indicator.left {
  left: 0;
}

.drop-indicator.right {
  right: 0;
}
```

### 3. 添加拖拽事件处理

**新增位置**：在 `bindPaneSelection()` 后（第 2727 行）

```javascript
function bindPaneDragDrop(container) {
  let draggedPath = null;
  let draggedNode = null;

  container.querySelectorAll(".pane[draggable]").forEach((pane) => {
    // 开始拖拽
    pane.addEventListener("dragstart", (event) => {
      draggedPath = pane.dataset.panePath ? pane.dataset.panePath.split(".") : [];
      draggedNode = nodeAtPath(selectedWindow().tree, draggedPath);
      
      pane.classList.add("dragging");
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", pane.dataset.dragAgent);
      
      // 设置拖拽预览
      const preview = pane.cloneNode(true);
      preview.style.opacity = "0.8";
      document.body.appendChild(preview);
      event.dataTransfer.setDragImage(preview, 50, 25);
      setTimeout(() => document.body.removeChild(preview), 0);
    });

    // 拖拽结束
    pane.addEventListener("dragend", (event) => {
      pane.classList.remove("dragging");
      container.querySelectorAll(".pane").forEach((p) => p.classList.remove("drag-over"));
      removeDropIndicators();
      draggedPath = null;
      draggedNode = null;
    });

    // 拖拽进入目标
    pane.addEventListener("dragenter", (event) => {
      if (draggedPath && pane.dataset.panePath !== pathKey(draggedPath)) {
        event.preventDefault();
        pane.classList.add("drag-over");
      }
    });

    // 拖拽悬停
    pane.addEventListener("dragover", (event) => {
      if (draggedPath && pane.dataset.panePath !== pathKey(draggedPath)) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "move";
        
        // 显示 drop 位置指示器
        showDropIndicator(pane, event);
      }
    });

    // 离开目标
    pane.addEventListener("dragleave", (event) => {
      if (event.currentTarget === event.target) {
        pane.classList.remove("drag-over");
      }
    });

    // 放下
    pane.addEventListener("drop", (event) => {
      event.preventDefault();
      pane.classList.remove("drag-over");
      removeDropIndicators();
      
      if (!draggedPath || !draggedNode) return;
      
      const targetPath = pane.dataset.panePath ? pane.dataset.panePath.split(".") : [];
      if (pathKey(targetPath) === pathKey(draggedPath)) return;
      
      const dropPosition = calculateDropPosition(pane, event);
      performPaneDrop(draggedPath, targetPath, dropPosition);
    });
  });
}

function calculateDropPosition(targetElement, event) {
  const rect = targetElement.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const width = rect.width;
  const height = rect.height;
  
  // 将目标分为 4 个区域：上、下、左、右
  const threshold = 0.35; // 35% 的边缘区域
  
  if (y < height * threshold) return "top";
  if (y > height * (1 - threshold)) return "bottom";
  if (x < width * threshold) return "left";
  if (x > width * (1 - threshold)) return "right";
  
  return "center"; // 中心区域 = 替换
}

function showDropIndicator(targetPane, event) {
  removeDropIndicators();
  
  const position = calculateDropPosition(targetPane, event);
  if (position === "center") return;
  
  const indicator = document.createElement("div");
  indicator.className = `drop-indicator ${position === "top" || position === "bottom" ? "vertical" : "horizontal"} ${position}`;
  
  targetPane.closest(".layout-node").style.position = "relative";
  targetPane.closest(".layout-node").appendChild(indicator);
}

function removeDropIndicators() {
  document.querySelectorAll(".drop-indicator").forEach((el) => el.remove());
}

function performPaneDrop(fromPath, toPath, position) {
  mutateVisual(() => {
    const windowItem = selectedWindow();
    const draggedNode = clone(nodeAtPath(windowItem.tree, fromPath));
    const targetNode = nodeAtPath(windowItem.tree, toPath);
    
    if (!draggedNode || !targetNode) return;
    
    // 1. 从原位置移除（保存相邻节点来填充）
    windowItem.tree = removePaneFromTree(windowItem.tree, fromPath);
    
    // 2. 重新计算目标路径（因为树结构可能已改变）
    const newToPath = findNodePath(windowItem.tree, targetNode.name);
    if (!newToPath) return;
    
    // 3. 插入到新位置
    windowItem.tree = insertPaneAtPosition(windowItem.tree, newToPath, draggedNode, position);
    
    // 4. 选中被拖拽的 pane
    selectedPanePath = findNodePath(windowItem.tree, draggedNode.name) || [];
  });
}

function removePaneFromTree(tree, path) {
  if (path.length === 0) {
    // 移除 root，返回空树或默认节点
    return { kind: "leaf", name: uniqueAgentName(), provider: "codex", workspace_mode: "inplace", percent: null };
  }
  
  const parentPath = path.slice(0, -1);
  const side = path[path.length - 1];
  const parent = nodeAtPath(tree, parentPath);
  
  if (!parent || parent.kind === "leaf") return tree;
  
  // 用另一侧的子树替换父节点
  const sibling = clone(parent[side === "left" ? "right" : "left"]);
  return replaceNodeAtPath(tree, parentPath, sibling);
}

function insertPaneAtPosition(tree, targetPath, newNode, position) {
  const target = nodeAtPath(tree, targetPath);
  if (!target) return tree;
  
  if (position === "center") {
    // 替换目标节点
    return replaceNodeAtPath(tree, targetPath, clone(newNode));
  }
  
  // 创建新的分支节点
  const kind = (position === "top" || position === "bottom") ? "vertical" : "horizontal";
  const newBranch = {
    kind,
    left: (position === "top" || position === "left") ? clone(newNode) : clone(target),
    right: (position === "top" || position === "left") ? clone(target) : clone(newNode)
  };
  
  return replaceNodeAtPath(tree, targetPath, newBranch);
}

function findNodePath(tree, nodeName, currentPath = []) {
  if (!tree) return null;
  
  if (tree.kind === "leaf") {
    return tree.name === nodeName ? currentPath : null;
  }
  
  const leftPath = findNodePath(tree.left, nodeName, [...currentPath, "left"]);
  if (leftPath) return leftPath;
  
  return findNodePath(tree.right, nodeName, [...currentPath, "right"]);
}
```

### 4. 在渲染函数中启用拖拽

**修改位置**：`renderVisualEditors()` 函数（第 2829 行）

```javascript
function renderVisualEditors() {
  if (!visualState) return;
  // ... 现有代码 ...
  
  ["staticLayoutPreview", "basicLayoutPreview"].forEach((id) => {
    const container = document.getElementById(id);
    if (!container) return;
    container.innerHTML = renderTreeHtml(windowItem.tree);
    bindPaneSelection(container);
    bindPaneDragDrop(container);  // 👈 添加这一行
  });
  
  // ... 现有代码 ...
}
```

## 用户体验流程

### 拖拽交互
1. 用户**鼠标按住** pane 并开始拖动
2. 被拖拽的 pane 显示半透明效果
3. 鼠标移动到其他 pane 上时：
   - 目标 pane 高亮（蓝色边框）
   - 根据鼠标位置显示 **drop 指示器**（上/下/左/右边缘的蓝色线条）
4. 松开鼠标：
   - 被拖拽的 pane 移动到新位置
   - 原位置的相邻 pane **自动扩展填充**
   - 目标位置根据 drop 位置创建新的分割

### Drop 位置逻辑

```
┌─────────────────┐
│       TOP       │ ← 上 35% 区域：在目标上方插入
├─────────────────┤
│ L │  CENTER │ R │ ← 左/右 35%：在目标左/右插入
│ E │         │ I │ ← 中心 30%：替换目标
│ F │         │ G │
├─────────────────┤
│     BOTTOM      │ ← 下 35% 区域：在目标下方插入
└─────────────────┘
```

## 技术细节

### 树重建算法

**关键点**：
1. **先删除后插入**：确保 pane 不会重复
2. **路径更新**：删除节点后重新查找目标路径
3. **自动填充**：删除使用 `removePaneFromTree()`，相邻节点自动上移
4. **分割创建**：插入时根据位置创建 horizontal/vertical 分支

### 状态管理

- 使用现有的 `mutateVisual()` 包装所有修改
- 自动触发 undo 快照
- 自动清理 stale overlays
- 自动触发 TOML 渲染

### 兼容性

- ✅ 不影响现有点击选择
- ✅ 不影响现有工具栏操作
- ✅ 支持撤销（Undo）
- ✅ 支持多 window
- ✅ 与 Rich pane 兼容

## 实现优先级

### Phase 1: 核心拖拽（1-2 天）
- [ ] 添加 draggable 属性
- [ ] 实现基本拖拽事件
- [ ] 实现树重建逻辑
- [ ] 测试单 window 场景

### Phase 2: 视觉优化（1 天）
- [ ] 添加 CSS 样式和动画
- [ ] 实现 drop 指示器
- [ ] 优化拖拽预览

### Phase 3: 高级功能（1 天）
- [ ] 跨 window 拖拽
- [ ] 拖拽到空白区域创建新 window
- [ ] 键盘辅助（Ctrl 复制等）

### Phase 4: 测试和优化（1 天）
- [ ] 边界情况测试
- [ ] 性能优化
- [ ] 用户体验优化

## 测试场景

1. **基本拖拽**
   - 2 panes：A 和 B 互换
   - 3 panes：A 移动到 B 和 C 之间
   
2. **复杂布局**
   - 4 panes 网格布局重排
   - 嵌套分割的拖拽

3. **边界情况**
   - 拖拽到自身（无操作）
   - 只有 1 个 pane（禁用拖拽）
   - Rich tool pane 拖拽

4. **多 window**
   - Window A 的 pane 拖到 Window B

## 后续扩展

1. **触摸屏支持**
   - 添加 touch events
   - 长按触发拖拽

2. **拖拽到空白创建 Window**
   - 拖拽到 window rail 创建新窗口

3. **视觉预览**
   - 拖拽时实时显示布局预览
   - 使用半透明占位符

4. **批量操作**
   - Shift + 拖拽选择多个 pane
   - 一次性重排

## 总结

这个方案完美利用了现有的 Config UI 架构：
- ✅ 自动填充功能已存在（删除逻辑）
- ✅ 树结构完美支持重排
- ✅ 代码侵入性小，易于维护
- ✅ 用户体验流畅自然

预计总开发时间：**4-5 天**
