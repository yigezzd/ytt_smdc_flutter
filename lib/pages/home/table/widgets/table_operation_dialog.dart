import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/deposit_sheet.dart';
import 'package:flutter_deer/components/edit_table_info_sheet.dart';
import 'package:flutter_deer/components/table_select_sheet.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/table_data_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 待下单桌台操作弹窗（对齐 smdcapp OperationPopup2，path=1 台桌页弹出模式）
///
/// 点击"待下单"状态的桌台后弹出，包含：
/// - 第一行：转台 | 并台/拆台 | 消台 | 锁台
/// - 第二行：交押金 | 押金记录
/// - 修改台桌信息
/// - 底部红色"开始点菜"按钮 → 跳转点菜页
class TableOperationDialog extends StatefulWidget {
  const TableOperationDialog({
    super.key,
    required this.table,
  });

  final TableInfo table;

  @override
  State<TableOperationDialog> createState() => _TableOperationDialogState();
}

class _TableOperationDialogState extends State<TableOperationDialog> {
  /// 品牌红（对齐 smdcapp loginbtn 红色）
  static const Color _brandRed = Color(0xFFE13426);

  /// 弹窗背景灰（对齐 smdcapp @color/line）
  static const Color _bgGray = Color(0xFFF5F5F5);

  bool _operating = false;

  // ==================== 操作 ====================

  /// 开始点菜（对齐 smdcapp OperationPopup2.ll_dishes:
  /// 若 ClockTableFlag=="1" 则先锁台再进入点菜页）
  Future<void> _onStartOrder() async {
    // 对齐 smdcapp: val qy_st = decodeString(QY_ST, "0"); if (qy_st == "1") st(1)
    final String clockFlag = SpUtil.getString('ClockTableFlag') ?? '0';
    if (clockFlag == '1') {
      // 桌台未锁时先执行锁台（已锁则跳过）
      final int lockflag = widget.table.tmp?.lockflag ?? 0;
      if (lockflag != 1) {
        setState(() => _operating = true);
        try {
          await _doLockTable();
        } catch (_) {
          if (mounted) setState(() => _operating = false);
          return; // 锁台失败则不进入点菜页
        }
        if (mounted) setState(() => _operating = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    NavigatorUtils.push(
      context,
      Routes.orderPage,
      arguments: <String, dynamic>{
        'tableId': widget.table.tableid,
        'tableName': widget.table.name,
        'tableCode': widget.table.code,
        'persons': widget.table.tmp?.personnum ?? widget.table.person,
        'serverId': widget.table.tmp?.serverid ?? '',
        'serverName': widget.table.tmp?.servername ?? '',
        'remark': widget.table.tmp?.remark ?? '',
        'saleid': widget.table.tmp?.saleid ?? '',
        'tableJson': widget.table.toJson(),
      },
    );
  }

  /// 消台（对齐 smdcapp OperationPopup2.xt → TableCancelBottomDialog → TableDao.cancelTable）
  Future<void> _onCancelTable() async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定要对${widget.table.name}进行消台吗？',
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _operating = true);
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      if (useMaster) {
        // 主设备模式：对齐 smdcapp TableDao.cancelTable →
        // PCTableHttpUtil.cancelTable(JSON.toJSONString(tableInfoBean))，
        // tablemaster 传完整桌台 Bean（含 spid/sid/newtableid/完整 tmp），不能只传字段子集
        final Map<String, dynamic> tableBean = TableDataUtils.buildFullTableBean(
          rawJson: widget.table.rawJson,
          fallback: <String, dynamic>{
            'tableid': widget.table.tableid,
            'name': widget.table.name,
            'code': widget.table.code,
          },
        );
        final Map<String, dynamic> params = <String, dynamic>{
          'tablemaster': jsonEncode(tableBean),
        };
        await requestForm(
          HttpApi.pcCancelTable,
          params,
          masterDevice: true,
        );
      } else {
        // 云服务模式：对齐 smdcapp TableApi /YttSvr/app/sale/cancelTable
        final Map<String, dynamic> params = <String, dynamic>{
          'tableid': widget.table.tableid,
        };
        await requestForm(HttpApi.cancelTable, params);
      }
      if (!mounted) {
        return;
      }
      Toast.show('消台成功');
      Navigator.of(context).pop();
      TableEventBus.fireTableChanged();
    } catch (_) {
      // 错误已在 requestForm 中 Toast
    } finally {
      if (mounted) {
        setState(() => _operating = false);
      }
    }
  }

