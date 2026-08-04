import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/main.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/dio_utils.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/pages/login/page/login_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sp_util/sp_util.dart';

/// 防止多个并发请求同时触发跳转登录页
bool _isRedirectingToLogin = false;

/// 记录接口操作日志（对齐 smdcapp WriteErrorLogUtils.writeErrorLog(null, url, params, tips)）
///
/// 所有接口调用（[request] / [requestForm]）的成功与失败都会经此记录到 crash_log 分类，
/// 使运行日志能完整追溯每一次接口操作。[params] 过大时由 FileLogWriter 自动截断保护。
void _logApi(String url, dynamic params, String result) {
  String path = url;
  try {
    path = Uri.parse(url).path;
  } catch (_) {}
  FileLogWriter.instance.writeErrorLog(
    null,
    path,
    params is String ? params : json.encode(params),
    result,
  );
}

/// ylx-boss 风格的统一请求方法（与 Vue 端 util.ts 保持一致）
///
/// 默认 POST，请求体为两层结构：
///   外层：sid / spid / client / token / sign / requestId（公共参数）
///   内层 params：clientflag / userid / ...业务参数
///
/// 返回完整接口响应 Map（包含 retcode / retmsg / data 等字段）。
/// - retcode == 0 时 Future 正常完成 → 执行 .then()
/// - retcode != 0 或网络异常时 Future 以异常完成 → 执行 .catchError()
///   拦截器已统一 Toast 提示 retmsg，调用方 .catchError 中无需再弹错误
///
/// 用法示例：
/// ```dart
/// // data 为 Map → 自动合并 clientflag/userid 后作为 params
/// request(HttpApi.someUrl, {'key': 'value'})
///
/// // data 为非 Map（如字符串）→ 直接作为 params 原始值
/// request(HttpApi.delProduct, productId)
/// ```
Future<Map<String, dynamic>> request(
  String url, [
  dynamic data,
  bool showLoading = false,
  bool showError = true,
  dynamic rawParamsValue,
]) async {
  final String token = SpUtil.getString(Constant.token) ?? '';

  // 从 store 中读取 sid / spid
  String sid = '';
  String spid = '';
  try {
    final String storeStr = SpUtil.getString(Constant.store) ?? '';
    if (storeStr.isNotEmpty) {
      final Map<String, dynamic> storeMap =
          jsonDecode(storeStr) as Map<String, dynamic>;
      sid = storeMap['id']?.toString() ?? '';
      spid = storeMap['spid']?.toString() ?? '';
    }
  } catch (_) {}

  // 从 user 中读取 userid
  String? userid;
  try {
    final String userStr = SpUtil.getString(Constant.user) ?? '';
    if (userStr.isNotEmpty) {
      final Map<String, dynamic> userMap =
          jsonDecode(userStr) as Map<String, dynamic>;
      userid = userMap['userid']?.toString();
    }
  } catch (_) {}

  // 构建 params：
  // - rawParamsValue 优先（兼容旧调用）
  // - data 为非 Map 时，直接作为 params 原始值（如删除接口传 productid 字符串）
  // - data 为 Map 时，合并 clientflag/userid/sid/spid（与 boss 项目一致）
  final dynamic params;
  if (rawParamsValue != null) {
    params = rawParamsValue;
  } else if (data is Map<String, dynamic>) {
    params = <String, dynamic>{
      'clientflag': 1,
      'sid': sid.isNotEmpty ? sid : '0',
      'spid': spid.isNotEmpty ? spid : '0',
      if (userid != null && userid.isNotEmpty) 'userid': userid,
      ...data,
    };
  } else if (data != null) {
    // 非 Map（如 String / int），直接作为 params
    params = data;
  } else {
    params = <String, dynamic>{
      'clientflag': 1,
      'sid': sid.isNotEmpty ? sid : '0',
      'spid': spid.isNotEmpty ? spid : '0',
      if (userid != null && userid.isNotEmpty) 'userid': userid,
    };
  }
  
  // 构建外层请求体（公共参数 + params）
  // 仅当 params 为 Map 时注入 client 字段；字符串等原始值直接透传（如 getSupplierInfo 传 id）
  if (params is Map<String, dynamic>) {
    params['client'] = "WEBAPP";
  }
  final Map<String, dynamic> requestData = <String, dynamic>{
    'sid': sid.isNotEmpty ? sid : '0',
    'spid': spid.isNotEmpty ? spid : '0',
    'client': 'WEBAPP',
    'token': token,
    'sign': '83690002',
    'requestId': DateTime.now().millisecondsSinceEpoch,
    'params': params,
  };

  const String baseUrl = HttpApi.baseUrlYtt;
  final String fullUrl = url.startsWith('http') ? url : '$baseUrl$url';

  try {
    final Response<String> response = await DioUtils.instance.dio.post<String>(
      fullUrl,
      data: requestData,
    );
    final String content = response.data.toString();
    final Map<String, dynamic> jsonMap =
        json.decode(content) as Map<String, dynamic>;

    if (jsonMap.containsKey('retcode')) {
      final dynamic retcode = jsonMap['retcode'];
      final String retmsg = jsonMap['retmsg']?.toString() ?? '请求失败';
      if (retcode == 0) {
        _logApi(fullUrl, params, '接口成功 retcode=0');
        return jsonMap;
      }
      if (retcode == -2 || retcode == -3) {
        // 登录信息失效：清除缓存并跳转登录页
        _handleLoginExpired(retmsg);
        throw _ApiException(jsonMap);
      }
      if (showError && retmsg.isNotEmpty) {
        Toast.show(retmsg);
      }
      _logApi(fullUrl, params, '接口失败 retcode=$retcode retmsg=$retmsg');
      throw _ApiException(jsonMap);
    }
    // 兼容非 retcode 格式（如拦截器包装的 code/message）
    if (jsonMap['code'] == 0) {
      _logApi(fullUrl, params, '接口成功 code=0');
      return jsonMap;
    }
    final String msg = jsonMap['message']?.toString() ?? '请求失败';
    if (showError && msg.isNotEmpty) {
      Toast.show(msg);
    }
    throw _ApiException(jsonMap);
  } on _ApiException {
    // 业务异常直接向上抛出（已 Toast）
    rethrow;
  } catch (e) {
    // 网络异常 / DioException —— 始终提取真实错误信息，不论 showError
    String errorMsg = '网络请求异常';
    if (e is DioException) {
      if (e.response?.data != null) {
        try {
          final dynamic respData = e.response!.data;
          final Map<String, dynamic> errMap = respData is String
              ? json.decode(respData) as Map<String, dynamic>
              : (respData as Map<String, dynamic>);
          final dynamic retcode = errMap['retcode'];
          final String? retmsg = errMap['retmsg']?.toString();
          if (retcode == -2 || retcode == -3) {
            _handleLoginExpired(retmsg ?? '登录信息失效，请重新登录');
          }
          if (retmsg != null && retmsg.isNotEmpty) {
            errorMsg = retmsg;
          }
        } catch (_) {}
      } else if (e.message != null && e.message!.isNotEmpty) {
        // 无响应体时（超时/连接拒绝等），保留 Dio 的原始描述
        errorMsg = e.message!;
      }
    }
    if (showError) Toast.show(errorMsg);
    _logApi(fullUrl, params, '接口异常: $errorMsg');
    throw _ApiException(<String, dynamic>{'retcode': -1, 'retmsg': errorMsg});
  }
}

