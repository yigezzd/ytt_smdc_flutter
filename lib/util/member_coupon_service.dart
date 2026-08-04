import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/log_utils.dart';

/// 会员与优惠券服务（对齐 smdcapp SettleApi 会员/优惠券相关接口）
///
/// 提供：
/// - 优惠券撤销（unVerify）
/// - 团购券撤销（cancelPrepare）
/// - 优惠券支付核销（verify）
class MemberCouponService {
  MemberCouponService._();
  static final MemberCouponService instance = MemberCouponService._();

  /// 撤销已核销的优惠券（对齐 smdcapp SettleApi.unVerify）
  ///
  /// [vipid] 会员ID
  /// [billno] 单号
  /// 返回是否成功
  Future<bool> unVerifyCoupon({
    required String vipid,
    required String billno,
  }) async {
    try {
      await requestForm(HttpApi.vipUnVerify, <String, dynamic>{
        'vipid': vipid,
        'billno': billno,
      });
      // requestForm 失败时抛异常，到达此处即为成功
      return true;
    } catch (e) {
      Log.e('MemberCouponService.unVerifyCoupon error: $e');
      return false;
    }
  }

  /// 撤销已验的团购券（对齐 smdcapp SettleApi.cancelPrepare）
  ///
  /// [saleid] 销售单ID（t_sale_master.saleid）
  /// [businesstype] 核销类型：0=抖音, 1=美团, 3=快手
  /// [signinfo] 指定退的验券后返回的id，多张逗号分割（可选，为空则全退）
  /// 返回是否成功
  Future<bool> cancelPrepare({
    required String saleid,
    required String businesstype,
    String signinfo = '',
  }) async {
    try {
      await requestForm(HttpApi.douyinCancelPrepare, <String, dynamic>{
        'saleid': saleid,
        'businesstype': businesstype,
        'signinfo': signinfo,
      });
      // requestForm 失败时抛异常，到达此处即为成功
      return true;
    } catch (e) {
      Log.e('MemberCouponService.cancelPrepare error: $e');
      return false;
    }
  }

  /// 优惠券支付核销（对齐 smdcapp SettleApi.verifyPay）
  ///
  /// [vipid] 会员ID
  /// [master] 主单JSON
  /// [projectlist] 优惠券明细JSON
  /// [clienttype] 客户端类型
  /// [fav] 优惠券信息
  /// 返回是否成功
  Future<bool> verifyCouponPay({
    required String vipid,
    required String master,
    required String projectlist,
    String clienttype = '2',
    required String fav,
  }) async {
    try {
      await requestForm(HttpApi.vipVerify, <String, dynamic>{
        'vipid': vipid,
        'master': master,
        'projectlist': projectlist,
        'clienttype': clienttype,
        'fav': fav,
      });
      // requestForm 失败时抛异常，到达此处即为成功
      return true;
    } catch (e) {
      Log.e('MemberCouponService.verifyCouponPay error: $e');
      return false;
    }
  }

  /// 会员挂账（对齐 smdcapp SettleApi.vipoverPay）
  ///
  /// 返回是否成功
  Future<bool> vipOverPay({
    required String billno,
    required String billid,
    required String vipid,
    required String vipno,
    required String payid,
    required String payname,
    required String saleid,
    required String salename,
    required String amt,
  }) async {
    try {
      await requestForm(HttpApi.vipOverPay, <String, dynamic>{
        'billno': billno,
        'billid': billid,
        'vipid': vipid,
        'vipno': vipno,
        'payid': payid,
        'payname': payname,
        'saleid': saleid,
        'salename': salename,
        'amt': amt,
      });
      // requestForm 失败时抛异常，到达此处即为成功
      return true;
    } catch (e) {
      Log.e('MemberCouponService.vipOverPay error: $e');
      return false;
    }
  }
}