  /// 锁台（对齐 smdcapp OperationPopup2.st(1) → TableDao.lockFlagTable）
  Future<void> _onLockTable() async {
    setState(() => _operating = true);
    try {
      await _doLockTable();
      if (!mounted) return;
      Toast.show('锁台成功');
      Navigator.of(context).pop();
      TableEventBus.fireTableChanged();
    } catch (_) {
      // 错误已在 requestForm 中 Toast
    } finally {
      if (mounted) {
        setState(() => _operating = false);
      }
    }
  }

  /// 执行锁台请求（复用逻辑，供 _onLockTable 和 _onStartOrder 调用）
  Future<void> _doLockTable() async {
    final bool useMaster = ConnectionManager.pcAlive;
    if (useMaster) {
      final Map<String, dynamic> tableBean = TableDataUtils.buildFullTableBean(
        rawJson: widget.table.rawJson,
        fallback: <String, dynamic>{
          'tableid': widget.table.tableid,
          'name': widget.table.name,
          'code': widget.table.code,
        },
      );
      tableBean['newtableid'] = widget.table.tableid;
      if (tableBean['tmp'] is Map) {
        (tableBean['tmp'] as Map<String, dynamic>)['lockflag'] = 1;
      }
      final Map<String, dynamic> pcMaster = <String, dynamic>{
        'tableMasterTmpDto': tableBean,
        'flag': 1,
        'autoflag': 1,
      };
      final Map<String, dynamic> params = <String, dynamic>{
        'tablemaster': jsonEncode(pcMaster),
      };
      await requestForm(
        HttpApi.pcTableLock,
        params,
        masterDevice: true,
      );
    } else {
      final Map<String, dynamic> params = <String, dynamic>{
        'tableid': widget.table.tableid,
        'lockflag': '1',
        'autoflag': '1',
      };
      await requestForm(HttpApi.lockFlagTable, params);
    }
  }

  /// 交押金（对齐 smdcapp JYJPopup）
  void _onDepositPay() {
    final String saleid = widget.table.tmp?.saleid ?? '';
    if (saleid.isEmpty) {
      Toast.show('该桌台未开台，无法交押金');
      return;
    }
    DepositSheet.showPay(
      context,
      saleid: saleid,
      tableId: widget.table.tableid,
      tableName: widget.table.name,
      serverId: widget.table.tmp?.serverid ?? '',
      serverName: widget.table.tmp?.servername ?? '',
    );
  }

  /// 押金记录（对齐 smdcapp YJOrderActivity）
  void _onDepositRecords() {
    final String saleid = widget.table.tmp?.saleid ?? '';
    if (saleid.isEmpty) {
      Toast.show('该桌台未开台，无押金记录');
      return;
    }
    DepositSheet.showRecords(context, saleid: saleid);
  }

  /// 修改台桌信息（对齐 smdcapp TableOpenBottomDialog 修改模式）
  Future<void> _onEditTableInfo() async {
    final String saleid = widget.table.tmp?.saleid ?? '';
    if (saleid.isEmpty) {
      Toast.show('该桌台未开台，无需修改');
      return;
    }
    final bool success = await EditTableInfoSheet.show(
      context,
      saleid: saleid,
      tableId: widget.table.tableid,
      tableCode: widget.table.code,
      tableName: widget.table.name,
      personnum: widget.table.tmp?.personnum?.toString() ?? widget.table.person.toString(),
      remark: widget.table.tmp?.remark ?? '',
      serverId: widget.table.tmp?.serverid ?? '',
      serverName: widget.table.tmp?.servername ?? '',
      tableJson: widget.table.toJson(),
    );
    if (success && mounted) {
      Navigator.of(context).pop();
      TableEventBus.fireTableChanged();
    }
  }

