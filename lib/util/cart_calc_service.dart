import 'package:flutter_deer/util/amount_calc_utils.dart';

/// 购物车商品项（对齐 smdcapp ProductBean 核心计算字段）
///
/// 用于购物车金额计算的商品数据模型。
class CartItem {
  CartItem({
    required this.productid,
    required this.name,
    required this.sellprice,
    this.qty = 1,
    this.mprice1 = 0,
    this.weighflag = 0,
    this.weighNum = 0,
    this.isGive = false,
    this.zsNum = 0,
    this.presentflag = 0,
    this.isChangePrice = false,
    this.cPrice = 0,
    this.cookaddamt = 0,
    this.specaddamt = 0,
    this.combflag = 0,
    this.combaddamt = 0,
    this.dscflag = 1,
    this.discount = 100,
    this.minsaleflag = 1,
    this.onlyid = '',
  });

  final String productid;
  final String name;

  /// 售价（单价）
  final double sellprice;

  /// 数量
  double qty;

  /// 会员价
  final double mprice1;

  /// 称重标志：1=称重菜
  final int weighflag;

  /// 称重数量（重量）
  double weighNum;

  /// 是否赠送
  bool isGive;

  /// 赠送数量
  double zsNum;

  /// 可赠送标志：1=可赠送
  final int presentflag;

  /// 是否改价
  bool isChangePrice;

  /// 改价后的单价
  double cPrice;

  /// 做法加价（总额）
  double cookaddamt;

  /// 规格加价（总额）
  double specaddamt;

  /// 套餐标志：1=套餐
  final int combflag;

  /// 套餐子商品加价（总额）
  double combaddamt;

  /// 折扣标志：1=可打折
  final int dscflag;

  /// 折扣率（100=不打折，85=8.5折）
  double discount;

  /// 计入低消标志：1=计入
  final int minsaleflag;

  /// 唯一标识
  String onlyid;

  /// 实际计价数量（对齐 smdcapp 称重取weighNum、赠送取zsNum）
  double get effectiveQty {
    if (weighflag == 1) return weighNum;
    if (isGive && presentflag == 1) return zsNum;
    return qty;
  }
}

/// 购物车计算服务（对齐 smdcapp ShoppingCartUtil 核心计算逻辑）
///
/// 提供：
/// - 单商品金额计算（对齐 getProductPrice）
/// - 购物车总金额计算
/// - 会员价应用（对齐 getDownMemberPrice）
/// - 赠送/改价/称重商品处理
class CartCalcService {
  CartCalcService._();

  /// 计算单个商品的应收金额（对齐 smdcapp getProductPrice doubles[0]）
  ///
  /// 返回 [售价金额, 会员价金额, 原价金额]
  ///
  /// 计算规则（对齐 smdcapp）：
  /// - 赠送商品（isGive && presentflag==1）：售价=0，原价=单价*赠送数
  /// - 改价商品（isChangePrice && cPrice>0）：售价=改价*数量
  /// - 称重商品（weighflag==1）：售价=单价*重量
  /// - 普通商品：售价=单价*数量
  /// - 做法/规格/套餐加价单独累加
  static List<double> calcProductPrice(CartItem item) {
    double saleAmt = 0.0;   // 售价金额（应收）
    double memberAmt = 0.0; // 会员价金额
    double originAmt = 0.0; // 原价金额

    final double qty = item.effectiveQty;
    final double price = item.sellprice;

    if (item.isGive && item.presentflag == 1) {
      // ── 赠送商品：售价为0，原价记录（对齐 smdcapp isGive 分支）──
      saleAmt = 0.0;
      memberAmt = 0.0;
      originAmt = AmountCalcUtils.mul(price, qty);
    } else if (item.isChangePrice && item.cPrice > 0) {
      // ── 改价商品（对齐 smdcapp isChangePrice 分支）──
      saleAmt = AmountCalcUtils.mul(item.cPrice, qty);
      memberAmt = AmountCalcUtils.mul(item.mprice1, qty);
      originAmt = saleAmt;
    } else {
      // ── 普通/称重商品 ──
      saleAmt = AmountCalcUtils.mul(price, qty);
      memberAmt = AmountCalcUtils.mul(item.mprice1, qty);
      originAmt = AmountCalcUtils.mul(price, qty);
    }

    // 应用折扣（对齐 smdcapp 折扣逻辑，仅可打折商品）
    if (item.dscflag == 1 && item.discount > 0 && item.discount < 100 && !item.isGive) {
      saleAmt = AmountCalcUtils.calcDiscountPrice(saleAmt, item.discount);
    }

    // 累加做法/规格/套餐加价（对齐 smdcapp cookaddamt/specaddamt/combaddamt）
    if (!item.isGive) {
      saleAmt = AmountCalcUtils.add(saleAmt, item.cookaddamt);
      saleAmt = AmountCalcUtils.add(saleAmt, item.specaddamt);
      saleAmt = AmountCalcUtils.add(saleAmt, item.combaddamt);
      originAmt = AmountCalcUtils.add(originAmt, item.cookaddamt);
      originAmt = AmountCalcUtils.add(originAmt, item.specaddamt);
      originAmt = AmountCalcUtils.add(originAmt, item.combaddamt);
    }

    return [saleAmt, memberAmt, originAmt];
  }