/// 强制下线处理：弹窗提示 → 清除缓存 → 跳转登录页
void _handleForceLogout(String retmsg) {
  if (_isRedirectingToLogin) return;
  _isRedirectingToLogin = true;

  final navigatorState = MyApp.navigatorKey.currentState;
  if (navigatorState == null) {
    // navigator 未就绪，降级为直接跳转
    _clearCachePreservingRemember();
    _navigateToLogin();
    return;
  }

  showDialog<void>(
    context: navigatorState.context,
    barrierDismissible: false,
    builder: (ctx) => ConfirmDialog(
      content: retmsg.isNotEmpty ? retmsg : '您已被强制下线，请重新登录',
      singleButton: true,
    ),
  ).then((_) {
    _clearCachePreservingRemember();
    _navigateToLogin();
  });
}

/// 登录失效统一处理：清除缓存 + 跳转登录页
/// 注意：保留"记住账号密码"相关数据，不清除
void _handleLoginExpired(String retmsg) {
  if (_isRedirectingToLogin) return;
  _isRedirectingToLogin = true;

  Toast.show(retmsg.isNotEmpty ? retmsg : '登录信息失效，请重新登录');

  _clearCachePreservingRemember();

  // 延迟重置标志，避免快速连续触发
  Future.delayed(const Duration(seconds: 3), () {
    _isRedirectingToLogin = false;
  });

  _navigateToLogin();
}

