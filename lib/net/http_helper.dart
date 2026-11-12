import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/db/app_database.dart';
import 'package:flutter_deer/main.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/dio_utils.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/lan_probe.dart';
import 'package:flutter_deer/pages/login/page/login_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sp_util/sp_util.dart';

/// 防止多个并发请求同时触发跳转登录页
bool _isRedirectingToLogin = false;

/// 本文件所有接口调用均为 POST（云服务 JSON、主设备表单编码）
const String _kHttpMethod = 'POST';

/// 主设备探活专用 Dio：独立短超时，避免移动数据下等满全局 15s 连接超时
final Dio _probeDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 2),
    sendTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 5),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
  ),
);

/// 不逐条记录成功流水的接口路径（对齐 smdcapp LoggingInterceptor.IGNORE_PATHS）
///
/// 这些接口响应体大（全量菜品/桌台数据）或调用频繁（桌台列表、主设备探活），
/// 逐条记录会让日志迅速膨胀并淹没有效信息；失败时仍会记录，便于排查。
const List<String> _ignoredLogPaths = <String>[
  '/update/tabledown',
  '/bi/product/getProductList',
  '/bi/type/getTypeListandCode',
  '/table/info/getTableInfoList',
  '/table/area/getAreaList',
  '/api/table/GetTableInfoList',
  '/api/table/QueryTableAreaList',
  '/reserve/findList',
  '/api/host/GetHostSyncTime',
];

