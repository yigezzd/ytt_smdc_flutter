import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/mq_service.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/pages/home/table/table_repository.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/table_data_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 桌台实时锁状态与持有人
class TableLockState {
  const TableLockState({
    required this.locked,
    this.table,
    this.operid = '',
    this.opername = '',
    this.opermachno = '',
  });

  final bool locked;

  /// 查询到的最新桌台（用于状态变化判断）
  final TableInfo? table;

  final String operid;
  final String opername;
  final String opermachno;
}

/// 桌台并发操作守卫（对齐 smdcapp 锁台逻辑）
///
/// - 点击桌台前拉取最新桌台状态，避免使用列表缓存里的旧状态；
/// - PC 主设备模式额外实时询问 PC 是否正在操作该桌台；
/// - 点菜/订单/结账页收到其他设备的锁台 MQ 时提示并返回桌台页；
/// - 提供统一的锁台/解锁接口封装，供点菜页自动锁台使用。
class TableConcurrencyGuard {
  TableConcurrencyGuard._();

  /// 是否启用锁台（对齐 smdcapp ConstantSetKey.QY_ST = ClockTableFlag）
  static bool get lockEnabled =>
      (SpUtil.getString('ClockTableFlag') ?? '0') == '1';

  /// 拉取指定桌台的最新数据；失败返回 null（调用方按原数据继续）。
  ///
  /// [throwOnError] 为 true 时网络/接口异常向上抛出，供并发校验阻断进入。
  static Future<TableInfo?> fetchLatest(
    String tableId, {
    String areaid = '',
    bool throwOnError = false,
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
    } catch (_) {
      if (throwOnError) rethrow;
    }
    return null;
  }

  /// 查询桌台实时锁状态与锁持有人。
  ///
  /// - PC 主设备模式：额外调用 /api/table/GetTableLockStatus 询问 PC 端是否正在操作
  ///   （对齐 smdcapp TableInfoActivity.getTableLockStatusPC）；
  /// - 云服务模式：以桌台列表的 tmp.lockflag 为准。
  /// 查询异常向上抛出，由调用方阻断操作并提示。
  static Future<TableLockState> fetchLockState(
    String tableId, {
    String areaid = '',
  }) async {
    if (tableId.isEmpty) return const TableLockState(locked: false);
    final TableInfo? table = await fetchLatest(
      tableId,
      areaid: areaid,
      throwOnError: true,
    );
    bool pcLocked = false;
    // 空闲桌台没有 tmp，不存在锁台状态，无需询问 PC（对齐 smdcapp 仅 tmp != null 时查询）
    if (ConnectionManager.pcAlive && table?.tmp != null) {
      pcLocked = await _fetchPcLockStatus(table!);
    }
    String operid = table?.tmp?.operid ?? '';
    String opername = table?.tmp?.opername ?? '';
    String opermachno = table?.tmp?.opermachno ?? '';
    // PC 实时返回已锁但列表尚未同步时，列表里的操作人是旧值，不能用来判断锁持有人
    if (pcLocked && !(table?.isLocked ?? false)) {
      operid = '';
      opername = '';
      opermachno = '';
    }
    // 服务端未回传锁台操作人时，用 MQ 锁台事件缓存兜底
    if (operid.isEmpty && opername.isEmpty && opermachno.isEmpty) {
      final String saleid = table?.tmp?.saleid ?? '';
      final Map<String, String>? cached =
          saleid.isEmpty ? null : MqService.instance.lockOwnerForSaleid(saleid);
      if (cached != null) {
        operid = cached['operid'] ?? '';
        opername = cached['opername'] ?? '';
        opermachno = cached['machno'] ?? '';
      }
    }
    return TableLockState(
      locked: pcLocked || (table?.isLocked ?? false),
      table: table,
      operid: operid,
      opername: opername,
      opermachno: opermachno,
    );
  }

  /// 主设备-获取单桌锁定状态（对齐 smdcapp /api/table/GetTableLockStatus）
  static Future<bool> _fetchPcLockStatus(TableInfo table) async {
    final Map<String, dynamic> raw = table.toJson();
    final dynamic rawTmp = raw['tmp'];
    final Map<String, dynamic> tmp = rawTmp is Map
        ? Map<String, dynamic>.from(rawTmp)
        : (table.tmp?.toJson() ?? <String, dynamic>{});
    tmp['tableid'] = table.tableid;
    final Map<String, dynamic> resp = await requestForm(
      HttpApi.pcGetTableLockStatus,
      <String, dynamic>{
        'tablemaster': jsonEncode(<String, dynamic>{'tmp': tmp}),
      },
      masterDevice: true,
      showError: false,
    );
    final dynamic data = resp['Data'] ??
        resp['data'] ??
        resp['iRetValue'] ??
        resp['IRetValue'];
    return (int.tryParse(data?.toString() ?? '') ?? 0) == 1;
  }

