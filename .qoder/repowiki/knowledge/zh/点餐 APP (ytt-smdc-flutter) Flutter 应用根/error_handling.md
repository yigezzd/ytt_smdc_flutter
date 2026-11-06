## 1. 采用的方案

本项目在 Flutter 3.19+ 上采用三层错误处理架构：

- **Dio 网络层**：通过自定义 `Interceptor`（认证、Token 刷新、日志、响应适配）将底层 `DioException` 统一映射为业务语义的 code/message，并以 `_ApiException` 向上抛出。
- **MVP 展示层**：`BasePagePresenter` 拦截所有 `requestNetwork/asyncRequestNetwork` 的错误，统一关闭进度、弹出 Toast，并可选回调 `NetErrorCallback`。
- **全局异常捕获**：`handleError` 重写 `FlutterError.onError` 并使用 `runZonedGuarded` 捕获未处理异常，落盘到 `FileLogWriter`，Release 下可上传服务器。

核心依赖：`dio`（网络）、`oktoast`（提示）、`sp_util`（本地缓存）、`flutter_deer` 内部工具库。

## 2. 关键文件

| 文件 | 职责 |
|---|---|
| `lib/net/error_handle.dart` | HTTP/Dart 原生异常 → 业务错误码映射 (`ExceptionHandle` + `NetError`) |
| `lib/net/intercept.dart` | Dio Interceptor：`AuthInterceptor`、`TokenInterceptor`、`LoggingInterceptor`、`AdapterInterceptor` |
| `lib/net/http_helper.dart` | 统一 POST 入口 `request()`，解析 retcode/code，抛 `_ApiException`，处理登录过期强制下线 |
| `lib/mvp/base_page_presenter.dart` | MVP Presenter 基类，封装网络请求的生命周期与错误展示 |
| `lib/util/handle_error_utils.dart` | 全局 Flutter 异常捕获 + Crash 日志落盘 |
| `lib/util/toast_utils.dart` | 基于 `oktoast` 的静态提示工具 |
| `lib/net/base_entity.dart` | 通用响应体泛型 `BaseEntity<T>` (code/message/data) |
| `lib/main.dart` | 启动时调用 `handleError(body)` |

## 3. 架构与约定

### 3.1 错误码分层

`ExceptionHandle` 定义两类常量：

- **HTTP 状态码**：`success=200`、`success_not_content=204`、`not_modified=304`、`unauthorized=401`、`forbidden=403`、`not_found=404`。
- **业务网络错误码**：`net_error=1000`、`parse_error=1001`、`socket_error=1002`、`http_error=1003`、`connect_timeout_error=1004`、`send_timeout_error=1005`、`receive_timeout_error=1006`、`cancel_error=1007`、`unknown_error=9999`。

通过扩展 `DioErrorTypeExtension` 把 `DioExceptionType.index` 映射到上述业务码；`ExceptionHandle.handleException` 再根据 `DioException.error` 类型二次细分 Socket/Http/FormatException，全部落入预定义的 `Map<int, NetError>`，保证返回给上层的是统一的 `NetError {code, msg}`。

### 3.2 Dio 拦截器链

请求顺序：`AuthInterceptor` → `TokenInterceptor` → `LoggingInterceptor` → `AdapterInterceptor`。

- `AuthInterceptor`：仅对 `HttpApi.baseUrlYtt` 或非 `/api/` 路径附加 `Authorization: token $accessToken`。
- `TokenInterceptor`：401 自动拉取 refresh_token，成功后用独立 `Dio` 实例重试原请求，避免循环拦截。
- `LoggingInterceptor`：记录 URL/method/headers/body/response/耗时，成功走 `Log.d`，失败走 `Log.e`。
- `AdapterInterceptor`：将后端非标准 JSON 包装成 `{"code":0,"data":...}` 或 `{"code":%d,"message":"..."}`，并把 `404` 转为 success + 固定文案；对包含 `retcode` 的后端响应透传原始 body。

### 3.3 统一请求入口 `request()`

`lib/net/http_helper.dart` 的 `request(url, data?, showLoading?, showError?)` 是业务调用的唯一入口：

