import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// 支付结果（对齐 smdcapp ShowScanPayCodeListener.returnBack）
class ScanPayResult {
  const ScanPayResult({
    required this.success,
    required this.trade,
    required this.payid,
    required this.billNo,
    this.errorMsg = '',
  });

  /// 是否支付成功
  final bool success;

  /// 第三方交易号（优支付: leshua_order_id,third_order_id；收钱吧: sn/trade_no）
  final String trade;

  /// 支付方式ID（08=支付宝 09=微信 10=云闪付）
  final String payid;

  /// 销售单号
  final String billNo;

  /// 错误信息
  final String errorMsg;
}

/// 移动支付网关服务（对齐 smdcapp 收钱吧HttpProxy + 优支付BoYouPay）
///
/// 根据门店 paytype 配置选择支付平台：
/// - paytype=1 → 收钱吧（https://api.shouqianba.com）
/// - paytype=4 → 优支付（http://pay.bypos.net/pay-gateway）
class PayGateway {
  PayGateway({
    required this.terminalsn,
    required this.terminalkey,
    required this.payType,
    this.shopId = '',
    this.operator = '',
  });

  /// 商户号/终端号（对齐 smdcapp ConstantKey.TERMINALSN）
  final String terminalsn;

  /// 密钥（对齐 smdcapp ConstantKey.TERMINALKEY）
  final String terminalkey;

  /// 支付平台类型（对齐 smdcapp NetHelpUtils.payType: 1=收钱吧 2=乐刷 4=优支付）
  final String payType;

  /// 门店shopid（对齐 smdcapp SpUtils.getSHOP_ID）
  final String shopId;

  /// 操作员（对齐 smdcapp SpUtils.getGetEmployeeName）
  final String operator;

  /// 收钱吧域名（对齐 smdcapp Net.API_DOMAIN）
  static const String _sqbDomain = 'https://api.shouqianba.com';

  /// 优支付域名（对齐 smdcapp BoYouPay.is_url_new）
  static const String _boyouDomain = 'http://pay.bypos.net/pay-gateway';

  /// 优支付通知地址（对齐 smdcapp BoYouPay.notify_url）
  static const String _boyouNotifyUrl = 'http://pay.bypos.net/notify.do';

