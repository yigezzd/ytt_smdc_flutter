## 概览

本仓库是一个 Flutter 3.19+ 点餐 APP（flutter_deer），没有引入 dotenv、`.env` 文件或外部配置中心。运行时配置由三层组成：

1. **编译期常量** — `lib/res/constant.dart` 中的 `Constant` 类；
2. **进程内可写配置** — 通过 `sp_util` (`SharedPreferences`) 持久化的键值对；
3. **网络层 baseUrl** — 通过 `configDio(baseUrl: ...)` 在 `main()` 中注入，当前硬编码为 GitHub API。

没有发现 `.env`、`*.yaml` 配置文件、Feature Flag 框架或远程配置拉取逻辑。

## 关键文件与职责

- `lib/res/constant.dart`：所有静态常量与 SP key 的单一来源。包括环境标志 `inProduction = kReleaseMode`、登录/商户/设备/RabbitMQ/结账开关等字段名。
- `lib/net/dio_utils.dart`：暴露 `configDio({connectTimeout, receiveTimeout, sendTimeout, baseUrl, interceptors})`，内部维护 `_baseUrl` 并构造全局 `Dio` 实例。
- `lib/main.dart`：应用启动入口，调用 `SpUtil.getInstance()`、`FileLogWriter.instance.init()`、`OrderLogUtils.instance.init()`、`Device.initDeviceInfo()`，然后 `runApp(MyApp())`，并在 `MyApp.initDio()` 中 `configDio(baseUrl: 'https://api.github.com/', interceptors: ...)`。
- `lib/util/local_cache_service.dart`：业务数据（菜品、分类、桌台、支付方式）缓存到 `sp_util` 的封装，注释明确说明“当前使用 SharedPreferences(sp_util) 实现轻量级缓存”。
- `lib/util/user_helper.dart`：从 `Constant.user` / `Constant.store` 读取登录态 JSON 字符串，并提供 `getSpid()` / `getSid()` / `getSidStr()` 等便捷方法。
- `lib/net/intercept.dart`：`AuthInterceptor` 从 `SpUtil.getString(Constant.accessToken)` 注入 Authorization 头，仅对云路径（`HttpApi.baseUrlYtt` 或不含 `/api/`）生效；`TokenInterceptor` 用 `refresh_token` 自动刷新。

## 架构约定

### 1. 常量集中管理
`Constant` 类是所有字符串常量的唯一入口，业务代码一律通过 `Constant.xxx` 引用，而不是散落的字面量。注释大量出现“对齐 smdcapp SpUtils xxx”“对齐 YttPhone room”，表明这些 key 需要与 Android/iOS 原生端保持一致。

### 2. 用户态/会话态配置走 SharedPreferences
登录后返回的数据（token、user、store、rolemap、biz flags、RabbitMQ 地址端口、设备号、门店编码等）统一以 JSON 字符串形式写入 `sp_util`，key 全部定义在 `Constant` 中。读取侧集中在 `UserHelper` 和 `LocalCacheService`。

### 3. 环境变量区分只依赖 `kReleaseMode`
`Constant.inProduction` 直接绑定 `foundation.kReleaseMode`，用于：
- `main()` 中屏蔽 `debugPrint`；
- `MyApp.initDio()` 中决定是否添加 `LoggingInterceptor`。
没有 `.env` 或构建时变量替换。

### 4. baseUrl 通过函数参数注入而非全局常量
`configDio` 接收可选 `baseUrl`，`main.dart` 中调用时传入固定 URL。该设计允许不同构建变体（dev/prod）在启动时注入不同 baseUrl，但当前仓库只有一个硬编码值。

### 5. 权限判断与功能开关存储在 SP
如 `serverType`（连接模式）、`localhost`（主设备地址）、`storeMode`（快餐/正餐）、`pstoreVipflag` 等，均由登录接口写入 SP，再由业务层按值分支。

## 约束与规则

- **SP key 必须声明在 `Constant` 中**：所有 `SpUtil.putString` / `getString` 使用的 key 均来自 `Constant.*`，新增字段需先在 `Constant` 中添加常量并保持与原生端一致（见多处“对齐 smdcapp SpUtils”注释）。
- **Release 环境禁用调试日志**：`Constant.inProduction = kReleaseMode` 是强制判定依据，`main()` 与 `initDio()` 均据此关闭 `debugPrint` 与 `LoggingInterceptor`。
- **Authorization 头仅附加给云请求**：`AuthInterceptor` 显式检查 `path.startsWith(HttpApi.baseUrlYtt) || !path.contains('/api/')`，直连主设备的请求不携带 token。
- **baseUrl 必须通过 `configDio` 设置**：`DioUtils.instance.dio` 是唯一对外暴露的 `Dio` 实例，其 `options.baseUrl` 取自模块级 `_baseUrl`，由 `configDio` 赋值。
- **无独立配置文件或 Feature Flag 系统**：未发现 `.env`、`config.yaml`、`feature_flag` 等机制；所有可切换行为均以 SP 存储的整型/布尔标志驱动。

## 已知问题

`main.dart` 中 `configDio(baseUrl: 'https://api.github.com/', ...)` 显然是示例占位值，实际后端地址应来自登录返回或构建配置，当前未实现多环境 baseUrl 切换。