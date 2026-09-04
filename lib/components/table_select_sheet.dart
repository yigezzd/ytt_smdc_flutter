import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 桌台选择弹窗（对齐 smdcapp TableUnitBottomDialog/TableChangeBottomDialog 的桌台网格）
///
/// 可复用于转台、并台、转菜等需要选择目标桌台的场景。
class TableSelectSheet extends StatelessWidget {
  const TableSelectSheet({super.key, required this.tables, this.title = '选择桌台'});

  final List<Map<String, dynamic>> tables;
  final String title;

  /// 显示桌台选择弹窗（单选），返回选中的桌台 JSON 或 null
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> tables,
    String title = '选择桌台',
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TableSelectSheet(tables: tables, title: title),
    );
  }

  /// 显示并台/拆台多选弹窗（对齐 smdcapp TableUnitBottomDialog）
  ///
  /// 返回选中的桌台列表，取消则返回 null。
  static Future<List<Map<String, dynamic>>?> showUniTable(
    BuildContext context, {
    required List<Map<String, dynamic>> tables,
  }) {
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UniTableSelectSheet(tables: tables),
    );
  }

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
            child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E6EB), borderRadius: BorderRadius.circular(2))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.3,
              ),
              itemCount: tables.length,
              itemBuilder: (BuildContext c, int i) {
                final Map<String, dynamic> t = tables[i];
                final String name = t['name']?.toString() ?? t['tablename']?.toString() ?? '';
                final String code = t['code']?.toString() ?? t['tablecode']?.toString() ?? '';
                return GestureDetector(
                  onTap: () => Navigator.pop(context, t),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E6EB)),
                    ),
                    child: Text(
                      name.isNotEmpty ? name : code,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333), fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
class _UniTableSelectSheet extends StatefulWidget {
  const _UniTableSelectSheet({required this.tables});

  final List<Map<String, dynamic>> tables;

  @override
  State<_UniTableSelectSheet> createState() => _UniTableSelectSheetState();
}

