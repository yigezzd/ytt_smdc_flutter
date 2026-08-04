import 'package:flutter/material.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 无法连接主设备提示弹窗（对齐 smdcapp 桌台页的主设备连接校验弹窗）
///
/// 登录成功进入桌台页后，若探测主设备（直连PC）不可达则弹出本弹窗：
/// - [连接云服务]：切换为云服务模式（serverType=2），关闭弹窗继续正常使用
/// - [重连主设备]：重新调用探活接口（GetHostSyncTime），成功则关闭弹窗，失败则保留弹窗
class MasterDeviceCheckDialog extends StatefulWidget {
  const MasterDeviceCheckDialog({super.key});

  @override
  State<MasterDeviceCheckDialog> createState() =>
      _MasterDeviceCheckDialogState();
}

class _MasterDeviceCheckDialogState extends State<MasterDeviceCheckDialog> {
  /// 品牌红（与桌台页保持一致）
  static const Color _brandRed = Color(0xFFE63F31);

  /// 是否正在重连中
  bool _reconnecting = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 与 smdcapp 一致：必须选择"连接云服务"或"重连主设备"，不允许返回键关闭
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildTitle(),
              const SizedBox(height: 16),
              _buildLinkDiagram(),
              const SizedBox(height: 16),
              _buildWarning(),
              const SizedBox(height: 12),
              _buildTroubleshooting(),
              const SizedBox(height: 18),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部标题"提示" + 关闭按钮
  Widget _buildTitle() {
    return Row(
      children: <Widget>[
        const Expanded(
          child: Text(
            '提示',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1D2129),
            ),
          ),
        ),
        GestureDetector(
          onTap: _reconnecting ? null : () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 18, color: Color(0xFF999999)),
          ),
        ),
      ],
    );
  }

  /// 连接链路示意图：PC → × → WiFi → × → 平板（对齐 smdcapp 插图）
  Widget _buildLinkDiagram() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.computer, size: 44, color: Color(0xFF3B3B3B)),
        _buildLinkSegment(hasError: true),
        const Icon(Icons.wifi, size: 40, color: Color(0xFF3B3B3B)),
        _buildLinkSegment(hasError: true),
        const Icon(Icons.tablet_mac, size: 40, color: Color(0xFF3B3B3B)),
      ],
    );
  }

  /// 链路节点之间的连线 + 红色×（中断点）
  Widget _buildLinkSegment({required bool hasError}) {
    return SizedBox(
      width: 36,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(height: 1.5, color: const Color(0xFFD8D8D8)),
          if (hasError)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: _brandRed),
            ),
        ],
      ),
    );
  }

  /// 警告行：⚠️ 无法连接到主设备
  Widget _buildWarning() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.error_outline, size: 18, color: _brandRed),
        SizedBox(width: 6),
        Text(
          '无法连接到主设备',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1D2129),
          ),
        ),
      ],
    );
  }

  /// 灰色背景排查建议区域
  Widget _buildTroubleshooting() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '建议排查以下问题：\n'
        '1、检查PC主设备是否开启并成功登录；\n'
        '2、当前设备是否开启WIFI并成功连上路由器；\n'
        '3、当前设备与PC主设备是否在同一局域网内；',
        style: TextStyle(fontSize: 12.5, color: Color(0xFF666666), height: 1.8),
      ),
    );
  }

  /// 底部操作按钮：[连接云服务]（白底灰边） + [重连主设备]（红色填充，主操作）
  Widget _buildActions() {
    return Row(
      children: <Widget>[
        // 连接云服务：切换为云服务模式
        Expanded(
          child: GestureDetector(
            onTap: _reconnecting
                ? null
                : () {
                    ConnectionManager.setServerType('2');
                    Navigator.of(context).pop();
                    Toast.show('已切换为云服务模式');
                  },
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: const Color(0xFFDDDDDD)),
              ),
              child: const Center(
                child: Text(
                  '连接云服务',
                  style: TextStyle(fontSize: 14, color: Color(0xFF333333)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 重连主设备：重新探活，成功关闭弹窗，失败保留弹窗可继续重试
        Expanded(
          child: GestureDetector(
            onTap: _reconnecting ? null : _reconnect,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: _reconnecting
                    ? _brandRed.withOpacity(0.6)
                    : _brandRed,
                borderRadius: BorderRadius.circular(21),
              ),
              child: Center(
                child: _reconnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        '重连主设备',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 重连主设备：调用探活接口，成功则关闭弹窗，失败则 Toast 提示并保留弹窗
  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    final bool alive = await checkMasterDeviceAlive();
    if (!mounted) {
      return;
    }
    if (alive) {
      Navigator.of(context).pop();
      Toast.show('已连接主设备');
    } else {
      setState(() => _reconnecting = false);
      Toast.show('连接失败，请检查主设备后重试');
    }
  }
}
