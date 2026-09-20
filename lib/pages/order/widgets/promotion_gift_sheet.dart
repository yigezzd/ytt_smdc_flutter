import 'package:flutter/material.dart';
import 'package:flutter_deer/util/promotion_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 选中的赠品（下单前并入待下单明细，对齐 smdcapp PrometionGivePopup.onCallBack）
class PromotionGiftSelection {
  const PromotionGiftSelection({
    required this.cxmbillid,
    required this.bxxpxxflag,
    required this.productid,
    required this.name,
    required this.qty,
    this.unit = '',
    this.typeid = '',
    this.sellprice = 0,
  });

  /// 赠品所属促销活动ID（对齐 smdcapp cxmbillid）
  final String cxmbillid;

  /// 赠品标记：1=买赠 4=满赠（对齐 smdcapp bxxpxxflag）
  final int bxxpxxflag;

  final String productid;
  final String name;
  final double qty;
  final String unit;
  final String typeid;
  final double sellprice;
}

/// 促销赠品选择弹窗（对齐 smdcapp PrometionGivePopup）
///
/// 下单前校验买赠/满赠活动：有剩余可赠额度时弹出，供服务员勾选赠品；
/// - 返回 null：取消（中止下单）
/// - 返回空列表：跳过（不参与活动，直接下单）
/// - 返回列表：选中的赠品及数量
class PromotionGiftSheet extends StatefulWidget {
  const PromotionGiftSheet({super.key, required this.activities});

  final List<PromotionGiftActivity> activities;

  static Future<List<PromotionGiftSelection>?> show(
    BuildContext context, {
    required List<PromotionGiftActivity> activities,
  }) {
    return showModalBottomSheet<List<PromotionGiftSelection>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => PromotionGiftSheet(activities: activities),
    );
  }

  @override
  State<PromotionGiftSheet> createState() => _PromotionGiftSheetState();
}

class _PromotionGiftSheetState extends State<PromotionGiftSheet> {
  static const Color _kBrandRed = Color(0xFFE13426);

  /// 当前活动已选赠品数量合计
  double _selectedQty(PromotionGiftActivity activity) {
    double sum = 0;
    for (final PromotionGift g in activity.prolsit) {
      sum += g.selectQty;
    }
    return sum;
  }

  void _changeGiftQty(PromotionGiftActivity activity, PromotionGift gift, double delta) {
    if (delta > 0 && _selectedQty(activity) + delta > activity.remainQty) {
      Toast.show('已选最大数量');
      return;
    }
    setState(() {
      final double next = gift.selectQty + delta;
      gift.selectQty = next > 0 ? next : 0;
    });
  }

  List<PromotionGiftSelection> _collectSelections() {
    final List<PromotionGiftSelection> selections = <PromotionGiftSelection>[];
    for (final PromotionGiftActivity activity in widget.activities) {
      for (final PromotionGift gift in activity.prolsit) {
        if (gift.selectQty <= 0) continue;
        selections.add(PromotionGiftSelection(
          cxmbillid: activity.billid,
          bxxpxxflag: activity.giftFlag,
          productid: gift.productid,
          name: gift.name,
          qty: gift.selectQty,
          unit: gift.unit,
          typeid: gift.typeid,
          sellprice: gift.sellprice,
        ));
      }
    }
    return selections;
  }

  String _fmtQty(double qty) =>
      qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color titleColor = isDark ? Colors.white : const Color(0xFF1D2129);
    final Color subColor = isDark ? const Color(0xFF999999) : const Color(0xFF86909C);
    final Color cardColor = isDark ? const Color(0xFF2A2B2C) : const Color(0xFFF7F8FA);

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
                    '促销活动',
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
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: widget.activities.length,
              itemBuilder: (BuildContext context, int index) {
                final PromotionGiftActivity activity = widget.activities[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        '${activity.name}（${activity.prolsit.length}选${_fmtQty(activity.remainQty)}）',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                    ),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 3.4,
                      children: activity.prolsit
                          .map((PromotionGift gift) =>
                              _buildGiftItem(activity, gift, cardColor, titleColor, subColor))
                          .toList(),
                    ),
                  ],
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
                      onPressed: () =>
                          Navigator.of(context).pop(<PromotionGiftSelection>[]),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: subColor,
                        side: const BorderSide(color: Color(0xFFE5E6EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: const Text('跳过', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(_collectSelections()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrandRed,
                        foregroundColor: Colors.white,
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

  /// 单个赠品（名称 + 数量加减，对齐 smdcapp dishes_item_specification_grid_pop）
  Widget _buildGiftItem(
    PromotionGiftActivity activity,
    PromotionGift gift,
    Color cardColor,
    Color titleColor,
    Color subColor,
  ) {
    final bool selected = gift.selectQty > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? _kBrandRed : const Color(0xFFE5E6EB),
          width: 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              gift.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: titleColor),
            ),
          ),
          GestureDetector(
            onTap: () => _changeGiftQty(activity, gift, -1),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5E6EB), width: 1.2),
              ),
              child: Icon(Icons.remove, size: 12, color: subColor),
            ),
          ),
          SizedBox(
            width: 26,
            child: Center(
              child: Text(
                _fmtQty(gift.selectQty),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _changeGiftQty(activity, gift, 1),
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: _kBrandRed,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
