## 1. 使用的框架与工具

- **控制台调试日志**：基于第三方包 `common_utils` 的 `LogUtil`，通过自封装的 `lib/util/log_utils.dart` 中的 `Log` 类暴露 `d/e/json` 三个级别（debug / error / json）。生产模式（`Constant.inProduction == true`）下所有 `Log.*` 调用均被短路不输出。
- **本地文件日志**：自实现的 `lib/util/file_log_writer.dart` 中的 `FileLogWriter`，通过 `StreamController` 异步批量写入，按日期 + 分类分目录落盘。
- **敏感业务日志**：`lib/util/order_log_utils.dart` 中的 `OrderLogUtils`，记录开台/退菜等敏感操作到本地 JSON，再 POST 到云服务接口 `/YttSvr/app/salelog/setLog`。
- **日志压缩与远程上传**：`lib/util/log_upload_utils.dart` 中的 `LogUploadUtils`，收集最近 N 天的日志目录和 SQLite 数据库目录，打包为 zip 后通过手动 Socket 实现 FTP 上传至 `yundb.bypos.net:15671`。

## 2. 关键文件

| 文件 | 职责 |
|---|---|
| `lib/util/log_utils.dart` | 控制台调试日志门面（`Log.d/e/json`），依赖 `common_utils.LogUtil` |
| `lib/util/file_log_writer.dart` | 本地运行日志写入器，支持多分类、批量缓冲、过期清理 |
| `lib/util/order_log_utils.dart` | 敏感操作日志持久化与云端上报 |
| `lib/util/log_upload_utils.dart` | 日志 zip 压缩 + FTP 上传 |
| `lib/main.dart` | 应用启动时依次初始化 `FileLogWriter`、`OrderLogUtils`、`Log` |
| `lib/net/http_helper.dart`、`lib/net/mq_service_impl.dart` 等 | 调用方，使用 `FileLogWriter.writeApiLog/writeMqLog/writeErrorLog/writeSqlLog` 等 |

## 3. 架构与约定

### 3.1 双通道设计

- **调试通道**：`Log.init()` → `LogUtil.init(isDebug: !Constant.inProduction)`。仅开发/调试环境生效，提供结构化 JSON 美化打印（`Log.json` 内部递归 `_printMap/_printList`，列表超 50 项或嵌套过深时自动扁平化以避免控制台行数限制）。
- **持久化通道**：`FileLogWriter.instance.writeToFile(data, tag, category)`。数据统一走 Stream 队列，默认每 10 条或 500ms 刷盘一次；崩溃/错误场景通过 `immediate: true` 同步写盘，不走缓冲。

### 3.2 日志分类体系

`FileLogWriter` 定义以下分类常量（对应磁盘子目录名）：

| 分类常量 | 用途 |
|---|---|
| `categoryJsonWriter` | 通用运行日志（默认） |
| `categoryApiLog` | HTTP 请求流水（方法 + 路径 + 成功/失败 + 耗时 + 参数/响应） |
| `categoryCrashLog` | 未捕获异常、HTTP 错误、MQ 错误、SQL 错误、打印错误 |
| `categoryMqLog` | MQ 通信日志 |
| `categorySqlLog` | 数据库 SQL 日志 |
| `categoryPrintLog` | 打印相关日志 |
| `categoryWmLog` | 外设/扫码等外围设备日志 |
| `categoryPoolLog` | 连接池日志 |

### 3.3 文件布局

```
{appDocDir}/log/{yyyy-MM-dd}/{category}/{yyyy-MM-dd}.log
```

每条记录的固定格式为：

```
时间_{yyyy-MM-dd HH:mm:ss.SSS}_{pcAlive状态}_{tag} [Size: x]:{正文}
```

其中 `pcAlive` 来自 `ConnectionManager.pcAlive`，用于区分主设备直连与云服务模式。

### 3.4 初始化时序

在 `main.dart` 中顺序执行：

1. `await FileLogWriter.instance.init()` — 创建 `{appDocDir}/log` 根目录并启动队列监听；Web 平台跳过。
2. `await OrderLogUtils.instance.init()` — 创建 `{appDocDir}/order_logs/pending_logs.json`。
3. `Log.init()` — 初始化 `common_utils.LogUtil`。
4. 登录成功后调用 `FileLogWriter.instance.logDeviceInfo()`，写入设备信息首行。

