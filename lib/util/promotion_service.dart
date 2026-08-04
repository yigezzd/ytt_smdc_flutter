import 'dart:convert';

import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/log_utils.dart';

/// 促销数据模型（对齐 smdcapp PrometionBean / MPMaster）
///
/// billtype 促销类型：
/// 1=分类折扣, 2=菜品折扣, 3=特价菜, 4=买赠(满量),
/// 5=满量折扣, 6=满减, 7=满赠(满额), 8=满折
class PromotionInfo {
  PromotionInfo({
    required this.billid,
    required this.billtype,
    required this.billname,
    this.applytype = 0,
    this.vipflag = '1',
    this.discount = 0,
    this.qty = 0,
    this.amt = 0,
    this.giveqty = 0,
    this.status = 1,
    this.effectday = '',
    this.startdate = '',
    this.enddate = '',
  });

  factory PromotionInfo.fromJson(Map<String, dynamic> json) {
    return PromotionInfo(
      billid: json['billid']?.toString() ?? '',
      billtype: _toInt(json['billtype']),
      billname: json['billname']?.toString() ?? '',
      applytype: _toInt(json['applytype']),
      vipflag: json['vipflag']?.toString() ?? '1',
      discount: _toDouble(json['discount']),
      qty: _toDouble(json['qty']),
      amt: _toDouble(json['amt']),
      giveqty: _toDouble(json['giveqty']),
      status: _toInt(json['status']),
      effectday: json['effectday']?.toString() ?? '',
      startdate: json['startdate']?.toString() ?? '',
      enddate: json['enddate']?.toString() ?? '',
    );
  }

  /// 促销活动ID
  final String billid;

  /// 促销类型（1-8）
  final int billtype;

  /// 促销名称
  final String billname;

  /// 适用类型：0=全部商品, 1=按分类, 2=按商品
  final int applytype;

  /// 会员标志：1=全部, 2=仅散客, 3=仅会员
  final String vipflag;

  /// 折扣率（如 85 表示 8.5折）
  final double discount;

  /// 满量条件数量
  final double qty;

  /// 满额条件金额
  final double amt;

  /// 赠送数量
  final double giveqty;

  /// 状态
  final int status;

  /// 有效星期（7位字符串，1=周一...7=周日）
  final String effectday;

  /// 开始日期
  final String startdate;

  /// 结束日期
  final String enddate;

  /// 获取促销类型描述
  String get billtypeDesc {
    switch (billtype) {
      case 1: return '分类折扣';
      case 2: return '菜品折扣';
      case 3: return '特价菜';
      case 4: return '买赠';
      case 5: return '满量折扣';
      case 6: return '满减';
      case 7: return '满赠';
      case 8: return '满折';
      default: return '促销';
    }
  }
}

/// 促销折扣计算结果（对齐 smdcapp amountAfterDiscount 返回）
class PromotionDiscountResult {
  PromotionDiscountResult({
    required this.details,
    this.totalDiscountAmt = 0,
  });

  /// 折扣后的明细列表（每项含 rrprice, discount, discountamt 等）
  final List<Map<String, dynamic>> details;

  /// 总折扣金额
  final double totalDiscountAmt;
}

/// 促销服务（对齐 smdcapp MpService + DishesApi 促销接口）
///
/// 通过云服务 API 获取促销列表和计算折扣，
/// 服务器端完成规则匹配，客户端只需传入当前订单明细。
class PromotionService {
  PromotionService._();
  static final PromotionService instance = PromotionService._();

  /// 获取当前可用的促销活动列表（对齐 smdcapp /mp/getSalesPromotionList）
  ///
  /// [details] 当前订单明细 JSON 数组字符串
  /// [vipid] 会员ID（空=散客）
  /// 返回匹配的促销活动列表
  Future<List<PromotionInfo>> getSalesPromotionList({
    required String details,
    String vipid = '',
  }) async {
    try {
      final resp = await requestForm(HttpApi.getSalesPromotionList, <String, dynamic>{
        'details': details,
        'vipid': vipid,
        'appflag': '1',
      });
      // requestForm 失败时抛异常，到达此处即为成功
      final data = resp['data'];
      if (data is List) {
        return data.map((e) => PromotionInfo.fromJson(
          e is Map<String, dynamic> ? e : <String, dynamic>{},
        )).toList();
      }
      // 有时 data 是嵌套结构
      if (data is Map<String, dynamic> && data['list'] is List) {
        return (data['list'] as List).map((e) => PromotionInfo.fromJson(
          e is Map<String, dynamic> ? e : <String, dynamic>{},
        )).toList();
      }
      return [];
    } catch (e) {
      Log.e('PromotionService.getSalesPromotionList error: $e');
      return [];
    }
  }

  /// 计算促销折扣后金额（对齐 smdcapp /mp/amountAfterDiscount）
  ///
  /// [billid] 促销活动ID
  /// [details] 当前订单明细 JSON 数组字符串
  /// [amt] 当前订单总金额
  /// 返回折扣计算结果
  Future<PromotionDiscountResult?> amountAfterDiscount({
    required String billid,
    required String details,
    required double amt,
  }) async {
    try {
      final resp = await requestForm(HttpApi.amountAfterDiscount, <String, dynamic>{
        'billid': billid,
        'details': details,
        'amt': amt.toStringAsFixed(2),
      });
      // requestForm 失败时抛异常，到达此处即为成功
      final data = resp['data'];
      if (data is List) {
        final details = data.map((e) =>
          e is Map<String, dynamic> ? e : <String, dynamic>{}
        ).toList();
        double totalDsc = 0;
        for (final d in details) {
          totalDsc += _toDouble(d['discountamt']);
        }
        return PromotionDiscountResult(details: details, totalDiscountAmt: totalDsc);
      }
      if (data is Map<String, dynamic>) {
        final list = data['list'] is List ? data['list'] as List : [];
        final details = list.map((e) =>
          e is Map<String, dynamic> ? e : <String, dynamic>{}
        ).toList();
        double totalDsc = 0;
        for (final d in details) {
          totalDsc += _toDouble(d['discountamt']);
        }
        return PromotionDiscountResult(details: details, totalDiscountAmt: totalDsc);
      }
      return null;
    } catch (e) {
      Log.e('PromotionService.amountAfterDiscount error: $e');
      return null;
    }
  }

  /// 构建订单明细 JSON（用于促销接口参数）
  ///
  /// [items] 购物车商品列表，每项需含：
  /// productid, typeid, qty, sellprice, rramt(=qty*sellprice), specid(可选)
  static String buildDetailsJson(List<Map<String, dynamic>> items) {
    return json.encode(items);
  }

  /// 判断促销类型是否为折扣类（1,2,3,5,8）
  static bool isDiscountType(int billtype) {
    return billtype == 1 || billtype == 2 || billtype == 3 ||
           billtype == 5 || billtype == 8;
  }

  /// 判断促销类型是否为赠送类（4,7）
  static bool isGiveType(int billtype) {
    return billtype == 4 || billtype == 7;
  }

  /// 判断促销类型是否为满减类（6）
  static bool isReductionType(int billtype) {
    return billtype == 6;
  }
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? 0;
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
