import 'package:flutter/material.dart';

/// 公共表单选择行组件
///
/// 左侧标签（支持必填 * 标记），右侧展示已选值或"请选择"占位文字，
/// 带右箭头，点击触发回调。
class SelectFieldItem extends StatelessWidget {
  /// 标签文字
  final String label;

  /// 当前已选值（为空时显示 hint）
  final String value;

  /// 占位提示文字，默认"请选择"
  final String hint;

  /// 点击事件
  final VoidCallback onTap;

  /// 是否展示必填 * 标记
  final bool required;

  /// 标签宽度，默认 72
  final double labelWidth;

  const SelectFieldItem({
    super.key,
    required this.label,
    required this.value,
    this.hint = '请选择',
    required this.onTap,
    this.required = false,
    this.labelWidth = 72,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // 星号固定占 8px，文字始终从同一起点左对齐
            SizedBox(
              width: 8,
              child: required
                  ? const Text(
                      '*',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    )
                  : null,
            ),
            SizedBox(
              width: labelWidth - 8,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : hint,
                style: TextStyle(
                  fontSize: 13,
                  color: value.isNotEmpty
                      ? const Color(0xFF111827)
                      : const Color(0xFF006EFF),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
