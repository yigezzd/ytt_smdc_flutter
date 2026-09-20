import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/dish_operation_dialogs.dart';
import 'package:flutter_deer/db/dao/table_type_dao.dart';
import 'package:flutter_deer/db/entity/table_type_entity.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红
const Color _brandRed = Color(0xFFE63F31);

/// 开台弹窗（对齐 smdcapp TableInfoActivity.openTable 流程）
///
/// 点击空闲桌台后弹出，填写人数/服务员/备注，
/// 点击“点菜”或“开台”→ 均先调用 beginTable 接口，成功后关闭弹窗并跳转点菜页
/// （对齐 smdcapp TableOpenBottomV2Dialog.openTableOrOrder：点菜/开台都先 beginTable）。
class OpenTableDialog extends StatefulWidget {
  const OpenTableDialog({super.key, required this.table});

  final TableInfo table;

  @override
  State<OpenTableDialog> createState() => _OpenTableDialogState();
}

class _OpenTableDialogState extends State<OpenTableDialog> {
  late TextEditingController _personController;
  late TextEditingController _remarkController;

  /// 服务员信息（默认取当前登录用户）
  String _serverId = '';
  String _serverName = '系统管理员';

  /// 附加费选项与当前选中项（对齐 smdcapp TableOpenBottomV2Dialog.getFjf）
  List<_FjfOption> _fjfOptions = const <_FjfOption>[];
  String _fjfId = '';
  String _fjfName = '无';

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 默认人数为桌台容量
    _personController = TextEditingController(
      text: widget.table.person > 0 ? '${widget.table.person}' : '2',
    );
    _remarkController = TextEditingController();
    _loadCurrentUser();
    _loadFjf();
  }

  /// 附加费开关：参数 OpenTableAmtFlag=1 才展示（对齐 smdcapp SpUtils.getOpenTableAmtFlag）
  bool get _showFjf => ParamsSpUtils.getOpenTableAmtFlag() == '1';

  /// 载入附加费选项并确定默认选中项（对齐 smdcapp getFjf：
  /// 数据源为本地桌台类型表，首项“无”；默认取桌台绑定的 tabletypeid）
  Future<void> _loadFjf() async {
    try {
      final List<TableTypeEntity> types = await TableTypeDao.instance.queryAll();
      final List<_FjfOption> options = <_FjfOption>[
        const _FjfOption(id: '', name: '无'),
        for (final TableTypeEntity t in types)
          if (t.tabletypeid.isNotEmpty)
            _FjfOption(id: t.tabletypeid, name: t.name),
      ];
      _FjfOption selected = options.first;
      final String bound = widget.table.tabletypeid;
      if (bound.isNotEmpty) {
        for (final _FjfOption o in options) {
          if (o.id == bound) {
            selected = o;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _fjfOptions = options;
        _fjfId = selected.id;
        _fjfName = selected.name;
      });
    } catch (_) {
      // 本地表缺失时保持默认“无”
    }
  }

  /// 选择附加费（对齐 smdcapp 点击 ll_fjf 切换选项列表）
  Future<void> _onPickFjf() async {
    if (_fjfOptions.isEmpty) return;
    final _FjfOption? picked = await _FjfSelectSheet.show(
      context,
      options: _fjfOptions,
      selectedId: _fjfId,
    );
    if (picked != null && mounted) {
      setState(() {
        _fjfId = picked.id;
        _fjfName = picked.name;
      });
    }
  }

  void _loadCurrentUser() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        _serverId = userMap['userid']?.toString() ?? '';
        _serverName = userMap['username']?.toString() ?? '系统管理员';
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _personController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  /// 获取人数输入值
  int get _personNum {
    final int n = int.tryParse(_personController.text.trim()) ?? 0;
    return n > 0 ? n : 1;
  }

  /// 生成唯一单号（对齐 smdcapp OrderModel.getBillno）
  String _generateBillNo() {
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  /// 跳转点菜页
  void _goOrderPage({
    String saleid = '',
    Map<String, dynamic>? tableJson,
  }) {
    NavigatorUtils.push(
      context,
      Routes.orderPage,
      arguments: <String, dynamic>{
        'tableId': widget.table.tableid,
        'tableName': widget.table.name,
        'tableCode': widget.table.code,
        'persons': _personNum,
        'serverId': _serverId,
        'serverName': _serverName,
        'remark': _remarkController.text.trim(),
        'saleid': saleid.isNotEmpty ? saleid : (widget.table.tmp?.saleid ?? ''),
        'tableJson': tableJson ?? widget.table.toJson(),
      },
    );
  }

  /// 点菜按钮：先调开台接口再跳转点菜页
  /// （对齐 smdcapp TableOpenBottomV2Dialog.openTableOrOrder(false)：点菜也先 beginTable）
  Future<void> _onOrderTap() async {
    await _beginTable(goOrder: true);
  }

  /// 开台按钮：仅调用 beginTable 开台并关闭弹窗，不进入点菜页
  Future<void> _onOpenTableTap() async {
    await _beginTable(goOrder: false);
  }

  /// 调用 beginTable 开台接口，成功后关闭弹窗；[goOrder] 为 true 时再跳转点菜页
  /// （对齐 smdcapp openTableOrOrder：点菜/开台都先调 beginTable，成功后 dismiss）
  Future<void> _beginTable({required bool goOrder}) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final bool useMaster = ConnectionManager.pcAlive;
      final String billNo = _generateBillNo();
      final Map<String, dynamic> result;

      if (useMaster) {
        // 主设备模式：对齐 smdcapp PCTableHttpUtil.beginTable
        // 接口 /api/table/TableOpeFull，参数 tablemaster 为整个桌台对象的 JSON
        final Map<String, dynamic> tableMaster = <String, dynamic>{
          'tableid': widget.table.tableid,
          'name': widget.table.name,
          'code': widget.table.code,
          'areaid': widget.table.areaid,
          'areaname': widget.table.areaname,
          'person': widget.table.person,
          'billtype': 7,
          'tmp': <String, dynamic>{
            'tablestatus': 0,
            'personnum': _personNum,
            'serverid': _serverId,
            'servername': _serverName,
            'remark': _remarkController.text.trim(),
            'tablename': widget.table.name,
            'billtype': 7,
            'localbillno': billNo,
            'additionid': _fjfId,
          },
        };
        result = await requestForm(
          HttpApi.pcBeginTable,
          <String, dynamic>{'tablemaster': jsonEncode(tableMaster)},
          masterDevice: true,
          showError: true,
        );
      } else {
        // 云服务模式：对齐 smdcapp /YttSvr/app/sale/beginTable，扁平参数
        result = await requestForm(
          HttpApi.beginTable,
          <String, dynamic>{
            'tableid': widget.table.tableid,
            'billtype': '7', // 7=移动点餐（安卓APP点餐）
            'personnum': '$_personNum',
            'tablecode': widget.table.code,
            'serverid': _serverId,
            'servername': _serverName,
            'remark': _remarkController.text.trim(),
            'localbillno': billNo,
            'additionid': _fjfId,
          },
          masterDevice: false,
          showError: true,
        );
      }

      if (!mounted) return;

      // 从响应中提取 saleid（对齐 smdcapp OpenTableVTBean.getSaleid）
      String saleid = '';
      final dynamic data = useMaster ? result['Data'] : result['data'];
      if (data is Map<String, dynamic>) {
        saleid = data['saleid']?.toString() ?? '';
      }

      // 将响应数据合并到 tableJson.tmp（对齐 smdcapp openTableOrOrder：
      // 用 OpenTableVTBean 构造 TableDetailBean 设入 tableInfoBean.tmp，tablestatus=1）
      final Map<String, dynamic> updatedTableJson =
          Map<String, dynamic>.from(widget.table.toJson());
      if (data is Map<String, dynamic>) {
        final Map<String, dynamic> newTmp = Map<String, dynamic>.from(data);
        newTmp['tablestatus'] = 1;
        updatedTableJson['tmp'] = newTmp;
        updatedTableJson['tablestatus'] = '1';
      }

      Toast.show('开台成功');
      TableEventBus.fireTableChanged();
      // 关闭弹窗（对齐 smdcapp dismiss）
      Navigator.of(context).pop();
      // 仅"点菜"按钮跳转点菜页；"开台"按钮开台后停留在桌台页
      if (goOrder) {
        _goOrderPage(saleid: saleid, tableJson: updatedTableJson);
      }
    } catch (_) {
      // 错误已在 requestForm 中 Toast
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    // 键盘弹起时把内容顶到键盘上方，避免输入框被遮挡
    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + keyboardInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 顶部拖拽指示条
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E6EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 标题 + 右上角关闭按钮（与标题同行垂直居中）
            SizedBox(
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  const Text(
                    '开台',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1D2129),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.close,
                          size: 22,
                          color: Color(0xFF86909C),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // 人数
            _buildRow(
              label: '人数：',
              child: SizedBox(
                height: 36,
                width: 100,
                child: TextField(
                  controller: _personController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF1D2129)),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: _brandRed),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 服务员
            _buildRow(
              label: '服务员：',
              child: GestureDetector(
                onTap: () async {
                  final Waiter? waiter = await DishWaiterSheet.show(
                    context,
                    dishName: widget.table.name,
                    currentWaiter: _serverName,
                  );
                  if (waiter != null && mounted) {
                    setState(() {
                      _serverId = waiter.userid;
                      _serverName = waiter.name;
                    });
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _serverName,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFF86909C)),
                  ],
                ),
              ),
            ),
            if (_showFjf) ...<Widget>[
              const SizedBox(height: 12),
              // 附加费（对齐 smdcapp：OpenTableAmtFlag=1 时展示，可点击选择）
              _buildRow(
                label: '附加费：',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onPickFjf,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _fjfName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF1D2129),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Color(0xFF86909C),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // 备注
            _buildRow(
              label: '备注：',
              child: Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _remarkController,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
                    decoration: InputDecoration(
                      hintText: '请输入备注',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFC9CDD4)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: _brandRed),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 按钮行
            Row(
              children: <Widget>[
                // 点菜按钮（灰色）
                Expanded(
                  child: GestureDetector(
                    onTap: _submitting ? null : _onOrderTap,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: const Center(
                        child: Text(
                          '点菜',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4E5969),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 开台按钮（红色）
                Expanded(
                  child: GestureDetector(
                    onTap: _submitting ? null : _onOpenTableTap,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0xFFF0503F), _brandRed],
                        ),
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: Center(
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '开台',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
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

  Widget _buildRow({required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Color(0xFF4E5969)),
        ),
        const SizedBox(width: 4),
        Flexible(child: child),
      ],
    );
  }
}

/// 附加费选项（对齐 smdcapp TableFjfBean）
class _FjfOption {
  const _FjfOption({required this.id, required this.name});

  /// 桌台类型id（空串表示“无”）
  final String id;

  /// 展示名称
  final String name;
}

/// 附加费选择弹层（对齐 smdcapp FjfRecycleView：两列网格，选中项红框）
class _FjfSelectSheet extends StatelessWidget {
  const _FjfSelectSheet({required this.options, required this.selectedId});

  final List<_FjfOption> options;
  final String selectedId;

  static Future<_FjfOption?> show(
    BuildContext context, {
    required List<_FjfOption> options,
    required String selectedId,
  }) {
    return showModalBottomSheet<_FjfOption>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FjfSelectSheet(options: options, selectedId: selectedId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 顶部拖拽指示条
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E6EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题 + 右上角关闭按钮
          SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                const Text(
                  '选择附加费',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1D2129),
                  ),
                ),
                Positioned(
                  right: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.close,
                        size: 22,
                        color: Color(0xFF86909C),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 40,
              ),
              itemCount: options.length,
              itemBuilder: (BuildContext context, int index) {
                final _FjfOption option = options[index];
                final bool selected = option.id == selectedId;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(option),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? _brandRed : const Color(0xFFE5E6EB),
                      ),
                    ),
                    child: Text(
                      option.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF1D2129),
                      ),
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
