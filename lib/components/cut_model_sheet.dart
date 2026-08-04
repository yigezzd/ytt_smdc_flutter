import 'package:flutter/material.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';

/// 模式切换底部弹窗（对齐 smdcapp CutModelPopup）
///
/// 选项：正餐模式 / 快餐模式 / 配送模式
/// 点击选项后通过 [onSelected] 回调所选模式码，并自动关闭弹窗。
class CutModelSheet extends StatefulWidget {
  const CutModelSheet({super.key, required this.onSelected});

  /// 选中模式回调（1=快餐 2=正餐 3=配送）
  final ValueChanged<int> onSelected;

  @override
  State<CutModelSheet> createState() => _CutModelSheetState();
}

class _CutModelSheetState extends State<CutModelSheet> {
  /// 当前选中的模式（对齐 smdcapp SpUtils.getCurrentStoremodel 回显选中态）
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = StoreModeUtils.getCurrentStoreModel();
  }

  void _select(int mode) {
    setState(() => _selected = mode);
    // 先关闭弹窗再触发回调（回调中可能 push 新路由，若先 push 再 pop 会误弹新页面）
    Navigator.of(context).pop();
    widget.onSelected(mode);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF2F3F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 标题行：选择模式 + 关闭按钮
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '选择模式',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1D2129),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: Color(0xFF86909C)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 正餐模式（对齐 smdcapp ll_zheng）
          _ModeCard(
            title: '正餐模式',
            subtitle: '桌台点餐·正餐场景',
            selected: _selected == StoreModeUtils.storeModelNormal,
            onTap: () => _select(StoreModeUtils.storeModelNormal),
          ),
          const SizedBox(height: 10),
          // 快餐模式（对齐 smdcapp ll_kuai）
          _ModeCard(
            title: '快餐模式',
            subtitle: '快捷点餐·快餐场景',
            selected: _selected == StoreModeUtils.storeModelFast,
            onTap: () => _select(StoreModeUtils.storeModelFast),
          ),
          const SizedBox(height: 10),
          // 配送模式
          _ModeCard(
            title: '配送模式',
            subtitle: '外卖配送·配送场景',
            selected: _selected == 3,
            onTap: () => _select(3),
          ),
        ],
      ),
    );
  }
}

/// 单个模式选项卡片
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            // 单选指示器（对齐 smdcapp icon_select_yes / icon_select_no）
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? const Color(0xFFE63F31) : const Color(0xFFC9CDD4),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D2129),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF86909C),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
