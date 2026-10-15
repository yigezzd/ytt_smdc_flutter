import 'package:flutter/material.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/pages/home/table/table_repository.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/state_layout.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红（对齐 smdcapp red_e13426）
const Color _kBrandRed = Color(0xFFE13426);

/// 卡片边框默认灰（对齐 smdcapp color_D1D1D1）
const Color _kLineGray = Color(0xFFD1D1D1);

/// 主文字色（对齐 smdcapp color_1E1E1E）
const Color _kTextBlack = Color(0xFF1E1E1E);

/// 转菜打印开关存储键（对齐 smdcapp Constant.DISHES_ZC）
const String _kZcPrintKey = 'DISHES_ZC';

/// 转菜转出范围（对齐 smdcapp ChangeDishesPopup：确定=部分菜品转，整桌转菜=全部转出）
enum ChangeDishesAction { partial, all }

/// 转菜桌台选择结果
class ChangeDishesResult {
  const ChangeDishesResult({required this.table, required this.action});

  /// 选中的转入桌台
  final TableInfo table;

  /// 转出范围
  final ChangeDishesAction action;
}

/// 转菜桌台选择弹窗（对齐 smdcapp ChangeDishesPopup / dialog_change_dishes.xml）
///
/// 弹窗自行拉取区域列表与已开台桌台（tablestatus=1,2），区域Tab切换时重载桌台；
/// 桌台卡片对齐 smdcapp item_table_info：状态色底 + 名称状态色 + 并台/预打标签 +
/// 人数/开台时长/金额 + 状态色底部状态条 + 锁台遮罩 + 选中角标；
/// 底部为"打印转菜单"开关与 取消 / 整桌转菜 / 确定 三按钮。
class ChangeDishesSheet extends StatefulWidget {
  const ChangeDishesSheet({
    super.key,
    this.excludeTableId = '',
    this.excludeSaleid = '',
  });

  /// 需排除的桌台（当前桌台，转出与转入同桌无意义）
  final String excludeTableId;

  /// 需排除的主单（当前桌台主单）
  final String excludeSaleid;

  /// 显示转菜桌台选择弹窗，取消返回 null
  static Future<ChangeDishesResult?> show(
    BuildContext context, {
    String excludeTableId = '',
    String excludeSaleid = '',
  }) {
    return showModalBottomSheet<ChangeDishesResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeDishesSheet(
        excludeTableId: excludeTableId,
        excludeSaleid: excludeSaleid,
      ),
    );
  }

  @override
  State<ChangeDishesSheet> createState() => _ChangeDishesSheetState();
}

class _ChangeDishesSheetState extends State<ChangeDishesSheet> {
  bool _loading = true;
  List<TableArea> _areas = <TableArea>[];

  /// 区域下标: 0=全部, 其余对应 [_areas]
  int _areaIndex = 0;
  List<TableInfo> _tables = <TableInfo>[];
  String? _selectedTableId;
  late bool _zcPrint;

  @override
  void initState() {
    super.initState();
    // 转菜打印开关持久化（对齐 smdcapp Constant.DISHES_ZC）
    _zcPrint = SpUtil.getBool(_kZcPrintKey) ?? false;
    _loadAreas();
    _loadTables();
  }

  /// 当前区域id（"全部"为空串，对齐 smdcapp areaid=""）
  String get _currentAreaid {
    if (_areaIndex <= 0 || _areaIndex > _areas.length) {
      return '';
    }
    return _areas[_areaIndex - 1].areaid;
  }

  TableInfo? get _selectedTable {
    for (final TableInfo t in _tables) {
      if (t.tableid == _selectedTableId) {
        return t;
      }
    }
    return null;
  }

  /// 区域列表（对齐 smdcapp ChangeDishesPopup.getAreaList）
  Future<void> _loadAreas() async {
    try {
      final List<TableArea> areas = await TableRepository.fetchAreaList(
        masterDevice: ConnectionManager.pcAlive,
      );
      if (!mounted) {
        return;
      }
      setState(() => _areas = areas);
    } catch (_) {}
  }

  /// 已开台桌台列表（对齐 smdcapp getTableInfo：tablestatus="1,2"）
  Future<void> _loadTables() async {
    final String requestedAreaid = _currentAreaid;
    setState(() => _loading = true);
    try {
      final List<TableInfo> tables = await TableRepository.fetchTableInfoList(
        masterDevice: ConnectionManager.pcAlive,
        areaid: requestedAreaid,
        tablestatus: '1,2',
      );
      if (!mounted || requestedAreaid != _currentAreaid) {
        return;
      }
      setState(() {
        _tables = tables.where(_isSelectable).toList();
        _loading = false;
        if (_selectedTableId != null &&
            !_tables.any((TableInfo t) => t.tableid == _selectedTableId)) {
          _selectedTableId = null;
        }
      });
    } catch (_) {
      if (!mounted || requestedAreaid != _currentAreaid) {
        return;
      }
      setState(() {
        _tables = <TableInfo>[];
        _loading = false;
      });
    }
  }

