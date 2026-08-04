import 'package:flutter/material.dart';
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '用户授权-${widget.title}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: const Icon(Icons.close, size: 20, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 授权方式切换 Tab（对齐 smdcapp tvSqm/tvYhm）
              Row(
                children: [
                  _buildTabButton('授权码', _type == '0', () => _switchType('0')),
                  _buildTabButton('用户名', _type == '1', () => _switchType('1')),
                ],
              ),
              const SizedBox(height: 16),
              // 授权码/用户名输入框
              TextField(
                controller: _codeController,
                obscureText: _type == '0',
                autofocus: true,
                decoration: InputDecoration(
                  labelText: _type == '0' ? '授权码' : '用户名',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _verify(),
              ),
              // 用户授权模式显示密码框
              if (_type == '1') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '用户密码',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => _verify(),
                ),
              ],
              const SizedBox(height: 20),
              // 按钮行
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _verifying ? null : _verify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE13426),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _verifying
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE13426) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: selected ? Colors.white : Colors.black87,
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