### 3.5 敏感操作日志流

`OrderLogUtils.saveOrderLog(saleid, memo, billno, isUpload)` 会：

1. 从 `SpUtil` 读取商户号(`spid`)、门店号(`sid`)、操作员(`operid`/`opername`)、机号(`machNo`)。
2. 构造包含 `client: 'APP'`、`opertime`、`createtime` 等字段的 Map。
3. 同时写入运行日志（`FileLogWriter.writeToFile(tag: '敏感操作日志')`）和本地待上传缓存 `pending_logs.json`。
4. 可选立即上传；否则由定时任务或设置页触发 `uploadLog()`，POST 到 `HttpApi.saleLogSetLog`，成功后清空已上传记录。

### 3.6 日志上传与清理

`LogUploadUtils.uploadLog()`：

- 收集最近 `_keepDays` 天（1–2 月为 20 天，其他月份为 10 天）的日期目录及 SQLite 数据库目录。
- 使用 `archive` 库打包为 zip，文件名形如 `{date}_SMDC_APP_{acc}_{storeCode}_{machNo}_logs.zip`。
- 通过 `dart:io.Socket` 手工实现 FTP PASV 传输，目标 `yundb.bypos.net:15671`，凭据硬编码在源码中。
- 上传成功后删除本地 zip。

`FileLogWriter.deleteOldLogs()` 会在每次 init 时扫描 log 根目录，删除早于保留期的日期目录以及残留 `.zip` 文件。

## 4. 约定与约束

- **调试日志仅在非生产环境输出**：`Log.d/e/json` 内部以 `if (!Constant.inProduction)` 守卫（来源：`lib/util/log_utils.dart`）。
- **单条日志最大长度截断**：`FileLogWriter` 对任何写入内容超过 650000 字符的记录进行截断并追加 `[Truncated, Original total: N chars]` 标记（来源：`lib/util/file_log_writer.dart` `_enqueue`）。
- **崩溃与错误日志强制即时落盘**：`writeCrashLog`、`writeErrorLog` 调用 `_enqueue(..., immediate: true)`，绕过批量缓冲（来源：`lib/util/file_log_writer.dart`）。
- **Web 平台跳过文件系统日志**：`FileLogWriter` 与 `OrderLogUtils` 均在 `kIsWeb` 时跳过初始化与写入（来源：两个类的 `init` 方法）。
- **日志分类枚举集中声明**：新增日志类型需先添加 `categoryXxx` 常量，并在对应的 `writeXxxLog` 中使用，避免散落的字符串字面量（来源：`lib/util/file_log_writer.dart`）。
- **敏感操作日志字段契约**：`OrderLogUtils` 构造的 Map 字段 (`spid`, `sid`, `saleid`, `billno`, `memo`, `operid`, `opername`, `client`, `machno`, `opertime`, `createtime`) 与服务端接口 `/YttSvr/app/salelog/setLog` 对齐（来源：`lib/util/order_log_utils.dart`）。
- **日志文件命名与解析契约**：解析逻辑依赖目录名为 `yyyy-MM-dd` 格式，非法目录名会被跳过（来源：`lib/util/file_log_writer.dart` `deleteOldLogs`）。
- **FTP 服务器地址与凭据硬编码**：`LogUploadUtils` 将 host/port/user/pass/remoteDir 作为 `static const` 直接声明，未配置化（来源：`lib/util/log_upload_utils.dart`）。
- **控制台日志标签统一前缀**：`Log.tag = 'DEER-LOG'`，所有控制台输出使用该 tag（来源：`lib/util/log_utils.dart`）。
- **埋点日志结构**：`writeActionLog` 统一产出 `{viewTag, action, target, extra}` 四个字段（来源：`lib/util/file_log_writer.dart`）。

## 5. 调用方分布

根据 grep 结果，主要调用点在：

- `lib/net/http_helper.dart` — 接口请求/响应流水（`writeApiLog`）
- `lib/net/mq_service_impl.dart` — MQ 消息收发（`writeMqLog`）
- `lib/util/handle_error_utils.dart` — 全局错误处理（`writeErrorLog`）
- `lib/pages/order/*` — 订单确认、详情等业务页面（`Log.json` 输出订单模型）
- `lib/main.dart` — 应用启动初始化
- `lib/setting/page/personal_center_page.dart`、`lib/setting/page/setting_page.dart` — 手动触发日志上传入口
