import 'package:flutter/material.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 可选必点菜选中项（对齐 smdcapp MustPopup2 → ProductBusiness.processMustCheck 输出）
class MustSelectResult {
  MustSelectResult({required this.raw, required this.selectNum});

  /// 必点菜商品原始数据（productid/name/sellprice/specid/specname/combflag/mustqty）
  final Map<String, dynamic> raw;

  /// 选项数（弹窗内点选份数，对齐 smdcapp MustproductlistBean.selectNum）
  final double selectNum;

  /// 每份必点数量（对齐 smdcapp mustqty，最低 1）
  double get mustqty {
    final double q = _toDouble(raw['mustqty']);
    return q > 0 ? q : 1;
  }

  /// 加入购物车数量 = 选项数 × 每份必点数量
  /// （对齐 smdcapp ProductBusiness.processMustProduct：qty = selectNum * mustNum）
  double get qty => selectNum * mustqty;
}

/// 可选必点菜选择弹窗（对齐 smdcapp MustPopup2 / dialog_must.xml）
///
/// 去下单时可选必点菜不满足时弹出（对齐 smdcapp goDownActivity → CartGoodsModel.addMust(true)）：
/// - 点右上角关闭：返回 null（下单拦截，调用方提示"可选必点菜未选择"）
/// - 点"加入购物车"：勾选项数合计满足每组要求后返回选中项
///   （对齐 processMustCheck：每人必点取人数、每笔订单取 1，
///   不足时 Toast"xxx，请至少选择N项商品"并停留弹窗）
class MustSelectSheet extends StatefulWidget {
  const MustSelectSheet({
    super.key,
    required this.groups,
    required this.personNum,
    this.preselected = const <String, double>{},
  });

  /// 可选必点方案组（mustrule==1，含 mustproductlist 商品明细）
  final List<Map<String, dynamic>> groups;

  /// 桌台人数（musttype==0 每人必点时的要求项数）
  final int personNum;

  /// 购物车已有可选必点菜回显（productid → 已点数量）
  final Map<String, double> preselected;

  static Future<List<MustSelectResult>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> groups,
    required int personNum,
    Map<String, double> preselected = const <String, double>{},
  }) {
    return showModalBottomSheet<List<MustSelectResult>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 对齐 smdcapp suspendShowPopup 默认值：点外部/返回键不关闭，仅右上角关闭
      isDismissible: false,
      enableDrag: false,
      builder: (_) => MustSelectSheet(
        groups: groups,
        personNum: personNum,
        preselected: preselected,
      ),
    );
  }

  @override
  State<MustSelectSheet> createState() => _MustSelectSheetState();
}

/// 方案组（含选择状态）
class _MustGroup {
  _MustGroup({required this.name, required this.musttype, required this.items});

  final String name;

  /// 0=每人必点一份 1=每笔订单必点一份
  final int musttype;
  final List<_MustItem> items;
}

/// 方案商品（含选择状态）
class _MustItem {
  _MustItem({required this.raw, this.selectNum = 0, this.isCheck = false});

  final Map<String, dynamic> raw;
  double selectNum;
  bool isCheck;
}

class _MustSelectSheetState extends State<MustSelectSheet> {
  static const Color _kBrandRed = Color(0xFFE13426);
  static const Color _kSelectedBg = Color(0xFFFCEBEB);
  static const Color _kUnselectedBorder = Color(0xFFD6D6D6);
  static const Color _kTextColor = Color(0xFF333333);

  /// 方案商品行高（对齐 smdcapp dishes_item_specification_grid_pop 约 40dp）
  static const double _kItemHeight = 42;

