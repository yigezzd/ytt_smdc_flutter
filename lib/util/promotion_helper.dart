import 'dart:convert';

import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 促销活动模型（对齐 smdcapp PrometionBean）
class PromotionInfo {
  PromotionInfo({
    required this.billid,
    required this.billtype,
    required this.billname,
    this.discount = 0,
    this.amt = 0,
  });

  factory PromotionInfo.fromJson(Map<String, dynamic> json) {
    return PromotionInfo(
      billid: json['billid']?.toString() ?? '',
      billtype: _toInt(json['billtype']),
      billname: json['billname']?.toString() ?? json['name']?.toString() ?? '',
      discount: _toDouble(json['discount']),
      amt: _toDouble(json['amt']),
    );
  }

  final String billid;

  /// 活动类型（对齐 smdcapp BilidType：5满量 6满减 8满折 等）
  final int billtype;
  final String billname;
  final double discount;
  final double amt;

  /// 活动类型描述
  String get typeText {
    switch (billtype) {
      case 5:
        return '满量优惠';
      case 6:
        return '满减';
      case 7:
        return '满赠';
      case 8:
        return '满折';
      default:
        return '促销';
    }
  }
}

/// 促销引擎辅助类（对齐 smdcapp MpService）
///
/// 通过云端接口获取可用促销并计算折扣金额，
/// 避免在本地复刻 smdcapp 基于 Room 数据库的完整促销规则计算。
class PromotionHelper {
  PromotionHelper._();

  /// 获取当前订单可用的促销活动列表（对齐 smdcapp getSalesPromotionList）
  ///
  /// [details] 订单明细 JSON 数组，[vipid] 会员ID（散客传空）
  static Future<List<PromotionInfo>> fetchPromotions({
    required List<Map<String, dynamic>> details,
    String vipid = '',
  }) async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getSalesPromotionList,
        <String, dynamic>{
          'details': jsonEncode(details),
          'vipid': vipid,
          'client': 'APP',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
      if (data is Map<String, dynamic>) {
        final dynamic l = data['list'];
        if (l is List) {
          list = l.whereType<Map<String, dynamic>>().toList();
        }
      } else if (data is List) {
        list = data.whereType<Map<String, dynamic>>().toList();
      }
      return list.map(PromotionInfo.fromJson).toList();
    } catch (_) {
      return <PromotionInfo>[];
    }
  }

  /// 计算促销折扣后的金额（对齐 smdcapp amountAfterDiscount）
  ///
  /// 返回服务端计算出的优惠金额。
  static Future<double> calcDiscountAmt({
    required List<Map<String, dynamic>> details,
    required String billid,
    String vipid = '',
  }) async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.amountAfterDiscount,
        <String, dynamic>{
          'details': jsonEncode(details),
          'billid': billid,
          'vipid': vipid,
          'client': 'APP',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        return _toDouble(data['dscamt'] ?? data['discountamt'] ?? data['amt']);
      }
      return _toDouble(data);
    } catch (_) {
      return 0;
    }
  }
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}