1. 从 `SpUtil` 组装 `sid/spid/clientflag/userid/token/sign/requestId` 外层参数。
2. 优先按 `retcode` 分支：`retcode==0` 直接返回 Map；`retcode==-2/-3` 触发强制下线流程后抛 `_ApiException`；其他值带 `retmsg` 弹窗并抛异常。
3. 兼容旧格式：`code==0` 成功，否则读 `message` 弹窗并抛异常。
4. `catch` 块中区分 `DioException`：有 response 体时尝试解析 retcode/retmsg，无 response 体时用 `_friendlyNetworkError` 输出中文友好提示。
5. 所有分支均通过 `_logApi` 写入 `api_log`，失败额外写 `crash_log`；对大体积接口（`_ignoredLogPaths`）跳过成功日志，但失败仍记录。

### 3.4 业务异常类型 `_ApiException`

`http_helper.dart` 内定义私有 `_ApiException(Map)`，承载完整的后端响应 Map。`BasePagePresenter._onError` 仅在 `code != ExceptionHandle.cancel_error` 时 Toast，从而允许调用方取消请求（如页面 dispose）不弹错误。

### 3.5 MVP 层的错误传播

`BasePagePresenter.requestNetwork/asyncRequestNetwork` 统一：

- 进入时 `view.showProgress()`，成功且 `isClose=true` 时 `view.closeProgress()`。
- 失败时先关闭进度，再判断是否 Toast，最后可选回调 `onError(code, msg)` 供 Presenter 自定义处理（如跳转、刷新等）。
- `dispose` 时自动 `CancelToken.cancel()`，避免后台请求继续执行。

### 3.6 全局 Flutter 异常捕获

`handleError(body)` 在 `main.dart` 启动时调用：

- 重写 `FlutterError.onError`：Debug 模式打印堆栈，Release 模式委托 `Zone.current.handleUncaughtError` 确保异常能落盘。
- `runZonedGuarded` 包裹整个 `body`，未捕获异常统一交给 `_reportError`。
- `_reportError` 同步写入 `FileLogWriter.writeCrashLog`；Debug 打印堆栈，Release 预留服务器上报逻辑（注释说明可用 `flutter_bugly`）。

### 3.7 登录态失效处理

`http_helper.dart` 维护单例标志 `_isRedirectingToLogin` 防止并发重复跳转：

- `_handleForceLogout(retmsg)`：弹窗 `ConfirmDialog` → 清缓存 → 导航至 `LoginPage`。
- `_handleLoginExpired(retmsg)`：Toast 提示 → 延迟 2s 清理缓存并跳转 → 延迟 3s 重置标志位。
- `_clearCachePreservingRemember`：先备份“记住账号密码”相关 key，清空后再恢复，避免用户下次重新输入。

## 4. 约定与约束

- **网络错误必须经 `ExceptionHandle` 映射**：所有 Dio 异常最终应通过 `ExceptionHandle.handleException` 转为 `NetError`，禁止在业务层直接使用 `DioException.toString()` 作为用户可见文案。
- **业务 API 返回体遵循 ylx-boss 风格**：外层含 `sid/spid/client/token/sign/requestId/params`，内层 `retcode` 为 0 表示成功，-2/-3 表示登录失效；非该格式的响应由 `AdapterInterceptor` 适配为标准 `code/message/data`。
- **用户可见错误一律中文**：`catch` 块中无 response 体的网络异常使用 `_friendlyNetworkError` 生成中文提示，避免暴露 Dio 英文原文。
- **登录失效集中处理**：只有 `http_helper.dart` 中的 `_handleLoginExpired/_handleForceLogout` 负责清缓存并跳转登录页，其他模块不得自行实现。
- **Presenter 层错误展示统一**：所有网络错误通过 `BasePagePresenter._onError` 处理，仅在非 cancel 场景 Toast；需要特殊处理的 Presenter 通过 `onError` 回调接管。
- **全局异常不可吞掉**：`handleError` 要求所有未捕获异常必须落盘到 `FileLogWriter`，Release 环境禁止静默丢弃。
- **大体积接口成功日志可忽略**：`_ignoredLogPaths` 白名单内的接口成功时跳过 `api_log`，但失败仍需记录，便于定位。
- **取消请求不弹错误**：`cancel_error(1007)` 是约定的“静默取消”码，Presenter 层会绕过 Toast，调用方可放心在 dispose 时取消请求。