/// 记录接口日志
///
/// - 成功与失败都写入 api_log 流水（[FileLogWriter.writeApiLog]），首行携带
///   `接口路径 → 成功/失败 结论 耗时`，便于直接检索定位；
/// - 失败/异常额外写一份到 crash_log（[FileLogWriter.writeErrorLog]），
///   使"出问题时刻"在 crash_log 中仍可一眼看到；
/// - [_ignoredLogPaths] 中的接口成功时不记录（避免日志膨胀），失败仍记录。
void _logApi(
  String url,
  dynamic params,
  String result, {
  bool success = false,
  int elapsedMs = 0,
  String response = '',
}) {
  String path = url;
  try {
    path = Uri.parse(url).path;
  } catch (_) {}
  final String paramsText = params == null ? '' : (params is String ? params : json.encode(params));

  if (success && _ignoredLogPaths.any(path.contains)) return;

  FileLogWriter.instance.writeApiLog(
    method: _kHttpMethod,
    path: path,
    result: result,
    success: success,
    elapsedMs: elapsedMs,
    params: paramsText,
    response: response,
  );
  if (!success) {
    FileLogWriter.instance.writeErrorLog(null, path, paramsText, result);
  }
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
      final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
      sid = storeMap['id']?.toString() ?? '';
      spid = storeMap['spid']?.toString() ?? '';
    }
  } catch (_) {}

  // 从 user 中读取 userid
  String? userid;
  try {
    final String userStr = SpUtil.getString(Constant.user) ?? '';
    if (userStr.isNotEmpty) {
      final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
      userid = userMap['userid']?.toString() ?? userMap['id']?.toString();
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

  final Stopwatch stopwatch = Stopwatch()..start();
  try {
    final Response<String> response = await DioUtils.instance.dio.post<String>(
      fullUrl,
      data: requestData,
    );
    stopwatch.stop();
    final int elapsed = stopwatch.elapsedMilliseconds;
    final String content = response.data.toString();
    final Map<String, dynamic> jsonMap = json.decode(content) as Map<String, dynamic>;

    if (jsonMap.containsKey('retcode')) {
      final dynamic retcode = jsonMap['retcode'];
      final String retmsg = jsonMap['retmsg']?.toString() ?? '请求失败';
      if (retcode == 0) {
        _logApi(fullUrl, params, 'retcode=0', success: true, elapsedMs: elapsed, response: content);
        return jsonMap;
      }
      if (retcode == -2 || retcode == -3) {
        // 登录信息失效：清除缓存并跳转登录页
        _logApi(fullUrl, params, 'retcode=$retcode retmsg=$retmsg',
            elapsedMs: elapsed, response: content);
        _handleLoginExpired(retmsg);
        throw _ApiException(jsonMap);
      }
      if (showError && retmsg.isNotEmpty) {
        Toast.show(retmsg);
      }
      _logApi(fullUrl, params, 'retcode=$retcode retmsg=$retmsg',
          elapsedMs: elapsed, response: content);
      throw _ApiException(jsonMap);
    }
    // 兼容非 retcode 格式（如拦截器包装的 code/message）
    if (jsonMap['code'] == 0) {
      _logApi(fullUrl, params, 'code=0', success: true, elapsedMs: elapsed, response: content);
      return jsonMap;
    }
    final String msg = jsonMap['message']?.toString() ?? '请求失败';
    if (showError && msg.isNotEmpty) {
      Toast.show(msg);
    }
    _logApi(fullUrl, params, 'code=${jsonMap['code']} message=$msg',
        elapsedMs: elapsed, response: content);
    throw _ApiException(jsonMap);
  } on _ApiException {
    // 业务异常直接向上抛出（已 Toast）
    rethrow;
  } catch (e) {
    // 网络异常 / DioException —— 始终提取真实错误信息，不论 showError
    String errorMsg = '网络请求异常';
    String respText = '';
    if (e is DioException) {
      if (e.response?.data != null) {
        try {
          final dynamic respData = e.response!.data;
          respText = respData.toString();
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
      } else {
        // 无响应体时（超时/连接拒绝等）统一中文提示，避免把 Dio 英文原文暴露给商家
        errorMsg = _friendlyNetworkError(e);
      }
    }
    if (showError) Toast.show(errorMsg);
    _logApi(fullUrl, params, '异常: $errorMsg',
        elapsedMs: stopwatch.elapsedMilliseconds, response: respText);
    throw _ApiException(<String, dynamic>{'retcode': -1, 'retmsg': errorMsg});
  }
}

/// 强制下线处理：弹窗提示 → 清除缓存 → 跳转登录页
///
/// 供 MQ retcode=6（后台数据清空/强制下线）等外部通道调用。
void handleForceLogout(String retmsg) {
  if (_isRedirectingToLogin) return;
  _isRedirectingToLogin = true;

  void finish() {
    _clearCachePreservingRemember();
    _navigateToLogin();
    // 跳转完成后释放防重入标记，否则重新登录后再次被踢下线会被忽略
    Future.delayed(const Duration(seconds: 3), () {
      _isRedirectingToLogin = false;
    });
  }

  final navigatorState = MyApp.navigatorKey.currentState;
  if (navigatorState == null) {
    // navigator 未就绪，降级为直接跳转
    finish();
    return;
  }

  showDialog<void>(
    context: navigatorState.context,
    barrierDismissible: false,
    builder: (ctx) => ConfirmDialog(
      content: retmsg.isNotEmpty ? retmsg : '您已被强制下线，请重新登录',
      singleButton: true,
    ),
  ).then((_) => finish());
}

void _handleLoginExpired(String retmsg) {
  if (_isRedirectingToLogin) return;
  _isRedirectingToLogin = true;

  Toast.show(retmsg.isNotEmpty ? retmsg : '登录信息失效，请重新登录');

  Future.delayed(const Duration(seconds: 2), () {
    _clearCachePreservingRemember();
    _navigateToLogin();

    Future.delayed(const Duration(seconds: 3), () {
      _isRedirectingToLogin = false;
    });
  });
}

/// 清除会话缓存，保留记住密码与本机参数设置
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
  const localSettingKeys = <String>[
    Constant.serverType,
    'print_bill',
    Constant.settleDy,
    'full_payment',
    'ENABLE_NFC',
    'ENABLE_KD',
    'ENABLE_PRODUCT_NUM',
    'WeightTwoConfirm',
    'KQ_ZJ',
    'ClockTableFlag',
    'qy_print',
    'setting_ShowWaiter',
    'setting_product_is_scans',
    'setting_show_display_waiter',
    'setting_show_public_cook',
    'setting_check_down_goods',
    'setting_single_cook',
  ];
  final localSettings = <String, dynamic>{};
  for (final key in localSettingKeys) {
    final value = SpUtil.getDynamic(key);
    if (value != null) {
      localSettings[key] = value;
    }
  }

  SpUtil.clear();

  // 恢复字符串类型数据
  rememberKeys.forEach((key, value) {
    SpUtil.putString(key, value);
  });

  // 恢复布尔类型数据
  if (rememberPwdEnabled != null) {
    SpUtil.putBool(Constant.rememberPwdEnabled, rememberPwdEnabled);
  }
  localSettings.forEach((key, value) {
    if (value is String) {
      SpUtil.putString(key, value);
    } else if (value is bool) {
      SpUtil.putBool(key, value);
    } else if (value is int) {
      SpUtil.putInt(key, value);
    } else if (value is double) {
      SpUtil.putDouble(key, value);
    }
  });
}

/// 主动退出登录：清除缓存（保留记住密码）并跳转登录页
void logoutAndRedirect(BuildContext context) {
  _clearCachePreservingRemember();
  // 非 Web：退出登录清空本地数据库全部业务表（失败静默，不影响退出流程）
  if (!kIsWeb) {
    AppDatabase.instance.clearAll().then((_) {}, onError: (Object e) {
      debugPrint('本地数据库清库失败: $e');
    });
  }
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
  if (!fullUrl.contains('app/update/tabledown') && !fullUrl.contains('reserve/findList')) {
    all['url_info'] = path;
  }

  // 公共参数（登录阶段 sid/spid/token 均为空，默认 0/""）
  String sid = '0';
  String spid = '0';
  try {
    final String storeStr = SpUtil.getString(Constant.store) ?? '';
    if (storeStr.isNotEmpty) {
      final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
      sid = storeMap['id']?.toString() ?? '0';
      spid = storeMap['spid']?.toString() ?? '0';
    }
  } catch (_) {}
  String operid = '0';
  String opername = '';
  try {
    final String userStr = SpUtil.getString(Constant.user) ?? '';
    if (userStr.isNotEmpty) {
      final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
      operid = userMap['userid']?.toString() ?? userMap['id']?.toString() ?? '0';
      opername = userMap['name']?.toString() ?? userMap['username']?.toString() ?? '';
    }
  } catch (_) {}

  String appVerName = '';
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    appVerName = info.version;
  } catch (_) {}

  // 对齐 smdcapp EncryptKey.StrEncrypt：machserial 取设备标识（缺省"0000"），
  // machno 取登录分配的机号（缺省"0"），opername 取当前登录用户名。
  // 此前写死 0000/0/'' 与 smdcapp 不一致，影响云服务端按机号关联数据的行为。
  String machserial = '';
  try {
    machserial = Device.getDeviceSerial();
  } catch (_) {}
  all['machserial'] = machserial.isNotEmpty ? machserial : '0000';
  final String machno = SpUtil.getString(Constant.machNo) ?? '';
  all['machno'] = machno.isNotEmpty ? machno : '0';
  all['opername'] = opername;
  all['client'] = 'APP';
  all['token'] = SpUtil.getString(Constant.token) ?? '';
  all['sid'] = sid;
  all['spid'] = spid;
  all['operid'] = operid;
  // 对齐 smdcapp EncryptKey.StrEncrypt: ip 填主设备 localhost 地址
  all['ip'] = ConnectionManager.getLocalhost();
  all['app_v_name'] = appVerName;
  all['temp_request_time'] = _formatNow();
  // 业务参数可显式传 newclient 覆盖默认值（iOS 登录接口传 IOS）
  final String newClient = formData['newclient']?.toString() ?? '';
  all['newclient'] = newClient.isNotEmpty ? newClient : 'YG';
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
  final String baseUrl = ConnectionManager.resolveBaseUrl(masterDevice: masterDevice);
  String fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
  // 规范化路径中的双斜杠（避免 baseUrl 尾部 / 与接口前导 / 重叠），与 smdcapp 保持一致
  final Uri parsed = Uri.parse(fullUrl);
  fullUrl = parsed.replace(path: parsed.path.replaceAll(RegExp('/{2,}'), '/')).toString();

  // 追加公共参数并计算签名
  final Map<String, dynamic> signedData = await _buildSignedParams(formData, fullUrl);

  final Stopwatch stopwatch = Stopwatch()..start();
  try {
    final Response<String> response = await DioUtils.instance.dio.post<String>(
      fullUrl,
      data: signedData,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    stopwatch.stop();
    final int elapsed = stopwatch.elapsedMilliseconds;
    final String content = response.data.toString();
    final Map<String, dynamic> jsonMap = json.decode(content) as Map<String, dynamic>;

    // 主设备响应格式：PCRootDataBean（Success/Message/Data）
    if (jsonMap.containsKey('Success')) {
      final bool success = jsonMap['Success'] == true;
      final String message = jsonMap['Message']?.toString() ?? '请求失败';
      if (success) {
        _logApi(fullUrl, signedData, 'Success=true',
            success: true, elapsedMs: elapsed, response: content);
        return jsonMap;
      }
      if (showError && message.isNotEmpty) {
        Toast.show(message);
      }
      _logApi(fullUrl, signedData, 'Message=$message', elapsedMs: elapsed, response: content);
      throw _ApiException(jsonMap);
    }

    if (jsonMap.containsKey('retcode')) {
      final dynamic retcode = jsonMap['retcode'];
      final String retmsg = jsonMap['retmsg']?.toString() ?? '请求失败';
      if (retcode == 0) {
        _logApi(fullUrl, signedData, 'retcode=0',
            success: true, elapsedMs: elapsed, response: content);
        return jsonMap;
      }
      if (retcode == -2 || retcode == -3) {
        _handleLoginExpired(retmsg);
      } else if (showError && retmsg.isNotEmpty) {
        Toast.show(retmsg);
      }
      _logApi(fullUrl, signedData, 'retcode=$retcode retmsg=$retmsg',
          elapsedMs: elapsed, response: content);
      throw _ApiException(jsonMap);
    }
    // 兼容非 retcode 格式
    if (jsonMap['code'] == 0) {
      _logApi(fullUrl, signedData, 'code=0', success: true, elapsedMs: elapsed, response: content);
      return jsonMap;
    }
    final String msg = jsonMap['message']?.toString() ?? '请求失败';
    if (showError && msg.isNotEmpty) {
      Toast.show(msg);
    }
    _logApi(fullUrl, signedData, 'code=${jsonMap['code']} message=$msg',
        elapsedMs: elapsed, response: content);
    throw _ApiException(jsonMap);
  } on _ApiException {
    rethrow;
  } catch (e) {
    String errorMsg = '网络请求异常';
    String respText = '';
    if (e is DioException) {
      // 主设备请求发生网络层失败（无响应体：连接拒绝/超时等，对齐 smdcapp
      // GlobalEventListener.callFailed → 广播 NetModeEvent），标记主设备丢失
      if (masterDevice && e.response == null) {
        ConnectionManager.notifyMasterDeviceLost();
      }
      if (e.response?.data != null) {
        try {
          final dynamic respData = e.response!.data;
          respText = respData.toString();
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
      } else {
        errorMsg = _friendlyNetworkError(e);
      }
    }
    if (showError) {
      Toast.show(errorMsg);
    }
    _logApi(fullUrl, signedData, '异常: $errorMsg',
        elapsedMs: stopwatch.elapsedMilliseconds, response: respText);
    throw _ApiException(<String, dynamic>{'retcode': -1, 'retmsg': errorMsg});
  }
}

/// 网络层异常统一中文提示（R52：断网/超时不再显示 Dio 英文原文）
String _friendlyNetworkError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
      return '连接超时，请检查网络后重试';
    case DioExceptionType.sendTimeout:
      return '请求超时，请稍后重试';
    case DioExceptionType.receiveTimeout:
      return '响应超时，请稍后重试';
    case DioExceptionType.connectionError:
      return '网络连接失败，请检查网络或主设备';
    case DioExceptionType.badCertificate:
      return '安全证书校验失败，请联系管理员';
    case DioExceptionType.badResponse:
      final int? status = e.response?.statusCode;
      return '服务器异常${status == null ? '' : '（$status）'}，请稍后重试';
    case DioExceptionType.cancel:
      return '请求已取消';
    case DioExceptionType.unknown:
      return '网络异常，请检查网络后重试';
    default:
      return '网络异常，请检查网络后重试';
  }
}

