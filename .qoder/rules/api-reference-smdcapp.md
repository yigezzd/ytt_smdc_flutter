---
description: 本项目基于smdcapp改造，所有接口调用（云服务模式和主设备模式）必须参考E:\VUEAPP\smdcapp中的接口定义和业务逻辑
alwaysApply: true
---

# 接口与业务参考规范（smdcapp）

## 项目背景

本项目 `ytt-smdc-flutter` 是基于 Android 原生项目 `smdcapp`（路径：`E:\VUEAPP\smdcapp`）改造而来的 Flutter 版本。smdcapp 的包名为 `com.bycloud.catering`，是接口定义和业务逻辑的权威参考来源。

## 核心规则

### 1. 接口实现必须参考 smdcapp

在实现任何接口调用时（无论是云服务模式还是主设备模式），**必须先查阅 smdcapp 中对应的接口实现**，确保：

- 接口路径（URL path）与 smdcapp 一致
- 请求参数（字段名、类型、编码方式）与 smdcapp 一致
- 响应数据结构（字段名、嵌套层级）与 smdcapp 一致
- 业务逻辑流程（调用顺序、条件判断、异常处理）与 smdcapp 对齐

### 2. 双模式接口参考路径

smdcapp 中接口相关代码位于：

- **网络层**：`E:\VUEAPP\smdcapp\app\src\main\java\com\bycloud\catering\http\`
  - `Net.java` — 接口地址常量定义（云服务 + 主设备）
  - `HttpPostClient.java` — 请求封装与发送逻辑
  - `NetInterceptor.java` — HMAC-MD5 签名拦截器
  - `EncryptKey.java` — 签名密钥与加密逻辑
  - `ByCloudObserver.java` / `YunObserver.java` — 响应解析（主设备/云服务）
- **数据模型**：`E:\VUEAPP\smdcapp\app\src\main\java\com\bycloud\catering\bean\`
- **业务逻辑**：`E:\VUEAPP\smdcapp\app\src\main\java\com\bycloud\catering\ui\`
- **工具类**：`E:\VUEAPP\smdcapp\app\src\main\java\com\bycloud\catering\util\`

### 3. 两种模式的接口规范

#### 云服务模式

- Base URL：`baseUrlYtt`（如 `https://yun.bypos.net/YttSvr/app`）
- 路径格式：`/YttSvr/app/xxx`
- 响应结构：`{ retcode, retmsg, data }`
- 参考 smdcapp 中 `YunObserver.java` 的解析逻辑

#### 主设备模式

- Base URL：登录响应中的 `localhost` 字段（如 `http://192.168.8.47:9094`）
- 路径格式：`/api/xxx`（如 `/api/table/GetTableInfoList`）
- 响应结构：`{ Success, Message, Data }`（字段首字母大写）
- 参考 smdcapp 中 `ByCloudObserver.java` 的解析逻辑

### 4. 签名规范

两种模式的接口请求均需携带 HMAC-MD5 签名，签名逻辑参考：

- `E:\VUEAPP\smdcapp\app\src\main\java\com\bycloud\catering\http\NetInterceptor.java`
- `E:\VUEAPP\smdcapp\app\src\main\java\com\bycloud\catering\http\EncryptKey.java`

### 5. 新增接口开发流程

1. 在 smdcapp 中找到对应功能的接口调用代码
2. 确认接口路径、请求参数、响应结构
3. 确认该接口属于云服务模式、主设备模式还是两者都有
4. 在本项目中按 Flutter/Dart 规范实现，保持业务逻辑一致
5. 如 smdcapp 中找不到对应接口，需明确说明并与用户确认

## 注意事项

- 本项目是 Flutter（Dart）实现，smdcapp 是 Android（Java/Kotlin）实现，语言不同但业务逻辑必须对齐
- 字段命名风格可能有差异（Java 驼峰 vs Dart 驼峰），但接口传输的字段名必须与后端一致
- 遇到不确定的接口细节时，优先去 smdcapp 源码中查找验证，而非猜测