  /// 序列化桌台信息（对齐 smdcapp JSON.toJSONString(tableInfoBean)）
  Map<String, dynamic> _tableToJson() {
    return <String, dynamic>{
      'tableid': widget.table.tableid,
      'name': widget.table.name,
      'code': widget.table.code,
      'areaid': widget.table.areaid,
      'areaname': widget.table.areaname,
      'person': widget.table.person,
      'unicount': widget.table.unicount,
      if (widget.table.tmp != null)
        'tmp': <String, dynamic>{
          'tablestatus': widget.table.tmp!.tablestatus,
          'amt': widget.table.tmp!.amt,
          'personnum': widget.table.tmp!.personnum,
          'saleid': widget.table.tmp!.saleid,
          'billdate': widget.table.tmp!.billdate,
          'unitableid': widget.table.tmp!.unitableid,
          'unitableno': widget.table.tmp!.unitableno,
          'unitablename': widget.table.tmp!.unitablename,
          'uniflowno': widget.table.tmp!.uniflowno,
          'lockflag': widget.table.tmp!.lockflag,
          'hangflag': widget.table.tmp!.hangflag,
          'preprintflag': widget.table.tmp!.preprintflag,
          'serverid': widget.table.tmp!.serverid,
          'servername': widget.table.tmp!.servername,
          'remark': widget.table.tmp!.remark,
        },
    };
  }

