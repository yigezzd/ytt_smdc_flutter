import 'dart:convert';

import 'package:sp_util/sp_util.dart';

/// 系统参数工具类 —— 对齐 smdcapp ParamsSpUtils / SpUtils.saveParamsData
///
/// 登录接口返回的 params 数组（每项含 code/value），smdcapp 在 LoginModel.handleResponse 中：
/// 1. 先将上一次保存的旧参数 code 全部置空（避免旧参数残留）
/// 2. 将新 params 列表 JSON 存入 "app_params"
/// 3. 将每个 param 的 code → value 逐项存入本地存储
/// 后续业务直接通过 code 读取对应 value（如 OverStockPerSale、SmallChangeType 等）
class ParamsSpUtils {
  ParamsSpUtils._();

  /// 存储 key：params 列表完整 JSON（对齐 smdcapp MMKV "app_params"）
  static const String _appParamsKey = 'app_params';

  // ──────────── 参数保存（登录成功后调用）────────────

  /// 保存登录返回的 params 数组（对齐 smdcapp LoginModel.handleResponse params 处理）
  ///
  /// [params] 为登录响应 data.params，每项结构 {code, type, spid, value, sid, ...}
  static void saveParams(List<dynamic> params) {
    // 1. 清除旧参数：将上次保存的每个 code 置空（对齐 smdcapp: parseJsonToList → forEach put(code, "")）
    final String oldJson = SpUtil.getString(_appParamsKey) ?? '';
    if (oldJson.isNotEmpty) {
      try {
        final List<dynamic> oldList = json.decode(oldJson) as List<dynamic>;
        for (final item in oldList) {
          if (item is Map) {
            final String code = item['code']?.toString() ?? '';
            if (code.isNotEmpty) {
              SpUtil.putString(code, '');
            }
          }
        }
      } catch (_) {}
    }

    // 2. 保存新 params 完整 JSON（对齐 smdcapp: SpUtils.put("app_params", Gson().toJson(p))）
    SpUtil.putString(_appParamsKey, json.encode(params));

    // 3. 逐项存储 code → value（对齐 smdcapp: p.forEach { SpUtils.put(it.code, it.value) }）
    for (final item in params) {
      if (item is Map) {
        final String code = item['code']?.toString() ?? '';
        final String value = item['value']?.toString() ?? '';
        if (code.isNotEmpty) {
          SpUtil.putString(code, value);
        }
      }
    }
  }

  // ──────────── 通用读取 ─────────────────────────────────────────

  /// 通用参数读取：通过 code 获取 value
  static String getParam(String code, {String defValue = ''}) {
    final String? v = SpUtil.getString(code);
    return (v == null || v.isEmpty) ? defValue : v;
  }

  // ──────────── 已知参数 code 的便捷读取（对齐 smdcapp 各 SpUtils 方法）────────────

  /// 负库存是否允许销售（对齐 smdcapp ParamsSpUtils.getOverStockPerSale）
  /// 1 允许不提示、2 允许提示、3 不允许提示
  static String getOverStockPerSale() => getParam('OverStockPerSale', defValue: '1');

  /// 会员扣款校验方式（对齐 smdcapp SpUtils.getVipPayAuthType）：1按密码 2按短信
  static String getVipPayAuthType() => getParam('VipPayAuthType');

  /// 未关联私有做法点菜弹出做法选择（对齐 smdcapp SpUtils.notCookSelectCook）
  static bool notCookSelectCook() => getParam('NotSelectCookieFlag', defValue: '1') == '1';

  /// 抹零设置（对齐 smdcapp SpUtils.getSmallChangeType）：0不抹零 1币种抹零 2单品抹零
  static String getSmallChangeType() => getParam('SmallChangeType', defValue: '0');

  /// 抹零方式（对齐 smdcapp SpUtils.getSmallChangeFlag）：
  /// 1四舍五入到角 2四舍五入到元 3四舍五入到十元 4去分 5去角 6抹零到五角 7四舍五入到五角 8进角 9进元
  static String getSmallChangeFlag() => getParam('SmallChangeFlag');

  /// 是否二次称重确认（对齐 smdcapp SpUtils.isReweigh）
  static bool isReweigh() => getParam('WeightTwoConfirm', defValue: '0') == '1';

  /// 开台费标志（对齐 smdcapp SpUtils.getOpenTableAmtFlag）
  static String getOpenTableAmtFlag() => getParam('OpenTableAmtFlag', defValue: '0');

  /// 是否显示已退完菜（对齐 smdcapp SpUtils.isShowReturnProduct）
  static bool isShowReturnProduct() => getParam('ShowReturnProduct', defValue: '1') == '1';

  /// 挂单是否允许销售（对齐 smdcapp SpUtils.isPendingProSaleFlag）：0不允许 2允许不提示
  static String isPendingProSaleFlag() => getParam('PendingProSaleFlag', defValue: '0');

  /// 服务员标记方式（对齐 smdcapp SpUtils.getMarkServerFlag）：0/1 普通 2一菜一位
  static String getMarkServerFlag() => getParam('MarkServerFlag', defValue: '0');

  /// 是否合并打印（对齐 smdcapp ParamSpUtils.isMergePrint: PrnUnionSame）
  static bool isMergePrint() => getParam('PrnUnionSame', defValue: '0') == '1';

  /// 叫号取餐开关（对齐 smdcapp SpUtils.getPickupCallSwitch: PickupCallSwitch）1开 0关
  static bool getPickupCallSwitch() => getParam('PickupCallSwitch', defValue: '0') == '1';

  /// 支持的订单类型（对齐 smdcapp SpUtils.getSupportOrderTypes: SupportOrderTypes）1=线下
  static String getSupportOrderTypes() => getParam('SupportOrderTypes', defValue: '0');
}