/// 清除缓存但保留"记住账号密码"相关数据
void _clearCachePreservingRemember() {
  // 字符串类型的记住密码 key
  final rememberKeys = <String, String>{};
  for (final key in [
    Constant.rememberLoginType,
    Constant.rememberPhone,
    Constant.rememberPhonePwd,
    Constant.rememberMerchantCode,
    Constant.rememberMerchantAccount,
    Constant.rememberMerchantPwd,
  ]) {
    final value = SpUtil.getString(key);
    if (value != null && value.isNotEmpty) {
      rememberKeys[key] = value;
    }
  }

  // 布尔类型的记住密码开关（单独处理，避免类型不匹配）
  final bool? rememberPwdEnabled = SpUtil.getBool(Constant.rememberPwdEnabled);

  SpUtil.clear();

  // 恢复字符串类型数据
  rememberKeys.forEach((key, value) {
    SpUtil.putString(key, value);
  });

  // 恢复布尔类型数据
  if (rememberPwdEnabled != null) {
    SpUtil.putBool(Constant.rememberPwdEnabled, rememberPwdEnabled);
  }
}

/// 主动退出登录：清除缓存（保留记住密码）并跳转登录页
void logoutAndRedirect(BuildContext context) {
  _clearCachePreservingRemember();
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    (route) => false,
  );
}

/// 跳转登录页，若 navigator 尚未就绪则延迟重试
void _navigateToLogin([int retryCount = 0]) {
  final navigatorState = MyApp.navigatorKey.currentState;
  if (navigatorState != null) {
    navigatorState.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  } else if (retryCount < 5) {
    // navigator 未就绪，等待下一帧后重试（最多重试 5 次）
    debugPrint('⚠️ _navigateToLogin: navigator 未就绪，第 ${retryCount + 1} 次重试');
    Future.delayed(const Duration(milliseconds: 500), () {
      _navigateToLogin(retryCount + 1);
    });
  } else {
    debugPrint('❌ _navigateToLogin: 重试 ${retryCount} 次后仍无法跳转登录页');
    _isRedirectingToLogin = false;
  }
}

/// 签名密钥（与 smdcapp 项目 Net.key 保持一致）
const String _kSignKey = r'83690002云专卖as5dfas博优软件df@#$!@%#^$#%^';

/// 当前时间格式化为 yyyy-MM-dd HH:mm:ss
String _formatNow() {
  final DateTime now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
}

