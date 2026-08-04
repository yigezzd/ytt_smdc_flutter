import 'dart:math';

import 'package:flutter_deer/util/params_sp_utils.dart';

/// 金额计算工具（对齐 smdcapp EraseAmountUtils + GetServiceAmountUtils + Arith）
///
/// 提供：
/// - 抹零计算（9种方式，对齐 SmallChangeFlag）
/// - 低消差计算（对齐 GetServiceAmountUtils.getMinSalemoney）
/// - 服务费计算（对齐 GetServiceAmountUtils 核心逻辑）
/// - 精确四则运算（对齐 Arith BigDecimal）
class AmountCalcUtils {
  AmountCalcUtils._();

  // ──────────── 精确四则运算（对齐 smdcapp Arith）─────────────────

  /// 加法（保留2位小数，四舍五入）
  static double add(double a, double b) {
    return _round2(a + b);
  }

  /// 减法（保留2位小数）
  static double sub(double a, double b) {
    return _round2(a - b);
  }

  /// 乘法（保留2位小数）
  static double mul(double a, double b) {
    return _round2(a * b);
  }

  /// 除法（保留2位小数）
  static double div(double a, double b) {
    if (b == 0) return 0;
    return _round2(a / b);
  }

  /// 保留2位小数（四舍五入）
  static double _round2(double v) {
    return (v * 100).roundToDouble() / 100;
  }

  // ──────────── 抹零计算（对齐 smdcapp EraseAmountUtils + SmallChangeFlag）─────────────────

  /// 抹零方式枚举（对齐 smdcapp SmallChangeFlag）：
  /// 1=四舍五入到角, 2=四舍五入到元, 3=四舍五入到十元,
  /// 4=去分, 5=去角, 6=抹零到五角, 7=四舍五入到五角, 8=进角, 9=进元
  ///
  /// [amount] 应收金额
  /// 返回抹零后的金额
  static double eraseAmount(double amount, {String? flag}) {
    final String smallChangeFlag = flag ?? ParamsSpUtils.getSmallChangeFlag();
    if (smallChangeFlag.isEmpty) return amount;

    switch (smallChangeFlag) {
      case '1': // 四舍五入到角
        return _roundToJiao(amount);
      case '2': // 四舍五入到元
        return amount.roundToDouble();
      case '3': // 四舍五入到十元
        return _roundToShiYuan(amount);
      case '4': // 去分
        return _truncateToJiao(amount);
      case '5': // 去角
        return amount.truncateToDouble();
      case '6': // 抹零到五角
        return _eraseToWuJiao(amount);
      case '7': // 四舍五入到五角
        return _roundToWuJiao(amount);
      case '8': // 进角（向上取整到角）
        return _ceilToJiao(amount);
      case '9': // 进元（向上取整到元）
        return amount.ceilToDouble();
      default:
        return amount;
    }
  }

  /// 四舍五入到角
  static double _roundToJiao(double v) {
    return (v * 10).roundToDouble() / 10;
  }

  /// 去分（截断到角）
  static double _truncateToJiao(double v) {
    return (v * 10).truncateToDouble() / 10;
  }

  /// 四舍五入到十元
  static double _roundToShiYuan(double v) {
    final double digits = v % 10;
    if (digits >= 5) {
      return ((v / 10).floor() + 1) * 10.0;
    }
    return (v / 10).floor() * 10.0;
  }

  /// 抹零到五角（去掉小于5角的分）
  static double _eraseToWuJiao(double v) {
    final int yuan = v.floor();
    final double jiao = (v - yuan) * 10;
    if (jiao >= 5) {
      return yuan + 0.5;
    }
    return yuan.toDouble();
  }

  /// 四舍五入到五角
  static double _roundToWuJiao(double v) {
    final int yuan = v.floor();
    final double jiao = (v - yuan) * 10;
    if (jiao >= 7.5) {
      return yuan + 1.0;
    } else if (jiao >= 2.5) {
      return yuan + 0.5;
    }
    return yuan.toDouble();
  }

  /// 向上取整到角
  static double _ceilToJiao(double v) {
    return (v * 10).ceilToDouble() / 10;
  }

  /// 计算抹零金额（应收 - 抹零后）
  static double getEraseAmt(double amount, {String? flag}) {
    final double erased = eraseAmount(amount, flag: flag);
    return sub(amount, erased);
  }

  // ──────────── 低消差计算（对齐 smdcapp GetServiceAmountUtils.getMinSalemoney）─────────────────

  /// 计算低消标准金额（对齐 smdcapp calcLowMoney）
  ///
  /// [lowtype] 低消方式：0=不收费, 1=餐桌低消, 2=人均低消
  /// [lowamt] 低消标准单价
  /// [personnum] 人数
  static double calcLowMoney({
    required int lowtype,
    required double lowamt,
    int personnum = 1,
  }) {
    switch (lowtype) {
      case 1: // 餐桌低消
        return lowamt;
      case 2: // 人均低消
        return mul(lowamt, personnum.toDouble());
      default:
        return 0.0;
    }
  }

