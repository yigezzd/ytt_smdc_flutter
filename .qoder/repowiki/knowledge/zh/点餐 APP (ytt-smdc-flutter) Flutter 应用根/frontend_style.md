## 1. 体系概览

本项目是一个 Flutter 3.19+ 点餐 APP，UI 风格完全基于 `package:flutter/material.dart`，**未引入任何第三方 UI 组件库**（如 flutter_sliver、flutter_staggered_grid_view 等），也未使用 SCSS/Tailwind 或 CSS-in-JS 类方案。视觉一致性通过以下机制实现：

- **Design Tokens**：颜色、字号、间距全部集中在 `lib/res/` 目录下的纯 Dart 常量文件中。
- **样式组合**：在 `styles.dart` 中把 `Colours` 与 `Dimens` 组装为 `TextStyles` 静态 TextStyle。
- **主题切换**：通过 `ThemeProvider`（`ChangeNotifier` + `sp_util` 持久化）构建两套 `ThemeData`（Light/Dark），由 `useMaterial3: false` 显式关闭 Material 3。
- **全局系统栏适配**：`ThemeUtils` 提供 `SystemUiOverlayStyle.light/dark` 以及 `BuildContext` 扩展，供页面侧统一设置状态栏与导航栏。

## 2. 关键文件

| 文件 | 职责 |
|---|---|
| `lib/res/colors.dart` | `Colours` 类，集中定义主色、背景、文字、分割线等所有 Color 常量，并成对提供 `_dark_*` 变体 |
| `lib/res/dimens.dart` | `Dimens` 类，定义字体字号（font_sp10~18）与间距（gap_dp4~50） |
| `lib/res/styles.dart` | `TextStyles` 类，把字号与颜色组合为可复用的 `TextStyle`（如 `textSize16`、`textBold18`、`textGray14`） |
| `lib/res/gaps.dart` | `Gaps` 类，封装水平/垂直 `SizedBox`、`Divider`、`VerticalDivider`、空 Widget 等布局占位 |
| `lib/res/resources.dart` | 聚合导出上述三个文件，并提供 `Images` 图标资源入口 |
| `lib/util/theme_utils.dart` | `ThemeUtils` + `BuildContext` 扩展，判断深浅色、返回对应 SystemUiOverlayStyle |
| `lib/setting/provider/theme_provider.dart` | `ThemeProvider`，根据 `sp_util` 中存储的 theme key 生成 `ThemeData`，并持久化用户选择 |
| `pubspec.yaml` | 声明 `uses-material-design: true`，注册 `assets/images/*`、`assets/svg/`、`assets/fonts/RobotoThin.ttf` |

## 3. 架构与设计约定

### 3.1 Design Token 分层

```text
colors.dart (原始数值) → dimens.dart (字号/间距) → styles.dart (TextStyle 组合) → 业务组件直接引用
```

- 颜色以 `app_main` / `bg_color` / `text` / `line` / `red` 等业务语义命名，深色模式有对应的 `dark_app_main`、`dark_bg_color`、`dark_text`、`dark_line`、`dark_red`。
- 字号采用 `font_sp10` ~ `font_sp18`，间距采用 `gap_dp4` ~ `gap_dp50`，均为固定 double 值；未见 `MediaQuery` 动态缩放或响应式断点逻辑。
- `TextStyles` 仅做组合，不封装业务语义（如 `titleLarge`），而是按尺寸/粗细/颜色组合出多个静态字段，例如 `textBold18`、`textGray14`、`textDarkGray12`。

### 3.2 主题构建规则

`ThemeProvider.getTheme({bool isDarkMode = false})` 是全局主题的唯一来源，核心约定：

