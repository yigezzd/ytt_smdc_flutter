import 'dart:io';
import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// https://medium.com/gskinner-team/flutter-simplify-platform-screen-size-detection-4cb6fc4f7ed1
class Device {
  static bool get isMobile => isAndroid || isIOS;
  static bool get isWeb => kIsWeb;

  static bool get isAndroid => !isWeb && Platform.isAndroid;
  static bool get isIOS => !isWeb && Platform.isIOS;

  static late AndroidDeviceInfo _androidInfo;
  static late IosDeviceInfo _iosInfo;
  static late WebBrowserInfo _webInfo;

  static Future<void> initDeviceInfo() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (isWeb) {
      _webInfo = await deviceInfo.webBrowserInfo;
    } else if (isAndroid) {
      _androidInfo = await deviceInfo.androidInfo;
    } else if (isIOS) {
      _iosInfo = await deviceInfo.iosInfo;
    }
  }

  /// 使用前记得初始化
  static int getAndroidSdkInt() {
    if (Constant.isDriverTest) {
      return -1;
    }
    if (isAndroid) {
      return _androidInfo.version.sdkInt;
    } else {
      return -1;
    }
  }

  /// 获取设备唯一标识（machserial）
  /// - Android: 使用 serialNumber（Build.SERIAL），降级用 id（Build.ID）
  /// - iOS: 使用 identifierForVendor
  /// - Web: 使用本地持久化的随机标识（对齐 smdcapp Security.getUUID；
  ///   userAgent 过长且含特殊字符，作为 machserial 会导致服务端校验失败）
  static String getDeviceSerial() {
    if (Constant.isDriverTest) return '';
    try {
      if (isWeb) {
        String webId = SpUtil.getString(_kWebDeviceIdKey) ?? '';
        if (webId.isEmpty) {
          webId = _genWebDeviceId();
          SpUtil.putString(_kWebDeviceIdKey, webId);
        }
        return webId;
      } else if (isAndroid) {
        final serial = _androidInfo.serialNumber;
        // Android 10+ 无 READ_PHONE_STATE 权限时 serialNumber 为 "unknown"
        if (serial.isNotEmpty && serial.toLowerCase() != 'unknown') {
          return serial;
        }
        return _androidInfo.id;
      } else if (isIOS) {
        return _iosInfo.identifierForVendor ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// 获取设备名称（clientName）
  /// - Android: brand + model
  /// - iOS: name
  /// - Web: 从 userAgent 解析浏览器名称
  static String getDeviceName() {
    if (Constant.isDriverTest) return 'Test';
    try {
      if (isWeb) {
        final ua = _webInfo.userAgent ?? '';
        return _parseBrowserName(ua);
      } else if (isAndroid) {
        final brand = _androidInfo.brand;
        final model = _androidInfo.model;
        return '$brand $model';
      } else if (isIOS) {
        return _iosInfo.name;
      }
    } catch (_) {}
    return 'Unknown';
  }

  /// 从 UserAgent 字符串中解析浏览器名称
  static String _parseBrowserName(String ua) {
    if (ua.isEmpty) return 'Web Browser';
    if (ua.contains('Edg/')) return 'Microsoft Edge';
    if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
    if (ua.contains('Chrome/')) return 'Google Chrome';
    if (ua.contains('Firefox/')) return 'Mozilla Firefox';
    if (ua.contains('Safari/') && !ua.contains('Chrome')) return 'Safari';
    return 'Web Browser';
  }

  /// Web 设备标识存储 key
  static const String _kWebDeviceIdKey = 'web_device_id';

  /// 生成 Web 设备标识（20位字母数字，对齐 smdcapp Security.getUUID 用途）
  static String _genWebDeviceId() {
    const String base =
        'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final math.Random rnd = math.Random.secure();
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 20; i++) {
      sb.write(base[rnd.nextInt(base.length)]);
    }
    return sb.toString();
  }
}
