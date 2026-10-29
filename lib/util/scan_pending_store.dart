import 'dart:convert';

import 'package:sp_util/sp_util.dart';

/// 扫码支付异常订单本地缓存（对齐 smdcapp PayFlow 表）
///
/// 支付中途断网/超时/用户关闭支付弹窗时记录一笔待查询订单，
/// 供“异常订单”页面重新发起交易查询。
class ScanPendingStore {
  ScanPendingStore._();

  static const String _key = 'pending_scan_orders';

  static List<Map<String, dynamic>> load() {
    try {
      final String raw = SpUtil.getString(_key) ?? '';
      if (raw.isEmpty) return <Map<String, dynamic>>[];
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((Map e) => e.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static void add({
    required String billno,
    required double amt,
    required String payid,
    required String payname,
    String tableName = '',
    String cashname = '',
    Map<String, String> payConfig = const <String, String>{},
  }) {
    if (billno.isEmpty) return;
    final List<Map<String, dynamic>> list = load();
    if (list.any((Map<String, dynamic> e) => e['billno'] == billno)) return;
    list.add(<String, dynamic>{
      'billno': billno,
      'amt': amt,
      'payid': payid,
      'payname': payname,
      'tablename': tableName,
      'cashname': cashname,
      'billdate': DateTime.now().toString().substring(0, 19),
      'hasUploadFlag': '0',
      'payConfig': payConfig,
    });
    SpUtil.putString(_key, json.encode(list));
  }

  static void remove(String billno) {
    final List<Map<String, dynamic>> list = load();
    list.removeWhere((Map<String, dynamic> e) => e['billno'] == billno);
    SpUtil.putString(_key, json.encode(list));
  }

  static void clear() {
    SpUtil.putString(_key, '[]');
  }
}