- `useMaterial3: false`，强制使用 Material 2。
- `primaryColor`、`indicatorColor`、`colorScheme.secondary`、`error` 均取自 `Colours.app_main` / `dark_app_main`。
- `scaffoldBackgroundColor` 在浅色下为白色，深色下为 `Colours.dark_bg_color`。
- `canvasColor` 浅色白、深色 `Colours.dark_material_bg`。
- `textSelectionTheme` 统一使用 `Colours.app_main`（含 cursor、selectionHandle）。
- `textTheme.titleMedium/bodyMedium` 指向 `TextStyles.text` 或 `TextStyles.textDark`。
- `inputDecorationTheme.hintStyle` 指向 `TextStyles.textHint14` 或 `TextStyles.textDarkGray14`。
- `AppBarTheme.elevation: 0.0`，即默认无阴影。
- `CupertinoOverrideTheme.brightness` 同步 Material 主题亮度。
- `pageTransitionsTheme` 被替换为自定义 `NoTransitionsOnWeb()`。
- `visualDensity: VisualDensity.standard`，禁用紧凑密度。

### 3.3 深浅色切换流程

1. 用户在 `theme_page.dart` 调用 `ThemeProvider.setTheme(themeMode)`。
2. `ThemeProvider` 将字符串 `'System'/'Light'/'Dark'` 写入 `Constant.theme`（key 在 `res/constant.dart`）。
3. 应用重启时（或通过 `notifyListeners()` 触发重建）读取该值，解析为 `ThemeMode.system/light/dark`。
4. 各页面通过 `Theme.of(context).brightness` 或 `ThemeUtils.isDark(context)` 判断当前模式。

### 3.4 资源与图片

- 图片资源位于 `assets/images/` 下按模块划分（home/pay/state/login），SVG 位于 `assets/svg/`。
- 字体通过 `pubspec.yaml` 的 `fonts` 段声明 `RobotoThin` 家族，路径 `assets/fonts/Roboto-Thin.ttf`。
- 通用图标通过 `LoadAssetImage` 组件加载，`resources.dart` 中的 `Images.arrowRight` 即为示例。

## 4. 观察到的约定与约束

- **Token 唯一来源**：颜色、字号、间距仅在 `lib/res/` 下定义，业务代码不应出现硬编码的 `Color(0xFF...)`、`fontSize:` 字面量或 `Padding` 字面量——这是从 `Colours`、`Dimens`、`TextStyles`、`Gaps` 四个集中文件归纳出的约定。
- **深浅色对称命名**：每个主题相关颜色都有 `dark_*` 对应项（如 `dark_bg_color`、`dark_material_bg`、`dark_text_gray`、`dark_line`、`dark_app_main`、`dark_red`、`dark_button_disabled`），深色主题通过 `isDarkMode` 参数切换。
- **Material 2 锁定**：`useMaterial3: false` 在 `ThemeProvider` 中显式关闭，说明项目有意保持 Material 2 行为。
- **App Bar 无阴影**：`AppBarTheme.elevation` 设为 `0.0`，属于全局视觉约束。
- **文本基线对齐**：`TextStyles.text` / `TextStyles.textDark` 显式设置 `textBaseline: TextBaseline.alphabetic`，注释引用了 Flutter issue #40248，作为跨平台文本渲染的一致性约束。
- **系统栏样式分离**：浅色模式下 `ThemeUtils.light` 使用 `systemNavigationBarIconBrightness: Brightness.light`，深色模式下 `ThemeUtils.dark` 使用 `systemNavigationBarIconBrightness: Brightness.dark`，由 `AppBarTheme.systemOverlayStyle` 注入。
- **Provider 驱动主题状态**：`ThemeProvider` 继承 `ChangeNotifier`，并通过 `SpUtil` 持久化，主题变更通过 `notifyListeners()` 通知 UI 重建。
- **无第三方样式框架**：`pubspec.yaml` 未引入 `flutter_svg` 之外的样式增强包（`flutter_svg` 用于 SVG 图标），SCSS、Tailwind、styled-components 等均不存在。

## 5. 结论

本项目的“前端风格”是一套轻量但完整的 Flutter Material 设计令牌系统：以 `lib/res/` 为单一事实源（颜色、字号、间距、TextStyle、Gap），通过 `ThemeProvider` 构建 Light/Dark 两套 `ThemeData`，并由 `ThemeUtils` 统一处理系统栏与上下文辅助方法。它没有引入外部 UI 库，也没有响应式断点策略，适合平板/POS 端固定尺寸的点餐场景。