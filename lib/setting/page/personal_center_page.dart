import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/login/login_router.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/setting/setting_router.dart';
import 'package:flutter_deer/util/log_upload_utils.dart';
import 'package:flutter_deer/util/order_log_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sp_util/sp_util.dart';

/// 个人中心/设置页（对齐 smdcapp PersonalCenterActivity）
class PersonalCenterPage extends StatefulWidget {
  const PersonalCenterPage({super.key});

  @override
  State<PersonalCenterPage> createState() => _PersonalCenterPageState();
}

class _PersonalCenterPageState extends State<PersonalCenterPage> {
  /// 品牌红（对齐 smdcapp colorPrimary / red_e13426）
  static const Color _brandRed = Color(0xFFE13426);

  String _storeName = '';
  String _businessNumber = '';
  String _userName = '';
  String _machNo = '';
  String _appVersion = '';
  String _avatarUrl = '';

  /// 是否有新版本
  bool _hasNewVersion = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadAppVersion();
    _checkVersion();
  }

  void _loadUserInfo() {
    // 商户名称
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            json.decode(storeStr) as Map<String, dynamic>;
        _storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {
      // ignore
    }

    // 商户号
    _businessNumber = SpUtil.getString(Constant.businessNumber) ?? '';

    // 用户名（对齐 smdcapp: employeeName + "(" + code + ")"）
    // smdcapp UserBean 字段: name(操作员名字), code(员工号), imgurl(头像)
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            json.decode(userStr) as Map<String, dynamic>;
        final String name = userMap['name']?.toString() ?? userMap['username']?.toString() ?? '';
        final String code = userMap['code']?.toString() ?? '';
        _userName = code.isNotEmpty ? '$name($code)' : name;
        // 头像（对齐 smdcapp: NetHelpUtils.getImgAddress() + imgurl）
        final String imgurl = userMap['imgurl']?.toString() ?? '';
        if (imgurl.isNotEmpty && imgurl != 'null') {
          _avatarUrl = 'http://byyoupic.oss-cn-shenzhen.aliyuncs.com/$imgurl';
        }
      }
    } catch (_) {
      // ignore
    }

    // 设备号
    _machNo = SpUtil.getString(Constant.machNo) ?? '';

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _appVersion = 'V${info.version}';
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // ignore
    }
  }

  /// 检查版本更新（对齐 smdcapp LoginHttpUtil.getVersion）
  Future<void> _checkVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String vcode = info.buildNumber;
      final result = await request(
        HttpApi.appCheckVersion,
        <String, dynamic>{
          'vcode': vcode,
          'clienttype': '2',
          'appid': '1',
          'isdebug': '0',
        },
        false, // showLoading
        false, // showError=false，版本检查失败静默处理
      );
      final List<dynamic>? data = result['data'] as List<dynamic>?;
      if (data != null && data.isNotEmpty) {
        _hasNewVersion = true;
        if (mounted) {
          setState(() {});
        }
      }
    } catch (_) {
      // 版本检查失败静默处理
    }
  }

  // ==================== 菜单项点击事件 ====================

  /// 版本更新（对齐 smdcapp cl_update_version → checkVersion）
  void _onVersionUpdate() {
    if (_hasNewVersion) {
      Toast.show('发现新版本，请前往应用商店更新');
    } else {
      Toast.show('当前已是最新版本');
    }
  }

  /// 本机设备号（对齐 smdcapp cl_mach_no → 仅展示）
  void _onDeviceNo() {
    if (_machNo.isNotEmpty) {
      Toast.show('本机设备号: $_machNo');
    } else {
      Toast.show('未获取到设备号');
    }
  }

  /// 日志上传（对齐 smdcapp cl_log_upload → JsonWriter.uploadLog）
  Future<void> _onLogUpload() async {
    Toast.show('上传日志中...');
    try {
      // 1. 先上传敏感操作日志（HTTP 接口，失败静默记录）
      await OrderLogUtils.instance.uploadLog();
      // 2. 再 FTP 上传运行日志压缩包
      final result = await LogUploadUtils.uploadLog();
      if (!mounted) return;
      if (result == '1') {
        Toast.show('日志上传成功');
      } else {
        Toast.show('日志上传失败: $result');
      }
    } catch (e) {
      if (mounted) {
        Toast.show('日志上传失败: $e');
      }
    }
  }

  /// 参数设置（对齐 smdcapp cl_setting → SettingActivity）
  void _onParamSetting() {
    NavigatorUtils.push(context, SettingRouter.paramSettingPage);
  }

  /// 异常订单查询（对齐 smdcapp cl_yc_order → YcOrderActivity）
  void _onAbnormalOrder() {
    NavigatorUtils.push(context, SettingRouter.ycOrderPage);
  }

  /// 数据交换（对齐 smdcapp cl_data_change → ChangeDataPopup type=1，设置页入口默认全量交换）
  void _onDataExchange() {
    NavigatorUtils.push(context, LoginRouter.dataExchangePage,
        arguments: <String, dynamic>{'type': 1});
  }

  /// 交接班（对齐 smdcapp cl_transfer_show → HandWordActivity）
  void _onHandover() {
    NavigatorUtils.push(context, SettingRouter.handoverPage);
  }

  /// 磁卡读取方式（对齐 smdcapp cl_ckdq_show → OptionsPickerView）
  void _onCardReader() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        final List<String> options = ['无', '联迪', 'NFC'];
        final String current = SpUtil.getString('other_device_ck') ?? '无';
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('磁卡读取方式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              ...options.map((opt) => ListTile(
                    title: Text(opt),
                    trailing: current == opt
                        ? const Icon(Icons.check, color: Color(0xFFE13426), size: 20)
                        : null,
                    onTap: () {
                      SpUtil.putString('other_device_ck', opt);
                      Navigator.pop(ctx);
                      setState(() {});
                      Toast.show('已选择: $opt');
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 补单（对齐 smdcapp cl_bd → EditDialog + saleflow）
  Future<void> _onSupplementOrder() async {
    final String? input = await InputDialog.show(
      context,
      title: '补单',
      hintText: '请输入订单号',
      maxLines: 1,
    );
    if (input == null || input.isEmpty || !mounted) {
      return;
    }
    try {
      Toast.show('补单中...');
      final result = await requestForm(
        HttpApi.saleflow,
        <String, dynamic>{
          'data': input,
          'printtype': '1',
          'printalltype': '1',
          'newprinttype': '1',
          'seq': 1,
        },
      );
      // 解析逐条结果（对齐 smdcapp PersonalCenterActivity: retcode==0 才算成功），
      // 不能仅凭顶层 retcode 判成功，否则补单实际失败也会提示成功
      final dynamic data = result['data'] ?? result['Data'];
      bool ok = true;
      String retmsg = result['retmsg']?.toString() ?? '';
      if (data is List && data.isNotEmpty && data[0] is Map<String, dynamic>) {
        final Map<String, dynamic> first = data[0] as Map<String, dynamic>;
        ok = first['retcode'] == 0;
        final String rmsg = first['retmsg']?.toString() ?? '';
        if (rmsg.isNotEmpty) {
          retmsg = rmsg;
        }
      }
      if (ok) {
        Toast.show(retmsg.isNotEmpty ? retmsg : '补单成功');
      } else {
        Toast.show(retmsg.isNotEmpty ? '补单失败：$retmsg' : '补单失败');
      }
    } catch (_) {
      // 拦截器已统一提示错误
    }
  }

  /// 退出登录（对齐 smdcapp tv_exit → TipDialog 确认后跳转 LoginActivity）
  Future<void> _onLogout() async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确认退出当前登录账号？',
    );
    if (confirmed && mounted) {
      NavigatorUtils.push(context, LoginRouter.loginPage, clearStack: true);
    }
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        body: Column(
          children: <Widget>[
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 8),
                    _buildVersionItem(),
                    const SizedBox(height: 4),
                    _buildDeviceNoItem(),
                    const SizedBox(height: 4),
                    _buildMenuItem(
                      icon: Icons.cloud_upload_outlined,
                      title: '日志上传',
                      onTap: _onLogUpload,
                    ),
                    const SizedBox(height: 4),
                    _buildMenuItem(
                      icon: Icons.settings_outlined,
                      title: '参数设置',
                      onTap: _onParamSetting,
                    ),
                    const SizedBox(height: 4),
                    _buildMenuItem(
                      icon: Icons.warning_amber_outlined,
                      title: '异常订单查询',
                      onTap: _onAbnormalOrder,
                    ),
                    const SizedBox(height: 4),
                    _buildMenuItem(
                      icon: Icons.sync_outlined,
                      title: '数据交换',
                      onTap: _onDataExchange,
                    ),
                    const SizedBox(height: 4),
                    _buildMenuItem(
                      icon: Icons.swap_horiz_outlined,
                      title: '交接班',
                      onTap: _onHandover,
                    ),
                    const SizedBox(height: 4),
                    _buildMenuItemWithTrailing(
                      icon: Icons.settings_outlined,
                      title: '磁卡读取方式',
                      trailing: SpUtil.getString('other_device_ck') ?? '无',
                      onTap: _onCardReader,
                    ),
                    const SizedBox(height: 4),
                    _buildMenuItem(
                      icon: Icons.receipt_long_outlined,
                      title: '补单',
                      onTap: _onSupplementOrder,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _buildLogoutButton(),
          ],
        ),
      ),
    );
  }

  /// 顶部红色区域（对齐 smdcapp: TitleLayout + 用户信息区）
  Widget _buildHeader() {
    return ColoredBox(
      color: _brandRed,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // 标题栏
            SizedBox(
              height: 46,
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 20),
                    color: Colors.white,
                    onPressed: () => NavigatorUtils.goBack(context),
                  ),
                  const Expanded(
                    child: Text(
                      '设置',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // 平衡返回按钮宽度
                ],
              ),
            ),
            // 用户信息区
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 8),
                  // 门店名称
                  Text(
                    _storeName.isNotEmpty ? _storeName : '门店',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 商户号
                  Text(
                    '商户号：$_businessNumber',
                    style: const TextStyle(
                      color: Color(0xFFFAB6B5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 头像（对齐 smdcapp: CircleImageView + Glide加载 imgurl）
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(color: Colors.white54, width: 2),
                    ),
                    child: _avatarUrl.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              _avatarUrl,
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                size: 42,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 42,
                            color: Colors.white,
                          ),
                  ),
                  const SizedBox(height: 8),
                  // 用户名(工号)
                  Text(
                    _userName.isNotEmpty ? _userName : '用户',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 版本更新项（对齐 smdcapp cl_update_version: 图标 + 文字 + NEW徽章 + 版本号）
  Widget _buildVersionItem() {
    return _buildCard(
      child: InkWell(
        onTap: _onVersionUpdate,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: Row(
            children: <Widget>[
              const Icon(Icons.system_update_outlined, size: 26, color: _brandRed),
              const SizedBox(width: 12),
              const Text(
                '版本更新',
                style: TextStyle(fontSize: 14, color: Color(0xFF000000)),
              ),
              const Spacer(),
              if (_hasNewVersion)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _brandRed,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (_hasNewVersion) const SizedBox(width: 8),
              Text(
                _appVersion,
                style: const TextStyle(fontSize: 16, color: Color(0xFF000000)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 本机设备号项（对齐 smdcapp cl_mach_no: 图标 + 文字 + 设备号值）
  Widget _buildDeviceNoItem() {
    return _buildCard(
      child: InkWell(
        onTap: _onDeviceNo,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: Row(
            children: <Widget>[
              const Icon(Icons.devices_other_outlined, size: 26, color: Color(0xFF666666)),
              const SizedBox(width: 12),
              const Text(
                '本机设备号',
                style: TextStyle(fontSize: 14, color: Color(0xFF000000)),
              ),
              const Spacer(),
              Text(
                _machNo,
                style: const TextStyle(fontSize: 16, color: Color(0xFF000000)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 通用菜单项（图标 + 标题 + 右箭头）
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return _buildCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 26, color: const Color(0xFF666666)),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCCCCCC)),
            ],
          ),
        ),
      ),
    );
  }

  /// 带右侧文本的菜单项（图标 + 标题 + trailing文字 + 右箭头）
  Widget _buildMenuItemWithTrailing({
    required IconData icon,
    required String title,
    required String trailing,
    required VoidCallback onTap,
  }) {
    return _buildCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 26, color: const Color(0xFF666666)),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
              ),
              const Spacer(),
              Text(
                trailing,
                style: const TextStyle(fontSize: 14, color: Color(0xFF999999)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCCCCCC)),
            ],
          ),
        ),
      ),
    );
  }

  /// 白色圆角卡片容器（对齐 smdcapp white_rounded6_bg_v2）
  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }

  /// 底部退出登录按钮（对齐 smdcapp tv_exit: gray_shape_radius3dp）
  Widget _buildLogoutButton() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 20),
        child: GestureDetector(
          onTap: _onLogout,
          child: Container(
            width: double.infinity,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              '退出登录',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF000000),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
