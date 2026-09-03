/**
 * Pane Drag & Drop 功能实现
 * 为 CCB Config UI 添加拖拽式 pane 布局编辑
 */

// ============================================================================
// 拖拽状态管理
// ============================================================================

let dragState = {
  draggedPath: null,
  draggedNode: null,
  targetPath: null,
  dropPosition: null
};

// ============================================================================
// 拖拽位置计算
// ============================================================================

/**
 * 计算拖拽放置位置
 * 将目标 pane 分为 5 个区域：top, bottom, left, right, center
 */
function calculateDropPosition(targetElement, event) {
  const rect = targetElement.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const width = rect.width;
  const height = rect.height;

  // 边缘阈值：35% 的区域用于创建相邻分割
  const threshold = 0.35;

  // 优先判断上下（更符合直觉）
  if (y < height * threshold) return "top";
  if (y > height * (1 - threshold)) return "bottom";

  // 然后判断左右
  if (x < width * threshold) return "left";
  if (x > width * (1 - threshold)) return "right";

  // 中心区域：替换目标
  return "center";
}

// ============================================================================
// 视觉反馈
// ============================================================================

/**
 * 显示 drop 位置指示器
 */
function showDropIndicator(targetPane, position) {
  removeDropIndicators();

  if (position === "center") return;

  const container = targetPane.closest(".layout-node");
  if (!container) return;

  const indicator = document.createElement("div");
  indicator.className = `drop-indicator ${
    position === "top" || position === "bottom" ? "vertical" : "horizontal"
  } ${position}`;

  container.style.position = "relative";
  container.appendChild(indicator);
}

/**
 * 移除所有 drop 指示器
 */
function removeDropIndicators() {
  document.querySelectorAll(".drop-indicator").forEach((el) => el.remove());
}

// ============================================================================
// 树操作辅助函数
// ============================================================================

/**
 * 在树中查找节点路径（通过节点名称）
 */
function findNodePath(tree, nodeName, currentPath = []) {
  if (!tree) return null;

  if (tree.kind === "leaf") {
    return tree.name === nodeName ? currentPath : null;
  }

  const leftPath = findNodePath(tree.left, nodeName, [...currentPath, "left"]);
  if (leftPath) return leftPath;

  return findNodePath(tree.right, nodeName, [...currentPath, "right"]);
}

/**
 * 从树中移除指定路径的 pane
 * 相邻的 sibling 会自动填充该位置
 */
function removePaneFromTree(tree, path) {
  if (!path || path.length === 0) {
    // 不能移除根节点（至少保留一个 pane）
    return tree;
  }

  const parentPath = path.slice(0, -1);
  const side = path[path.length - 1];

  if (parentPath.length === 0) {
    // 移除根节点的直接子节点，用另一侧替换整个树
    const parent = tree;
    if (parent.kind === "leaf") return tree;
    const sibling = clone(parent[side === "left" ? "right" : "left"]);
    return sibling;
  }

  const parent = nodeAtPath(tree, parentPath);
  if (!parent || parent.kind === "leaf") return tree;

  // 用 sibling 替换父节点（实现自动填充）
  const sibling = clone(parent[side === "left" ? "right" : "left"]);
  return replaceNodeAtPath(tree, parentPath, sibling);
}

/**
 * 在指定位置插入 pane
 */
function insertPaneAtPosition(tree, targetPath, newNode, position) {
  const target = nodeAtPath(tree, targetPath);
  if (!target) return tree;

  if (position === "center") {
    // 替换目标节点
    return replaceNodeAtPath(tree, targetPath, clone(newNode));
  }

  // 创建新的分支节点
  const kind = (position === "top" || position === "bottom") ? "vertical" : "horizontal";
  const isLeft = (position === "top" || position === "left");

  const newBranch = {
    kind,
    left: isLeft ? clone(newNode) : clone(target),
    right: isLeft ? clone(target) : clone(newNode)
  };

  return replaceNodeAtPath(tree, targetPath, newBranch);
}

/**
 * 判断两个路径是否相同
 */
function isSamePath(path1, path2) {
  if (!path1 || !path2) return false;
  if (path1.length !== path2.length) return false;
  return path1.every((part, index) => part === path2[index]);
}

/**
 * 判断 path1 是否是 path2 的祖先
 */
function isAncestorPath(ancestorPath, descendantPath) {
  if (!ancestorPath || !descendantPath) return false;
  if (ancestorPath.length >= descendantPath.length) return false;
  return ancestorPath.every((part, index) => part === descendantPath[index]);
}

// ============================================================================
// 核心拖拽逻辑
// ============================================================================

/**
 * 执行 pane 拖拽放置操作
 */
