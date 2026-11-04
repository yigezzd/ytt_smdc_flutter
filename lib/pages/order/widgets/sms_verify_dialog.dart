import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/util/aux_business_service.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 品牌红（与 ConfirmDialog 保持一致）
const Color _kBrandRed = Color(0xFFE63F31);

/// 会员支付短信验证弹窗（对齐 smdcapp PwsPopup 短信验证分支，smstype=7）
///
/// 使用方式：
/// ```dart
/// final bool ok = await SmsVerifyDialog.show(context, mobile: mobile);
/// ```
class SmsVerifyDialog extends StatefulWidget {
  const SmsVerifyDialog({super.key, required this.mobile});

  /// 接收验证码的手机号
  final String mobile;

  /// 弹出短信验证弹窗，返回 true 表示验证通过
  static Future<bool> show(
    BuildContext context, {
    required String mobile,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SmsVerifyDialog(mobile: mobile),
    );
    return result ?? false;
  }

  @override
  State<SmsVerifyDialog> createState() => _SmsVerifyDialogState();
}

class _SmsVerifyDialogState extends State<SmsVerifyDialog> {
  final TextEditingController _codeController = TextEditingController();
  Timer? _timer;
  int _secondsLeft = 0;
  bool _sending = false;

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  /// 手机号脱敏（对齐 smdcapp ToolsUtils.getMemberShowText 模式2）
  String get _maskedMobile {
    final String text = widget.mobile;
    if (text.isEmpty) {
      return '';
    }
    if (text.length >= 11) {
      return '${text.substring(0, 3)}****${text.substring(7)}';
    }
    if (text.length > 5) {
      final int i = (text.length - 4) ~/ 2;
      return '${text.substring(0, i)}****${text.substring(i + 4)}';
    }
    if (text.length == 1) {
      return '${text[0]}****';
    }
    return '${text[0]}****${text[text.length - 1]}';
  }

  /// 获取验证码（60秒倒计时，对齐 smdcapp PwsPopup changeSMS）
  Future<void> _sendCode() async {
    if (_sending || _secondsLeft > 0) {
      return;
    }
    setState(() => _sending = true);
    final bool ok =
        await AuxBusinessService.instance.sendVipPaySmsCode(widget.mobile);
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    if (!ok) {
      return;
    }
    setState(() => _secondsLeft = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _verify() async {
    final String code = _codeController.text.trim();
    if (code.isEmpty) {
      Toast.show('请输入验证码');
      return;
    }
    final bool ok = await AuxBusinessService.instance
        .verifyVipPaySmsCode(mobile: widget.mobile, code: code);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      Toast.show('验证码错误');
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardAvoidingDialogBody(child: _buildCard(context));
  }

  Widget _buildCard(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF1D2129);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '密码校验',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '验证码将发送至 $_maskedMobile',
              style: const TextStyle(fontSize: 13, color: Color(0xFF86909C)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: TextStyle(fontSize: 14, color: textColor),
              decoration: InputDecoration(
                hintText: '请输入验证码',
                hintStyle:
                    const TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                filled: true,
                fillColor: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF7F8FA),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: TextButton(
                  onPressed: _secondsLeft > 0 ? null : _sendCode,
                  child: Text(
                    _secondsLeft > 0 ? '${_secondsLeft}s' : '获取验证码',
                    style: const TextStyle(fontSize: 13, color: _kBrandRed),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFFE5E6EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed, width: 1.2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3A3A3C)
                            : const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? const Color(0xFFCCCCCC)
                              : const Color(0xFF4E5969),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _verify,
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _kBrandRed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
