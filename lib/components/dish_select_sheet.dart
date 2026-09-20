import 'package:flutter/material.dart';

/// 可选菜品项（整单操作用）
class DishSelectEntry {
  const DishSelectEntry({
    required this.key,
    required this.name,
    this.subtitle = '',
    this.disabled = false,
  });

  /// 业务唯一标识（调用方自行映射回原始数据）
  final String key;

  final String name;

  /// 副标题（如已退数量、备注）
  final String subtitle;

  /// 不可选（如已退完/赠送商品不能退菜）
  final bool disabled;
}

/// 整单操作菜品选择弹窗（对齐 smdcapp 整桌操作前的菜品勾选步骤）
///
/// 返回选中的 key 列表；返回 null 表示取消。
class DishSelectSheet extends StatefulWidget {
  const DishSelectSheet({
    super.key,
    required this.title,
    required this.entries,
  });

  final String title;
  final List<DishSelectEntry> entries;

  static Future<List<String>?> show(
    BuildContext context, {
    required String title,
    required List<DishSelectEntry> entries,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishSelectSheet(title: title, entries: entries),
    );
  }

  @override
  State<DishSelectSheet> createState() => _DishSelectSheetState();
}

class _DishSelectSheetState extends State<DishSelectSheet> {
  final Set<String> _checked = <String>{};

  static const Color _kBrandRed = Color(0xFFE63F31);

  List<DishSelectEntry> get _selectable =>
      widget.entries.where((DishSelectEntry e) => !e.disabled).toList();

  bool get _allChecked =>
      _selectable.isNotEmpty && _selectable.every((DishSelectEntry e) => _checked.contains(e.key));

  void _toggleAll() {
    setState(() {
      if (_allChecked) {
        _checked.clear();
      } else {
        _checked
          ..clear()
          ..addAll(_selectable.map((DishSelectEntry e) => e.key));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color titleColor = isDark ? Colors.white : const Color(0xFF1D2129);
    final Color subColor = isDark ? const Color(0xFF999999) : const Color(0xFF86909C);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _kBrandRed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close, size: 20, color: subColor),
                ),
              ],
            ),
          ),
          // 全选
          InkWell(
            onTap: _toggleAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    _allChecked ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: _allChecked ? _kBrandRed : subColor,
                  ),
                  const SizedBox(width: 8),
                  Text('全选', style: TextStyle(fontSize: 14, color: titleColor)),
                  const Spacer(),
                  Text(
                    '已选${_checked.length}项',
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF2F3F5)),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: widget.entries.length,
              itemBuilder: (BuildContext context, int index) {
                final DishSelectEntry e = widget.entries[index];
                final bool checked = _checked.contains(e.key);
                return InkWell(
                  onTap: e.disabled
                      ? null
                      : () => setState(() {
                            if (checked) {
                              _checked.remove(e.key);
                            } else {
                              _checked.add(e.key);
                            }
                          }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          checked ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 20,
                          color: e.disabled
                              ? const Color(0xFFC9CDD4)
                              : (checked ? _kBrandRed : subColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: e.disabled ? const Color(0xFFC9CDD4) : titleColor,
                                ),
                              ),
                              if (e.subtitle.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    e.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: subColor),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: subColor,
                        side: const BorderSide(color: Color(0xFFE5E6EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: const Text('取消', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _checked.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(_checked.toList()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrandRed,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFF2C4BF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '确定',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