/// 复刻 smdcapp NetInterceptor + EncryptKey 逻辑：
/// 追加公共参数 + url_info，并按 key 字典序拼接后计算 HMAC-MD5 签名（大写）。
Future<Map<String, dynamic>> _buildSignedParams(
  Map<String, dynamic> formData,
  String fullUrl,
) async {
  final Map<String, dynamic> all = <String, dynamic>{};
  formData.forEach((key, value) {
    all[key] = value?.toString() ?? '';
  });

  // url_info：域名后的路径，如 YttSvr/app/yttlogin
  // 对齐 smdcapp NetInterceptor：tabledown 和 reserve/findList 不发送 url_info
  final String path = Uri.parse(fullUrl).path.replaceFirst(RegExp('^/'), '');
  if (!fullUrl.contains('app/update/tabledown') &&
      !fullUrl.contains('reserve/findList')) {
    all['url_info'] = path;
  }

  // 公共参数（登录阶段 sid/spid/token 均为空，默认 0/""）
  String sid = '0';
  String spid = '0';
  try {
    final String storeStr = SpUtil.getString(Constant.store) ?? '';
    if (storeStr.isNotEmpty) {
      final Map<String, dynamic> storeMap =
          jsonDecode(storeStr) as Map<String, dynamic>;
      sid = storeMap['id']?.toString() ?? '0';
      spid = storeMap['spid']?.toString() ?? '0';
    }
  } catch (_) {}
  String operid = '0';
  try {
    final String userStr = SpUtil.getString(Constant.user) ?? '';
    if (userStr.isNotEmpty) {
      final Map<String, dynamic> userMap =
          jsonDecode(userStr) as Map<String, dynamic>;
      operid = userMap['userid']?.toString() ?? '0';
    }
  } catch (_) {}

  String appVerName = '';
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    appVerName = info.version;
  } catch (_) {}

  all['machserial'] = '0000';
  all['machno'] = '0';
  all['opername'] = '';
  all['client'] = 'APP';
  all['token'] = SpUtil.getString(Constant.token) ?? '';
  all['sid'] = sid;
  all['spid'] = spid;
  all['operid'] = operid;
  // 对齐 smdcapp EncryptKey.StrEncrypt: ip 填主设备 localhost 地址
  all['ip'] = ConnectionManager.getLocalhost();
  all['app_v_name'] = appVerName;
  all['temp_request_time'] = _formatNow();
  all['newclient'] = 'YG';
  all['uuid'] = DateTime.now().millisecondsSinceEpoch.toString();

  // key 字典序排序后拼接为 key=valuekey=value...（无分隔符）
  final List<String> keys = all.keys.toList()..sort();
  final StringBuffer sb = StringBuffer();
  for (final String key in keys) {
    sb.write('$key=${all[key]}');
  }

  // HMAC-MD5 签名（大写十六进制）
  final Hmac hmac = Hmac(md5, utf8.encode(_kSignKey));
  final Digest digest = hmac.convert(utf8.encode(sb.toString()));
  all['sign'] = digest.toString().toUpperCase();

  return all;
}