function performPaneDrop(fromPath, toPath, position) {
  // 验证：不能拖拽到自身
  if (isSamePath(fromPath, toPath)) {
    return;
  }

  // 验证：不能拖拽到自己的子节点（会产生循环）
  if (isAncestorPath(fromPath, toPath)) {
    return;
  }

  mutateVisual(() => {
    const windowItem = selectedWindow();
    if (!windowItem) return;

    // 1. 保存被拖拽节点的副本
    const draggedNode = clone(nodeAtPath(windowItem.tree, fromPath));
    if (!draggedNode) return;

    // 2. 从原位置移除（相邻 pane 自动填充）
    windowItem.tree = removePaneFromTree(windowItem.tree, fromPath);

    // 3. 重新计算目标路径（树结构已改变）
    const targetNode = nodeAtPath(windowItem.tree, toPath);
    if (!targetNode) return;

    const newToPath = findNodePath(windowItem.tree, targetNode.name);
    if (!newToPath) return;

    // 4. 插入到新位置
    windowItem.tree = insertPaneAtPosition(windowItem.tree, newToPath, draggedNode, position);

    // 5. 选中被拖拽的 pane
    const finalPath = findNodePath(windowItem.tree, draggedNode.name);
    if (finalPath) {
      selectedPanePath = finalPath;
    }
  });
}

// ============================================================================
// 事件绑定
// ============================================================================

/**
 * 为容器内的所有 pane 绑定拖拽事件
 */
function bindPaneDragDrop(container) {
  if (!container) return;

  // 只对叶子节点（实际的 pane）启用拖拽
  const panes = container.querySelectorAll(".pane[draggable]");

  panes.forEach((pane) => {
    // ========================================================================
    // dragstart: 开始拖拽
    // ========================================================================
    pane.addEventListener("dragstart", (event) => {
      const pathStr = pane.dataset.panePath;
      if (!pathStr) return;

      dragState.draggedPath = pathStr.split(".");
      dragState.draggedNode = nodeAtPath(selectedWindow().tree, dragState.draggedPath);

      // 视觉反馈
      pane.classList.add("dragging");

      // 设置拖拽数据
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", pane.dataset.dragAgent || "pane");

      // 创建自定义拖拽预览
      const preview = pane.cloneNode(true);
      preview.style.opacity = "0.8";
      preview.style.transform = "rotate(2deg)";
      document.body.appendChild(preview);
      event.dataTransfer.setDragImage(preview, event.offsetX, event.offsetY);

      // 清理临时预览元素
      setTimeout(() => {
        if (document.body.contains(preview)) {
          document.body.removeChild(preview);
        }
      }, 0);
    });

    // ========================================================================
    // dragend: 拖拽结束
    // ========================================================================
    pane.addEventListener("dragend", (event) => {
      pane.classList.remove("dragging");
      container.querySelectorAll(".pane").forEach((p) => {
        p.classList.remove("drag-over");
      });
      removeDropIndicators();

      // 清理状态
      dragState = {
        draggedPath: null,
        draggedNode: null,
        targetPath: null,
        dropPosition: null
      };
    });

    // ========================================================================
    // dragenter: 拖拽进入目标
    // ========================================================================
    pane.addEventListener("dragenter", (event) => {
      if (!dragState.draggedPath) return;

      const targetPathStr = pane.dataset.panePath;
      if (!targetPathStr) return;

      const targetPath = targetPathStr.split(".");

      // 不能拖拽到自身
      if (isSamePath(dragState.draggedPath, targetPath)) return;

      // 不能拖拽到自己的子节点
      if (isAncestorPath(dragState.draggedPath, targetPath)) return;

      event.preventDefault();
      pane.classList.add("drag-over");
    });

    // ========================================================================
    // dragover: 拖拽悬停
    // ========================================================================
    pane.addEventListener("dragover", (event) => {
      if (!dragState.draggedPath) return;

      const targetPathStr = pane.dataset.panePath;
      if (!targetPathStr) return;

      const targetPath = targetPathStr.split(".");

      // 不能拖拽到自身或子节点
      if (isSamePath(dragState.draggedPath, targetPath)) return;
      if (isAncestorPath(dragState.draggedPath, targetPath)) return;

      event.preventDefault();
      event.dataTransfer.dropEffect = "move";

      // 计算并显示 drop 位置
      const position = calculateDropPosition(pane, event);
      dragState.targetPath = targetPath;
      dragState.dropPosition = position;

      showDropIndicator(pane, position);
    });

    // ========================================================================
    // dragleave: 离开目标
    // ========================================================================
    pane.addEventListener("dragleave", (event) => {
      // 只在真正离开元素时移除样式（避免子元素触发）
      if (event.target === pane && !pane.contains(event.relatedTarget)) {
        pane.classList.remove("drag-over");
      }
    });

    // ========================================================================
    // drop: 放下
    // ========================================================================
    pane.addEventListener("drop", (event) => {
      event.preventDefault();
      event.stopPropagation();

      pane.classList.remove("drag-over");
      removeDropIndicators();

      if (!dragState.draggedPath || !dragState.targetPath || !dragState.dropPosition) {
        return;
      }

      // 执行拖拽操作
      performPaneDrop(
        dragState.draggedPath,
        dragState.targetPath,
        dragState.dropPosition
      );
    });
  });
}

// ============================================================================
// 导出（插入到现有的 config_ui/index.html 中）
// ============================================================================

// 此文件的函数需要添加到 index.html 的 <script> 标签中
// 并在 renderVisualEditors() 函数中调用 bindPaneDragDrop()
