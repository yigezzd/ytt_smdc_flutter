/// 订单单品价格重算（对齐 smdcapp ShoppingCartUtil / PriceEngine 单品规则）
///
/// 会员价、促销价、手工折扣之间按「取最优」处理：
/// 所有有效优惠都以原价 sellprice 为基准独立计算，最终写入价格更低者。
class OrderPriceCalc {
  OrderPriceCalc._();

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// 重算单个明细的会员价并回写 rrprice/rramt/oldrramt
  ///
  /// 移植 smdcapp ShoppingCartUtil.getMemberPrice + getDownMemberPrice：
  /// - [prefetype] 会员优惠类型：0=无优惠，1=零售价折扣，2/3/4=会员价1/2/3
  /// - [memberDiscount] 会员折扣率（prefetype=1 时使用，10 表示 1 折）
  /// - [clearMemberMark] 为 true 时先清除上次会员价标记（specpriceflag=5），
  ///   用于切换/退出会员后从原价重新计算，避免旧会员折扣残留
  ///
  /// 会员价生效条件（对齐 smdcapp）：
  /// - prefetype=1：商品可打折(dscflag=1) 且 0<会员折扣<100，价格需低于当前价
  /// - prefetype=2/3/4：对应 mprice1/2/3>0 且低于当前价
  /// - 手工折扣更优时恢复原优惠类型
  static void applyMemberPrice(
    Map<String, dynamic> b, {
    required int prefetype,
    required double memberDiscount,
    bool clearMemberMark = false,
  }) {
    if (clearMemberMark && _toInt(b['specpriceflag']) == 5) {
      b['discount'] = 100.0;
      b['rrprice'] = 0.0;
      b['specpriceflag'] = 0;
      b['jcmbillid'] = '';
    }

    final double sellPrice = _toDouble(b['sellprice']);
    final double cookaddamt = _toDouble(b['cookaddamt']);
    final double combaddamt = _toDouble(b['combaddamt']);
    final int presentflag = _toInt(b['presentflag']);
    // 退菜行数量恒为负（对齐 smdcapp ReturnDishesPopup：qty = -退菜数量），
    // 服务端回传正数时按负数还原，否则退菜金额会被按正价计入
    double qty = _toDouble(b['qty']);
    if (presentflag == 2 && qty > 0) {
      qty = -qty;
    }
    final int dscflag = _toInt(b['dscflag']);
    double discount = _toDouble(b['discount']);
    if (discount == 0) discount = 100;
    final int origSpec = _toInt(b['specpriceflag']);

    // specpriceflag → disType 映射（对齐 smdcapp getMemberPrice）
    int disType;
    if (origSpec == 0) {
      disType = 0;
    } else if (origSpec < 4 || origSpec == 7) {
      disType = 3;
    } else if (origSpec == 5) {
      disType = 5;
    } else if (origSpec == 4) {
      disType = 1;
    } else {
      disType = 0;
    }
    final int startDisType = disType;

    // 不可打折但存在手工折扣 → 恢复原价（对齐 smdcapp getMemberPrice）
    if (dscflag != 1 && discount > 0 && discount < 100) {
      b['disType'] = 0;
      b['discount'] = 100;
      b['rrprice'] = sellPrice;
    } else {
      // 基础现价：原价与服务器现单价取低，手工折扣优先
      double tempPrice = sellPrice;
      final double serverRr = _toDouble(b['rrprice']);
      if (serverRr == 0 && origSpec != 0) tempPrice = serverRr;
      if (serverRr > 0 && serverRr < tempPrice) tempPrice = serverRr;
      if (dscflag == 1 && discount > 0 && discount < 100) {
        tempPrice = _round2(sellPrice * discount / 100);
      }
      // 会员价计算（对齐 smdcapp：仅当会员价低于当前价时生效）
      if (prefetype != 0) {
        switch (prefetype) {
          case 1:
            final double md = memberDiscount;
            if (dscflag == 1 && md > 0 && md < 100) {
              final double p = _round2(sellPrice * md / 100);
              if (p < tempPrice) {
                tempPrice = p;
                b['discount'] = md;
                b['specpriceflag'] = 5;
                disType = 5;
              }
            }
            break;
          case 2:
          case 3:
          case 4:
            final double mp = _toDouble(b['mprice${prefetype - 1}']);
            if (mp != 0 && mp < tempPrice) {
              tempPrice = mp;
              b['specpriceflag'] = 5;
              disType = 5;
            }
            // 手工折扣更优时恢复原优惠类型
            if (discount > 0 && discount < 100) {
              final double p = _round2(sellPrice * discount / 100);
              if (p < tempPrice) {
                tempPrice = p;
                b['specpriceflag'] = origSpec;
                disType = startDisType;
              }
            }
            break;
        }
      }
      // 赠送商品现价为0（对齐 smdcapp）
      if (presentflag == 1) {
        disType = 2;
        b['rrprice'] = 0;
        tempPrice = 0;
      } else {
        b['rrprice'] = tempPrice;
      }
      b['disType'] = disType;
    }

    // ═══ 金额汇总（对齐 smdcapp getDownMemberPrice） ═══
    final double memberPrice = _toDouble(b['rrprice']);
    double tO = _round2(sellPrice * qty + combaddamt);
    double tR = _round2(memberPrice * qty + combaddamt);
    final int bxxpxxflag = _toInt(b['bxxpxxflag']);
    if (presentflag == 2) {
      // 退菜：赠送后退菜先归零，再退做法加价
      if (_toDouble(b['presentprice']) > 0) {
        tO = 0;
        tR = 0;
      }
      if (cookaddamt < 0) {
        tO = _round2(tO + cookaddamt);
        tR = _round2(tR + cookaddamt);
      } else {
        tO = _round2(tO - cookaddamt);
        tR = _round2(tR - cookaddamt);
      }
    } else if (presentflag == 1 ||
        bxxpxxflag == 1 ||
        bxxpxxflag == 2 ||
        bxxpxxflag == 6) {
      // 赠送：优惠金额为原价，现价仅含做法费
      tO = _round2(tO + cookaddamt);
      tR = cookaddamt;
      b['disType'] = 2;
    } else {
      tO = _round2(tO + cookaddamt);
      tR = _round2(tR + cookaddamt);
    }
    b['oldrramt'] = tO;
    b['rramt'] = tR;
  }
}
