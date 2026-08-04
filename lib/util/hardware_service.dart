import 'package:flutter/foundation.dart';

/// 硬件集成服务（对齐 smdcapp NfcUtils + 扫码枪 + 电子秤 + 钱箱）
///
/// 提供 NFC 读卡、扫码枪、电子秤、钱箱等硬件设备的统一接入接口。
///
/// 当前为接口定义与占位实现。实际硬件功能需要引入对应插件：
/// - NFC读卡: `nfc_manager` 或 `flutter_nfc_kit`
/// - 扫码枪: 已使用 `mobile_scanner`（见 pubspec.yaml）
/// - 电子秤: 需定制串口/蓝牙协议插件
/// - 钱箱: 通过打印机指令触发（ESC/POS p 指令）
///
/// 对齐 smdcapp 的硬件工具类：
/// - NfcUtils.java（NFC读卡）
/// - MipcaActivityCapture.java（扫码）
/// - 电子秤/钱箱（通过打印指令）
class HardwareService {
  HardwareService._();
  static final HardwareService instance = HardwareService._();

  // ──────────── NFC（对齐 smdcapp NfcUtils）─────────────────

  /// NFC 是否可用
  bool get isNfcAvailable {
    // TODO: 引入 nfc_manager 后实现真实检测
    return false;
  }

  /// 读取 NFC 卡号（对齐 smdcapp NfcUtils 读取会员卡）
  ///
  /// 返回卡号字符串，失败返回 null
  Future<String?> readNfcCard() async {
    // TODO: 引入 nfc_manager 后实现
    // 对齐 smdcapp: 读取 NFC 标签的 ID 作为会员卡号
    debugPrint('[HardwareService] NFC 读卡功能待接入 nfc_manager 插件');
    return null;
  }

  /// 停止 NFC 监听
  Future<void> stopNfc() async {
    // TODO: 引入 nfc_manager 后实现
  }

  // ──────────── 扫码枪（对齐 smdcapp MipcaActivityCapture）─────────────────

  /// 扫码功能已由 mobile_scanner 插件提供。
  /// 见 lib/pages/order/pay_scan_page.dart（支付扫码）
  /// 和点菜页的扫码点菜功能。

  // ──────────── 电子秤（对齐 smdcapp 称重菜功能）─────────────────

  /// 电子秤是否可用
  bool get isScaleAvailable {
    // TODO: 引入电子秤串口/蓝牙插件后实现
    return false;
  }

  /// 读取电子秤重量（对齐 smdcapp 称重菜 weighflag=1）
  ///
  /// 返回重量（千克），失败返回 null
  Future<double?> readScaleWeight() async {
    // TODO: 引入电子秤插件后实现
    // 对齐 smdcapp: 称重菜点菜时从电子秤读取重量
    debugPrint('[HardwareService] 电子秤功能待接入定制插件');
    return null;
  }

  // ──────────── 钱箱（对齐 smdcapp 钱箱指令）─────────────────

  /// 打开钱箱（通过打印机 ESC/POS 指令触发）
  ///
  /// 对齐 smdcapp: 结账成功后发送开钱箱指令
  /// ESC/POS 指令: 0x1B 0x70 0x00 0x19 0x19 (p 指令)
  Future<void> openCashDrawer() async {
    // TODO: 通过打印通道发送开钱箱指令
    // 对齐 smdcapp: 结账后自动弹开钱箱
    debugPrint('[HardwareService] 钱箱功能需通过打印通道发送 ESC/POS 指令');
  }
}