  /// 计算单个商品的应收金额（便捷方法）
  static double calcItemAmt(CartItem item) {
    return calcProductPrice(item)[0];
  }

  /// 计算购物车总金额（对齐 smdcapp 购物车总价计算）
  ///
  /// 返回 [总售价, 总会员价, 总原价]
  static List<double> calcCartTotal(List<CartItem> items) {
    double totalSale = 0.0;
    double totalMember = 0.0;
    double totalOrigin = 0.0;

    for (final CartItem item in items) {
      final List<double> prices = calcProductPrice(item);
      totalSale = AmountCalcUtils.add(totalSale, prices[0]);
      totalMember = AmountCalcUtils.add(totalMember, prices[1]);
      totalOrigin = AmountCalcUtils.add(totalOrigin, prices[2]);
    }

    return [totalSale, totalMember, totalOrigin];
  }

  /// 计算购物车总数量（对齐 smdcapp getCartNum）
  ///
  /// 赠送商品不计入数量统计
  static double calcCartQty(List<CartItem> items) {
    double totalQty = 0.0;
    for (final CartItem item in items) {
      if (item.isGive && item.presentflag == 1) continue;
      totalQty = AmountCalcUtils.add(totalQty, item.qty);
    }
    return totalQty;
  }

  /// 计算计入低消的商品总额（对齐 smdcapp getMinSalemoney 中的 totalmoney 计算）
  ///
  /// 排除：赠送商品(presentflag==2)、数量为0、不计低消(minsaleflag==0)、套餐子商品
  static double calcMinSaleAmt(List<CartItem> items) {
    double total = 0.0;
    for (final CartItem item in items) {
      // 赠送商品不计入低消
      if (item.isGive && item.presentflag == 1) continue;
      // 数量为0不计入
      if (item.effectiveQty <= 0) continue;
      // 不计低消标志
      if (item.minsaleflag == 0) continue;
      total = AmountCalcUtils.add(total, calcItemAmt(item));
    }
    return total;
  }

  /// 应用会员价（对齐 smdcapp getDownMemberPrice）
  ///
  /// 根据会员类型返回对应的会员价：
  /// - mprice1: 会员价1
  /// - mprice2: 会员价2
  /// - mprice3: 会员价3
  ///
  /// [memberPriceLevel] 会员价格等级：1/2/3
  /// 返回应用会员价后的单价
  static double applyMemberPrice(CartItem item, double memberPrice, int memberPriceLevel) {
    // 赠送/改价商品不应用会员价
    if (item.isGive || item.isChangePrice) return item.sellprice;
    // 会员价为0或大于等于售价时不应用
    if (memberPrice <= 0 || memberPrice >= item.sellprice) return item.sellprice;
    return memberPrice;
  }

  /// 根据会员优惠类型解析会员单价（对齐 smdcapp ShoppingCartUtil.getDownMemberPrice）
  ///
  /// [prefetype] 会员优惠类型（对齐 smdcapp VipInfo.prefetype）：
  ///   0=无优惠, 1=零售价折扣, 2=会员价1, 3=会员价2, 4=会员价3
  /// [sellprice] 商品售价
  /// [discount] 会员折扣率（prefetype=1 时使用，如 90 表示 9折）
  /// [mprice1]/[mprice2]/[mprice3] 会员价1/2/3
  /// 返回解析后的会员单价（无优惠时返回 sellprice）
  static double resolveMemberPrice({
    required int prefetype,
    required double sellprice,
    int discount = 100,
    double mprice1 = 0,
    double mprice2 = 0,
    double mprice3 = 0,
  }) {
    switch (prefetype) {
      case 1: // 零售价折扣
        if (discount <= 0 || discount >= 100) return sellprice;
        return AmountCalcUtils.mul(sellprice, discount / 100);
      case 2: // 会员价1
        return (mprice1 > 0 && mprice1 < sellprice) ? mprice1 : sellprice;
      case 3: // 会员价2
        return (mprice2 > 0 && mprice2 < sellprice) ? mprice2 : sellprice;
      case 4: // 会员价3
        return (mprice3 > 0 && mprice3 < sellprice) ? mprice3 : sellprice;
      default: // 0=无优惠
        return sellprice;
    }
  }

  /// 计算折扣金额（对齐 smdcapp 折扣计算）
  ///
  /// [amt] 原金额
  /// [discount] 折扣率（如 85 表示 8.5折）
  /// 返回折扣后的金额
  static double applyDiscount(double amt, double discount) {
    return AmountCalcUtils.calcDiscountPrice(amt, discount);
  }

  /// 计算整单折扣后的金额
  ///
  /// [items] 购物车商品列表
  /// [discount] 整单折扣率（如 90 表示 9折）
  /// 返回 [折扣后总额, 折扣金额]
  static List<double> calcOrderDiscount(List<CartItem> items, double discount) {
    final double totalAmt = calcCartTotal(items)[0];
    final double discountedAmt = AmountCalcUtils.calcDiscountPrice(totalAmt, discount);
    final double discountAmt = AmountCalcUtils.sub(totalAmt, discountedAmt);
    return [discountedAmt, discountAmt];
  }
}
