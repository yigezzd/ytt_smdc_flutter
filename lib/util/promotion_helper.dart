import 'dart:convert';

import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/file_log_writer.dart';

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

/// 买赠/满赠活动的赠品（对齐 smdcapp ProductBean）
class PromotionGift {
  PromotionGift({
    required this.productid,
    required this.name,
    this.unit = '',
    this.typeid = '',
    this.sellprice = 0,
  });

  factory PromotionGift.fromJson(Map<String, dynamic> json) {
    return PromotionGift(
      productid: json['productid']?.toString() ?? '',
      name: json['name']?.toString() ?? json['productname']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      typeid: json['typeid']?.toString() ?? '',
      sellprice: _toDouble(json['sellprice']),
    );
  }

  final String productid;
  final String name;
  final String unit;
  final String typeid;
  final double sellprice;

  /// 弹窗内已选数量（临时变量，对齐 smdcapp ProductBean.selectNum）
  double selectQty = 0;
}

/// 买赠/满赠活动（对齐 smdcapp PrometionBean.DataBean）
///
/// [billtype] 4=买赠（按数量赠） 7=满赠（按金额赠）。
/// [sumgiveqty] 仅买赠返回（本单可赠总数）；满赠取规则的 [giveqty]。
class PromotionGiftActivity {
  PromotionGiftActivity({
    required this.billid,
    required this.billtype,
    required this.name,
    this.giveqty = 0,
    this.sumgiveqty = 0,
    this.prolsit = const <PromotionGift>[],
  });

  factory PromotionGiftActivity.fromJson(Map<String, dynamic> json) {
    final dynamic rawList = json['prolsit'] ?? json['prolist'];
    final List<PromotionGift> gifts = rawList is List
        ? rawList
            .whereType<Map<String, dynamic>>()
            .map(PromotionGift.fromJson)
            .where((PromotionGift g) => g.productid.isNotEmpty)
            .toList()
        : <PromotionGift>[];
    return PromotionGiftActivity(
      billid: json['billid']?.toString() ?? '',
      billtype: _toInt(json['billtype']),
      name: json['name']?.toString() ?? json['billname']?.toString() ?? '',
      giveqty: _toDouble(json['giveqty']),
      sumgiveqty: _toDouble(json['sumgiveqty']),
      prolsit: gifts,
    );
  }

  final String billid;
  final int billtype;
  final String name;

  /// 满赠每档可赠数量
  final double giveqty;

  /// 买赠本单可赠总数量
  final double sumgiveqty;

  final List<PromotionGift> prolsit;

  /// 已赠数量（客户端按明细统计，对齐 smdcapp giveNum）
  double givenQty = 0;

  /// 可赠上限（对齐 smdcapp：买赠取 sumgiveqty，满赠取 giveqty）
  double get maxGiveQty => billtype == 4 ? sumgiveqty : giveqty;

  /// 剩余可赠数量
  double get remainQty {
    final double remain = maxGiveQty - givenQty;
    return remain > 0 ? remain : 0;
  }

  /// 赠品明细标记（对齐 smdcapp PrometionGivePopup：买赠=1，满赠=4）
  int get giftFlag => billtype == 4 ? 1 : 4;
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

  /// 下单前促销校验：获取买赠/满赠活动及赠品（对齐 smdcapp
  /// PrometionModel.getSalesPromotionList(promoflag = 2)）
  ///
  /// [saleid] 订单ID，[amt] 菜品总原价（含做法加价），[qty] 总数量，
  /// [details] 完整明细 JSON 数组字符串（待下单 + 已下单），[vipid] 会员ID（散客传空）。
  static Future<List<PromotionGiftActivity>> fetchGiftActivities({
    required String saleid,
    required double amt,
    required String qty,
    required String details,
    String vipid = '',
  }) async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getSalesPromotionList,
        <String, dynamic>{
          'saleid': saleid,
          'amt': amt.toStringAsFixed(2),
          'qty': qty,
          'details': details,
          'vipid': vipid,
          // 2=（买赠、满赠活动），对齐 smdcapp PrometionModel
          'promoflag': '2',
        },
        showError: false,
      );
      final List<PromotionGiftActivity> activities = _extractList(resp)
          .map(PromotionGiftActivity.fromJson)
          .where((PromotionGiftActivity a) =>
              (a.billtype == 4 || a.billtype == 7) && a.prolsit.isNotEmpty)
          .toList();
      FileLogWriter.instance.writeToFile(
          '下单前促销校验: 活动${activities.length}个 '
          '${activities.map((PromotionGiftActivity a) => '${a.name}(类型${a.billtype} 可赠${a.maxGiveQty} 赠品${a.prolsit.length})').join(' ')}',
          tag: '促销');
      return activities;
    } catch (e) {
      // 校验失败不阻塞下单（对齐结账页促销查询的容错口径）
      FileLogWriter.instance.writeToFile('下单前促销校验失败: $e', tag: '促销');
      return <PromotionGiftActivity>[];
    }
  }

  /// 从促销接口响应中提取活动列表（data 数组或 data.list）
  static List<Map<String, dynamic>> _extractList(Map<String, dynamic> resp) {
    final dynamic data = resp['data'] ?? resp['Data'];
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final dynamic list = data['list'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().toList();
      }
    }
    return <Map<String, dynamic>>[];
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
