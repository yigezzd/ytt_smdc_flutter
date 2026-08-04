import 'dart:math';

import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 门店商业模式工具类（对齐 smdcapp SpUtils storemodel3 / BillUtils.getSaleId）
///
/// 商业模式：1=快餐  2=正餐（正餐可以切换成快餐）
class StoreModeUtils {
  StoreModeUtils._();

  /// 快餐模式（对齐 smdcapp SpUtils.STORE_MODEL_TYPE_1）
  static const int storeModelFast = 1;

  /// 正餐模式（对齐 smdcapp SpUtils.STORE_MODEL_TYPE_2）
  static const int storeModelNormal = 2;

  /// 保存当前商业模式（对齐 smdcapp SpUtils.putStoremodel3）
  static void putCurrentStoreModel(int storeModel) {
    SpUtil.putInt(Constant.storeMode, storeModel);
  }

  /// 获取当前商业模式（对齐 smdcapp SpUtils.getCurrentStoremodel，默认正餐）
  static int getCurrentStoreModel() {
    return SpUtil.getInt(Constant.storeMode) ?? storeModelNormal;
  }

  /// 是否快餐模式
  static bool isFastMode() => getCurrentStoreModel() == storeModelFast;

  /// 生成销售单id（对齐 smdcapp BillUtils.getSaleId：yyMMdd + machNo + millis%1000 + random6）
  static String generateSaleId() {
    final DateTime now = DateTime.now();
    final String yyMMdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final String machNo = SpUtil.getString(Constant.machNo) ?? '';
    final String millis =
        (DateTime.now().millisecondsSinceEpoch % 1000).toString();
    return '$yyMMdd$machNo$millis${_randomString(6)}';
  }

  /// 随机生成字符串（对齐 smdcapp BillUtils.getRandomString）
  static String _randomString(int length) {
    const String chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random random = Random();
    return String.fromCharCodes(Iterable<int>.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(62))));
  }
}
