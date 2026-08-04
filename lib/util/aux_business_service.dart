import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/log_utils.dart';

/// 辅助业务服务（聚客一卡通 / 预订报表 / 松鼠屋渠道）
///
/// 对齐 smdcapp SettleApi(jk-card) + YDApi(reserve/trade) + ChannelApi(ssw)
class AuxBusinessService {
  AuxBusinessService._();
  static final AuxBusinessService instance = AuxBusinessService._();

  // ──────────── 聚客一卡通（对齐 smdcapp SettleApi jk-card）─────────────────

  /// 聚客一卡通查询会员（对齐 smdcapp SettleApi.getJkCardVipInfo）
  ///
  /// [cond] 卡号/姓名/手机号
  /// 返回会员列表
  Future<List<Map<String, dynamic>>> getJkCardVipInfo(String cond) async {
    try {
      final resp = await requestForm(HttpApi.jkCardGetVipInfo, <String, dynamic>{
        'cond': cond,
      }, showError: false);
      // requestForm 失败时抛异常，到达此处即为成功
      if (resp['data'] is List) {
        return (resp['data'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      return [];
    } catch (e) {
      Log.e('AuxBusinessService.getJkCardVipInfo error: $e');
      return [];
    }
  }

  /// 聚客一卡通支付（对齐 smdcapp SettleApi.JkCardPay）
  ///
  /// 返回是否成功
  Future<bool> jkCardPay({
    required String vipid,
    required String vipno,
    required String payid,
    required String payname,
    required String saleid,
    required String salename,
    required String billno,
    required String payamt,
  }) async {
    try {
      final resp = await requestForm(HttpApi.jkCardPay, <String, dynamic>{
        'vipid': vipid,
        'vipno': vipno,
        'payid': payid,
        'payname': payname,
        'saleid': saleid,
        'salename': salename,
        'billno': billno,
        'payamt': payamt,
      });
      // requestForm 失败时抛异常，到达此处即为成功
      return true;
    } catch (e) {
      Log.e('AuxBusinessService.jkCardPay error: $e');
      return false;
    }
  }

  // ──────────── 预订报表/冲突检测（对齐 smdcapp YDApi）─────────────────

  /// 预订冲突检测（对齐 smdcapp YDApi.toTableAboutTime）
  ///
  /// [arrivaltime] 到店时间
  /// [tablelist] 预订桌台列表JSON
  /// [nobillid] 排除的预订单ID（编辑时排除自身）
  /// 返回冲突的预订列表
  Future<List<Map<String, dynamic>>> checkReserveConflict({
    required String arrivaltime,
    required String tablelist,
    String nobillid = '',
  }) async {
    try {
      final resp = await requestForm(HttpApi.reserveToTableAboutTime, <String, dynamic>{
        'arrivaltime': arrivaltime,
        'tablelist': tablelist,
        'nobillid': nobillid,
      }, showError: false);
      // requestForm 失败时抛异常，到达此处即为成功
      if (resp['data'] is List) {
        return (resp['data'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      return [];
    } catch (e) {
      Log.e('AuxBusinessService.checkReserveConflict error: $e');
      return [];
    }
  }

  /// 预订报表查询（对齐 smdcapp YDApi.getPredetermineList）
  ///
  /// 返回预订报表明细
  Future<Map<String, dynamic>> getPredetermineList({
    String status = '',
    String startdate = '',
    String enddate = '',
    String cond = '',
    int page = 1,
    int pagesize = 50,
  }) async {
    try {
      final resp = await requestForm(HttpApi.getPredetermineList, <String, dynamic>{
        'status': status,
        'startdate': startdate,
        'enddate': enddate,
        'cond': cond,
        'page': page.toString(),
        'pagesize': pagesize.toString(),
        'field': 'id',
        'type': 'desc',
      }, showError: false);
      // requestForm 失败时抛异常，到达此处即为成功
      if (resp['data'] is Map<String, dynamic>) {
        return resp['data'] as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      Log.e('AuxBusinessService.getPredetermineList error: $e');
      return {};
    }
  }

  // ──────────── 松鼠屋渠道（对齐 smdcapp ChannelApi）─────────────────

  /// 松鼠屋推单（对齐 smdcapp ChannelApi.sswOrderAdd）
  ///
  /// [saleid] 销售单ID
  /// [opertype] 操作类型
  /// [source] 来源（默认other）
  /// 返回推单结果
  Future<Map<String, dynamic>> sswOrderAdd({
    required String saleid,
    required String opertype,
    String source = 'other',
  }) async {
    try {
      final resp = await requestForm(HttpApi.sswOrderAdd, <String, dynamic>{
        'saleid': saleid,
        'opertype': opertype,
        'source': source,
      }, showError: false);
      // requestForm 失败时抛异常，到达此处即为成功
      if (resp['data'] is Map<String, dynamic>) {
        return resp['data'] as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      Log.e('AuxBusinessService.sswOrderAdd error: $e');
      return {};
    }
  }

  /// 获取松鼠屋页面URL（对齐 smdcapp ChannelApi.sswOrderUrl）
  ///
  /// [billno] 单号
  /// [module] 模块：orderDetail=订单详情, setting=我的页面设置
  /// 返回页面URL
  Future<String> sswOrderUrl({
    required String billno,
    required String module,
  }) async {
    try {
      final resp = await requestForm(HttpApi.sswOrderUrl, <String, dynamic>{
        'billno': billno,
        'module': module,
      }, showError: false);
      // requestForm 失败时抛异常，到达此处即为成功
      final dynamic data = resp['data'];
      if (data is Map<String, dynamic>) {
        return data['url']?.toString() ?? '';
      }
      return data?.toString() ?? '';
    } catch (e) {
      Log.e('AuxBusinessService.sswOrderUrl error: $e');
      return '';
    }
  }
}