  late final List<_MustGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = _buildGroups();
  }

  /// 组装方案组，并按购物车已有数量回显选中状态
  /// （对齐 smdcapp MustPopup2：productType==2 且 qty>0 的行按 productid 匹配，
  /// selectNum = 已点数量、isCheck = true）
  List<_MustGroup> _buildGroups() {
    final List<_MustGroup> groups = <_MustGroup>[];
    for (final Map<String, dynamic> g in widget.groups) {
      final dynamic rawList = g['mustproductlist'];
      if (rawList is! List || rawList.isEmpty) continue;
      final List<_MustItem> items = <_MustItem>[];
      for (final dynamic raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        final String pid = raw['productid']?.toString() ?? '';
        if (pid.isEmpty) continue;
        final double pre = widget.preselected[pid] ?? 0;
        items.add(_MustItem(
          raw: raw,
          selectNum: pre > 0 ? pre : 0,
          isCheck: pre > 0,
        ));
      }
      if (items.isEmpty) continue;
      groups.add(_MustGroup(
        name: g['name']?.toString() ?? '',
        musttype: _toInt(g['musttype']),
        items: items,
      ));
    }
    return groups;
  }

  /// 每组要求项数（对齐 processMustCheck：musttype==0 每人必点取人数，否则取 1）
  double _requiredNum(_MustGroup group) => group.musttype == 0
      ? (widget.personNum < 1 ? 1 : widget.personNum).toDouble()
      : 1.0;

  /// 加减数量（对齐 MustPopup2 ll_add/ll_minus：减到 0 取消勾选）
  void _changeQty(_MustItem item, double delta) {
    setState(() {
      final double next = item.selectNum + delta;
      if (next > 0) {
        item.selectNum = next;
        item.isCheck = true;
      } else {
        item.selectNum = 0;
        item.isCheck = false;
      }
    });
  }

  /// 加入购物车（对齐 MustPopup2.addCart → ProductBusiness.processMustCheck）
  void _submit() {
    for (final _MustGroup group in _groups) {
      final double total = group.items
          .where((_MustItem item) => item.isCheck)
          .fold(0.0, (double sum, _MustItem item) => sum + item.selectNum);
      final double required = _requiredNum(group);
      if (total < required) {
        Toast.show('${group.name}，请至少选择${required.toInt()}项商品');
        return;
      }
    }
    final List<MustSelectResult> results = <MustSelectResult>[];
    for (final _MustGroup group in _groups) {
      for (final _MustItem item in group.items) {
        if (!item.isCheck || item.selectNum <= 0) continue;
        results.add(MustSelectResult(raw: item.raw, selectNum: item.selectNum));
      }
    }
    Navigator.of(context).pop(results);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color titleColor = isDark ? Colors.white : const Color(0xFF1D2129);
    final Color closeColor = isDark ? const Color(0xFF999999) : const Color(0xFF4E5969);
    final Color cardColor = isDark ? const Color(0xFF2A2B2C) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 标题栏（对齐 dialog_must：居中标题 + 右上关闭按钮）
          SizedBox(
            height: 46,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Text(
                  '请选择必点菜',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: closeColor, width: 1.2),
                        ),
                        child: Icon(Icons.close, size: 14, color: closeColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 方案组 + 商品网格
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              itemCount: _groups.length,
              itemBuilder: (BuildContext context, int index) {
                return _buildGroup(_groups[index], titleColor, cardColor, isDark);
              },
            ),
          ),
          // 加入购物车
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              10 + MediaQuery.of(context).padding.bottom,
            ),
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '加入购物车',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单个方案组（对齐 dishes_item_specification_title_pop：方案标题 + 两列商品网格）
  Widget _buildGroup(
    _MustGroup group,
    Color titleColor,
    Color cardColor,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Text(
            // 对齐 smdcapp MustPopup2：musttype 0=每人必点一份 1=每笔订单必点一份
            '${group.name}(${group.musttype == 0 ? '每人必点一份' : '每笔订单必点一份'})',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double cellW = (constraints.maxWidth - 12) / 2;
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 12,
              childAspectRatio: cellW / _kItemHeight,
              children: group.items
                  .map((_MustItem item) => _buildItem(item, cardColor, isDark))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  /// 单个商品（对齐 dishes_item_specification_grid_pop：名称(价格)x必点数量 +
  /// 左减号/右加号 + 右上数量角标，选中态红框粉底）
  Widget _buildItem(
    _MustItem item,
    Color cardColor,
    bool isDark,
  ) {
    final String name = item.raw['name']?.toString() ?? '';
    final double sellprice = _toDouble(item.raw['sellprice']);
    final double mustqty = _toDouble(item.raw['mustqty']) > 0
        ? _toDouble(item.raw['mustqty'])
        : 1;
    final bool selected = item.isCheck && item.selectNum > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // 名称框（对齐 tv_size：满宽居中、选中红框粉底/未选灰框白底）
        Positioned.fill(
          child: GestureDetector(
            // 对齐 MustPopup2 tv_size.onClick：点击名称框同样 +1
            onTap: () => _changeQty(item, 1),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? _kSelectedBg : cardColor,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: selected ? _kBrandRed : _kUnselectedBorder,
                  width: 0.8,
                ),
              ),
              child: Text(
                // 对齐 smdcapp：name(sellprice)x mustqty（保持 1.0 形式的数字展示）
                '$name(${_fmtNum(sellprice)})x${_fmtNum(mustqty)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? _kTextColor
                      : (isDark ? const Color(0xFFDDDDDD) : _kTextColor),
                ),
              ),
            ),
          ),
        ),
        // 减号（对齐 icon_minus_red：白底红圈红减号，与左边框留出间距）
        Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => _changeQty(item, -1),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF242526) : Colors.white,
                  border: Border.all(color: _kBrandRed, width: 1.4),
                ),
                child: const Icon(Icons.remove, size: 13, color: _kBrandRed),
              ),
            ),
          ),
        ),
        // 加号（对齐 icon_add：红底白十字，与右边框留出间距）
        Positioned(
          right: 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => _changeQty(item, 1),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBrandRed,
                ),
                child: const Icon(Icons.add, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
        // 已选数量角标（选中且数量>0 时显示，跨压在名称框右上角，避开加号）
        if (selected)
          Positioned(
            right: -9,
            top: -7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _kBrandRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  item.selectNum.toInt().toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 数字展示（对齐 smdcapp Kotlin Double.toString：整数值保留一位小数 1.0/2.0）
String _fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(1);
  return v.toString();
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
