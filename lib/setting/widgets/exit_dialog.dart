import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/pages/login/login_router.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';

class ExitDialog extends StatelessWidget {
  const ExitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: DialogCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '提示',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '您确定要退出登录吗？',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF4E5969),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: DialogActionButton(
                    text: '取消',
                    primary: false,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DialogActionButton(
                    text: '退出',
                    onTap: () => NavigatorUtils.push(
                      context,
                      LoginRouter.loginPage,
                      clearStack: true,
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
