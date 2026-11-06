import 'package:flutter_deer/util/amount_calc_utils.dart';

/// 优惠券抵扣金额计算（对齐 smdcapp TicketNumSearchPopup/MemberDateilsActivity.dealCouponAmt）
///
/// 项目券、礼品券的抵扣金额来自券适用商品/分类在当前订单中的金额，
/// 但只能覆盖券自身约定的份数，不能把同名菜品的整行数量全部核销；
/// 券接口返回了面额时以面额为上限，面额为 0 时按券份数（默认 1 份）逐份抵扣。
/// 现金券按面额抵扣，同样不能超过适用商品金额。

/// 券可用的订单明细（对齐 smdcapp：proflag 1=指定商品可用 2=指定商品不可用
/// 3=指定分类可用 4=指定分类不可用，pronames 为对应名称（英文逗号分隔）；
/// 未配置限制时全部商品可用）
List<Map<String, dynamic>> _usableDetails(
  Map<String, dynamic> coupon,
  List<Map<String, dynamic>> details,
) {
  final List<String> names = (coupon['pronames']?.toString() ?? '')
      .split(',')
      .map((String e) => e.trim())
      .where((String e) => e.isNotEmpty)
      .toList();
  final String proflag = coupon['proflag']?.toString() ?? '';
  final List<Map<String, dynamic>> usable = <Map<String, dynamic>>[];
  for (final Map<String, dynamic> detail in details) {
    bool matched = true;
    if (names.isNotEmpty) {
      final String productName =
          (detail['productname']?.toString() ?? '').trim();
      final String typeName = (detail['typename']?.toString() ?? '').trim();
      switch (proflag) {
        case '1':
          matched = names.contains(productName);
          break;
        case '2':
          matched = !names.contains(productName);
          break;
        case '3':
          matched = names.contains(typeName);
          break;
        case '4':
          matched = !names.contains(typeName);
          break;
        default:
          matched = true;
      }
    }
    if (matched) usable.add(detail);
  }
  return usable;
}

/// 计算券适用于当前订单的商品金额合计
double calcCouponEligibleAmount(
  Map<String, dynamic> coupon,
  List<Map<String, dynamic>> details,
) {
  double total = 0;
  for (final Map<String, dynamic> detail in _usableDetails(coupon, details)) {
    total = AmountCalcUtils.add(total, _toDouble(detail['rramt']));
  }
  return total;
}

/// 按券份数计算可抵扣金额
///
/// 券只能覆盖 [quantity] 份适用商品（如 1 张项目券只核销 1 份菜品），
/// 按单价从高到低逐份累计，份数用尽即停止，避免把整行数量都算进券金额。
double calcCouponQuantityAmount(
  Map<String, dynamic> coupon,
  List<Map<String, dynamic>> details,
  double quantity,
) {
  final List<Map<String, dynamic>> usable = _usableDetails(coupon, details)
    ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
        _unitPrice(b).compareTo(_unitPrice(a)));
  double remain = quantity > 0 ? quantity : 1;
  double total = 0;
  for (final Map<String, dynamic> detail in usable) {
    if (remain <= 0) break;
    final double unit = _unitPrice(detail);
    if (unit <= 0) continue;
    final double qty = _toDouble(detail['qty']);
    final double lineQty = qty > 0 ? qty : 1;
    final double take = remain < lineQty ? remain : lineQty;
    total = AmountCalcUtils.add(total, AmountCalcUtils.mul(unit, take));
    remain = AmountCalcUtils.sub(remain, take);
  }
  return total;
}

/// 计算券本次可抵扣金额
///
/// - 服务端已返回 userAmt 时优先使用（会员券列表接口可能按订单算好）；
/// - 现金券(favtype=1)按面额抵扣；
/// - 项目券/礼品券(favtype!=1)：面额大于 0 时以面额为上限（对齐 smdcapp
///   TicketNumSearchPopup），面额为 0 时按券份数（默认 1 份）抵扣；
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
    amount = faceAmt > 0
        ? faceAmt
        : calcCouponQuantityAmount(coupon, details, _couponQuantity(coupon));
  }
  return amount < eligible ? amount : eligible;
}

/// 券份数：优先取券数据中的 qty，其次 billcount（服务端券单数量），默认 1 份
double _couponQuantity(Map<String, dynamic> coupon) {
  final double qty = _toDouble(coupon['qty']);
  if (qty > 0) return qty;
  final double billCount = _toDouble(coupon['billcount']);
  return billCount > 0 ? billCount : 1;
}

/// 明细单价（折后行金额 / 数量；数量缺失按 1 份处理）
double _unitPrice(Map<String, dynamic> detail) {
  final double lineQty = _toDouble(detail['qty']);
  final double lineAmt = _toDouble(detail['rramt']);
  if (lineQty <= 0) return lineAmt;
  return AmountCalcUtils.div(lineAmt, lineQty);
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