  /// 支付网关专用 Dio 实例（独立于项目公共Dio，避免Auth/Token拦截器干扰，
  /// 对齐 smdcapp BoYouPay 使用独立 HttpURLConnection、HttpProxy 使用独立 HttpClient）
  static final Dio _payDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 5),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
  ));

  // ═══════════════════ 统一支付入口 ═══════════════════

  /// 付款码支付（对齐 smdcapp ReceiveMoneyPayDialog.pay / BoYouPayDialog.PayLeCode）
  ///
  /// [payid] 支付方式：08=支付宝 09=微信
  /// [billNo] 商户订单号（已含后缀）
  /// [amtFen] 金额（分）
  /// [authCode] 客户付款码
  /// 返回 true 表示支付直接成功（无需轮询），false 表示需要轮询查询
  Future<bool> pay({
    required String payid,
    required String billNo,
    required int amtFen,
    required String authCode,
  }) async {
    if (payType == '1') {
      return _sqbPay(payid: payid, billNo: billNo, amtFen: amtFen, authCode: authCode);
    }
    if (payType == '2') {
      return leshuaPay(payid: payid, billNo: billNo, amtFen: amtFen, authCode: authCode);
    }
    // 默认走优支付（payType=4 及其他）
    return _boyouPay(payid: payid, billNo: billNo, amtFen: amtFen, authCode: authCode);
  }

  /// 查询支付状态（对齐 smdcapp queryLeshua / hp.queryV3）
  ///
  /// 返回 ScanPayResult：
  /// - success=true → 支付成功（trade 为交易号）
  /// - success=false 且 trade 非空 → 确定失败
  /// - trade 为空且 success=false → 非终态，继续轮询
  Future<ScanPayResult> queryStatus({
    required String billNo,
    required String payid,
  }) async {
    if (payType == '1') {
      return _sqbQuery(billNo: billNo, payid: payid);
    }
    if (payType == '2') {
      return leshuaQuery(billNo: billNo, payid: payid);
    }
    return _boyouQuery(billNo: billNo, payid: payid);
  }

  /// 关闭订单（对齐 smdcapp closeTrade / boYouPay.closeOrdersLoad）
  Future<void> closeOrder(String billNo) async {
    if (payType == '1') {
      return; // 收钱吧不需要主动关闭（对齐 smdcapp 注释掉的 cancel 调用）
    }
    await _boyouClose(billNo);
  }

  // ═══════════════════ 收钱吧（payType=1）═══════════════════

  /// 收钱吧付款码支付（对齐 smdcapp HttpProxy.pay）
  /// payway: 1=支付宝 3=微信（对齐 smdcapp flag.equals("08")?"1":"3"）
  Future<bool> _sqbPay({
    required String payid,
    required String billNo,
    required int amtFen,
    required String authCode,
  }) async {
    final String payway = payid == '08' ? '1' : '3';
    final Map<String, dynamic> params = <String, dynamic>{
      'terminal_sn': terminalsn,
      'client_sn': billNo,
      'total_amount': amtFen.toString(),
      'payway': payway,
      'dynamic_id': authCode,
      'subject': '结算',
      'operator': operator,
    };
    final String body = jsonEncode(params);
    final String sign = _md5(body + terminalkey);

    final Response<String> response = await _payDio.post<String>(
      '$_sqbDomain/upay/v2/pay',
      data: body,
      options: Options(
        contentType: 'application/json',
        headers: <String, dynamic>{
          'Authorization': '$terminalsn $sign',
        },
      ),
    );

    final Map<String, dynamic> json =
        jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    _sqbPayResponse = json;

    final String resultCode = json['result_code']?.toString() ?? '';
    if (resultCode != '200') return false;

    final dynamic bizRaw = json['biz_response'];
    final Map<String, dynamic> biz = bizRaw is Map
        ? Map<String, dynamic>.from(bizRaw)
        : (bizRaw is String && bizRaw.isNotEmpty
            ? jsonDecode(bizRaw) as Map<String, dynamic>
            : <String, dynamic>{});

    final String bizCode = biz['result_code']?.toString() ?? '';
    if (bizCode == 'PAY_SUCCESS') {
      final dynamic dataRaw = biz['data'];
      final Map<String, dynamic> data = dataRaw is Map
          ? Map<String, dynamic>.from(dataRaw)
          : <String, dynamic>{};
      _sqbTradeNo = data['trade_no']?.toString() ?? data['sn']?.toString() ?? '';
      return true;
    }
    // PAY_FAIL 或其他状态
    return false;
  }

  /// 收钱吧支付响应缓存（用于提取错误信息）
  Map<String, dynamic> _sqbPayResponse = <String, dynamic>{};
  String _sqbTradeNo = '';

  /// 收钱吧支付是否明确失败（对齐 smdcapp handlerTradeSuccess: PAY_FAIL / result_code!=200）
  /// 网络异常未收到响应时返回 false（对齐 smdcapp onFailure → 轮询查询）
  bool get sqbPayDefinitelyFailed {
    if (_sqbPayResponse.isEmpty) return false;
    final String resultCode = _sqbPayResponse['result_code']?.toString() ?? '';
    if (resultCode != '200') return true;
    final dynamic bizRaw = _sqbPayResponse['biz_response'];
    final Map<String, dynamic> biz = bizRaw is Map
        ? Map<String, dynamic>.from(bizRaw)
        : (bizRaw is String && bizRaw.isNotEmpty
            ? (jsonDecode(bizRaw) as Map<String, dynamic>)
            : <String, dynamic>{});
    return biz['result_code']?.toString() == 'PAY_FAIL';
  }

  /// 获取收钱吧支付错误信息
  String get sqbErrorMsg {
    final dynamic bizRaw = _sqbPayResponse['biz_response'];
    final Map<String, dynamic> biz = bizRaw is Map
        ? Map<String, dynamic>.from(bizRaw)
        : <String, dynamic>{};
    return biz['error_message']?.toString() ??
        _sqbPayResponse['error_message']?.toString() ??
        '支付失败';
  }

  /// 收钱吧交易号
  String get sqbTradeNo => _sqbTradeNo;

  /// 收钱吧查询支付状态（对齐 smdcapp HttpProxy.queryV3 → ReceiveMoneyPayDialog.queryLeshua）
  Future<ScanPayResult> _sqbQuery({
    required String billNo,
    required String payid,
  }) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'terminal_sn': terminalsn,
      'sn': '',
      'client_sn': billNo,
    };
    final String body = jsonEncode(params);
    final String sign = _md5(body + terminalkey);

    try {
      final Response<String> response = await _payDio.post<String>(
        '$_sqbDomain/upay/v2/query',
        data: body,
        options: Options(
          contentType: 'application/json',
          headers: <String, dynamic>{
            'Authorization': '$terminalsn $sign',
          },
        ),
      );

      final Map<String, dynamic> json =
          jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
      final String resultCode = json['result_code']?.toString() ?? '';
      if (resultCode != '200') {
        // 通信失败，非终态
        return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
      }

      final dynamic bizRaw = json['biz_response'];
      final Map<String, dynamic> biz = bizRaw is Map
          ? Map<String, dynamic>.from(bizRaw)
          : (bizRaw is String && bizRaw.isNotEmpty
              ? jsonDecode(bizRaw) as Map<String, dynamic>
              : <String, dynamic>{});

      final String bizCode = biz['result_code']?.toString() ?? '';
      if (bizCode == 'SUCCESS') {
        final dynamic dataRaw = biz['data'];
        final Map<String, dynamic> data = dataRaw is Map
            ? Map<String, dynamic>.from(dataRaw)
            : <String, dynamic>{};
        final String orderStatus = data['order_status']?.toString() ?? '';
        if (orderStatus == 'PAID') {
          final String sn = data['sn']?.toString() ?? '';
          return ScanPayResult(success: true, trade: sn, payid: payid, billNo: billNo);
        }
        if (orderStatus == 'PAY_CANCELED') {
          final String errMsg = biz['error_message']?.toString() ?? '支付失败';
          return ScanPayResult(
              success: false, trade: errMsg, payid: payid, billNo: billNo, errorMsg: errMsg);
        }
        // CANCELED/REFUNDED/PARTIAL_REFUNDED 等非终态继续轮询
        return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
      }
      if (bizCode == 'FAIL') {
        final String errMsg = biz['error_message']?.toString() ?? '支付失败';
        return ScanPayResult(
            success: false, trade: errMsg, payid: payid, billNo: billNo, errorMsg: errMsg);
      }
      // 其他状态继续轮询
      return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
    } catch (_) {
      return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
    }
  }

  // ═══════════════════ 优支付（payType=4）═══════════════════

  /// 优支付付款码支付（对齐 smdcapp BoYouPay.payAuthCode）
  /// pay_way: ZFBZF=支付宝 WXZF=微信
  Future<bool> _boyouPay({
    required String payid,
    required String billNo,
    required int amtFen,
    required String authCode,
  }) async {
    final String payWay = payid == '08' ? 'ZFBZF' : 'WXZF';
    final String orderid = billNo.replaceAll('-', '');

    final Map<String, String> params = <String, String>{
      'service': 'upload_authcode',
      'pay_way': payWay,
      'merchant_id': terminalsn,
      'user_name': '',
      'third_order_id': orderid,
      'amount': amtFen.toString(),
      't0': '1',
      'notify_url': _boyouNotifyUrl,
      'client_ip': '192.168.8.1',
      'body': '授权码销售',
      'auth_code': authCode,
      'nonce_str': _uuid(),
    };
    if (shopId.isNotEmpty) {
      params['shopid'] = shopId;
    }

    // 签名（对齐 smdcapp SignMD5.newSignHashMap）
    params['sign'] = _signParams(params);
    // 请求体（对齐 smdcapp SignMD5.StrHashMap2：字典序 k=v&k=v）
    final String requestBody = _sortedParamStr(params);

    try {
      final Response<String> response = await _payDio.post<String>(
        _boyouDomain,
        data: requestBody,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final Map<String, String> result = _parseXml(response.data ?? '');
      _boyouPayResponse = result;
      _boyouResponseReceived = true;

      final String respCode = result['resp_code'] ?? '';
      if (respCode != '0') return false;

      final String resultCode = result['result_code'] ?? '';
      if (resultCode != '0') return false;

      final String status = result['status'] ?? '';
      if (status == '2') {
        // 支付成功
        _boyouTrade =
            '${result['leshua_order_id'] ?? ''},${result['third_order_id'] ?? ''}';
        return true;
      }
      // status 0=支付中 等其他非终态 → 需要轮询
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 优支付支付响应缓存
  Map<String, String> _boyouPayResponse = <String, String>{};
  String _boyouTrade = '';
  bool _boyouResponseReceived = false;

  /// 优支付交易号
  String get boyouTrade => _boyouTrade;

  /// 获取优支付支付错误信息
  String get boyouErrorMsg {
    final String errMsg = _boyouPayResponse['error_msg'] ?? '';
    if (errMsg.isNotEmpty) return errMsg;
    final String respMsg = _boyouPayResponse['resp_msg'] ?? '';
    return respMsg.isNotEmpty ? respMsg : '支付失败';
  }

  /// 判断优支付支付响应是否为明确失败（对齐 smdcapp status 6/8 或 result_code!=0）
  /// 网络异常未收到响应时返回 false（对齐 smdcapp onFailure → clickTrade 轮询）
  bool get boyouPayDefinitelyFailed {
    if (!_boyouResponseReceived) return false;
    final String respCode = _boyouPayResponse['resp_code'] ?? '';
    if (respCode != '0') return true;
    final String resultCode = _boyouPayResponse['result_code'] ?? '';
    if (resultCode != '0') return true;
    final String status = _boyouPayResponse['status'] ?? '';
    return status == '6' || status == '8';
  }

  /// 优支付查询支付状态（对齐 smdcapp BoYouPay.payCheckStatusV3）
  /// status: 0=支付中 2=支付成功 6=订单已关闭 8=支付失败
  Future<ScanPayResult> _boyouQuery({
    required String billNo,
    required String payid,
  }) async {
    final String orderid = billNo.replaceAll('-', '');
    final Map<String, String> params = <String, String>{
      'service': 'query_status',
      'merchant_id': terminalsn,
      'third_order_id': orderid,
      'nonce_str': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    params['sign'] = _signParams(params);
    final String requestBody = _sortedParamStr(params);

    try {
      final Response<String> response = await _payDio.post<String>(
        _boyouDomain,
        data: requestBody,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final Map<String, String> result = _parseXml(response.data ?? '');
      final String respCode = result['resp_code'] ?? '';
      if (respCode != '0') {
        final String respMsg = result['resp_msg'] ?? '支付失败';
        return ScanPayResult(
            success: false, trade: respMsg, payid: payid, billNo: billNo, errorMsg: respMsg);
      }

      final String resultCode = result['result_code'] ?? '';
      if (resultCode != '0') {
        // 非终态，继续轮询
        return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
      }

      final String status = result['status'] ?? '';
      final String leOrderId = result['leshua_order_id'] ?? '';
      final String thirdOrderId = result['third_order_id'] ?? '';

      if (status == '2') {
        // 支付成功（对齐 smdcapp closeOrder(trueLeOrderId + "," + third_order_id, true)）
        return ScanPayResult(
            success: true,
            trade: '$leOrderId,$thirdOrderId',
            payid: payid,
            billNo: billNo);
      }
      if (status == '6' || status == '8') {
        // 订单已关闭/支付失败
        final String errMsg = result['error_msg'] ?? '支付失败';
        return ScanPayResult(
            success: false, trade: errMsg, payid: payid, billNo: billNo, errorMsg: errMsg);
      }
      // 其他非终态继续轮询
      return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
    } catch (_) {
      return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
    }
  }

  /// 优支付关闭订单（对齐 smdcapp BoYouPay.closeOrdersLoad）
  Future<void> _boyouClose(String billNo) async {
    final String orderid = billNo.replaceAll('-', '');
    final Map<String, String> params = <String, String>{
      'service': 'close_order',
      'merchant_id': terminalsn,
      'third_order_id': orderid,
      'nonce_str': _uuid(),
    };
    params['sign'] = _signParams(params);
    final String requestBody = _sortedParamStr(params);

    try {
      await _payDio.post<String>(
        _boyouDomain,
        data: requestBody,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      // 关闭订单失败不处理（对齐 smdcapp）
    }
  }

  // ═══════════════════ 乐刷（payType=2）═══════════════════

  /// 乐刷支付网关地址（对齐 smdcapp LePos.is_url_new）
  static const String _leshuaDomain =
      'https://paygate.leshuazf.com/cgi-bin/lepos_pay_gateway.cgi';

  /// 乐刷通知地址（对齐 smdcapp LePos.notify_url）
  static const String _leshuaNotifyUrl = 'http://yun.bypos.net/LePos/common/notify.do';

  /// 乐刷付款码支付（对齐 smdcapp LePos.payAuthCode）
  ///
  /// [payid] 08=支付宝 09=微信
  /// [amtFen] 金额（分）
  /// [authCode] 客户付款码
  Future<bool> leshuaPay({
    required String payid,
    required String billNo,
    required int amtFen,
    required String authCode,
  }) async {
    // pay_way: 支付宝=ALIPAY 微信=WECHAT（对齐 smdcapp LePos payway 映射）
    final String payWay = payid == '08' ? 'ALIPAY' : 'WECHAT';
    final Map<String, String> params = <String, String>{
      'service': 'upload_authcode',
      'pay_way': payWay,
      'merchant_id': terminalsn,
      'user_name': operator.isNotEmpty ? operator : '结算',
      'third_order_id': billNo,
      'amount': amtFen.toString(),
      't0': '0',
      'notify_url': _leshuaNotifyUrl,
      'client_ip': '127.0.0.1',
      'body': '授权码销售',
      'auth_code': authCode,
      'nonce_str': _uuid(),
    };
    params['sign'] = _leshuaSign(params);
    final String requestBody = _sortedParamStr(params);

    try {
      final Response<String> response = await _payDio.post<String>(
        _leshuaDomain,
        data: requestBody,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final Map<String, String> result = _parseXml(response.data ?? '');
      final String respCode = result['resp_code'] ?? '';
      final String resultCode = result['result_code'] ?? '';
      _leshuaTradeNo = result['leshua_order_id'] ?? '';
      // resp_code=0 且 result_code=0 表示支付成功
      return respCode == '0' && resultCode == '0';
    } catch (_) {
      return false;
    }
  }

  /// 乐刷查询支付状态（对齐 smdcapp LePos.payCheckStatusV3）
  Future<ScanPayResult> leshuaQuery({
    required String billNo,
    required String payid,
  }) async {
    final Map<String, String> params = <String, String>{
      'service': 'query_status',
      'merchant_id': terminalsn,
      'third_order_id': billNo,
      'nonce_str': _uuid(),
    };
    params['sign'] = _leshuaSign(params);
    final String requestBody = _sortedParamStr(params);

    try {
      final Response<String> response = await _payDio.post<String>(
        _leshuaDomain,
        data: requestBody,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final Map<String, String> result = _parseXml(response.data ?? '');
      final String respCode = result['resp_code'] ?? '';
      final String status = result['status'] ?? '';
      final String tradeNo = result['leshua_order_id'] ?? '';
      // status=2 表示支付成功（对齐 smdcapp LePos 状态判断）
      if (respCode == '0' && status == '2') {
        return ScanPayResult(success: true, trade: tradeNo, payid: payid, billNo: billNo);
      }
      // status=0/1 为未支付/支付中，非终态
      return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
    } catch (_) {
      return ScanPayResult(success: false, trade: '', payid: payid, billNo: billNo);
    }
  }

  /// 乐刷交易号缓存
  String _leshuaTradeNo = '';
  String get leshuaTradeNo => _leshuaTradeNo;

  /// 乐刷签名（对齐 smdcapp LePos.LesSignHashMap）
  ///
  /// 规则：参数字典序拼接 "k1=v1&k2=v2...&key=密钥"，MD5 后转大写
  String _leshuaSign(Map<String, String> params) {
    final String paramStr = _sortedParamStr(params);
    return _md5('$paramStr&key=$terminalkey').toUpperCase();
  }

  // ═══════════════════ 退款 ═══════════════════

  /// 退款（对齐 smdcapp RefundUtil_BY / RefundUtil_les / RefundUtil）
  ///
  /// [billNo] 原商户订单号
  /// [refundNo] 退款单号
  /// [totalAmtFen] 原订单金额（分）
  /// [refundAmtFen] 退款金额（分）
  /// [tradeNo] 第三方交易号（可选）
  /// 返回是否退款成功
  Future<bool> refund({
    required String billNo,
    required String refundNo,
    required int totalAmtFen,
    required int refundAmtFen,
    String tradeNo = '',
  }) async {
    if (payType == '1') {
      return _sqbRefund(billNo: billNo, refundNo: refundNo, refundAmtFen: refundAmtFen);
    }
    if (payType == '2') {
      return _leshuaRefund(billNo: billNo, refundNo: refundNo,
          totalAmtFen: totalAmtFen, refundAmtFen: refundAmtFen);
    }
    return _boyouRefund(billNo: billNo, refundNo: refundNo,
        totalAmtFen: totalAmtFen, refundAmtFen: refundAmtFen);
  }

  /// 收钱吧退款（对齐 smdcapp RefundUtil）
  Future<bool> _sqbRefund({
    required String billNo,
    required String refundNo,
    required int refundAmtFen,
  }) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'terminal_sn': terminalsn,
      'client_sn': billNo,
      'sn': _sqbTradeNo,
      'refund_request_no': refundNo,
      'amount': refundAmtFen.toString(),
      'operator': operator,
    };
    final String body = jsonEncode(params);
    final String sign = _md5(body + terminalkey);
    try {
      final Response<String> response = await _payDio.post<String>(
        '$_sqbDomain/upay/v2/refund',
        data: body,
        options: Options(
          contentType: 'application/json',
          headers: <String, dynamic>{'Authorization': '$terminalsn $sign'},
        ),
      );
      final Map<String, dynamic> json =
          jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
      return json['result_code']?.toString() == '200';
    } catch (_) {
      return false;
    }
  }

  /// 乐刷退款（对齐 smdcapp RefundUtil_les）
  Future<bool> _leshuaRefund({
    required String billNo,
    required String refundNo,
    required int totalAmtFen,
    required int refundAmtFen,
  }) async {
    final Map<String, String> params = <String, String>{
      'service': 'refund',
      'merchant_id': terminalsn,
      'third_order_id': billNo,
      'refund_third_order_id': refundNo,
      'total_fee': totalAmtFen.toString(),
      'refund_fee': refundAmtFen.toString(),
      'nonce_str': _uuid(),
    };
    params['sign'] = _leshuaSign(params);
    final String requestBody = _sortedParamStr(params);
    try {
      final Response<String> response = await _payDio.post<String>(
        _leshuaDomain,
        data: requestBody,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final Map<String, String> result = _parseXml(response.data ?? '');
      return result['resp_code'] == '0' && result['result_code'] == '0';
    } catch (_) {
      return false;
    }
  }

  /// 优支付退款（对齐 smdcapp RefundUtil_BY）
  Future<bool> _boyouRefund({
    required String billNo,
    required String refundNo,
    required int totalAmtFen,
    required int refundAmtFen,
  }) async {
    final String orderid = billNo.replaceAll('-', '');
    final Map<String, String> params = <String, String>{
      'service': 'refund',
      'merchant_id': terminalsn,
      'third_order_id': orderid,
      'refund_third_order_id': refundNo.replaceAll('-', ''),
      'total_fee': totalAmtFen.toString(),
      'refund_fee': refundAmtFen.toString(),
      'nonce_str': _uuid(),
    };
    params['sign'] = _signParams(params);
    final String requestBody = _sortedParamStr(params);
    try {
      final Response<String> response = await _payDio.post<String>(
        _boyouDomain,
        data: requestBody,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final Map<String, String> result = _parseXml(response.data ?? '');
      return result['resp_code'] == '0' && result['result_code'] == '0';
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════ 工具方法 ═══════════════════

  /// MD5签名（对齐 smdcapp SignMD5.SignHashMap）：
  /// 参数字典序排列拼接 k=v&k=v + &key=密钥 → MD5 → 大写
  String _signParams(Map<String, String> params) {
    final List<String> keys = params.keys.toList()..sort();
    final StringBuffer sb = StringBuffer();
    for (final String key in keys) {
      final String? value = params[key];
      if (value == null) continue;
      if (sb.isNotEmpty) sb.write('&');
      sb.write('$key=$value');
    }
    final String msg = '$sb&key=$terminalkey';
    return _md5(msg).toUpperCase();
  }

  /// 参数字典序拼接为请求体（对齐 smdcapp SignMD5.StrHashMap2）
  String _sortedParamStr(Map<String, String> params) {
    final List<String> keys = params.keys.toList()..sort();
    final StringBuffer sb = StringBuffer();
    for (final String key in keys) {
      final String? value = params[key];
      if (value == null) continue;
      if (sb.isNotEmpty) sb.write('&');
      sb.write('$key=$value');
    }
    return sb.toString();
  }

  /// MD5 哈希
  String _md5(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// 生成UUID（无横线，对齐 smdcapp BoYouPay.getUUID）
  static final Random _random = Random();

  String _uuid() {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 32; i++) {
      sb.write(_random.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  /// 解析XML响应为Map（key小写，对齐 smdcapp BoYouPay.parse）
  ///
  /// 优支付返回格式: <xml><resp_code>0</resp_code><result_code>0</result_code>...</xml>
  static Map<String, String> _parseXml(String xml) {
    final Map<String, String> result = <String, String>{};
    if (xml.isEmpty) return result;

    // 简单正则解析 <key>value</key>（对齐 smdcapp dom4j 解析逻辑）
    final RegExp regExp = RegExp(r'<(\w+)><!\[CDATA\[(.*?)\]\]></(\w+)>|<(\w+)>(.*?)</(\w+)>');
    for (final RegExpMatch match in regExp.allMatches(xml)) {
      if (match.group(1) != null) {
        // CDATA 格式
        result[match.group(1)!.toLowerCase()] = match.group(2) ?? '';
      } else if (match.group(4) != null) {
        result[match.group(4)!.toLowerCase()] = match.group(5) ?? '';
      }
    }
    return result;
  }
}
