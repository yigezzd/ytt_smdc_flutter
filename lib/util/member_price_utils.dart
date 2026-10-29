import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';

/// 购物车行会员价重算（对齐 smdcapp ShoppingCartUtil.getMemberPrice）
///
/// 会员价、基础促销、手工折扣之间按「取最优」：会员价只在低于
/// 当前促销折后价时生效；做法加价不参与会员价折扣，另行叠加。
class MemberPriceUtils {
  MemberPriceUtils._();

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// 对整批购物车行套用会员价；[member] 为空时清除会员价标记
  static void applyToItems(List<CartItem> items, VipMember? member) {
    for (final CartItem item in items) {
      applyToItem(item, member);
    }
  }

  static void applyToItem(CartItem item, VipMember? member) {
    if (item.isGift || item.isRefunded || item.isCombo) {
      item.memberUnitPrice = null;
      return;
    }
    if (member == null || member.prefetype == 0) {
      item.memberUnitPrice = null;
      return;
    }
    // 改价为最终价，不再叠加会员价
    if (item.customPrice != null) {
      item.memberUnitPrice = null;
      return;
    }
    // 团购核销菜按券分摊价结算
    if (item.douyinflag == 1) {
      item.memberUnitPrice = null;
      return;
    }

    // 会员价以菜品基础价（不含做法数量加价）为比较基准
    final double base = item.product.price - item.unitCookExtra;
    if (base <= 0) {
      item.memberUnitPrice = null;
      return;
    }

    double memberPrice = 0;
    switch (member.prefetype) {
      case 1:
        // 零售价折扣：只对可打折商品生效
        if (item.product.dscflag == 1 &&
            member.discount > 0 &&
            member.discount < 100) {
          memberPrice = base * member.discount / 100;
        }
        break;
      case 2:
        memberPrice = item.product.mprice1;
        break;
      case 3:
        memberPrice = item.product.mprice2;
        break;
      case 4:
        memberPrice = item.product.mprice3;
        break;
    }
    if (memberPrice <= 0 || memberPrice >= base - 0.005) {
      item.memberUnitPrice = null;
      return;
    }

    // 与当前促销价取最优（促销折后价更低时保留促销）
    final double promoBase = item.baseUnitPrice;
    final double promoAfter = item.discount > 0 && item.discount < 100
        ? promoBase * item.discount / 100
        : promoBase;
    if (memberPrice < promoAfter - 0.005) {
      item.memberUnitPrice = _round2(memberPrice);
    } else {
      item.memberUnitPrice = null;
    }
  }
}
