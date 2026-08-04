import 'package:flutter/material.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/res/resources.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/setting/provider/theme_provider.dart';
import 'package:flutter_deer/setting/widgets/exit_dialog.dart';
import 'package:flutter_deer/setting/widgets/update_dialog.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/log_upload_utils.dart';
import 'package:flutter_deer/util/order_log_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/click_item.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';

import '../setting_router.dart';


/// design/8设置/index.html
class SettingPage extends StatefulWidget {

  const SettingPage({super.key});

  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(
        centerTitle: '设置',
      ),
      body: Consumer<ThemeProvider>(
        builder: (_, ThemeProvider provider, __) {
          return Column(
            children: <Widget>[
              Gaps.vGap5,
              ClickItem(
                title: '账号管理',
                onTap: () => NavigatorUtils.push(context, SettingRouter.accountManagerPage),
              ),
              ClickItem(
                title: '打印设置',
                onTap: () => NavigatorUtils.push(context, SettingRouter.printSettingPage),
              ),
              if (Device.isMobile) ClickItem(
                title: '清除缓存',
                content: '23.5MB',
                onTap: () {},
              ),
              ClickItem(
                title: '夜间模式',
                content: _getCurrentTheme(),
                onTap: () => NavigatorUtils.push(context, SettingRouter.themePage),
              ),
              if (Device.isMobile) ClickItem(
                title: '检查更新',
                onTap: _showUpdateDialog,
              ),
              if (Device.isMobile) ClickItem(
                title: _isUploading ? '上传日志中...' : '上传日志',
                onTap: _isUploading ? null : _uploadLog,
              ),
              ClickItem(
                title: '关于我们',
                onTap: () => NavigatorUtils.push(context, SettingRouter.aboutPage),
              ),
              ClickItem(
                title: '退出当前账号',
                onTap: _showExitDialog,
              ),
              if (Device.isMobile) ClickItem(
                title: 'Deer Web版',
                onTap: () => NavigatorUtils.goWebViewPage(context, 'Flutter Deer', 'https://simplezhli.github.io/flutter_deer/'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getCurrentTheme() {
    final String? theme = SpUtil.getString(Constant.theme);
    String themeMode;
    switch(theme) {
      case 'Dark':
        themeMode = '开启';
        break;
      case 'Light':
        themeMode = '关闭';
        break;
      default:
        themeMode = '跟随系统';
        break;
    }
    return themeMode;
  }

  void _showExitDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const ExitDialog()
    );
  }

  void _showUpdateDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDialog()
    );
  }

  /// 上传日志（对齐 smdcapp 设置页"上传日志"按钮）
  Future<void> _uploadLog() async {
    setState(() => _isUploading = true);
    try {
      // 1. 先上传敏感操作日志（HTTP 接口）
      await OrderLogUtils.instance.uploadLog();
      // 2. 再 FTP 上传运行日志压缩包
      final result = await LogUploadUtils.uploadLog();
      if (mounted) {
        if (result == '1') {
          Toast.show('上传日志成功');
        } else {
          Toast.show('上传日志失败: $result');
        }
      }
    } catch (e) {
      if (mounted) {
        Toast.show('上传日志失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }
}
