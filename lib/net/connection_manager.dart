import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 连接模式管理器（对齐 smdcapp 的双模式架构）
///
/// - 云服务模式：请求发往 [HttpApi.baseUrlYtt]（yun.bypos.net）
/// - 主设备模式（直连PC）：请求发往登录返回的 localhost 地址（如 http://192.168.8.47:9094）
///
/// 模式判定（对齐 smdcapp SpUtils.getNetMode / getServerType）：
/// - pcAlive：业务是否走主设备，综合连接策略与探活结果判定
/// - serverType：连接模式配置，0=不限 1=仅主设备 2=仅云服务
class ConnectionManager {
  ConnectionManager._();

  /// 【调试用】主设备地址覆盖：非空时强制使用该地址，忽略登录返回的 localhost。
  /// 同事本地调试时填入其主设备 IP，调试完成后请清空为 ''。
  //static const String debugLocalhostOverride = 'http://192.168.8.53:9094'; //林荣辉
  static const String debugLocalhostOverride = '';

  static bool _masterDeviceReachable = false;
  static String? _activeServerType;

  // 业务调用以 pcAlive 选路；仅主设备断线时仍须保留 PC 路由，禁止降级到云端。
  static bool get pcAlive =>
      isMasterOnly || (!isCloudOnly && _masterDeviceReachable);

  static set pcAlive(bool alive) {
    _masterDeviceReachable = alive;
  }

  static bool get masterDeviceReachable => _masterDeviceReachable;
  static bool get sessionInitialized => _activeServerType != null;
  static bool get isMasterOnly => _activeServerType == '1';
  static bool get isCloudOnly => _activeServerType == '2';

  static void beginSession() {
    _activeServerType = getServerType();
    _masterDeviceReachable = false;
  }

  static final StreamController<void> _masterDeviceLostController =
      StreamController<void>.broadcast();

  /// 主设备连接丢失事件流（对齐 smdcapp GlobalEventListener → EventBus.post(NetModeEvent)）
  ///
  /// 运行期间主设备接口请求发生网络层失败时广播，桌台页订阅后弹出连接失败提示弹窗。
  static Stream<void> get onMasterDeviceLost => _masterDeviceLostController.stream;

  static void notifyMasterDeviceLost() {
    if (!_masterDeviceReachable) {
      return;
    }
    _masterDeviceReachable = false;
    if (!_masterDeviceLostController.isClosed) {
      _masterDeviceLostController.add(null);
    }
  }

  static int getNetMode() => pcAlive ? 1 : 2;

  static bool get isServerTypeManaged =>
      !kDebugMode && SpUtil.getString('ClientLinkModel') == '1';

  static String getServerType() {
    final String value = isServerTypeManaged
        ? SpUtil.getString('ClientLinkModelValue') ?? '0'
        : SpUtil.getString(Constant.serverType) ?? '0';
    final String type = const <String>['0', '1', '2'].contains(value) ? value : '0';
    if (isServerTypeManaged) {
      SpUtil.putString(Constant.serverType, type);
    }
    return type;
  }

  static bool setServerType(String type) {
    if (isServerTypeManaged) {
      return false;
    }
    SpUtil.putString(Constant.serverType, type);
    return true;
  }

  /// 主设备地址（登录响应的 localhost 字段）
  ///
  /// 调试期间若 [debugLocalhostOverride] 非空则优先返回该覆盖地址。
  static String getLocalhost() {
    if (debugLocalhostOverride.isNotEmpty) {
      return debugLocalhostOverride;
    }
    return SpUtil.getString(Constant.localhost) ?? '';
  }

  static void saveLocalhost(String host) {
    SpUtil.putString(Constant.localhost, host);
  }

  static String resolveBaseUrl({bool masterDevice = false}) {
    if (masterDevice) {
      if (isCloudOnly) {
        throw StateError('当前仅限云服务，不允许连接主设备');
      }
      final String host = getLocalhost();
      if (host.isEmpty || !host.startsWith('http')) {
        throw StateError('主设备ip地址获取失败，请检查主设备');
      }
      return host;
    }
    return HttpApi.baseUrlYtt;
  }
}
