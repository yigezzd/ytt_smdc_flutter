import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/order/order_models.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 规格选择抽屉弹窗(图二效果)
class SpecBottomSheet extends StatefulWidget {
  const SpecBottomSheet({
    super.key,
    required this.product,
    required this.onAddToCart,
    this.onBuyNow,
  });

  final Product product;

  /// 加入购物车回调(数量, 规格描述, 加价合计)
  final void Function(int quantity, String specText, double extraPrice) onAddToCart;

  /// 立即下单回调
  final void Function(int quantity, String specText, double extraPrice)? onBuyNow;

  @override
  State<SpecBottomSheet> createState() => _SpecBottomSheetState();
}

class _SpecBottomSheetState extends State<SpecBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  /// 每组规格选中的下标
  late List<int> _selectedIndexes;

  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _selectedIndexes = widget.product.specGroups
        .map((SpecGroup g) => g.defaultIndex)
        .toList();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前规格加价合计(单份)
  double get _extraPrice {
    double extra = 0;
    for (int i = 0; i < widget.product.specGroups.length; i++) {
      extra += widget.product.specGroups[i].options[_selectedIndexes[i]].extraPrice;
    }
    return extra;
  }

  /// 当前规格描述文本
  String get _specText {
    final List<String> names = <String>[];
    for (int i = 0; i < widget.product.specGroups.length; i++) {
      names.add(widget.product.specGroups[i].options[_selectedIndexes[i]].name);
    }
    return names.join(',');
  }

  double get _currentUnitPrice => widget.product.price + _extraPrice;

  double get _currentOriginalPrice =>
      (widget.product.originalPrice ?? widget.product.price) + _extraPrice;

  void _submit({required bool buyNow}) {
    if (buyNow) {
      widget.onBuyNow?.call(_quantity, _specText, _extraPrice);
    } else {
      widget.onAddToCart(_quantity, _specText, _extraPrice);
    }
    Navigator.pop(context);
  }

  /// 单个规格选项chip
  Widget _buildOptionChip(int groupIndex, int optionIndex, SpecOption option) {
    final bool selected = _selectedIndexes[groupIndex] == optionIndex;

    return GestureDetector(
      onTap: () {
        if (!selected) {
          setState(() => _selectedIndexes[groupIndex] = optionIndex);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? _kBrandRed : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? _kBrandRed : const Color(0xFFE8E8E8),
              ),
              boxShadow: selected
                  ? const <BoxShadow>[
                      BoxShadow(color: Color(0x33E63F31), blurRadius: 8, offset: Offset(0, 3)),
                    ]
                  : null,
            ),
            child: Text(
              '${option.name}${option.priceSuffix}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : const Color(0xFF333333),
              ),
            ),
          ),
          // "推荐"角标
          if (option.isRecommend)
            Positioned(
              top: -8,
              right: -10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8547),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x40FF8547), blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: const Text(
                  '推荐',
                  style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Product product = widget.product;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── 顶部商品信息区 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 左侧信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D2129),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.desc,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              const Text(
                                '¥',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1D2129),
                                ),
                              ),
                              Text(
                                product.price.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1D2129),
                                  height: 1,
                                ),
                              ),
                              if (product.originalPrice != null) ...<Widget>[
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '¥${product.originalPrice!.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFBBBBBB),
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // 商品图(emoji渐变块)
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: product.gradient,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Center(
                        child: Text(product.emoji, style: const TextStyle(fontSize: 42)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 关闭按钮
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF2F3F5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 16, color: Color(0xFF86909C)),
                      ),
                    ),
                  ],
                ),
              ),

              // ── 规格选项区(可滚动) ──
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.34,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List<Widget>.generate(
                      product.specGroups.length,
                      (int groupIndex) {
                        final SpecGroup group = product.specGroups[groupIndex];
                        return Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                group.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1D2129),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 12,
                                children: List<Widget>.generate(
                                  group.options.length,
                                  (int optionIndex) => _buildOptionChip(
                                    groupIndex,
                                    optionIndex,
                                    group.options[optionIndex],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // ── 价格 + 数量行 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                '¥${(_currentUnitPrice * _quantity).toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: _kBrandRed,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 1),
                                child: Text(
                                  '¥${(_currentOriginalPrice * _quantity).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFBBBBBB),
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _specText,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                          ),
                        ],
                      ),
                    ),
                    // 数量控制器
                    Row(
                      children: <Widget>[
                        _QuantityButton(
                          icon: Icons.remove,
                          enabled: _quantity > 1,
                          activeColor: const Color(0xFFC9CDD4),
                          onTap: () => setState(() => _quantity--),
                        ),
                        SizedBox(
                          width: 40,
                          child: Center(
                            child: Text(
                              '$_quantity',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1D2129),
                              ),
                            ),
                          ),
                        ),
                        _QuantityButton(
                          icon: Icons.add,
                          enabled: true,
                          activeColor: _kBrandRed,
                          onTap: () => setState(() => _quantity++),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── 底部操作按钮 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _submit(buyNow: true),
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F3F5),
                            borderRadius: BorderRadius.circular(23),
                          ),
                          child: const Center(
                            child: Text(
                              '下单',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4E5969),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: () => _submit(buyNow: false),
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                            ),
                            borderRadius: BorderRadius.circular(23),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(color: Color(0x40E63F31), blurRadius: 10, offset: Offset(0, 4)),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              '加入购物车',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 数量加减圆形按钮
class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.icon,
    required this.enabled,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: enabled ? activeColor : const Color(0xFFF2F3F5),
          shape: BoxShape.circle,
          boxShadow: enabled
              ? <BoxShadow>[
                  BoxShadow(color: activeColor.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
                ]
              : null,
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
