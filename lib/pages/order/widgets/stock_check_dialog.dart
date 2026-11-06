import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';

/// 品牌红（对齐 smdcapp red_e13426）
const Color _kBrandRed = Color(0xFFE13426);

/// 库存不足明细行（对齐 smdcapp CheckStockPopup2 列表项）
class StockCheckEntry {
  StockCheckEntry({required this.key, required this.name, required this.qty});

  /// 购物车行标识（随 saledetail 上传，服务端原样回传，用于删除对应行）
  final String key;

  /// 商品名称
  final String name;

  /// 下单数量
  final double qty;

  bool checked = false;
}

/// 库存不足弹窗结果
class StockCheckResult {
  const StockCheckResult({required this.deleteAll});

  /// 不允许销售-删除全部菜品
  final bool deleteAll;
}

/// 库存不足弹窗（对齐 smdcapp CheckStockPopup2 / dialog_check_stock.xml）
///
/// - 参数 2（允许出库，提示）：取消 / 删除（删除勾选行）/ 确定（允许销售，继续下单）
/// - 参数 3（不允许出库）：取消 / 删除全部菜品（清空全部无库存菜品后继续）
class StockCheckDialog extends StatefulWidget {
  const StockCheckDialog({
    super.key,
    required this.items,
    required this.allowSale,
    required this.onRemove,
  });

  final List<StockCheckEntry> items;

  /// true=允许出库，提示（参数2）；false=不允许出库（参数3）
  final bool allowSale;

  /// 删除勾选行（立即从购物车移除）
  final ValueChanged<List<StockCheckEntry>> onRemove;

  static Future<StockCheckResult?> show(
    BuildContext context, {
    required List<StockCheckEntry> items,
    required bool allowSale,
    required ValueChanged<List<StockCheckEntry>> onRemove,
  }) {
    return showDialog<StockCheckResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockCheckDialog(
        items: items,
        allowSale: allowSale,
        onRemove: onRemove,
      ),
    );
  }

  @override
  State<StockCheckDialog> createState() => _StockCheckDialogState();
}

class _StockCheckDialogState extends State<StockCheckDialog> {
  late final List<StockCheckEntry> _items = List<StockCheckEntry>.from(widget.items);

  bool get _allChecked =>
      _items.isNotEmpty && _items.every((StockCheckEntry e) => e.checked);

  void _toggleAll() {
    final bool next = !_allChecked;
    setState(() {
      for (final StockCheckEntry e in _items) {
        e.checked = next;
      }
    });
  }

  void _deleteChecked() {
    final List<StockCheckEntry> removed =
        _items.where((StockCheckEntry e) => e.checked).toList();
    if (removed.isEmpty) return;
    widget.onRemove(removed);
    setState(() => _items.removeWhere((StockCheckEntry e) => e.checked));
  }

  void _deleteAll() {
    if (_items.isEmpty) return;
    Navigator.of(context).pop(const StockCheckResult(deleteAll: true));
  }

  /// 确定：继续下单（勾选行由"删除"处理，对齐 smdcapp CheckStockPopup2）
  void _confirm() {
    Navigator.of(context).pop(const StockCheckResult(deleteAll: false));
  }

  /// 数量展示对齐 smdcapp（Java double toString：11.0 / 1.5）
  String _formatQty(double qty) =>
      qty == qty.roundToDouble() ? '${qty.toInt()}.0' : qty.toString();

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: DialogCard(
        width: 340,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildTitle(isDark),
            const SizedBox(height: 10),
            _buildHeader(isDark),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: _buildList(isDark),
            ),
            const SizedBox(height: 14),
            _buildActions(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(bool isDark) {
    return Row(
      children: <Widget>[
        Container(width: 3, height: 16, color: _kBrandRed),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            widget.allowSale ? '库存不足-允许销售' : '库存不足-不允许销售',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.close,
              size: 20,
              color: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF86909C),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      height: 38,
      color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F3F5),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          _CheckDot(checked: _allChecked, onTap: _toggleAll),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              '商品名称',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                '数量',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1D2129),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool isDark) {
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '暂无库存不足商品',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF86909C),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _items.length,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFEDEDEF),
      ),
      itemBuilder: (BuildContext context, int index) {
        final StockCheckEntry entry = _items[index];
        return InkWell(
          onTap: () => setState(() => entry.checked = !entry.checked),
          child: SizedBox(
            height: 44,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 8),
                _CheckDot(
                  checked: entry.checked,
                  onTap: () => setState(() => entry.checked = !entry.checked),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      _formatQty(entry.qty),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF1D2129),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        _button('取消', primary: false, onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 10),
        if (widget.allowSale) ...<Widget>[
          _button('删除', primary: false, onTap: _deleteChecked),
          const SizedBox(width: 10),
          _button('确定', onTap: _confirm),
        ] else
          _button('删除全部菜品', width: 132, onTap: _deleteAll),
      ],
    );
  }

  Widget _button(
    String text, {
    bool primary = true,
    double width = 84,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: DialogActionButton(
        text: text,
        primary: primary,
        height: 40,
        onTap: onTap,
      ),
    );
  }
}

/// 方形勾选框（对齐原生 CheckBox 视觉）
class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: checked ? _kBrandRed : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: checked
                ? _kBrandRed
                : (isDark ? const Color(0xFF5A5A5C) : const Color(0xFFC9CDD4)),
            width: 1.2,
          ),
        ),
        child: checked
            ? const Icon(Icons.check, size: 15, color: Colors.white)
            : null,
      ),
    );
  }
}