  /// 计算低消差（对齐 smdcapp getMinSalemoneyTab）
  ///
  /// [lowtype] 低消方式：0=不收费, 1=餐桌低消, 2=人均低消
  /// [lowamt] 低消标准单价
  /// [personnum] 人数
  /// [totalmoney] 当前商品总金额（计入低消的商品）
  /// [servicemoney] 服务费金额
  /// [minsalesamtflag] 服务费是否计入低消：0=不包含, 1=包含
  /// 返回需要补齐的低消差金额（0表示已达低消）
  static double getMinSalemoneyDiff({
    required int lowtype,
    required double lowamt,
    int personnum = 1,
    required double totalmoney,
    double servicemoney = 0,
    int minsalesamtflag = 0,
  }) {
    // 低消标准金额
    final double minsalesamt = calcLowMoney(
      lowtype: lowtype,
      lowamt: lowamt,
      personnum: personnum,
    );
    if (minsalesamt == 0.0) return 0.0;

    // 服务费是否计入低消
    if (minsalesamtflag == 1) {
      final double temptotal = add(totalmoney, servicemoney);
      if (temptotal < minsalesamt) {
        return sub(minsalesamt, temptotal);
      }
      return 0.0;
    } else {
      if (totalmoney < minsalesamt) {
        return sub(minsalesamt, totalmoney);
      }
      return 0.0;
    }
  }

  // ──────────── 服务费计算（对齐 smdcapp GetServiceAmountUtils 核心逻辑）─────────────────

  /// 服务费计费配置（对齐 smdcapp TableType 服务费字段）
  ///
  /// [startamt] 起步金额
  /// [starthour] 起步时长（小时或分钟，取决于 starthourtype）
  /// [starthourtype] 起步类型：1=小时, 2=分钟
  /// [overhour] 超时单位（小时或分钟）
  /// [overhourtype] 超时类型：1=分钟, 2=小时
  /// [overamt] 超时单价
  /// [maxhour] 封顶时长（0=不封顶）
  /// [maxhourtype] 封顶类型：1=小时, 2=分钟
  /// [freemin] 免费分钟数
  /// [automaticflag] 自动开始标志：0=手动, 1=自动
  static double calcServiceFee({
    required double startamt,
    required double starthour,
    required int starthourtype,
    required double overhour,
    required int overhourtype,
    required double overamt,
    double maxhour = 0,
    int maxhourtype = 1,
    double freemin = 0,
    required DateTime beginTime,
    DateTime? endTime,
  }) {
    final DateTime end = endTime ?? DateTime.now();
    final Duration interval = end.difference(beginTime);
    final int totalMinutes = interval.inMinutes;

    // 免费时间内不收费
    if (freemin > 0 && totalMinutes <= freemin) return 0.0;
    // 未设置起步时长不收费
    if (starthour <= 0) return 0.0;

    double amt = startamt;

    if (starthourtype == 1) {
      // ── 小时起步 ──
      final int hours = interval.inHours;
      final int remainMinutes = totalMinutes % 60;

      if (hours <= starthour) {
        // 未超起步时长，直接返回起步价
        amt = startamt;
      } else {
        // 超过起步时长
        double overUnits = (hours - starthour).toDouble();

        // 封顶判断
        if (maxhour > 0 && maxhourtype == 1 && hours >= maxhour) {
          overUnits = maxhour - starthour;
        }

        // 计算超时费用
        final double overUnitAmt = overhourtype == 1
            ? overamt / (overhour * 60)  // 分钟单价
            : overamt / overhour;         // 小时单价
        final double overCount = overhourtype == 1
            ? (overUnits * 60 / overhour).floorToDouble()
            : (overUnits / overhour).floorToDouble();
        amt = add(amt, mul(overCount, overamt > 0 ? overamt : overUnitAmt * overhour));
      }
    } else {
      // ── 分钟起步 ──
      if (totalMinutes <= starthour) {
        amt = startamt;
      } else {
        double overMinutes = (totalMinutes - starthour).toDouble();

        // 封顶判断
        if (maxhour > 0 && maxhourtype == 2 && totalMinutes >= maxhour) {
          overMinutes = maxhour - starthour;
        }

        final double overCount = (overMinutes / overhour).floorToDouble();
        amt = add(amt, mul(overCount, overamt));
      }
    }

    return amt;
  }

  // ──────────── 折扣计算 ─────────────────────────────────────────

  /// 计算折扣后价格（对齐 smdcapp 折扣逻辑）
  ///
  /// [price] 原价
  /// [discount] 折扣率（如 85 表示 8.5折，即 85%）
  static double calcDiscountPrice(double price, double discount) {
    if (discount <= 0 || discount >= 100) return price;
    return mul(price, discount / 100);
  }

  /// 计算折扣金额
  static double calcDiscountAmt(double price, double discount) {
    return sub(price, calcDiscountPrice(price, discount));
  }

  /// 格式化金额显示（保留2位小数）
  static String formatAmount(double amount) {
    return amount.toStringAsFixed(2);
  }
}