/// 表单编码 POST 请求（用于登录等接口，参数以 form-urlencoded 方式发送）
///
/// 与 smdcapp 项目保持一致：发送扁平字段，并追加公共参数与 sign 签名。
///
/// [masterDevice] 为 true 时走主设备（直连PC）地址，否则走云服务地址。
/// 主设备接口（路径以 /api/ 开头）响应为 PCRootDataBean（Success/Message/Data），
/// 云端接口响应为 retcode/retmsg/data，本函数自动区分解析。
Future<Map<String, dynamic>> requestForm(
  String url,
  Map<String, dynamic> formData, {
  bool showError = true,
  bool masterDevice = false,
}) async {
  final String baseUrl =
      ConnectionManager.resolveBaseUrl(masterDevice: masterDevice);
  String fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
  // 规范化路径中的双斜杠（避免 baseUrl 尾部 / 与接口前导 / 重叠），与 smdcapp 保持一致
  final Uri parsed = Uri.parse(fullUrl);
  fullUrl = parsed
      .replace(path: parsed.path.replaceAll(RegExp('/{2,}'), '/'))
      .toString();

  // 追加公共参数并计算签名
  final Map<String, dynamic> signedData =
      await _buildSignedParams(formData, fullUrl);

  try {
    final Response<String> response = await DioUtils.instance.dio.post<String>(
      fullUrl,
      data: signedData,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final String content = response.data.toString();
    final Map<String, dynamic> jsonMap =
        json.decode(content) as Map<String, dynamic>;

    // 主设备响应格式：PCRootDataBean（Success/Message/Data）
    if (jsonMap.containsKey('Success')) {
      final bool success = jsonMap['Success'] == true;
      final String message = jsonMap['Message']?.toString() ?? '请求失败';
      if (success) {
        _logApi(fullUrl, signedData, '主设备接口成功 Success=true');
        return jsonMap;
      }
      if (showError && message.isNotEmpty) {
        Toast.show(message);
      }
      _logApi(fullUrl, signedData, '主设备接口失败 Message=$message');
      throw _ApiException(jsonMap);
    }

    if (jsonMap.containsKey('retcode')) {
      final dynamic retcode = jsonMap['retcode'];
      final String retmsg = jsonMap['retmsg']?.toString() ?? '请求失败';
      if (retcode == 0) {
        _logApi(fullUrl, signedData, '接口成功 retcode=0');
        return jsonMap;
      }
      if (showError && retmsg.isNotEmpty) {
        Toast.show(retmsg);
      }
      _logApi(fullUrl, signedData, '接口失败 retcode=$retcode retmsg=$retmsg');
      throw _ApiException(jsonMap);
    }
    // 兼容非 retcode 格式
    if (jsonMap['code'] == 0) {
      _logApi(fullUrl, signedData, '接口成功 code=0');
      return jsonMap;
    }
    final String msg = jsonMap['message']?.toString() ?? '请求失败';
    if (showError && msg.isNotEmpty) {
      Toast.show(msg);
    }
    throw _ApiException(jsonMap);
  } on _ApiException {
    rethrow;
  } catch (e) {
    String errorMsg = '网络请求异常';
    if (e is DioException) {
      if (e.response?.data != null) {
        try {
          final dynamic respData = e.response!.data;
          final Map<String, dynamic> errMap = respData is String
              ? json.decode(respData) as Map<String, dynamic>
              : (respData as Map<String, dynamic>);
          final String? retmsg = errMap['retmsg']?.toString();
          if (retmsg != null && retmsg.isNotEmpty) {
            errorMsg = retmsg;
          }
        } catch (_) {}
      } else if (e.message != null && e.message!.isNotEmpty) {
        errorMsg = e.message!;
      }
    }
    if (showError) {
      Toast.show(errorMsg);
    }
    _logApi(fullUrl, signedData, '接口异常: $errorMsg');
    throw _ApiException(<String, dynamic>{'retcode': -1, 'retmsg': errorMsg});
  }
}

/// 探测主设备是否可达（对齐 smdcapp 登录后的 checkPC/getStatus 逻辑）
///
/// 调用主设备 GetHostSyncTime 接口，并核对返回的 sid/spid 与当前登录门店是否一致，
/// 一致才认为主设备可达。结果写入 [ConnectionManager.pcAlive]。
Future<bool> checkMasterDeviceAlive() async {
  final String localhost = ConnectionManager.getLocalhost();
  if (localhost.isEmpty || !localhost.startsWith('http')) {
    ConnectionManager.pcAlive = false;
    return false;
  }

  final String fullUrl = '$localhost${HttpApi.pcGetHostSyncTime}';
  try {
    final Map<String, dynamic> signedData =
        await _buildSignedParams(<String, dynamic>{'data': ''}, fullUrl);
    final Response<String> response = await DioUtils.instance.dio.post<String>(
      fullUrl,
      data: signedData,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final Map<String, dynamic> jsonMap =
        json.decode(response.data.toString()) as Map<String, dynamic>;

    if (jsonMap['Success'] != true) {
      _logApi(fullUrl, signedData, '主设备探测失败 Success!=true');
      ConnectionManager.pcAlive = false;
      return false;
    }

    // 核对主设备 sid/spid 与当前登录门店是否一致
    final dynamic data = jsonMap['Data'];
    if (data is Map) {
      final String pcSid = data['sid']?.toString() ?? '';
      final String pcSpid = data['spid']?.toString() ?? '';
      String sid = '';
      String spid = '';
      try {
        final String storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          final Map<String, dynamic> storeMap =
              jsonDecode(storeStr) as Map<String, dynamic>;
          sid = storeMap['id']?.toString() ?? '';
          spid = storeMap['spid']?.toString() ?? '';
        }
      } catch (_) {}
      final bool match = pcSid.isNotEmpty && pcSid == sid && pcSpid == spid;
      _logApi(fullUrl, signedData, '主设备探测完成 可达=$match');
      ConnectionManager.pcAlive = match;
      return match;
    }

    ConnectionManager.pcAlive = true;
    _logApi(fullUrl, signedData, '主设备探测成功 pcAlive=true');
    return true;
  } catch (_) {
    _logApi(fullUrl, <String, dynamic>{'data': ''}, '主设备探测异常');
    ConnectionManager.pcAlive = false;
    return false;
  }
}

/// 内部异常类，携带完整接口响应 Map
/// 通过 [response] 可在 .catchError 中获取完整响应数据
class _ApiException implements Exception {
  final Map<String, dynamic> response;
  _ApiException(this.response);

  @override
  String toString() {
    final retmsg = response['retmsg']?.toString() ?? response['message']?.toString();
    return retmsg ?? '接口请求异常';
  }
}
