import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/log_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 权限授权弹窗（对齐 smdcapp AuthPermissionPopup.kt）
///
/// 用于敏感操作（打折、退菜、赠送等）的权限校验。
/// 支持两种授权方式：
/// - 授权码模式（type=0）：输入授权码，调用 searchUserAuth
/// - 用户授权模式（type=1）：输入用户名+密码，调用 searchUserAuth(usercode/userpwd)
class AuthPermissionDialog extends StatefulWidget {
  const AuthPermissionDialog({
    super.key,
    required this.title,
    required this.codeid,
  });

  /// 弹窗标题（如 "打折"、"退菜"）
  final String title;

  /// 权限码（对齐 smdcapp codeid / menuid）
  final String codeid;

  /// 显示弹窗，返回是否授权成功
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String codeid,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AuthPermissionDialog(title: title, codeid: codeid),
    );
    return result ?? false;
  }

  @override
  State<AuthPermissionDialog> createState() => _AuthPermissionDialogState();
}

class _AuthPermissionDialogState extends State<AuthPermissionDialog> {
  /// 授权类型：0=授权码, 1=用户授权（对齐 smdcapp type）
  String _type = '0';
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _pwdController = TextEditingController();
  bool _verifying = false;

  @override
  void dispose() {
    _codeController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF1D2129);

    return Center(
      child: DialogCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 标题栏
            Row(
              children: <Widget>[
                const SizedBox(width: 26),
                Expanded(
                  child: Text(
                    '用户授权-${widget.title}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 18,
                        color: isDark ? Colors.white54 : const Color(0xFF999999)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 授权方式切换 Tab（对齐 smdcapp tvSqm/tvYhm）
            Row(
              children: <Widget>[
                _buildTabButton('授权码', _type == '0', () => _switchType('0')),
                const SizedBox(width: 12),
                _buildTabButton('用户名', _type == '1', () => _switchType('1')),
              ],
            ),
            const SizedBox(height: 16),
            // 授权码/用户名输入框
            TextField(
              controller: _codeController,
              obscureText: _type == '0',
              autofocus: true,
              style: TextStyle(fontSize: 14, color: textColor),
              decoration: _fieldDecoration(
                hintText: _type == '0' ? '请输入授权码' : '请输入用户名',
                isDark: isDark,
              ),
              onSubmitted: (_) => _verify(),
            ),
            // 用户授权模式显示密码框
            if (_type == '1') ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: _pwdController,
                obscureText: true,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: _fieldDecoration(
                  hintText: '请输入用户密码',
                  isDark: isDark,
                ),
                onSubmitted: (_) => _verify(),
              ),
            ],
            const SizedBox(height: 24),
            // 按钮行
            Row(
              children: <Widget>[
                Expanded(
                  child: DialogActionButton(
                    text: '取消',
                    primary: false,
                    onTap: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DialogActionButton(
                    text: '确定',
                    loading: _verifying,
                    onTap: _verify,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 统一灰色填充输入框（与 InputDialog 保持一致）
  InputDecoration _fieldDecoration({
    required String hintText,
    required bool isDark,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
          fontSize: 14,
          color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4)),
      filled: true,
      fillColor: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF7F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
            color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
            width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE63F31), width: 1.2),
      ),
    );
  }

  Widget _buildTabButton(String label, bool selected, VoidCallback onTap) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE63F31)
                : (isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F3F5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white70 : const Color(0xFF4E5969)),
            ),
          ),
        ),
      ),
    );
  }

  void _switchType(String type) {
    setState(() {
      _type = type;
      _codeController.clear();
      _pwdController.clear();
    });
  }

  /// 验证授权（对齐 smdcapp AuthPermissionPopup.ok）
  Future<void> _verify() async {
    final String code = _codeController.text.trim();
    if (code.isEmpty) {
      Toast.show(_type == '0' ? '请输入授权码' : '请输入用户名');
      return;
    }
    if (_type == '1') {
      final String pwd = _pwdController.text.trim();
      if (pwd.isEmpty) {
        Toast.show('请输入用户密码');
        return;
      }
    }

    setState(() => _verifying = true);
    try {
      bool success;
      if (_type == '0') {
        success = await _verifyAuthCode(code);
      } else {
        success = await _verifyUserAuth(code, _pwdController.text.trim());
      }
      if (!mounted) return;
      if (success) {
        Navigator.pop(context, true);
      } else {
        Toast.show('授权失败');
      }
    } catch (e) {
      Log.e('AuthPermissionDialog._verify error: $e');
      if (mounted) Toast.show('授权失败');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// 授权码验证（对齐 smdcapp searchUserAuth）
  ///
  /// 授权码格式：
  /// - 不含 "-"：直接验证 rfid
  /// - 含 "-"：格式为 "code-time"，拆分后验证
  Future<bool> _verifyAuthCode(String codeEt) async {
    try {
      if (!codeEt.contains('-')) {
        // 普通授权码（对齐 smdcapp searchUserAuthSQM）
        await requestForm(HttpApi.searchUserAuth, <String, dynamic>{
          'menuid': widget.codeid,
          'rfid': codeEt,
        }, showError: false);
      } else {
        // 带时间的授权码（对齐 smdcapp searchUserAuth(codeid, code, time)）
        final List<String> parts = codeEt.split('-');
        if (parts.length < 2 || parts[1].isEmpty) {
          return false;
        }
        await requestForm(HttpApi.searchUserAuth, <String, dynamic>{
          'menuid': widget.codeid,
          'rfid': parts[0],
          'time': parts[1],
        }, showError: false);
      }
      // requestForm 失败时抛异常，到达此处即为授权成功
      return true;
    } catch (e) {
      Log.e('AuthPermissionDialog._verifyAuthCode error: $e');
      return false;
    }
  }

  /// 用户授权验证（对齐 smdcapp searchUserAuthUser）
  Future<bool> _verifyUserAuth(String usercode, String userpwd) async {
    try {
      await requestForm(HttpApi.searchUserAuth, <String, dynamic>{
        'usercode': usercode,
        'userpwd': userpwd,
        'menuid': widget.codeid,
      }, showError: false);
      // requestForm 失败时抛异常，到达此处即为授权成功
      return true;
    } catch (e) {
      Log.e('AuthPermissionDialog._verifyUserAuth error: $e');
      return false;
    }
  }
}