class _UniTableSelectSheetState extends State<_UniTableSelectSheet> {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text('并台',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
                final String displayText = name.isNotEmpty ? name : code;
                final String itemUnitableid = t['unitableid']?.toString() ?? '';
                final bool isSelected = _selectedIndices.contains(i);

                // 对齐 smdcapp TableUnityAdapter 徽章逻辑
                String badge = '';
                Color badgeColor = Colors.transparent;
                if (!isSelected && itemUnitableid.isNotEmpty) {
                  badge = '已合并';
                  badgeColor = const Color(0xFF52C41A);
                } else if (isSelected && itemUnitableid.isEmpty) {
                  badge = '待合并';
                  badgeColor = const Color(0xFF1890FF);
                } else if (isSelected && itemUnitableid.isNotEmpty) {
                  badge = '拆台';
                  badgeColor = const Color(0xFF999999);
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
                            ? _kBrandRed
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
          // 确定按钮（对齐 smdcapp bt_sure）
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
                  color: _kBrandRed,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Center(
                  child:
                      Text('确定', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 桌台操作工具类（转台/并台/转菜的共享逻辑）
///
/// 对齐 smdcapp transProMaster / uniTable / TableChangeProduct
class TableOpsHelper {
  TableOpsHelper._();

  /// 获取空闲桌台列表（用于转台/转菜选择目标桌）
  static Future<List<Map<String, dynamic>>> fetchFreeTables() async {
    final bool useMaster = ConnectionManager.pcAlive;
    final Map<String, dynamic> resp;
    if (useMaster) {
      resp = await requestForm(
        HttpApi.pcTableInfoList,
        <String, dynamic>{
          'is_page': 0,
          'page': 1,
          'pagesize': 100,
          'tablestatus': '0',
          'stopflag': '0',
        },
        masterDevice: true,
        showError: false,
      );
    } else {
      resp = await requestForm(
        HttpApi.tableInfoList,
        <String, dynamic>{
          'is_page': '0',
          'page': '1',
          'pagesize': '100',
          'tablestatus': '0',
          'stopflag': '0',
        },
        showError: false,
      );
    }
    return _parseTableList(resp);
  }

  /// 获取可并台桌台列表（对齐 smdcapp getCanUniTables）
  ///
  /// [unitableid] 若桌台已并台（unitableid非空），则传 unitableid，否则传 tableid
  static Future<List<Map<String, dynamic>>> fetchCanUniTables(
    String tableid, {
    String unitableid = '',
  }) async {
    final bool useMaster = ConnectionManager.pcAlive;
    final String queryTableid =
        unitableid.isNotEmpty ? unitableid : tableid;
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
        showError: false,
      );
    } else {
      resp = await requestForm(
        HttpApi.getCanUniTables,
        <String, dynamic>{
          'tableid': queryTableid,
          'is_page': '0',
          'page': '1',
          'pagesize': '100',
        },
        showError: false,
      );
    }
    return _parseTableList(resp);
  }

  /// 执行转台（对齐 smdcapp TableDao.tableChange）
  ///
  /// [tableJson] 当前桌台完整JSON（对齐 smdcapp objectClone），
  /// PC模式需要完整桌台对象构建 PCTableChangeVTO
  static Future<void> doChangeTable({
    required String tableId,
    required String saleid,
    required Map<String, dynamic> target,
    Map<String, dynamic>? tableJson,
  }) async {
    final bool useMaster = ConnectionManager.pcAlive;
    final String newTableId = target['tableid']?.toString() ?? target['id']?.toString() ?? '';
    final String newTableCode = target['code']?.toString() ?? target['tablecode']?.toString() ?? '';
    final String newTableName = target['name']?.toString() ?? target['tablename']?.toString() ?? '';
    if (useMaster) {
      // 对齐 smdcapp PCTableChangeVTO{masterTmpDto, inTableDto}，均设 tmp.lastbilltype=7
      final Map<String, dynamic> masterTmpDto =
          Map<String, dynamic>.from(tableJson ?? <String, dynamic>{'tableid': tableId});
      final Map<String, dynamic> masterTmp =
          Map<String, dynamic>.from(masterTmpDto['tmp'] as Map? ?? <String, dynamic>{});
      masterTmp['lastbilltype'] = 7;
      masterTmpDto['tmp'] = masterTmp;

      final Map<String, dynamic> inTableDto =
          Map<String, dynamic>.from(target);
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
      // 云服务模式：对齐 smdcapp updateMasterTmp
      final Map<String, dynamic>? tmp = tableJson?['tmp'] as Map<String, dynamic>?;
      await requestForm(HttpApi.updateMasterTmp, <String, dynamic>{
        'saleid': saleid,
        'remark': tmp?['remark']?.toString() ?? '',
        'personnum': (tmp?['personnum'] ?? 0).toString(),
        'tableid': newTableId,
        'tablecode': newTableCode,
        'unitableid': tmp?['unitableid']?.toString() ?? '',
        'serverid': tmp?['serverid']?.toString() ?? '',
        'servername': tmp?['servername']?.toString() ?? '',
        'tablename': newTableName,
        'printtype': '18',
      });
    }
  }

  /// 执行并台/拆台（对齐 smdcapp uniTable / PCTableUnitVTO）
  ///
  /// [unitableid] 当前桌台的并台主桌ID，非空表示已并台（用于拆台场景）
  static Future<void> doUniTable({
    required String tableId,
    required Map<String, dynamic> target,
    String unitableid = '',
  }) async {
    await doUniTableBatch(
        tableId: tableId, selectedList: <Map<String, dynamic>>[target],
        unitableid: unitableid);
  }

  /// 批量执行并台/拆台（对齐 smdcapp TableUnitBottomDialog.tableUnit + getUnitTable）
  ///
  /// 遍历选中列表，unitableid非空→拆台(cancelList)，否则→加台(unionList)
  static Future<void> doUniTableBatch({
    required String tableId,
    required List<Map<String, dynamic>> selectedList,
    String unitableid = '',
  }) async {
    final bool useMaster = ConnectionManager.pcAlive;
    // 对齐 smdcapp: masterTableid = unitableid非空 ? unitableid : tableid
    final String masterTableid =
        unitableid.isNotEmpty ? unitableid : tableId;
    // 对齐 smdcapp getUnitTable: 遍历选中列表分组
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
  }

  /// 解析桌台列表响应（对齐 smdcapp: 云服务取 data.list，主设备取 Data.tableMasterTmpList）
  static List<Map<String, dynamic>> _parseTableList(Map<String, dynamic> resp) {
    final dynamic data = resp['Data'] ?? resp['data'];
    if (data is Map<String, dynamic>) {
      final dynamic list =
          data['tableMasterTmpList'] ?? data['list'] ?? data['tableList'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().toList();
      }
    } else if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return <Map<String, dynamic>>[];
  }
}
