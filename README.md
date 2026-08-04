# 点餐APP (ytt-smdc-flutter)

基于 Flutter 的点餐应用起始项目。

## 技术栈

- Flutter 3.19+
- Dart 3.4+
- 状态管理：Provider
- 网络请求：Dio
- 路由：Fluro
- 本地存储：sp_util

## 快速开始

```bash
flutter pub get
flutter run
```

## 项目结构

```
lib/
├── main.dart          # 应用入口
├── generated/         # JSON 序列化基础设施
├── mvp/               # MVP 架构基类
├── net/               # 网络请求封装（Dio + 拦截器）
├── pages/             # 页面
│   ├── home/          # 首页
│   └── login/         # 登录
├── res/               # 资源定义（颜色/间距/样式/常量）
├── routers/           # 路由系统（Fluro + IRouterProvider）
├── setting/           # 主题/设置
├── util/              # 工具类
└── widgets/           # 通用组件
```

## 核心基础设施

- **网络层**：Dio 单例 + Auth/Token/Logging/Adapter 拦截器 + isolate JSON 解析
- **路由**：Fluro + IRouterProvider 模块化注册，新模块只需实现 IRouterProvider 并注册
- **MVP**：BasePageMixin + BasePagePresenter，自动管理 CancelToken 与生命周期
- **主题**：支持亮色/暗色模式切换

## 添加新模块

1. 在 `lib/pages/` 下创建模块目录
2. 创建 `xxx_router.dart` 实现 `IRouterProvider`
3. 在 `lib/routers/routers.dart` 中注册
