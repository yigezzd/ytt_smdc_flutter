import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 全应用统一的日期选择器（年/月/日），自动适配深色/浅色主题。
///
/// 用法：
/// ```dart
/// final picked = await showCommonDatePicker(context, initial: DateTime.now());
/// if (picked != null && mounted) { ... }
/// ```
Future<DateTime?> showCommonDatePicker(BuildContext context, {required DateTime initial}) async {
  DateTime tempDate = initial;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (c) {
      final textColor = Theme.of(c).colorScheme.onSurface;
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text('取消',
                        style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(c, tempDate),
                    child: Text('确定', style: TextStyle(color: Theme.of(c).colorScheme.primary)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(c).dividerColor),
            Expanded(
              child: Row(
                children: [
                  // 年
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.year - 2020,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        tempDate = DateTime(2020 + i, tempDate.month, tempDate.day);
                      },
                      children: List.generate(
                          20,
                          (i) => Center(
                              child: Text('${2020 + i}年',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                  // 月
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.month - 1,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        tempDate = DateTime(tempDate.year, i + 1, tempDate.day);
                      },
                      children: List.generate(
                          12,
                          (i) => Center(
                              child: Text('${i + 1}月',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                  // 日
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.day - 1,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        final maxDay = DateTime(tempDate.year, tempDate.month + 1, 0).day;
                        tempDate =
                            DateTime(tempDate.year, tempDate.month, (i + 1).clamp(1, maxDay));
                      },
                      children: List.generate(
                          31,
                          (i) => Center(
                              child: Text('${i + 1}日',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 全应用统一的月份选择器（仅年/月），自动适配深色/浅色主题。
///
/// 用于"本月"等仅需选择年月的场景。
/// 返回值中 day 字段为 1，调用方需自行计算起止日期。
///
/// 用法：
/// ```dart
/// final picked = await showCommonMonthPicker(context, initial: DateTime.now());
/// if (picked != null && mounted) {
///   final start = DateTime(picked.year, picked.month);
///   final end = DateTime(picked.year, picked.month + 1, 0);
/// }
/// ```
Future<DateTime?> showCommonMonthPicker(BuildContext context, {required DateTime initial}) async {
  DateTime tempDate = DateTime(initial.year, initial.month);
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (c) {
      final textColor = Theme.of(c).colorScheme.onSurface;
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text('取消',
                        style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(c, tempDate),
                    child: Text('确定', style: TextStyle(color: Theme.of(c).colorScheme.primary)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(c).dividerColor),
            Expanded(
              child: Row(
                children: [
                  // 年
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.year - 2020,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        tempDate = DateTime(2020 + i, tempDate.month);
                      },
                      children: List.generate(
                          20,
                          (i) => Center(
                              child: Text('${2020 + i}年',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                  // 月
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.month - 1,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        tempDate = DateTime(tempDate.year, i + 1);
                      },
                      children: List.generate(
                          12,
                          (i) => Center(
                              child: Text('${i + 1}月',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