  /// 并台/拆台（对齐 smdcapp TableUnitBottomDialog）
  ///
  /// 流程：获取可并台桌台列表 → 用户选择 → 调用 uniTable/TableUnion API
  Future<void> _onUniTable() async {
    setState(() => _operating = true);
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      // 对齐 smdcapp: 如果桌台已并台（unitableid非空），则传 unitableid，否则传 tableid
      final String unitableid = widget.table.tmp?.unitableid ?? '';
      final String queryTableid =
          unitableid.isNotEmpty ? unitableid : widget.table.tableid;
      // 1. 获取可并台桌台列表（对齐 smdcapp getCanUniTables）
      final Map<String, dynamic> resp;
      if (useMaster) {
        // 对齐 smdcapp PCCanUnitVTO{is_page, page, pagesize, areaid, tableid}
        resp = await requestForm(
          HttpApi.pcGetCanUniTables,
          <String, dynamic>{
            'data': jsonEncode(<String, dynamic>{
              'is_page': 0,
              'page': 1,
              'pagesize': 100,
              'areaid': '',
              'tableid': queryTableid,
            }),
          },
          masterDevice: true,
        );
      } else {
        resp = await requestForm(HttpApi.getCanUniTables, <String, dynamic>{
          'tableid': queryTableid,
          'is_page': '0',
          'page': '1',
          'pagesize': '100',
        });
      }

      if (!mounted) return;

      // 解析可并台桌台列表（对齐 smdcapp: 云服务取 data.list，主设备取 Data.tableMasterTmpList）
      final dynamic data = resp['Data'] ?? resp['data'];
      List<Map<String, dynamic>> tables = <Map<String, dynamic>>[];
      if (data is Map<String, dynamic>) {
        final dynamic list =
            data['tableMasterTmpList'] ?? data['list'] ?? data['tableList'];
        if (list is List) {
          tables = list.whereType<Map<String, dynamic>>().toList();
        }
      } else if (data is List) {
        tables = data.whereType<Map<String, dynamic>>().toList();
      }

      if (tables.isEmpty) {
        Toast.show('没有可并台的桌台');
        return;
      }

      // 2. 显示并台/拆台多选弹窗（对齐 smdcapp TableUnitBottomDialog 多选网格）
      final List<Map<String, dynamic>>? selectedList =
          await _showUniTableSheet(tables);
      if (selectedList == null || selectedList.isEmpty || !mounted) return;

      // 3. 对齐 smdcapp getUnitTable: 遍历选中列表，unitableid非空→拆台，否则→加台
      final String masterTableid = queryTableid;
      final List<Map<String, dynamic>> unionList = <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> cancelList = <Map<String, dynamic>>[];
      for (final Map<String, dynamic> item in selectedList) {
        final String itemUnitableid = item['unitableid']?.toString() ?? '';
        if (itemUnitableid.isNotEmpty) {
          cancelList.add(item);
        } else {
          unionList.add(item);
        }
      }

      // 4. 调用并台/拆台API（对齐 smdcapp uniTable/TableUnion）
      if (useMaster) {
        // 对齐 smdcapp PCTableUnitVTO{tableid, unionList, cancelList}
        final Map<String, dynamic> uniData = <String, dynamic>{
          'tableid': masterTableid,
          'unionList': unionList,
          'cancelList': cancelList,
        };
        await requestForm(
          HttpApi.pcUniTable,
          <String, dynamic>{'data': jsonEncode(uniData)},
          masterDevice: true,
        );
      } else {
        // 对齐 smdcapp: 逗号分隔的 tableid/code 字符串
        final String unityIds = unionList
            .map((Map<String, dynamic> e) => e['tableid']?.toString() ?? '')
            .where((String s) => s.isNotEmpty)
            .join(',');
        final String unityCodes = unionList
            .map((Map<String, dynamic> e) => e['code']?.toString() ?? '')
            .where((String s) => s.isNotEmpty)
            .join(',');
        final String detachIds = cancelList
            .map((Map<String, dynamic> e) => e['tableid']?.toString() ?? '')
            .where((String s) => s.isNotEmpty)
            .join(',');
        final String detachCodes = cancelList
            .map((Map<String, dynamic> e) => e['code']?.toString() ?? '')
            .where((String s) => s.isNotEmpty)
            .join(',');
        await requestForm(HttpApi.uniTable, <String, dynamic>{
          'tableid': masterTableid,
          'unitableids': unityIds,
          'unitablecodes': unityCodes,
          'cleartableids': detachIds,
          'cleartablecodes': detachCodes,
        });
      }

      if (!mounted) return;
      Toast.show('桌台拆并成功');
      Navigator.of(context).pop();
      TableEventBus.fireTableChanged();
    } catch (_) {
      if (mounted) Toast.show('桌台拆并失败，请重试');
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  /// 转台（对齐 smdcapp transProMaster / TableChangeBottomDialog）
  ///
  /// 流程：获取空闲桌台（排除当前桌台） → 用户选择目标桌 → 调用转台 API
  Future<void> _onChangeTable() async {
    setState(() => _operating = true);
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      // 复用 TableOpsHelper.fetchFreeTables（已兼容主设备 tableMasterTmpList 和云服务 data.list 两种响应结构）
      final List<Map<String, dynamic>> freeTables =
          await TableOpsHelper.fetchFreeTables();
      // 排除当前桌台自身（不能转到自己）
      final List<Map<String, dynamic>> tables = freeTables
          .where((Map<String, dynamic> t) =>
              (t['tableid']?.toString() ?? t['id']?.toString() ?? '') !=
              widget.table.tableid)
          .toList();

      if (!mounted) return;

      if (tables.isEmpty) {
        Toast.show('没有可用的空闲桌台');
        return;
      }

      final Map<String, dynamic>? selected = await _showTableSelectDialog(tables);
      if (selected == null || !mounted) return;

      final String newTableId = selected['tableid']?.toString() ?? selected['id']?.toString() ?? '';
      final String newTableCode = selected['code']?.toString() ?? '';
      final String newTableName = selected['name']?.toString() ?? '';
      if (newTableId.isEmpty) return;

      // 调用转台API（对齐 smdcapp TableDao.tableChange）
      if (useMaster) {
        // 主设备模式：对齐 smdcapp PCTableChangeVTO{masterTmpDto, inTableDto}
        // masterTmpDto = 当前桌台完整JSON，inTableDto = 目标桌台完整JSON，均设 tmp.lastbilltype=7
        final Map<String, dynamic> masterTmpDto =
            Map<String, dynamic>.from(widget.table.toJson());
        final Map<String, dynamic> masterTmp =
            Map<String, dynamic>.from(masterTmpDto['tmp'] as Map? ?? <String, dynamic>{});
        masterTmp['lastbilltype'] = 7;
        masterTmpDto['tmp'] = masterTmp;

        final Map<String, dynamic> inTableDto =
            Map<String, dynamic>.from(selected);
        final Map<String, dynamic> inTmp =
            Map<String, dynamic>.from(inTableDto['tmp'] as Map? ?? <String, dynamic>{});
        inTmp['lastbilltype'] = 7;
        inTableDto['tmp'] = inTmp;

        final Map<String, dynamic> vto = <String, dynamic>{
          'masterTmpDto': masterTmpDto,
          'inTableDto': inTableDto,
        };
        await requestForm(
          HttpApi.pcTableChange,
          <String, dynamic>{'data': jsonEncode(vto)},
          masterDevice: true,
        );
      } else {
        // 云服务模式：对齐 smdcapp updateMasterTmp（将当前订单转移到新桌台）
        await requestForm(HttpApi.updateMasterTmp, <String, dynamic>{
          'saleid': widget.table.tmp?.saleid ?? '',
          'remark': widget.table.tmp?.remark ?? '',
          'personnum':
              (widget.table.tmp?.personnum ?? 0).toString(),
          'tableid': newTableId,
          'tablecode': newTableCode,
          'unitableid': widget.table.tmp?.unitableid ?? '',
          'serverid': widget.table.tmp?.serverid ?? '',
          'servername': widget.table.tmp?.servername ?? '',
          'tablename': newTableName,
          'printtype': '18',
        });
      }

      if (!mounted) return;
      Toast.show('转台成功');
      Navigator.of(context).pop();
      TableEventBus.fireTableChanged();
    } catch (_) {
      if (mounted) Toast.show('转台失败，请重试');
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  /// 桌台选择弹窗（单选，用于转台等场景）
  Future<Map<String, dynamic>?> _showTableSelectDialog(
    List<Map<String, dynamic>> tables,
  ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('选择桌台', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.2,
              ),
              itemCount: tables.length,
              itemBuilder: (BuildContext c, int i) {
                final Map<String, dynamic> t = tables[i];
                final String name = t['name']?.toString() ?? t['tablename']?.toString() ?? '';
                final String code = t['code']?.toString() ?? '';
                return GestureDetector(
                  onTap: () => Navigator.pop(ctx, t),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE5E6EB)),
                    ),
                    child: Text(
                      code.isNotEmpty ? code : name,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  /// 并台/拆台多选弹窗（对齐 smdcapp TableUnitBottomDialog）
  ///
  /// 底部抽屉展示桌台网格，支持多选，已合并桌台显示绿色"已合并"徽章，
  /// 选中后根据 unitableid 状态显示"待合并"(蓝)/"拆台"(灰)徽章。
  /// 点击"确定"返回选中的桌台列表。
  Future<List<Map<String, dynamic>>?> _showUniTableSheet(
    List<Map<String, dynamic>> tables,
  ) {
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UniTableSheet(tables: tables),
    );
  }

  // ==================== UI ====================

  /// 宫格操作按钮（白底圆角，图标+文字，对齐 smdcapp ll_zt/ll_bt 等）
  Widget _buildGridItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: _operating ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 24, color: const Color(0xFF333333)),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 空白占位（对齐 smdcapp ll_tablev2 中的空 LinearLayout）
  Widget _buildGridPlaceholder() {
    return const Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 15),
        child: SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title = '${widget.table.name}-待下单';
    // 对齐 smdcapp ConstantSetKey.QY_ST（ClockTableFlag）：启用锁台参数才显示锁台按钮
    final bool lockEnabled = (SpUtil.getString('ClockTableFlag') ?? '0') == '1';

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: _bgGray,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        padding: const EdgeInsets.all(10),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 标题行：红色竖线 + 标题 + 关闭按钮
              Row(
                children: <Widget>[
                  Container(width: 2, height: 16, color: _brandRed),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 22, color: Color(0xFF666666)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // 第一行：转台 | 并台/拆台 | 消台 | 锁台
              Row(
                children: <Widget>[
                  _buildGridItem(
                    icon: Icons.swap_horiz,
                    label: '转台',
                    onTap: _onChangeTable,
                  ),
                  const SizedBox(width: 10),
                  _buildGridItem(
                    icon: Icons.layers_outlined,
                    label: '并台/拆台',
                    onTap: _onUniTable,
                  ),
                  const SizedBox(width: 10),
                  _buildGridItem(
                    icon: Icons.delete_outline,
                    label: '消台',
                    onTap: _onCancelTable,
                  ),
                  const SizedBox(width: 10),
                  if (lockEnabled)
                    _buildGridItem(
                      icon: Icons.lock_outline,
                      label: '锁台',
                      onTap: _onLockTable,
                    )
                  else //建议真机验证点：主设备连接状态下，对已下过套餐的桌台进入订单确认页，确认"已下单"tab 显示套餐主行+明细子行；顺带确认订单详情页展示正常。
                    _buildGridPlaceholder(),
                ],
              ),
              const SizedBox(height: 5),
              // 第二行：交押金 | 押金记录 | 占位 | 占位
              Row(
                children: <Widget>[
                  _buildGridItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '交押金',
                    onTap: _onDepositPay,
                  ),
                  const SizedBox(width: 10),
                  _buildGridItem(
                    icon: Icons.receipt_long_outlined,
                    label: '押金记录',
                    onTap: _onDepositRecords,
                  ),
                  const SizedBox(width: 10),
                  _buildGridPlaceholder(),
                  const SizedBox(width: 10),
                  _buildGridPlaceholder(),
                ],
              ),
              const SizedBox(height: 5),
              // 修改台桌信息 + 开始点菜（对齐 smdcapp ll_dis_and_change）
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 修改台桌信息
                    GestureDetector(
                      onTap: _onEditTableInfo,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.build_outlined, size: 22, color: Color(0xFF333333)),
                            SizedBox(width: 10),
                            Text(
                              '修改台桌信息',
                              style: TextStyle(fontSize: 14, color: Color(0xFF333333)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(height: 0.5, color: _bgGray),
                    const SizedBox(height: 10),
                    // 开始点菜（红色大按钮，对齐 smdcapp tv_dishes）
                    GestureDetector(
                      onTap: _operating ? null : _onStartOrder,
                      child: Container(
                        width: double.infinity,
                        height: 45,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: _brandRed,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Center(
                          child: Text(
                            '开始点菜',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 并台/拆台多选底部抽屉（对齐 smdcapp TableUnitBottomDialog）
///
/// 徽章逻辑（对齐 smdcapp TableUnityAdapter）：
/// - 未选中 + unitableid非空 → 绿色"已合并"
/// - 选中 + unitableid为空 → 蓝色"待合并"
/// - 选中 + unitableid非空 → 灰色"拆台"
class _UniTableSheet extends StatefulWidget {
  const _UniTableSheet({required this.tables});

  final List<Map<String, dynamic>> tables;

  @override
  State<_UniTableSheet> createState() => _UniTableSheetState();
}

class _UniTableSheetState extends State<_UniTableSheet> {
  /// 选中状态集合（索引）
  final Set<int> _selectedIndices = <int>{};

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E6EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题栏（对齐 smdcapp: 左侧"并台" + 右侧关闭）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text('并台',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close,
                      size: 20, color: Color(0xFFC9CDD4)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 桌台网格（对齐 smdcapp TableUnityRecycleView 3列网格）
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.4,
              ),
              itemCount: widget.tables.length,
              itemBuilder: (BuildContext c, int i) {
                final Map<String, dynamic> t = widget.tables[i];
                final String name =
                    t['name']?.toString() ?? t['tablename']?.toString() ?? '';
                final String code = t['code']?.toString() ?? '';
                final String displayText =
                    name.isNotEmpty ? name : code;
                final String itemUnitableid =
                    t['unitableid']?.toString() ?? '';
                final bool isSelected = _selectedIndices.contains(i);

                // 对齐 smdcapp TableUnityAdapter 徽章逻辑
                String badge = '';
                Color badgeColor = Colors.transparent;
                if (!isSelected && itemUnitableid.isNotEmpty) {
                  badge = '已合并';
                  badgeColor = const Color(0xFF52C41A); // 绿色
                } else if (isSelected && itemUnitableid.isEmpty) {
                  badge = '待合并';
                  badgeColor = const Color(0xFF1890FF); // 蓝色
                } else if (isSelected && itemUnitableid.isNotEmpty) {
                  badge = '拆台';
                  badgeColor = const Color(0xFF999999); // 灰色
                }

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedIndices.remove(i);
                      } else {
                        _selectedIndices.add(i);
                      }
                    });
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFFF1F0)
                          : const Color(0xFFFEF7E6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFE13426)
                            : const Color(0xFFF0E0C0),
                      ),
                    ),
                    child: Stack(
                      children: <Widget>[
                        Center(
                          child: Text(
                            displayText,
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFF333333)),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge.isNotEmpty)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(5),
                                  bottomLeft: Radius.circular(5),
                                ),
                              ),
                              child: Text(
                                badge,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 确定按钮（对齐 smdcapp bt_sure 红色全宽）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: GestureDetector(
              onTap: () {
                final List<int> indices = _selectedIndices.toList()..sort();
                final List<Map<String, dynamic>> result = indices
                    .map((int i) => widget.tables[i])
                    .toList();
                Navigator.pop(context, result);
              },
              child: Container(
                width: double.infinity,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE13426),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Center(
                  child: Text('确定',
                      style:
                          TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
