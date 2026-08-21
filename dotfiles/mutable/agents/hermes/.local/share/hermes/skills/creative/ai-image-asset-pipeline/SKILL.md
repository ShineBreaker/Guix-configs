---
name: ai-image-asset-pipeline
description: 把 AI 生成的图像素材（角色立绘、背景图、key visual）整合进设计工件（网站/海报/视频）的完整管线——风格一致性生成、flood-fill 去底抠图、合成验证、版权声明。触发信号：设计任务需要 AI 立绘/背景图、生成的图带浅色背景需融入深色页面、用户要求"人物立绘/原画丰富内容"。
version: 1.0.0
metadata:
  hermes:
    tags: [ai-images, image-processing, cutout, design, web, PIL, fan-art]
---

# AI 图像素材整合管线

用 `image_generate` 产出素材后，直接贴进设计稿通常失败：AI 立绘自带不透明浅色背景，在深色页面/海报上是一块突兀的矩形。本技能覆盖从生成到整合的全流程。

## 触发信号

- 设计任务（网站/海报/视频）需要角色立绘、背景图、key visual，且没有现成素材
- 生成的图有浅色/纯色背景，需要透明底融入设计
- 动漫/游戏/偶像主题的纪念页、粉丝站——用户期望看到"人物立绘/原画"级视觉素材，纯文字排版会被视为未完成

## 工作流

1. **氛围背景图**：无角色的场景图（空教室、校舍剪影、星空）无 IP 风险，直接生成下载到 `assets/`。
2. **角色图 = AI 致敬 Fan Art**：从角色特征 prompt 生成（发色发型、瞳色、制服、表情、姿势）。绝不宣称是官方图——页面 footer 必须声明"AI 生成致敬 Fan Art，版权归原作者/制作委员会"。
3. **去底抠图**：见下节。产出 `*-fg.png` 透明版。
4. **合成验证**：把 `-fg.png` 合成到目标深色背景上，用 vision 检查主体完整性、白边/光晕、误抠。
5. **整合**：HTML 引用 `-fg.png`；注意浏览器缓存——改了图片引用后重新 navigate 加载。

## 风格一致性（无 edit 模型时）

image-to-image（编辑/参考图）在 managed FAL 网关上可能 403（`*/edit` 模型未启用）。此时**不要放弃一致性**：

- 维护一个 master prompt 模板：制服描述 + 背景描述（如 "plain light pastel gradient background"）+ 画风短语，逐字复用
- 只替换角色特征段落（发色、瞳色、表情、姿势）
- 生成后抽查 1-2 张确认画风统一

## Flood-fill 去底抠图

脚本：`scripts/remove_bg.py`（参数化：`--dir --glob --threshold --feather`）。原理：

- 采样四边像素取中位数作为背景基准色
- 从四边种子 BFS：颜色距离 < 阈值 的 4-连通像素置为背景
- 高斯羽化 1px 柔和边缘

**PIL 坐标坑（实战踩过）**：PixelAccess 索引顺序是 `px[x, y]`（x=列，y=行）。写成 `px[y, x]` 在非正方形图上直接 IndexError。BFS 邻居坐标 `(nx, ny)` 必须统一按 `mpx[nx, ny]` 访问。

**连通域限制（实战踩过）**：flood-fill 只能清掉与边缘 4-连通且颜色接近背景的像素。角色脚下的浅色"地板/底座"若被身体/裙子隔断，就会残留——此时**提高阈值无效**（区域根本不连通）。

诊断顺序（重要，别先调阈值）：
1. 读 mask：`mask.getpixel((x, y))` 检查嫌疑像素是否已被标记为背景
2. 若 mask 正确但输出仍有色块 → 检查 alpha 合成环节（`Image.composite(black, a, mask)`：mask=255 取 black）
3. 若 mask 未覆盖 → 区域不连通，换策略：位置启发式（底部连续浅色块）或局部二次处理
4. 残留白色也可能就是角色本身的衣物（白衬衫/白裙）——先看包围盒和位置再决定是否清除

## 浏览器验证循环

`file://` 打开 HTML 常被拦（ERR_BLOCKED_BY_ADMINISTRATOR）：

```bash
python3 -m http.server 8899 --directory <project-dir>   # 后台进程
```

- 导航到 `http://127.0.0.1:8899/index.html`
- browser_console 查 JS 错误；browser_vision 逐 section 截图检查
- 页面 DOM 中途变空（title=''、imgs=0）→ 重新 navigate 恢复
- browser_console 里 async IIFE 可能序列化成空串 → 用同步表达式

## 版权与免责

- 氛围背景（无角色）：可直接用
- 角色致敬图：footer 声明 + 注明原作与制作委员会
- 官方立绘/原画：不抓取不 hotlink（无授权）；用户索要"原画"时交付 AI 致敬版并说明

## 关联

- 设计过程与品味：见 creative/claude-design（bundled，不可改——本技能补充其素材处理部分）
