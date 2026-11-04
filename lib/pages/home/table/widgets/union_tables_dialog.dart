import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';

/// 并台关联桌台明细弹窗（统一弹窗样式：标题 + 明细列表 + 关闭按钮）
class UnionTablesDialog extends StatelessWidget {
  const UnionTablesDialog({super.key, required this.tables});

  /// 并台关联的桌台列表
  final List<TableInfo> tables;

  static Future<void> show(BuildContext context, List<TableInfo> tables) {
    return showDialog<void>(
      context: context,
      builder: (_) => UnionTablesDialog(tables: tables),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: DialogCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '并台桌台',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < tables.length; i++)
                      _buildTableRow(
                        tables[i],
                        isDark,
                        isLast: i == tables.length - 1,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: DialogActionButton(
                text: '关闭',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableRow(TableInfo table, bool isDark, {required bool isLast}) {
    final double amt = table.tmp?.amt ?? 0;

    return Container(
      margin: isLast ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${table.name}（${table.status.label}）',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '¥${amt.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE63F31),
            ),
          ),
        ],
      ),
    );
  }
}
