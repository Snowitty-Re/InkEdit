# 纸白 · 墨绿：作品橱窗

## 方向

以用户确认的 [界面概念图](approved-showcase.png) 为视觉基准。原生 SwiftUI 组件实现，非截图贴图。

- 背景：暖纸白；导航：浅灰绿；正文：墨色；操作强调：鼠尾草绿。
- 中文标题采用宋体，工具与辅助信息沿用系统字体。
- 橱窗以书封为中心，细书脊、柔和投影、薄层板；提供列表视图和搜索。
- 默认封面按作品 UUID 稳定分配三种插画，书名作者实时绘制；自定义封面优先。
- 默认插画仅为界面装饰，不写入用户作品、不冒充导出封面。
- 摘要与字数从实际文件异步读取，不展示虚构进度或同步状态。
- 深色模式通过动态颜色适配；偏好设置可选择系统、纸白、墨色。

## 图片来源与制作

使用内置 imagegen 工具生成，没有外部素材、API 或手工重绘。图标依据已确认概念图提取优化；图标透明底，三个封面全幅不透明。原始生成稿复制进 Assets.xcassets。AppIcon 各分辨率仅使用 sips 等比缩放，无创意性二次修改。

| 资源 | 用途 | 工作区路径 |
| --- | --- | --- |
| InkMark | 品牌标记 / 原始图标 | InkEdit/Assets.xcassets/InkMark.imageset/InkMark.png |
| AppIcon | 16–1024 px macOS 图标 | InkEdit/Assets.xcassets/AppIcon.appiconset/ |
| CoverMoon | 山月墨蓝封面 | InkEdit/Assets.xcassets/CoverMoon.imageset/CoverMoon.png |
| CoverCoast | 海岸灰绿封面 | InkEdit/Assets.xcassets/CoverCoast.imageset/CoverCoast.png |
| CoverBlossom | 春枝纸白封面 | InkEdit/Assets.xcassets/CoverBlossom.imageset/CoverBlossom.png |

## 生成提示词

### inkedit-icon

Use case: logo-brand. The attached image is the user-approved design reference. Produce ONLY the single app icon shown large near the bottom of that reference, as a production-ready square macOS app icon asset. Keep the approved identity: warm ivory softly rounded-square ceramic-paper tile, subtle tactile texture and bevel, centered dark charcoal open book shape, a single taller sage-green turned page, crisp simple strong silhouette and balanced negative space. Front-facing orthographic, no perspective. Icon tile fills about 86 percent of a square 1024x1024 canvas, centered, generous equal outer transparent padding, truly transparent outside the tile, very restrained contact shadow. Preserve the mark's proportions and palette from the reference. No wordmark, no letters, no background board, no extra icons, no UI. This is an extraction/refinement of the APPROVED icon, not a new unrelated concept.

### cover-moon

Use case: illustration-story. Asset type: production default book jacket artwork for a Chinese literary writing app's elegant bookstore display. A single FLAT full-bleed portrait artwork, 2:3 aspect ratio, no book mockup, no frame, no spine, no shadow, no typography, no lettering whatsoever. Quiet layered Chinese ink-wash mountains in dusty slate blue and charcoal, small warm ivory moon in the upper-left quadrant, faint paper grain, a few soft pale mist layers. Upper-right third is calm dark blue-gray negative space reserved for live title text added in code. Landscape forms mainly fill bottom 55%. Refined printed art-book cover aesthetic, extremely low saturation, serene and elegant, not fantasy concept art, no person, no watermark. Palette consistent with ivory and sage macOS literary software. Cover edge to edge.

### cover-coast

Use case: illustration-story. Asset type: production default book jacket artwork for a Chinese literary writing app's elegant bookstore display. A single FLAT full-bleed portrait artwork, 2:3 aspect ratio, no book mockup, no frame, no spine, no shadow, no typography, no letters. Misty pale sea-glass sage watercolor coastline and layered distant islands, delicate cream shoreline and a few restrained wave strokes. A softly textured pale green-gray sky fills upper 45%, leaving upper-right third quiet and light for live dark title text. Quiet modern Chinese literary art-book illustration, subtle paper tactility, washed pigment, refined, poetic, airy; no people, no logos, no watermark. Palette soft sage, warm ivory, muted gray-green. Artwork extends edge to edge.

### cover-blossom

Use case: illustration-story. Asset type: production default book jacket artwork for a Chinese literary writing app's elegant bookstore display. A single FLAT full-bleed portrait artwork, 2:3 aspect ratio, no book mockup, no frame, no spine, no shadows around edges, absolutely no text or letters. Warm ivory paper ground, a sparse delicate dark plum blossom branch growing from lower-left, tiny pale blush blossoms, faint misty warm-gray hills in bottom quarter. Upper-right third must remain pale and quiet for live dark title text. Elegant restrained Chinese ink and watercolor art-book cover, very light paper texture, low saturation, exquisite fine details but not busy. No people, no logos, no watermarks. Artwork extends edge to edge.

## 视觉回归

`-ui-testing -ui-testing-showcase` 创建隔离、仅调试的六本示例作品（不修改真实书架），覆盖浅色/深色、搜索、收藏、进入写作与阅读、作品信息和导出入口。截图通过 XCTest 附件保存。
