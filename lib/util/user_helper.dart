import 'dart:convert';

import 'package:sp_util/sp_util.dart';

import '../res/constant.dart';

/// 当前登录用户信息工具类
///
/// 登录接口返回的 user 对象以 JSON 字符串形式存储在 SP（key = Constant.user），
/// 统一通过 [getUserMap] 获取，避免各业务页面重复解析。
class UserHelper {
  UserHelper._();

  /// 获取当前登录用户完整信息 Map（未登录或解析失败返回空 Map）
  static Map<String, dynamic> getUserMap() {
    final String userStr = SpUtil.getString(Constant.user) ?? '';
    if (userStr.isEmpty) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(json.decode(userStr) as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  // ──────────── 常用字段便捷方法 ─────────────────────────────────────────

  /// 用户ID（userid）
  static String getUserid() => getUserMap()['userid']?.toString() ?? '';

  /// 用户ID（id，部分场景用 id 字段）
  static String getId() => getUserMap()['id']?.toString() ?? '';

  /// 用户名（username）
  static String getUsername() => getUserMap()['username']?.toString() ?? '';

  /// 姓名（name，优先取 name，无则回退 username）
  static String getName() =>
      getUserMap()['name']?.toString() ??
      getUserMap()['username']?.toString() ??
      '';

  /// 工号（code）
  static String getCode() => getUserMap()['code']?.toString() ?? '';

  /// 操作员ID（operid）
  static String getOperid() => getUserMap()['operid']?.toString() ?? '';

  /// 角色ID（roleid）
  static String getRoleid() => getUserMap()['roleid']?.toString() ?? '';

  /// 头像URL（imgurl）
  static String getImgurl() => getUserMap()['imgurl']?.toString() ?? '';

  /// 门店ID（spid，登录时单独存储）
  static int getSpid() => SpUtil.getInt('spid') ?? 0;

  /// 门店sid（登录时单独存储）
  static int getSid() => SpUtil.getInt('sid') ?? 0;

  /// 门店sid 字符串形式（对齐 smdcapp SpUtils.getSID：取 store JSON 的 id 字段）
  ///
  /// SP 中 'sid'/'spid' 独立键登录时以 putInt 写入，直接 getString 读取
  /// 会触发类型强转异常（type 'int' is not a subtype of type 'String?'），
  /// 业务需要字符串形式时统一经此方法从 store JSON 解析。
  static String getSidStr() => _storeField('id');

  /// 门店spid 字符串形式（对齐 smdcapp SpUtils.getSPID：取 store JSON 的 spid 字段）
  static String getSpidStr() => _storeField('spid');

  static String _storeField(String field) {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isEmpty) return '0';
      final Map<String, dynamic> storeMap =
          json.decode(storeStr) as Map<String, dynamic>;
      return storeMap[field]?.toString() ?? '0';
    } catch (_) {
      return '0';
    }
  }
}
