import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/mq_service.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/pages/home/table/table_repository.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/table_data_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 桌台并发操作守卫（对齐 smdcapp 锁台逻辑）
///
/// - 点击桌台前拉取最新桌台状态，避免使用列表缓存里的旧状态；
/// - 点菜/订单/结账页收到其他设备的锁台 MQ 时提示并返回桌台页；
/// - 提供统一的锁台/解锁接口封装，供点菜页自动锁台使用。
class TableConcurrencyGuard {
  TableConcurrencyGuard._();

  /// 是否启用锁台（对齐 smdcapp ConstantSetKey.QY_ST = ClockTableFlag）
  static bool get lockEnabled =>
      (SpUtil.getString('ClockTableFlag') ?? '0') == '1';

  /// 拉取指定桌台的最新数据；失败返回 null（调用方按原数据继续）。
  static Future<TableInfo?> fetchLatest(
    String tableId, {
    String areaid = '',
  }) async {
    if (tableId.isEmpty) return null;
    try {
      final List<TableInfo> list = await TableRepository.fetchTableInfoList(
        masterDevice: ConnectionManager.pcAlive,
        areaid: areaid,
        tablestatus: '',
      );
      for (final TableInfo table in list) {
        if (table.tableid == tableId) return table;
      }
    } catch (_) {}
    return null;
  }

  /// 锁台/解锁（云服务 /sale/lockFlagTable、主设备 /api/table/TableLock）
  static Future<bool> postTableLock({
    required String tableId,
    required bool lock,
    Map<String, dynamic>? tableJson,
    int autoflag = 1,
  }) async {
    if (tableId.isEmpty) return false;
    try {
      if (ConnectionManager.pcAlive) {
        final Map<String, dynamic> tableBean =
            TableDataUtils.buildFullTableBean(
          rawJson: tableJson,
          fallback: <String, dynamic>{'tableid': tableId},
        );
        tableBean['newtableid'] = tableId;
        if (tableBean['tmp'] is Map) {
          (tableBean['tmp'] as Map<String, dynamic>)['lockflag'] =
              lock ? 1 : 0;
        }
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMasterTmpDto': tableBean,
          'flag': lock ? 1 : 0,
          'autoflag': autoflag,
        };
        await requestForm(
          HttpApi.pcTableLock,
          <String, dynamic>{'tablemaster': jsonEncode(pcMaster)},
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.lockFlagTable, <String, dynamic>{
          'tableid': tableId,
          'lockflag': lock ? '1' : '0',
          'autoflag': '$autoflag',
        });
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 订阅其他设备的锁台事件；只在启用锁台时生效。
  ///
  /// 仅当前展示中的页面弹提示，避免路由栈内多个页面同时弹窗。
  static StreamSubscription<Map<String, dynamic>>? listenLockEvent({
    required BuildContext context,
    required String saleid,
    required String tableName,
    required VoidCallback onExit,
  }) {
    if (!lockEnabled || saleid.isEmpty) return null;
    return MqService.instance.onLockTable.listen((event) {
      if (!context.mounted) return;
      if (event['saleid']?.toString() != saleid) return;
      if ((event['lockflag']?.toString() ?? '') != '1') return;
      if (event['machno']?.toString() ==
          (SpUtil.getString(Constant.machNo) ?? '')) {
        return;
      }
      final ModalRoute<dynamic>? route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      showLockedByOther(
        context,
        event: event,
        tableName: tableName,
        onExit: onExit,
      );
    });
  }

  /// 其他设备操作本桌台时的提示（对齐 smdcapp unlock_table_message）
  static Future<void> showLockedByOther(
    BuildContext context, {
    required Map<String, dynamic> event,
    required String tableName,
    required VoidCallback onExit,
  }) async {
    if (!context.mounted) return;
    final String opername = event['opername']?.toString() ?? '';
    final String machno = event['machno']?.toString() ?? '';
    final String message = '操作员：$opername，在$machno设备已解锁$tableName桌台，\n'
        '程序将在3秒后回到桌台页';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LockedByOtherDialog(message: message),
    );
    if (context.mounted) onExit();
  }
}

class _LockedByOtherDialog extends StatefulWidget {
  const _LockedByOtherDialog({required this.message});

  final String message;

  @override
  State<_LockedByOtherDialog> createState() => _LockedByOtherDialogState();
}

class _LockedByOtherDialogState extends State<_LockedByOtherDialog> {
  int _seconds = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_seconds <= 1) {
        timer.cancel();
        Navigator.of(context).pop();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '提示',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D2129),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Color(0xFF4E5969),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_seconds 秒后自动返回',
              style: const TextStyle(fontSize: 12, color: Color(0xFF86909C)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFE63F31),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '返回桌台页',
                  style: TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
