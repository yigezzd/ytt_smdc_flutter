import 'package:flutter_deer/util/amount_calc_utils.dart';

/// 优惠券抵扣金额计算（对齐 smdcapp TicketNumSearchPopup/MemberDateilsActivity.dealCouponAmt）
///
/// 项目券、礼品券本身没有面额（服务端 voucherVerify 返回 faceamt=0），
/// 其抵扣金额来自券适用商品/分类在当前订单中的金额合计；
/// 现金券按面额抵扣，但同样不能超过适用商品金额。

/// 计算券适用于当前订单的商品金额合计
///
/// 对齐 smdcapp：proflag 1=指定商品可用 2=指定商品不可用 3=指定分类可用
/// 4=指定分类不可用，pronames 为对应名称（英文逗号分隔）；未配置限制时全部商品可用。
double calcCouponEligibleAmount(
  Map<String, dynamic> coupon,
  List<Map<String, dynamic>> details,
) {
  final List<String> names = (coupon['pronames']?.toString() ?? '')
      .split(',')
      .map((String e) => e.trim())
      .where((String e) => e.isNotEmpty)
      .toList();
  final String proflag = coupon['proflag']?.toString() ?? '';
  double total = 0;
  for (final Map<String, dynamic> detail in details) {
    bool usable;
    if (names.isEmpty) {
      usable = true;
    } else {
      final String productName =
          (detail['productname']?.toString() ?? '').trim();
      final String typeName = (detail['typename']?.toString() ?? '').trim();
      switch (proflag) {
        case '1':
          usable = names.contains(productName);
          break;
        case '2':
          usable = !names.contains(productName);
          break;
        case '3':
          usable = names.contains(typeName);
          break;
        case '4':
          usable = !names.contains(typeName);
          break;
        default:
          usable = true;
      }
    }
    if (usable) {
      total = AmountCalcUtils.add(total, _toDouble(detail['rramt']));
    }
  }
  return total;
}

/// 计算券本次可抵扣金额
///
/// - 服务端已返回 userAmt 时优先使用（会员券列表接口可能按订单算好）；
/// - 现金券(favtype=1)按面额抵扣；
/// - 项目券/礼品券(favtype!=1)按适用商品金额抵扣；
/// - 最终不超过适用商品金额合计。
double calcCouponDeductAmount(
  Map<String, dynamic> coupon,
  List<Map<String, dynamic>> details,
) {
  final double eligible = calcCouponEligibleAmount(coupon, details);
  if (eligible <= 0) return 0;
  final double serverAmt = _toDouble(coupon['userAmt'] ?? coupon['useramt']);
  final double faceAmt = _toDouble(
      coupon['faceamt'] ?? coupon['favamt'] ?? coupon['amount']);
  final int favtype = _toInt(coupon['favtype']);
  double amount;
  if (serverAmt > 0) {
    amount = serverAmt;
  } else if (favtype == 1) {
    amount = faceAmt > 0 ? faceAmt : eligible;
  } else if (favtype == 0) {
    // 类型缺失时按面额兜底，面额为 0 再按适用商品金额
    amount = faceAmt > 0 ? faceAmt : eligible;
  } else {
    amount = eligible;
  }
  return amount < eligible ? amount : eligible;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}
