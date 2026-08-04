import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/util/theme_utils.dart';

/// 底部状态筛选栏
///
/// [activeStatus] 为 null 表示"全部"
class StatusFilterBar extends StatelessWidget {
  const StatusFilterBar({
    super.key,
    required this.activeStatus,
    required this.counts,
    required this.totalCount,
    required this.onChanged,
  });

  final TableStatus? activeStatus;

  /// 各状态数量
  final Map<TableStatus, int> counts;

  final int totalCount;

  final ValueChanged<TableStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isDark ? Colors.black38 : const Color(0x14202333),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          // 全部
          Expanded(
            child: _FilterButton(
              label: '全部',
              count: totalCount,
              color: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF333333),
              selected: activeStatus == null,
              isAll: true,
              onTap: () => onChanged(null),
            ),
          ),
          // 各状态
          ...TableStatus.values.map(
            (TableStatus status) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _FilterButton(
                  label: status.label,
                  count: counts[status] ?? 0,
                  color: status.color,
                  selected: activeStatus == status,
                  onTap: () =>
                      // 再次点击当前状态 => 取消筛选
                      onChanged(activeStatus == status ? null : status),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
    this.isAll = false,
  });

  final String label;
  final int count;

  /// 状态主题色
  final Color color;
  final bool selected;

  /// "全部"按钮(白底样式)
  final bool isAll;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    final Color textColor = isDark
        ? (selected ? Colors.white : const Color(0xFFB8B8B8))
        : const Color(0xFF333333);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 状态色块图标
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: isAll ? Colors.white : color,
                    borderRadius: BorderRadius.circular(3),
                    border: isAll
                        ? Border.all(color: const Color(0xFFD9D9D9))
                        : null,
                  ),
                ),
                const SizedBox(width: 5),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '($count)',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
