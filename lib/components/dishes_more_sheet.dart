import 'package:flutter/material.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红（对齐本项目 spec_cook_sheet 等较新弹窗组件）
const Color _kBrandRed = Color(0xFFE63F31);

/// 点菜页更多操作弹窗（对齐 smdcapp DishesMorePopup）
///
/// 选项：
/// - 录临时菜（始终显示，对齐 NAME_ADD_TEMP_PRODUCT）
/// - 团券核销（仅 verservice_dy_pay 开启且正餐模式，对齐 NAME_VERIFICATION_TUAN_COUPUN）
///
/// 点击选项后返回选项名称并自动关闭弹窗。
class DishesMoreSheet extends StatelessWidget {
  const DishesMoreSheet({super.key});

  /// 录临时菜（对齐 smdcapp DishesMorePopup.NAME_ADD_TEMP_PRODUCT）
  static const String nameAddTempProduct = '录临时菜';

  /// 团券核销（对齐 smdcapp DishesMorePopup.NAME_VERIFICATION_TUAN_COUPUN）
  static const String nameVerificationTuanCoupon = '团券核销';

  /// 显示更多操作弹窗，返回所选操作名称（取消返回 null）
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DishesMoreSheet(),
    );
  }

  /// 构建选项列表（对齐 smdcapp DishesMorePopup init：
  /// 录临时菜始终添加；团券核销需 getVerservice_Dy_Pay && storemodel==2）
  List<_MoreAction> _buildItems() {
    final List<_MoreAction> items = <_MoreAction>[
      const _MoreAction(
        name: nameAddTempProduct,
        subtitle: '手动录入临时菜品并加购',
        icon: Icons.edit_note,
      ),
    ];
    final bool dyPay = SpUtil.getBool(Constant.verservice612) ?? false;
    if (dyPay &&
        StoreModeUtils.getCurrentStoreModel() ==
            StoreModeUtils.storeModelNormal) {
      items.add(const _MoreAction(
        name: nameVerificationTuanCoupon,
        subtitle: '抖音 / 美团等团购券核销',
        icon: Icons.confirmation_number_outlined,
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final List<_MoreAction> items = _buildItems();
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildHeader(context, isDark),
          const SizedBox(height: 6),
          ...items
              .map((e) => _buildItem(context, e, isDark)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// 标题栏（红条 + 更多操作 + 关闭，对齐本项目统一弹窗风格）
  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 3.5,
            height: 16,
            decoration: BoxDecoration(
              color: _kBrandRed,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '更多操作',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              Icons.close,
              size: 20,
              color:
                  isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 选项卡片（图标 + 标题 + 说明 + 箭头，按压水波纹反馈）
  Widget _buildItem(BuildContext context, _MoreAction item, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(item.name),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF3D2826)
                        : const Color(0xFFFFF1F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, size: 22, color: _kBrandRed),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : const Color(0xFF1D2129),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFF999999)
                              : const Color(0xFF86909C),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color:
                      isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 更多操作选项模型
class _MoreAction {
  const _MoreAction({
    required this.name,
    required this.subtitle,
    required this.icon,
  });

  final String name;
  final String subtitle;
  final IconData icon;
}
