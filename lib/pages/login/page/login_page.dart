import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/login/login_router.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/res/resources.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sp_util/sp_util.dart';

/// 登录页面 - 红白配色，支持普通登录(商户号+员工工号+密码)和快捷登录(手机号+密码)
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 普通登录 controllers
  final TextEditingController _merchantController = TextEditingController(); // 商户号
  final TextEditingController _employeeController = TextEditingController(); // 员工工号
  final TextEditingController _pwdController = TextEditingController(); // 密码

  // 快捷登录 controllers
  final TextEditingController _phoneController = TextEditingController(); // 手机号
  final TextEditingController _phonePwdController = TextEditingController(); // 密码

  final FocusNode _nodeMerchant = FocusNode();
  final FocusNode _nodeEmployee = FocusNode();
  final FocusNode _nodePwd = FocusNode();
  final FocusNode _nodePhone = FocusNode();
  final FocusNode _nodePhonePwd = FocusNode();

  bool _isLoading = false;
  bool _isShowPwd = false;
  bool _isShowPhonePwd = false;
  bool _agreed = true;
  bool _rememberPwd = false;
  int _loginType = 0; // 0: 快捷登录(手机号), 1: 普通登录(商户号+员工工号)，默认快捷登录
  String _appVersion = '';
  String _buildNumber = ''; // 版本构建号，登录接口 vcode 参数

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    });
    // 恢复记住密码相关状态
    _rememberPwd = SpUtil.getBool(Constant.rememberPwdEnabled) ?? false;
    final savedLoginType = SpUtil.getString(Constant.rememberLoginType);
    _loginType = (savedLoginType != null && savedLoginType.isNotEmpty)
        ? int.tryParse(savedLoginType) ?? 0
        : 0;
    _restoreCredentials();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _employeeController.dispose();
    _pwdController.dispose();
    _phoneController.dispose();
    _phonePwdController.dispose();
    _nodeMerchant.dispose();
    _nodeEmployee.dispose();
    _nodePwd.dispose();
    _nodePhone.dispose();
    _nodePhonePwd.dispose();
    super.dispose();
  }

  /// 验证表单是否可提交（仅判断非空，详细校验在 _login 中提示）
  bool get _canSubmit {
    if (_loginType == 1) {
      return _merchantController.text.isNotEmpty &&
          _employeeController.text.isNotEmpty &&
          _pwdController.text.isNotEmpty;
    } else {
      return _phoneController.text.isNotEmpty &&
          _phonePwdController.text.isNotEmpty;
    }
  }

  /// 登录入口
  void _login() {
    if (!_agreed) {
      Toast.show('请阅读并勾选用户协议与隐私政策！');
      return;
    }
    if (_loginType == 1) {
      // 普通登录：商户号 + 员工工号 + 密码
      if (_merchantController.text.isEmpty) {
        Toast.show('请输入商户号');
        return;
      }
      if (_employeeController.text.isEmpty) {
        Toast.show('请输入员工工号');
        return;
      }
      if (_pwdController.text.isEmpty) {
        Toast.show('请输入密码');
        return;
      }
    } else {
      // 快捷登录：手机号 + 密码
      if (_phoneController.text.isEmpty || _phoneController.text.length != 11) {
        Toast.show('请输入正确的手机号');
        return;
      }
      if (_phonePwdController.text.isEmpty) {
        Toast.show('请输入密码');
        return;
      }
    }

    setState(() => _isLoading = true);
    _getStoreList();
  }

  /// 第一步：获取商户列表（判断是否绑定多个商户）
  Future<void> _getStoreList() async {
    final Map<String, dynamic> params;
    if (_loginType == 1) {
      // 普通登录：account=商户号, code=员工工号, pwd=密码
      params = {
        'mobile': '',
        'pwd': _pwdController.text,
        'code': _employeeController.text,
        'account': _merchantController.text,
      };
    } else {
      // 快捷登录：mobile=手机号, pwd=密码
      params = {
        'mobile': _phoneController.text,
        'pwd': _phonePwdController.text,
        'code': '',
        'account': '',
      };
    }

    try {
      final result = await requestForm(HttpApi.mobileStoreList, params);
      final data = result['data'];
      List<dynamic> stores = [];
      if (data is List) {
        stores = data;
      } else if (data is Map && data['list'] is List) {
        stores = data['list'] as List<dynamic>;
      }

      if (stores.length > 1) {
        // 多商户：弹窗选择
        if (mounted) {
          _showStoreSelectionDialog(stores);
        }
      } else {
        // 单商户或无列表：直接登录（与 smdcapp 一致，单商户不传 userid）
        if (stores.length == 1) {
          final Map<String, dynamic> store =
              Map<String, dynamic>.from(stores[0] as Map);
          // 保存 sid / spid
          SpUtil.putString(Constant.store, json.encode({
            'id': store['sid']?.toString() ?? '0',
            'spid': store['spid']?.toString() ?? '0',
          }));
        }
        _doLogin('');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 第二步：执行登录
  Future<void> _doLogin(String userid) async {
    final Map<String, dynamic> params;
    if (_loginType == 1) {
      // 普通登录(商户号)：account=商户号, code=员工工号, pwd=密码
      params = {
        'account': _merchantController.text,
        'code': _employeeController.text,
        'pwd': _pwdController.text,
        'vcode': _buildNumber,
      };
    } else {
      // 快捷登录(手机号)：mobile=手机号, userid=多商户选择时传入, pwd=密码
      params = {
        'mobile': _phoneController.text,
        'userid': userid,
        'pwd': _phonePwdController.text,
        'vcode': _buildNumber,
      };
    }

    try {
      final result = await requestForm(HttpApi.yttLogin, params);
      final raw = result['data'];
      final Map<String, dynamic> data =
          raw is Map ? Map<String, dynamic>.from(raw) : result;

      // 保存登录信息
      SpUtil.putString(Constant.token, data['token']?.toString() ?? '');
      SpUtil.putString(Constant.accessToken, data['token']?.toString() ?? '');
      SpUtil.putString(Constant.user, json.encode(data['user'] ?? {}));
      SpUtil.putString(Constant.rolemap, json.encode(data['rolemap'] ?? {}));
      SpUtil.putString(Constant.allLoginData, json.encode(data));

      // 保存 store 信息
      if (data['store'] != null) {
        SpUtil.putString(Constant.store, json.encode(data['store']));
      }
      if (data['sysStoreAccount'] != null) {
        SpUtil.putString(Constant.sysStoreAccount, json.encode(data['sysStoreAccount']));
      }
      // 保存参数配置（对齐 smdcapp LoginModel.handleResponse params 处理：
      // 清除旧参数 → 保存完整 JSON → 逐项存储 code→value，供业务按 code 直接读取）
      if (data['params'] is List) {
        final List<dynamic> paramsList = data['params'] as List<dynamic>;
        SpUtil.putString(Constant.loginParamResp, json.encode(paramsList));
        ParamsSpUtils.saveParams(paramsList);
      }

      // 保存 verservicelist 及 615/612 标志（对齐 smdcapp: putVerService615/612）
      SpUtil.putBool(Constant.verservice615, false);
      SpUtil.putBool(Constant.verservice612, false);
      if (data['verservicelist'] is List) {
        final List<dynamic> verList = data['verservicelist'] as List<dynamic>;
        SpUtil.putString(Constant.verserviceList, json.encode(verList));
        for (final item in verList) {
          if (item is Map) {
            final int verid = int.tryParse(item['verid']?.toString() ?? '') ?? 0;
            final int status = int.tryParse(item['status']?.toString() ?? '') ?? 0;
            if (verid == 615 && status == 1) {
              SpUtil.putBool(Constant.verservice615, true); // 聚合外卖平台
            }
            if (verid == 612 && status == 1) {
              SpUtil.putBool(Constant.verservice612, true); // 抖音/美团核销
            }
          }
        }
      }

      // 保存主设备停用标志（对齐 smdcapp: putMastermachstopflag，0启用 1停止）
      SpUtil.putInt(Constant.mastermachstopflag,
          int.tryParse(data['mastermachstopflag']?.toString() ?? '') ?? 1);

      // 保存 role 折扣权限上限（对齐 smdcapp: monthdiscountamt/prodiscount/orderdiscount/progiveamt）
      if (data['role'] is Map) {
        final Map<String, dynamic> role =
            Map<String, dynamic>.from(data['role'] as Map);
        SpUtil.putDouble(Constant.monthDiscountAmt,
            double.tryParse(role['monthdiscountamt']?.toString() ?? '') ?? 0);
        SpUtil.putDouble(Constant.proDiscount,
            double.tryParse(role['prodiscount']?.toString() ?? '') ?? 0);
        SpUtil.putDouble(Constant.orderDiscount,
            double.tryParse(role['orderdiscount']?.toString() ?? '') ?? 0);
        SpUtil.putDouble(Constant.proGiveAmt,
            double.tryParse(role['progiveamt']?.toString() ?? '') ?? 0);
      }

      // 保存最大单号（对齐 smdcapp: SpUtils.billNoMax）
      if (data['billno'] != null) {
        SpUtil.putString(Constant.billNoMax, data['billno'].toString());
      }

      // 保存主设备地址（登录响应的 localhost 字段），用于后续直连PC模式
      ConnectionManager.saveLocalhost(data['localhost']?.toString() ?? '');

      // 保存 RabbitMQ 推送配置（对齐 smdcapp LoginModel: rabbitaddress/mach/store）
      SpUtil.putString(Constant.rabbitAddress,
          data['rabbitaddress']?.toString() ?? 'ysp01.yun8609.net');
      SpUtil.putInt(Constant.rabbitPort,
          int.tryParse(data['rabbitport']?.toString() ?? '') ?? 5672);
      if (data['mach'] is Map) {
        SpUtil.putString(Constant.machNo,
            (data['mach'] as Map)['code']?.toString() ?? '');
      }
      if (data['store'] is Map) {
        final Map<String, dynamic> store =
            Map<String, dynamic>.from(data['store'] as Map);
        SpUtil.putString(Constant.storeCode, store['code']?.toString() ?? '');
        SpUtil.putString(Constant.businessNumber, store['account']?.toString() ?? '');
      }

      // 保存 pstore（总店）功能标志（对齐 smdcapp LoginBean.pstore）
      if (data['pstore'] is Map) {
        final Map<String, dynamic> pstore =
            Map<String, dynamic>.from(data['pstore'] as Map);
        SpUtil.putString(Constant.pstoreVipflag, pstore['vipflag']?.toString() ?? '');
        SpUtil.putString(Constant.pstoreTakeoutflag, pstore['takeoutflag']?.toString() ?? '');
        SpUtil.putString(Constant.pstoreMiniverflag, pstore['miniverflag']?.toString() ?? '');
        SpUtil.putString(Constant.pstorePaytype, pstore['paytype']?.toString() ?? '');
        SpUtil.putString(Constant.pstoreMobilepay, pstore['mobilepay']?.toString() ?? '');
      }

      // 保存 mach（设备）完整字段（对齐 smdcapp LoginBean.mach）
      if (data['mach'] is Map) {
        final Map<String, dynamic> mach =
            Map<String, dynamic>.from(data['mach'] as Map);
        SpUtil.putString(Constant.machTerminalsnLeshua,
            mach['terminalsn_leshua']?.toString() ?? '');
        SpUtil.putString(Constant.machGettakeoutorder,
            mach['gettakeoutorder']?.toString() ?? '');
        SpUtil.putString(Constant.machMasterflag,
            mach['masterflag']?.toString() ?? '');
        SpUtil.putString(Constant.machClienttype,
            mach['clienttype']?.toString() ?? '');
      }

      if (mounted) {
        _saveOrClearCredentials();
        // 登录成功后记录设备基础信息（对齐 smdcapp LoginActivity: JsonWriter.initLogInfo）
        FileLogWriter.instance.logDeviceInfo();
        //Toast.show('登录成功');
        // 登录成功后进入数据交换页，一次性下载全部基础表数据（对齐 smdcapp: 登录 → checkPC → downTable → ChangeDataPopup）
        NavigatorUtils.push(context, LoginRouter.dataExchangePage, clearStack: true);
      }
    } catch (e) {
      debugPrint('登录异常: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 多商户选择弹窗（参考 smdcapp SelectStorePopup）
  void _showStoreSelectionDialog(List<dynamic> stores) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          constraints: const BoxConstraints(maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '选择商户',
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() => _isLoading = false);
                    },
                    child: const Icon(Icons.close, size: 22, color: Color(0xFF999999)),
                  ),
                ],
              ),
              const SizedBox(height: 4.0),
              Text(
                '当前账号关联 ${stores.length} 个商户，请选择',
                style: const TextStyle(fontSize: 13.0, color: Color(0xFF999999)),
              ),
              const SizedBox(height: 12.0),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: stores.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 54),
                  itemBuilder: (context, index) {
                    final Map<String, dynamic> store =
                        Map<String, dynamic>.from(stores[index] as Map);
                    final name = store['name']?.toString() ?? '';
                    final username = store['username']?.toString() ?? '';
                    final account = store['account']?.toString() ?? '';
                    final usercode = store['usercode']?.toString() ?? '';
                    final displayText = name.isNotEmpty
                        ? '$name($username)'
                        : account.isNotEmpty
                            ? '$account($username)'
                            : username;
                    final subText = usercode.isNotEmpty ? '工号: $usercode' : '';
                    return InkWell(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        final userid = store['userid']?.toString() ?? '';
                        // 保存 sid / spid
                        SpUtil.putString(Constant.store, json.encode({
                          'id': store['sid']?.toString() ?? '0',
                          'spid': store['spid']?.toString() ?? '0',
                        }));
                        _doLogin(userid);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colours.app_main,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.store_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  if (subText.isNotEmpty) ...[
                                    const SizedBox(height: 3.0),
                                    Text(
                                      subText,
                                      style: const TextStyle(
                                        fontSize: 12.0,
                                        color: Color(0xFF999999),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Color(0xFFCCCCCC), size: 22),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: Colours.app_main,
        child: SafeArea(
          child: Column(
            children: [
              // 顶部红色区域
              _buildHeader(),
              // 白色卡片登录区域（自适应内容高度，不延伸到底部）
              _buildLoginCard(),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部红色区域：欢迎语 + 应用名 + 版本号 + 右侧插画
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24.0, 40.0, 24.0, 24.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '欢迎使用',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6.0),
                const Text(
                  '聚客美滋滋',
                  style: TextStyle(
                    fontSize: 28.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  _appVersion.isNotEmpty ? 'v$_appVersion' : '',
                  style: const TextStyle(
                    fontSize: 13.0,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          // 右侧插画区：与 smdcapp 一致的登录图片
          Image.asset(
            'assets/images/login/bg_login.png',
            width: 110.0,
            height: 110.0,
          ),
        ],
      ),
    );
  }

  /// 白色登录卡片
  Widget _buildLoginCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      padding: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTabs(),
            const SizedBox(height: 20.0),
            if (_loginType == 1) ..._buildNormalLoginFields(),
            if (_loginType == 0) ..._buildQuickLoginFields(),
            const SizedBox(height: 16.0),
            _buildRememberPwd(),
            const SizedBox(height: 20.0),
            _buildLoginButton(),
            const SizedBox(height: 16.0),
            _buildAgreement(),
          ],
        ),
      ),
    );
  }

  /// Tab 切换：快捷登录 / 普通登录
  Widget _buildTabs() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _switchTab(0),
            child: _buildTabItem('快捷登录', 0),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _switchTab(1),
            child: _buildTabItem('普通登录', 1),
          ),
        ),
      ],
    );
  }

  Widget _buildTabItem(String text, int index) {
    final bool isActive = _loginType == index;
    return Container(
      height: 56.0,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: isActive ? 17.0 : 15.0,
              color: isActive ? Colours.app_main : const Color(0xFF666666),
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6.0),
          Container(
            width: 28.0,
            height: 3.0,
            decoration: BoxDecoration(
              color: isActive ? Colours.app_main : Colors.transparent,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ),
    );
  }

  void _switchTab(int index) {
    if (_loginType == index) {
      return;
    }
    setState(() {
      _loginType = index;
    });
  }

  /// 普通登录输入框：商户号 + 员工工号 + 密码
  List<Widget> _buildNormalLoginFields() {
    return [
      _buildInputField(
        icon: Icons.store_outlined,
        hint: '请输入商户号',
        controller: _merchantController,
        focusNode: _nodeMerchant,
        keyboardType: TextInputType.number,
        maxLength: 8,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9]'))],
      ),
      const SizedBox(height: 14.0),
      _buildInputField(
        icon: Icons.person_outline,
        hint: '请输入员工工号',
        controller: _employeeController,
        focusNode: _nodeEmployee,
        keyboardType: TextInputType.number,
        maxLength: 20,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9]'))],
      ),
      const SizedBox(height: 14.0),
      _buildInputField(
        icon: Icons.lock_outline,
        hint: '请输入密码',
        controller: _pwdController,
        focusNode: _nodePwd,
        obscureText: !_isShowPwd,
        keyboardType: TextInputType.visiblePassword,
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp('[\u4e00-\u9fa5]'))],
        isLast: true,
        suffixIcon: GestureDetector(
          onTap: () => setState(() => _isShowPwd = !_isShowPwd),
          child: Icon(
            _isShowPwd ? Icons.visibility : Icons.visibility_off,
            color: const Color(0xFFBBBBBB),
            size: 20.0,
          ),
        ),
      ),
    ];
  }

  /// 快捷登录输入框：手机号 + 密码
  List<Widget> _buildQuickLoginFields() {
    return [
      _buildInputField(
        icon: Icons.phone_android,
        hint: '请输入手机号',
        controller: _phoneController,
        focusNode: _nodePhone,
        keyboardType: TextInputType.phone,
        maxLength: 11,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9]'))],
      ),
      const SizedBox(height: 14.0),
      _buildInputField(
        icon: Icons.lock_outline,
        hint: '请输入密码',
        controller: _phonePwdController,
        focusNode: _nodePhonePwd,
        obscureText: !_isShowPhonePwd,
        keyboardType: TextInputType.visiblePassword,
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp('[\u4e00-\u9fa5]'))],
        isLast: true,
        suffixIcon: GestureDetector(
          onTap: () => setState(() => _isShowPhonePwd = !_isShowPhonePwd),
          child: Icon(
            _isShowPhonePwd ? Icons.visibility : Icons.visibility_off,
            color: const Color(0xFFBBBBBB),
            size: 20.0,
          ),
        ),
      ),
    ];
  }

  /// 通用输入框组件
  Widget _buildInputField({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFBBBBBB), size: 22.0),
          const SizedBox(width: 10.0),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscureText,
              keyboardType: keyboardType,
              maxLength: maxLength,
              inputFormatters: inputFormatters,
              textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (isLast) {
                  _login();
                }
              },
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 14.0, color: Color(0xFFAAAAAA)),
                counterText: '',
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14.0),
              ),
              style: const TextStyle(fontSize: 15.0, color: Colours.text),
            ),
          ),
          if (suffixIcon != null) suffixIcon,
        ],
      ),
    );
  }

  /// 记住密码
  Widget _buildRememberPwd() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _rememberPwd = !_rememberPwd;
          if (!_rememberPwd) {
            _clearCredentials();
          }
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 16.0,
            height: 16.0,
            decoration: BoxDecoration(
              color: _rememberPwd ? Colours.app_main : Colors.transparent,
              borderRadius: BorderRadius.circular(3.0),
              border: Border.all(
                color: _rememberPwd ? Colours.app_main : const Color(0xFFCCCCCC),
                width: 1.5,
              ),
            ),
            child: _rememberPwd
                ? const Icon(Icons.check, size: 12.0, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 6.0),
          const Text(
            '记住密码',
            style: TextStyle(fontSize: 13.0, color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }

  /// 登录按钮
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 48.0,
      child: ElevatedButton(
        onPressed: (_canSubmit && !_isLoading) ? _login : null,
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return const Color(0xFFF5A8A2);
            }
            return Colours.app_main;
          }),
          foregroundColor: MaterialStateProperty.all(Colors.white),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
          ),
          elevation: MaterialStateProperty.all(0),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20.0,
                height: 20.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                '登录',
                style: TextStyle(
                  fontSize: 17.0,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
      ),
    );
  }

  /// 协议区域
  Widget _buildAgreement() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _agreed = !_agreed),
          child: Container(
            width: 18.0,
            height: 18.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _agreed ? Colours.app_main : Colors.transparent,
              border: Border.all(
                color: _agreed ? Colours.app_main : const Color(0xFFCCCCCC),
                width: 1.5,
              ),
            ),
            child: _agreed
                ? const Icon(Icons.check, size: 12.0, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 6.0),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12.0, color: Color(0xFF666666)),
              children: [
                const TextSpan(text: '我已阅读并同意'),
                TextSpan(
                  text: '《用户协议》',
                  style: const TextStyle(color: Colours.app_main, fontSize: 12.0),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      NavigatorUtils.goAssetHtmlPage(
                        context, '用户协议', 'assets/data/user_agreement.html');
                    },
                ),
                const TextSpan(text: '和'),
                TextSpan(
                  text: '《隐私政策》',
                  style: const TextStyle(color: Colours.app_main, fontSize: 12.0),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      NavigatorUtils.goAssetHtmlPage(
                        context, '隐私政策', 'assets/data/privacy_policy.html');
                    },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ========== 记住密码相关 ==========

  void _saveCredentials() {
    if (_loginType == 1) {
      SpUtil.putString(Constant.rememberMerchantCode, _merchantController.text);
      SpUtil.putString(Constant.rememberMerchantAccount, _employeeController.text);
      SpUtil.putString(Constant.rememberMerchantPwd, _pwdController.text);
    } else {
      SpUtil.putString(Constant.rememberPhone, _phoneController.text);
      SpUtil.putString(Constant.rememberPhonePwd, _phonePwdController.text);
    }
    SpUtil.putString(Constant.rememberLoginType, _loginType.toString());
  }

  void _restoreCredentials() {
    if (_loginType == 1) {
      _merchantController.text = SpUtil.getString(Constant.rememberMerchantCode) ?? '';
      _employeeController.text = SpUtil.getString(Constant.rememberMerchantAccount) ?? '';
      _pwdController.text = SpUtil.getString(Constant.rememberMerchantPwd) ?? '';
    } else {
      _phoneController.text = SpUtil.getString(Constant.rememberPhone) ?? '';
      _phonePwdController.text = SpUtil.getString(Constant.rememberPhonePwd) ?? '';
    }
  }

  void _clearCredentials() {
    if (_loginType == 1) {
      SpUtil.remove(Constant.rememberMerchantCode);
      SpUtil.remove(Constant.rememberMerchantAccount);
      SpUtil.remove(Constant.rememberMerchantPwd);
    } else {
      SpUtil.remove(Constant.rememberPhone);
      SpUtil.remove(Constant.rememberPhonePwd);
    }
  }

  void _saveOrClearCredentials() {
    SpUtil.putBool(Constant.rememberPwdEnabled, _rememberPwd);
    if (_rememberPwd) {
      _saveCredentials();
    } else {
      _clearCredentials();
    }
  }

  /// 动态加载版本号
  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber;
      _buildNumber = build;
      _appVersion = build.isNotEmpty ? '${info.version}.$build' : info.version;
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }
}