/// 本机是否存在与主设备同网段的网卡（失败时按可达处理，保持原探活行为）
Future<bool> _hasLanRouteTo(String localhost) async {
  // Web 端 dart:io 的 InternetAddress/NetworkInterface 会抛 UnsupportedError，
  // 该网卡枚举优化仅适用于原生移动端，Web 直接按可达处理，避免探活被整体跳过。
  if (kIsWeb) {
    return true;
  }
  try {
    return await isHostInLocalSubnet(Uri.parse(localhost).host);
  } catch (_) {
    return true;
  }
}

Future<bool> checkMasterDeviceAlive({bool updateConnection = true}) async {
  if (ConnectionManager.isCloudOnly) {
    return false;
  }

  bool alive = false;
  final String localhost = ConnectionManager.getLocalhost();
  final String fullUrl = '$localhost${HttpApi.pcGetHostSyncTime}';
  final Stopwatch stopwatch = Stopwatch()..start();
  try {
    if (localhost.isEmpty || !localhost.startsWith('http')) {
      _logApi(HttpApi.pcGetHostSyncTime, null, '登录响应未返回主设备地址，跳过探测');
      return false;
    }
    // 移动数据下本机网卡不在主设备网段，探活必然失败，直接跳过省掉连接超时
    if (!await _hasLanRouteTo(localhost)) {
      ConnectionManager.masterProbeSkipped = true;
      _logApi(HttpApi.pcGetHostSyncTime, null, '本机无与主设备同网段的网卡，跳过探活');
      return false;
    }
    ConnectionManager.masterProbeSkipped = false;
    final Map<String, dynamic> signedData =
        await _buildSignedParams(<String, dynamic>{'data': ''}, fullUrl);
    final Response<String> response = await _probeDio.post<String>(
      fullUrl,
      data: signedData,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    stopwatch.stop();
    final String content = response.data.toString();
    final Map<String, dynamic> jsonMap = json.decode(content) as Map<String, dynamic>;
    final dynamic data = jsonMap['Data'];
    if (jsonMap['Success'] != true || data is! Map) {
      _logApi(fullUrl, signedData, '主设备响应失败或缺少门店信息',
          elapsedMs: stopwatch.elapsedMilliseconds, response: content);
      return false;
    }

    final String pcSid = data['sid']?.toString() ?? '';
    final String pcSpid = data['spid']?.toString() ?? '';
    final Map<String, dynamic> store = jsonDecode(
      SpUtil.getString(Constant.store, defValue: '{}') ?? '{}',
    ) as Map<String, dynamic>;
    final String sid = store['id']?.toString() ?? '';
    final String spid = store['spid']?.toString() ?? '';
    alive = pcSid.isNotEmpty && pcSpid.isNotEmpty && pcSid == sid && pcSpid == spid;
    _logApi(fullUrl, signedData, '可达=$alive (主设备sid=$pcSid 门店sid=$sid)',
        success: alive, elapsedMs: stopwatch.elapsedMilliseconds, response: content);
    return alive;
  } catch (e) {
    _logApi(fullUrl, <String, dynamic>{'data': ''}, '异常: $e',
        elapsedMs: stopwatch.elapsedMilliseconds);
    return false;
  } finally {
    if (updateConnection) {
      ConnectionManager.pcAlive = alive;
    }
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
