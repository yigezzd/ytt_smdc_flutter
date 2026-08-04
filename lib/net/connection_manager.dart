import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 连接模式管理器（对齐 smdcapp 的双模式架构）
///
/// - 云服务模式：请求发往 [HttpApi.baseUrlYtt]（yun.bypos.net）
/// - 主设备模式（直连PC）：请求发往登录返回的 localhost 地址（如 http://192.168.8.47:9094）
///
/// 模式判定（对齐 smdcapp SpUtils.getNetMode / getServerType）：
/// - pcAlive：主设备是否可达，登录后由探活接口（GetHostSyncTime）核对 sid/spid 后置位
/// - serverType：连接模式配置，0=不限（按 pcAlive 自动）1=仅主设备 2=仅云服务
class ConnectionManager {
  ConnectionManager._();

  /// 【调试用】主设备地址覆盖：非空时强制使用该地址，忽略登录返回的 localhost。
  /// 同事本地调试时填入其主设备 IP，调试完成后请清空为 ''。
  //static const String debugLocalhostOverride = 'http://192.168.8.53:9094'; //林荣辉
  static const String debugLocalhostOverride = '';

  /// 主设备是否可达（内存态，登录后由探活接口设置）
  static bool pcAlive = false;

  /// 网络连接模式：1=直连主设备 2=云服务
  /// （暂不检测离线状态，后续可结合 connectivity_plus 返回 0=离线）
  static int getNetMode() => pcAlive ? 1 : 2;

  /// 连接模式配置：0=不限 1=仅主设备 2=仅云服务
  static String getServerType() => SpUtil.getString(Constant.serverType) ?? '0';

  static void setServerType(String type) {
    SpUtil.putString(Constant.serverType, type);
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

  /// 解析业务请求的 base URL
  ///
  /// [masterDevice] 为 true 时优先返回主设备地址（需 pcAlive 且 localhost 有效），
  /// 否则回退到云服务地址。登录类接口应始终走云服务（传 false）。
  static String resolveBaseUrl({bool masterDevice = false}) {
    if (masterDevice && pcAlive) {
      final String host = getLocalhost();
      if (host.isNotEmpty && host.startsWith('http')) {
        return host;
      }
    }
    return HttpApi.baseUrlYtt;
  }
}