  /// 可转入桌台：有主单且非当前桌
  bool _isSelectable(TableInfo t) {
    final String saleid = t.tmp?.saleid ?? '';
    return t.tableid.isNotEmpty &&
        saleid.isNotEmpty &&
        saleid != widget.excludeSaleid &&
        t.tableid != widget.excludeTableId;
  }

  void _onAreaChanged(int index) {
    if (_areaIndex == index) {
      return;
    }
    setState(() => _areaIndex = index);
    _loadTables();
  }

  void _toggleZcPrint() {
    setState(() => _zcPrint = !_zcPrint);
    SpUtil.putBool(_kZcPrintKey, _zcPrint);
  }

  /// 确定/整桌转菜前的桌台校验（对齐 smdcapp checkTableClick）
  void _popWithAction(ChangeDishesAction action) {
    final TableInfo? table = _selectedTable;
    if (table == null) {
      Toast.show('请先选择桌台');
      return;
    }
    if (table.isLocked) {
      Toast.show('桌台已被锁住无法操作！');
      return;
    }
    Navigator.pop(context, ChangeDishesResult(table: table, action: action));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _buildHeader(),
            _buildAreaTabs(),
            Expanded(child: _buildGrid()),
            _buildPrintSwitchRow(),
            _buildButtonBar(),
          ],
        ),
      ),
    );
  }

  /// 标题栏：红竖条 + 整单操作 + 关闭（对齐 dialog_change_dishes.xml 头部）
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 2),
      child: Row(
        children: <Widget>[
          Container(width: 2, height: 14, color: _kBrandRed),
          const SizedBox(width: 5),
          const Expanded(
            child: Text('整单操作',
                style: TextStyle(fontSize: 14, color: _kTextBlack)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.cancel_outlined,
                  size: 22, color: Color(0xFF666666)),
            ),
          ),
        ],
      ),
    );
  }

  /// 区域Tab：名称(桌台数)，选中红色下划线（对齐 smdcapp AreaAdapter）
  Widget _buildAreaTabs() {
    final int allTotal = _areas.fold<int>(
        0, (int sum, TableArea a) => sum + a.tabletotal);
    return SizedBox(
      height: 39,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _areas.length + 1,
        itemBuilder: (BuildContext context, int index) {
          final bool selected = _areaIndex == index;
          final String name = index == 0 ? '全部' : _areas[index - 1].name;
          final int count =
              index == 0 ? allTotal : _areas[index - 1].tabletotal;
          final String label =
              index == 0 && _areas.isEmpty ? name : '$name($count)';
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onAreaChanged(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      color: selected
                          ? const Color(0xFF1D2129)
                          : const Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: selected ? 20 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _kBrandRed,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_tables.isEmpty) {
      return const Center(
        child: StateLayout(type: StateType.order, hintText: '暂无数据'),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 1.1,
      ),
      itemCount: _tables.length,
      itemBuilder: (BuildContext context, int index) {
        final TableInfo t = _tables[index];
        return _ZcTableCard(
          table: t,
          selected: t.tableid == _selectedTableId,
          onTap: () => setState(() => _selectedTableId = t.tableid),
        );
      },
    );
  }

  /// 打印转菜单开关（对齐 smdcapp ChangeDishesPopup.imgdy：绿色开关 40x24）
  Widget _buildPrintSwitchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Row(
        children: <Widget>[
          const Text('打印转菜单',
              style: TextStyle(fontSize: 14, color: Colors.black)),
          const SizedBox(width: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleZcPrint,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 24,
              decoration: BoxDecoration(
                color: _zcPrint
                    ? const Color(0xFF07C160)
                    : const Color(0xFFC5C5C5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment:
                    _zcPrint ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部按钮：取消 / 整桌转菜 / 确定（对齐 smdcapp tv_cancel/tv_table_change/tv_sure）
  Widget _buildButtonBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildButton('取消', false, () => Navigator.pop(context)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildButton('整桌转菜', false,
                () => _popWithAction(ChangeDishesAction.all)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildButton('确定', true,
                () => _popWithAction(ChangeDishesAction.partial)),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(String text, bool primary, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? _kBrandRed : const Color(0xFFF5F5F6),
          borderRadius: BorderRadius.circular(primary ? 4 : 6),
          border: primary
              ? null
              : Border.all(color: const Color(0xFFD2D6D7), width: 0.5),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            color: primary ? Colors.white : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }
}

/// 转菜桌台卡片（对齐 smdcapp item_table_info.xml）
///
/// 从上到下：桌名(状态色) + 并台/反结标签 → 人数/开台时长 + 预打 → 金额 + 未称/已称
/// → 状态色底部状态条(挂单显示"挂"徽章)；锁台时整卡深色遮罩 + 红色锁图标，
/// 选中时四边状态色描边 + 左上角绿色对勾角标。
class _ZcTableCard extends StatelessWidget {
  const _ZcTableCard({
    required this.table,
    required this.selected,
    required this.onTap,
  });

  final TableInfo table;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TableStatus status = table.status;
    final bool isIdle = status.isPlain;
    final Color statusColor = status.color;
    final String name = table.name.isNotEmpty ? table.name : table.code;
    final (int, int, bool)? timeParts = table.timeParts;
    final String? amountText = table.amountText;
    final String weighText =
        ParamsSpUtils.isReweigh() ? (table.tmp?.weighText ?? '') : '';
    final String returnbillno =
        (table.rawJson?['tmp'] as Map?)?['returnbillno']?.toString() ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: status.bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected && !isIdle ? statusColor : _kLineGray,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 5, 6, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                  color: isIdle ? _kTextBlack : statusColor,
                                ),
                              ),
                            ),
                            if (table.mergeNote != null)
                              _redPill(table.mergeNote!),
                            if (returnbillno.isNotEmpty) _redPill('反结'),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const Icon(Icons.person_outline,
                                        size: 11, color: Color(0xFF4E5969)),
                                    const SizedBox(width: 2),
                                    Text(
                                      table.personText,
                                      style: const TextStyle(
                                          fontSize: 10, color: _kTextBlack),
                                    ),
                                    if (timeParts != null) ...<Widget>[
                                      const SizedBox(width: 7),
                                      const Icon(Icons.schedule,
                                          size: 11, color: Color(0xFF4E5969)),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${timeParts.$1}',
                                        style: const TextStyle(
                                            fontSize: 10, color: _kTextBlack),
                                      ),
                                      _unitBadge('h'),
                                      if (timeParts.$3) ...<Widget>[
                                        const SizedBox(width: 1),
                                        Text(
                                          '${timeParts.$2}',
                                          style: const TextStyle(
                                              fontSize: 10, color: _kTextBlack),
                                        ),
                                        _unitBadge('m'),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (table.isPrePrint) _outlinePill('预打'),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: <Widget>[
                            if (amountText != null) ...<Widget>[
                              const Text('¥',
                                  style: TextStyle(
                                      fontSize: 10, color: _kTextBlack)),
                              const SizedBox(width: 1),
                              Expanded(
                                child: Text(
                                  amountText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _kTextBlack,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                            if (weighText.isNotEmpty)
                              _redPill(weighText,
                                  color: weighText == '未称'
                                      ? _kBrandRed
                                      : const Color(0xFF00C15A)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _buildStatusBar(status),
                ],
              ),
              if (selected)
                const Positioned(
                    left: 0, top: 0, child: _CornerSelectBadge()),
              // 锁台遮罩：整卡深色 + 红色锁图标（对齐 smdcapp rl_lock/icon_lock）
              if (table.isLocked)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0x90000000),
                    child: Align(
                      alignment: const Alignment(0, -0.25),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _kBrandRed, width: 3),
                        ),
                        child: const Icon(Icons.lock,
                            size: 24, color: _kBrandRed),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部状态条：状态色底 + 居中白色状态文案，挂单时显示"挂"徽章
  Widget _buildStatusBar(TableStatus status) {
    return Container(
      height: 24,
      color: status.color,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (table.isHang) ...<Widget>[
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white),
              ),
              child: const Text('挂',
                  style: TextStyle(fontSize: 12, color: Colors.white)),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            status.label,
            style: const TextStyle(fontSize: 14, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// 红底白字标签（对齐 smdcapp red_shape_radius5：并台/反结/未称/已称）
  Widget _redPill(String text, {Color color = _kBrandRed}) {
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.3),
      ),
    );
  }

  /// 白底红框标签（对齐 smdcapp com_shape_line_red_4_bg_white：预打）
  Widget _outlinePill(String text) {
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kBrandRed, width: 0.5),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: _kBrandRed, height: 1.3),
      ),
    );
  }

  /// 时长单位徽章 h/m（对齐 smdcapp gray_shape_radius_5dp3：#8B8B8B 圆角）
  Widget _unitBadge(String unit) {
    return Container(
      margin: const EdgeInsets.only(left: 1),
      padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
      decoration: BoxDecoration(
        color: const Color(0xFF8B8B8B),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        unit,
        style: const TextStyle(fontSize: 8.5, color: Colors.white, height: 1.2),
      ),
    );
  }
}

/// 选中角标：左上角绿色三角 + 白色对勾（对齐 smdcapp tb_select）
class _CornerSelectBadge extends StatelessWidget {
  const _CornerSelectBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(
        painter: _CornerTrianglePainter(),
        child: const Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 3, top: 2),
            child: Icon(Icons.check, size: 12, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _CornerTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xFF00C23A);
    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
