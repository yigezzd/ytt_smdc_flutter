import 'package:flutter/material.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 连接状态底部弹窗（对齐 smdcapp ConnectionTypeDialog）
///
/// 点击桌台标题栏的网络状态图标后弹出，展示主设备与云服务的实时连接状态：
/// - 主设备行：绿色/红色 PC 图标 + "----当前连接"（仅当前模式为主设备时显示）
/// - 云服务器行：绿色/红色 云图标 + "----当前连接"（仅当前模式为云服务时显示）
class ConnectionStatusSheet extends StatefulWidget {
  const ConnectionStatusSheet({super.key});

  @override
  State<ConnectionStatusSheet> createState() => _ConnectionStatusSheetState();
}

class _ConnectionStatusSheetState extends State<ConnectionStatusSheet> {
  /// 主设备连接状态：null=检测中, true=成功, false=失败
  bool? _pcConnected;

  /// 云服务连接状态：null=检测中, true=成功, false=失败
  bool? _yunConnected;

  @override
  void initState() {
    super.initState();
    _checkConnections();
  }

  /// 同时检测主设备与云服务连接状态（对齐 smdcapp isPcAvailable + isNetworkAvailable）
  Future<void> _checkConnections() async {
    // 并行检测
    final results = await Future.wait(<Future<bool>>[
      _checkPc(),
      _checkYun(),
    ]);
    if (mounted) {
      setState(() {
        _pcConnected = results[0];
        _yunConnected = results[1];
      });
    }
  }

  /// 检测主设备连接（对齐 smdcapp PCTableHttpUtil.getHostSyncTime）
  Future<bool> _checkPc() async {
    try {
      return await checkMasterDeviceAlive();
    } catch (_) {
      return false;
    }
  }

  /// 检测云服务连接（对齐 smdcapp TableHttpUtil.getAreaList 简单请求验证可达性）
  Future<bool> _checkYun() async {
    try {
      await requestForm(
        HttpApi.tableAreaList,
        <String, dynamic>{
          'sid': '0',
          'name': '',
          'type': 2,
          'page': 1,
          'rows': 1,
          'flag': 1,
        },
        showError: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // 当前连接模式：1=主设备 2=云服务（对齐 smdcapp SpUtils.getNetMode）
    final int netMode = ConnectionManager.getNetMode();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2D2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildTitle(isDark),
          const SizedBox(height: 10),
          _buildPcRow(isDark, netMode),
          const SizedBox(height: 15),
          _buildYunRow(isDark, netMode),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// 标题行：红色竖线 + "连接状态" + 关闭按钮（对齐 smdcapp connect_type_dialog 标题区）
  Widget _buildTitle(bool isDark) {
    return Row(
      children: <Widget>[
        // 红色竖线（对齐 smdcapp 3dp red bar）
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFFE13426),
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '连接状态',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
        ),
        // 关闭按钮（对齐 smdcapp ll_close + login_icon_del）
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: Icon(
                Icons.cancel,
                size: 22,
                color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 主设备行（对齐 smdcapp ll_pc）
  Widget _buildPcRow(bool isDark, int netMode) {
    final bool isCurrentMode = netMode == 1;
    return Container(
      height: 49,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3C3D) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E5E5),
          width: 0.5,
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '主设备：',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const Spacer(),
          // 状态图标（对齐 smdcapp iv_status: ic_pc_success / ic_pc_error）
          _buildStatusIcon(
            connected: _pcConnected,
            successAsset: 'assets/images/ic_pc_success.png',
            errorAsset: 'assets/images/ic_pc_error.png',
          ),
          const SizedBox(width: 12),
          // "----当前连接" 文案（对齐 smdcapp tv_status1，仅当前模式显示）
          if (isCurrentMode)
            Text(
              '----当前连接',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF686868),
              ),
            ),
          if (isCurrentMode) const SizedBox(width: 20),
        ],
      ),
    );
  }

  /// 云服务器行（对齐 smdcapp ll_online）
  Widget _buildYunRow(bool isDark, int netMode) {
    final bool isCurrentMode = netMode == 2;
    return Container(
      height: 49,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3C3D) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E5E5),
          width: 0.5,
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '云服务器：',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const Spacer(),
          // 状态图标（对齐 smdcapp iv_yun_status: ic_yun_success / ic_yun_error）
          _buildStatusIcon(
            connected: _yunConnected,
            successAsset: 'assets/images/ic_yun_success.png',
            errorAsset: 'assets/images/ic_yun_error.png',
          ),
          const SizedBox(width: 12),
          // "----当前连接" 文案（对齐 smdcapp tv_status2，仅当前模式显示）
          if (isCurrentMode)
            Text(
              '----当前连接',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF686868),
              ),
            ),
          if (isCurrentMode) const SizedBox(width: 20),
        ],
      ),
    );
  }

  /// 状态图标：检测中显示 loading，否则根据结果显示成功/失败图标
  Widget _buildStatusIcon({
    required bool? connected,
    required String successAsset,
    required String errorAsset,
  }) {
    if (connected == null) {
      return const SizedBox(
        width: 36,
        height: 28,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Image.asset(
      connected ? successAsset : errorAsset,
      width: 36,
      height: 28,
      fit: BoxFit.contain,
    );
  }
}
