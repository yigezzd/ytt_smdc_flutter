import 'package:flutter/material.dart';
import 'package:flutter_deer/components/auth_permission_dialog.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 免密额度（角色折扣/赠送上限）校验（对齐 smdcapp DiscountLimitValidator）
///
/// 登录响应 role 中的 monthdiscountamt / prodiscount / orderdiscount / progiveamt
/// 为 0 表示不限制；超过额度需要经理授权（AuthPermissionDialog）。
class AuthLimitUtils {
  AuthLimitUtils._();

  /// 单品打折单次上限（100=不打折）
  static double get singleDiscountLimit =>
      SpUtil.getDouble(Constant.proDiscount) ?? 0;

  /// 整单打折单次上限
  static double get orderDiscountLimit =>
      SpUtil.getDouble(Constant.orderDiscount) ?? 0;

  /// 菜品单次赠送金额上限
  static double get giftAmtLimit => SpUtil.getDouble(Constant.proGiveAmt) ?? 0;

  /// 单品折扣是否超出免密额度
  static bool exceedSingleDiscount(double discount) {
    final double limit = singleDiscountLimit;
    return limit > 0 && discount < limit;
  }

  /// 整单折扣是否超出免密额度
  static bool exceedOrderDiscount(double discount) {
    final double limit = orderDiscountLimit;
    return limit > 0 && discount < limit;
  }

  /// 赠送金额是否超出免密额度
  static bool exceedGiftAmt(double amt) {
    final double limit = giftAmtLimit;
    return limit > 0 && amt > limit;
  }

  /// 单品折扣授权；返回 true 表示可执行
  static Future<bool> ensureSingleDiscount(
    BuildContext context, {
    required String dishName,
    required double discount,
  }) async {
    if (!exceedSingleDiscount(discount)) return true;
    if (!PermissionUtils.checkPermission(PermissionUtils.appDishDiscount,
        showTip: false)) {
      PermissionUtils.check(PermissionUtils.appDishDiscount, '打折');
      return false;
    }
    return AuthPermissionDialog.show(
      context,
      title: '单品打折：$dishName',
      codeid: PermissionUtils.appDishDiscount,
    );
  }

  /// 整单折扣授权；返回 true 表示可执行
  static Future<bool> ensureOrderDiscount(
    BuildContext context, {
    required double discount,
  }) async {
    if (!exceedOrderDiscount(discount)) return true;
    if (!PermissionUtils.checkPermission(PermissionUtils.appTotalDiscount,
        showTip: false)) {
      PermissionUtils.check(PermissionUtils.appTotalDiscount, '整单折扣');
      return false;
    }
    return AuthPermissionDialog.show(
      context,
      title: '整单打折',
      codeid: PermissionUtils.appTotalDiscount,
    );
  }

  /// 赠送金额授权；返回 true 表示可执行
  static Future<bool> ensureGiftAmt(
    BuildContext context, {
    required String dishName,
    required double amt,
  }) async {
    if (!exceedGiftAmt(amt)) return true;
    if (!PermissionUtils.checkPermission(PermissionUtils.appGive,
        showTip: false)) {
      PermissionUtils.check(PermissionUtils.appGive, '赠送');
      return false;
    }
    return AuthPermissionDialog.show(
      context,
      title: '赠送：$dishName',
      codeid: PermissionUtils.appGive,
    );
  }
}
