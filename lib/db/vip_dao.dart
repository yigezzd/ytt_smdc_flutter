import 'dart:convert';

import 'package:flutter_deer/res/constant.dart';
import 'package:intl/intl.dart';
import 'package:sp_util/sp_util.dart';

import 'app_database.dart';

/// 会员支付流水写入 DAO（对齐 YttPhone VipFlowDao + smdcapp vipInfoPay）
///
/// vip/pay 云端成功后双写本地 t_vip_flow（opertype=1 消费）；
/// [pay] 为 vipPay 请求参数（billno/vipid/vipno/payid/payname/saleid/salename/amt），
/// 操作人/门店/机号从登录缓存补齐（对齐 smdcapp saveFlowInDb）。
class VipDao {
  VipDao._();

  static final VipDao instance = VipDao._();

  final AppDatabase _db = AppDatabase.instance;

  /// 保存会员消费流水
  Future<void> saveVipFlow(Map<String, dynamic> pay) async {
    final Map<String, dynamic> row = Map<String, dynamic>.from(pay);
    // 金额映射：vipPay 请求 amt → t_vip_flow.salemoney
    row['salemoney'] = pay['amt'];
    row.remove('amt');
    row['opertype'] = 1; // 1=消费（对齐 smdcapp SaveVipFlowHandler）
    row['createtime'] =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    row['machno'] = SpUtil.getString(Constant.machNo) ?? '';

    // 操作人：优先取登录用户（对齐 smdcapp getLoginInfo）
    String operid = '';
    String opername = '';
    String spid = '0';
    String sid = '0';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        operid = userMap['userid']?.toString() ?? '';
        opername = userMap['username']?.toString() ?? '';
      }
    } catch (_) {}
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '0';
        spid = storeMap['spid']?.toString() ?? '0';
      }
    } catch (_) {}
    row['operid'] = operid;
    row['opername'] = opername;
    row['spid'] = spid;
    row['sid'] = sid;

    await _db.insert('t_vip_flow', row);
  }
}