  /// 锁台/解锁（云服务 /sale/lockFlagTable、主设备 /api/table/TableLock）
  static Future<bool> postTableLock({
    required String tableId,
    required bool lock,
    Map<String, dynamic>? tableJson,
    String tableName = '',
    int autoflag = 1,
  }) async {
    if (tableId.isEmpty) return false;
    try {
      if (ConnectionManager.pcAlive) {
        final Map<String, dynamic> tableBean =
            TableDataUtils.buildFullTableBean(
          rawJson: tableJson,
          fallback: <String, dynamic>{
            'tableid': tableId,
            if (tableName.isNotEmpty) 'name': tableName,
          },
        );
        tableBean['newtableid'] = tableId;
        if (tableBean['tmp'] is Map) {
          final Map<String, dynamic> tmp =
              tableBean['tmp'] as Map<String, dynamic>;
          tmp['lockflag'] = lock ? 1 : 0;
          // 主设备会把 tmp.opermachno/opername 原样同步到云端锁台接口并推送 MQ，
          // 缺省时推送的 machno 为空，本机会误判为“其他设备解锁”而弹窗返回桌台。
          tmp['opermachno'] = SpUtil.getString(Constant.machNo) ?? '';
          final Map<String, String> oper = _currentOperator();
          tmp['operid'] = oper['operid']!;
          tmp['opername'] = oper['opername']!;
          final String name = tableName.isNotEmpty
              ? tableName
              : (tmp['tablename']?.toString() ?? '');
          if (name.isNotEmpty) tmp['tablename'] = name;
          tmp['updatetime'] =
              DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
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

  static Map<String, String> _currentOperator() {
    String operid = '';
    String opername = '';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        operid = userMap['userid']?.toString() ??
            userMap['id']?.toString() ??
            '';
        opername = userMap['name']?.toString() ??
            userMap['username']?.toString() ??
            '';
      }
    } catch (_) {}
    return <String, String>{'operid': operid, 'opername': opername};
  }

  /// 锁是否由当前登录操作员持有（同操作员）
  static bool isSameOperator(TableLockState state) {
    final Map<String, String> self = _currentOperator();
    if (state.operid.isNotEmpty && self['operid']!.isNotEmpty) {
      return state.operid == self['operid'];
    }
    if (state.opername.isNotEmpty && self['opername']!.isNotEmpty) {
      return state.opername == self['opername'];
    }
    return false;
  }

  /// 锁是否由本机持有
  static bool isLockedBySelf(TableLockState state) {
    if (!state.locked) return false;
    final String selfMachno = SpUtil.getString(Constant.machNo) ?? '';
    if (state.opermachno.isEmpty || selfMachno.isEmpty) return false;
    if (state.opermachno != selfMachno) return false;
    if (state.operid.isEmpty && state.opername.isEmpty) return true;
    return isSameOperator(state);
  }

  /// 进入桌台/点菜时的冲突提示（区分其他设备/其他员工）
  static String lockConflictMessage(TableLockState state) {
    if (isLockedBySelf(state)) return '桌台已被本设备锁定';
    // 没有操作人信息时只能确认是其他机号，按“其他设备”提示
    if (state.operid.isEmpty && state.opername.isEmpty) {
      return '桌台已被其他设备操作';
    }
    return isSameOperator(state) ? '桌台已被其他设备操作' : '桌台已被其他员工操作';
  }

  /// 桌台页点击已锁桌台时的解锁确认文案
  static String unlockConfirmMessage(TableLockState state) {
    if (isLockedBySelf(state)) {
      return '桌台已被本设备锁定，解锁后本设备将退出该桌台操作，是否继续解锁？';
    }
    return '${lockConflictMessage(state)}，解锁会强制退出其它桌台，'
        '可能会造成未保存数据丢失，是否继续解锁？';
  }

  /// 订阅其他设备的锁台事件；只在启用锁台时生效。
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
      final String machno = event['machno']?.toString() ?? '';
      // 无法识别来源设备的消息不弹窗，避免误踢
      if (machno.isEmpty) return;
      if (machno == (SpUtil.getString(Constant.machNo) ?? '')) return;
      // 不限制“当前页在栈顶”：点菜/订单页打开弹窗、抽屉时也要能收到抢占提示，
      // 用静态标记保证同一时间只弹一个。
      showLockedByOther(
        context,
        event: event,
        tableName: tableName,
        onExit: onExit,
      );
    });
  }

  static bool _dialogVisible = false;

  /// 其他设备锁定/解锁本桌台时的提示
  static Future<void> showLockedByOther(
    BuildContext context, {
    required Map<String, dynamic> event,
    required String tableName,
    required VoidCallback onExit,
  }) async {
    if (!context.mounted || _dialogVisible) return;
    _dialogVisible = true;
    final String message = _lockEventMessage(event, tableName);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _LockedByOtherDialog(message: message),
      );
    } finally {
      _dialogVisible = false;
    }
    if (context.mounted) onExit();
  }

  static String _lockEventMessage(
    Map<String, dynamic> event,
    String tableName,
  ) {
    final String lockflag = event['lockflag']?.toString() ?? '';
    final String opername = event['opername']?.toString() ?? '';
    final String machno = event['machno']?.toString() ?? '';
    final String operid = event['operid']?.toString() ?? '';
    if (lockflag == '0') {
      // 对齐 smdcapp unlock_table_message
      return '操作员：$opername，在$machno设备已解锁$tableName桌台，\n'
          '程序将在3秒后回到桌台页';
    }
    final Map<String, String> self = _currentOperator();
    final bool hasOwner = operid.isNotEmpty || opername.isNotEmpty;
    final bool sameOperator = operid.isNotEmpty && self['operid']!.isNotEmpty
        ? operid == self['operid']
        : (opername.isNotEmpty &&
            self['opername']!.isNotEmpty &&
            opername == self['opername']);
    final String who = !hasOwner
        ? '其他设备'
        : (sameOperator ? '其他设备' : '其他员工');
    return '桌台已被$who操作（操作员：$opername，设备：$machno），\n'
        '程序将在3秒后回到桌台页';
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
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
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isDark ? Colors.white70 : const Color(0xFF4E5969),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_seconds 秒后自动返回',
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF86909C)),
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
