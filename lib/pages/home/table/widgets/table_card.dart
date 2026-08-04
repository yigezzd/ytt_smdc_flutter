import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/res/colors.dart';
import 'package:flutter_deer/util/theme_utils.dart';

/// 桌台卡片
///
/// 视觉设计：
/// - 非空闲卡片带状态色柔和渐变背景
/// - 胶囊形状态徽章（空闲为浅绿底+绿字）
/// - 柔和阴影 + 14px 圆角，整体轻商务风格
class TableCard extends StatefulWidget {
  const TableCard({
    super.key,
    required this.table,
    required this.onTap,
    this.animation,
  });

  final TableInfo table;
  final ValueChanged<TableInfo> onTap;

  /// 入场动画(网格切换时的交错动画)
  final Animation<double>? animation;

  @override
  State<TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<TableCard> {
  bool _pressed = false;

  /// 空闲状态徽章配色
  static const Color _idleBadgeBg = Color(0xFFE9F7EF);
  static const Color _idleBadgeText = Color(0xFF00A854);

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  /// 角标小标签（锁台/挂单/预打）
  Widget _miniTag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: color,
          height: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final bool isDark = context.isDark;
    final TableInfo table = widget.table;
    final TableStatus status = table.status;
    final Color statusColor = status.color;
    final bool isIdle = status.isPlain;

    // 桌号文字颜色：空闲用默认色，其它状态用状态主题色（对齐 smdcapp tableNameColor）
    final Color nameColor = isIdle
        ? (isDark ? Colours.dark_text : const Color(0xFF1D2129))
        : statusColor;

    final String? amountText = table.amountText;
    final String? timeText = table.timeText;

    // 卡片背景：非空闲带状态色柔和渐变，空闲纯净白
    final Color cardBg = isDark ? Colours.dark_material_bg : Colors.white;
    final Decoration decoration = BoxDecoration(
      gradient: isDark || isIdle
          ? null
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                statusColor.withValues(alpha: 0.06),
                cardBg,
              ],
              stops: const <double>[0.0, 0.65],
            ),
      color: (isDark || isIdle) ? cardBg : null,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        width: table.selected ? 1.5 : 0.7,
        color: table.selected
            ? const Color(0xFF00B42A)
            : isDark
                ? Colours.dark_line
                : isIdle
                    ? const Color(0xFFE5E6EB)
                    : statusColor.withValues(alpha: 0.18),
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: isDark
              ? Colors.black26
              : table.selected
                  ? const Color(0x3300B42A)
                  : isIdle
                      ? const Color(0x0F1D2129)
                      : statusColor.withValues(alpha: 0.10),
          blurRadius: table.selected ? 12 : 8,
          offset: const Offset(0, 3),
        ),
      ],
    );

    return AnimatedScale(
      scale: _pressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: decoration,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 桌号 + 角标 + 选中标记
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            table.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: nameColor,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (table.isLocked) _miniTag('锁', const Color(0xFF86909C)),
                        if (table.isHang) _miniTag('挂', const Color(0xFFD97706)),
                        if (table.isPrePrint) _miniTag('预打', const Color(0xFFD97706)),
                        if (table.selected)
                          Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.only(left: 3),
                            decoration: const BoxDecoration(
                              color: Color(0xFF00B42A),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 11, color: Colors.white),
                          ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    // 并台信息（对齐 smdcapp iv_other_table: 红底白字标签）
                    SizedBox(
                      height: 16,
                      child: table.mergeNote == null
                          ? null
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE13426),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                table.mergeNote!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                    ),
                    const Spacer(),
                    // 人数 / 开台时间
                    SizedBox(
                      height: 17,
                      child: Row(
                        children: <Widget>[
                          if (table.personText.isNotEmpty) ...<Widget>[
                            Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: isDark ? Colours.dark_text_gray : const Color(0xFF86909C),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              table.personText,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colours.dark_text_gray : const Color(0xFF86909C),
                              ),
                            ),
                          ],
                          if (timeText != null) ...<Widget>[
                            const SizedBox(width: 7),
                            Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: isDark ? Colours.dark_text_gray : const Color(0xFF86909C),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              timeText,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colours.dark_text_gray : const Color(0xFF86909C),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    // 金额（空闲/待清台无金额时占位保持高度一致）
                    SizedBox(
                      height: 19,
                      child: amountText == null
                          ? null
                          : Text(
                              '¥$amountText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colours.dark_text : const Color(0xFF1D2129),
                                height: 1.2,
                              ),
                            ),
                    ),
                    const SizedBox(height: 5),
                    // 状态徽章（胶囊形）
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: isIdle
                              ? (isDark ? const Color(0xFF2A3A30) : _idleBadgeBg)
                              : statusColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          status.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isIdle
                                ? (isDark ? const Color(0xFF7DD3A0) : _idleBadgeText)
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ),
            // 锁台覆盖层：卡片中央显示大红色锁图标（对齐 smdcapp 锁台状态展示）
            if (table.isLocked)
              Positioned.fill(
                child: Center(
                  child: Icon(
                    Icons.lock_rounded,
                    size: 38,
                    color: const Color(0xFFE63F31).withValues(alpha: 0.85),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () => widget.onTap(widget.table),
      child: _buildCard(context),
    );

    final Animation<double>? animation = widget.animation;
    if (animation == null) {
      return card;
    }

    // 入场: 淡入 + 轻微上移
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(animation),
        child: card,
      ),
    );
  }
}
