import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 打折结果（对齐 smdcapp DiscountPopup 回调: mark + discount）
class DiscountResult {
  const DiscountResult({required this.discount, this.remark = ''});

  /// 折扣率 1~100
  final double discount;

  /// 打折原因
  final String remark;
}

/// 改名结果（对齐 smdcapp ChangeNamePopup 回调: name + sellprice）
class RenameResult {
  const RenameResult({required this.name, required this.price});

  final String name;
  final double price;
}

/// 赠送结果（对齐 smdcapp GiveNumPopup 回调: mark + num）
class GiveResult {
  const GiveResult({required this.remark, required this.num});

  final String remark;
  final double num;
}

// ==================== 打折弹窗 ====================

/// 打折弹窗（对齐 smdcapp DiscountPopup）
///
/// 快捷折扣按钮（不打折/60/70/80/90）+ 折扣输入 + 原因选择
class DishDiscountSheet extends StatefulWidget {
  const DishDiscountSheet({
    super.key,
    required this.dishName,
    this.currentDiscount = 100,
  });

  final String dishName;
  final double currentDiscount;

  /// 显示弹窗，返回 DiscountResult 或 null（取消）
  static Future<DiscountResult?> show(
    BuildContext context, {
    required String dishName,
    double currentDiscount = 100,
  }) {
    return showModalBottomSheet<DiscountResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishDiscountSheet(
        dishName: dishName,
        currentDiscount: currentDiscount,
      ),
    );
  }

  @override
  State<DishDiscountSheet> createState() => _DishDiscountSheetState();
}

class _DishDiscountSheetState extends State<DishDiscountSheet> {
  late TextEditingController _controller;
  String _selectedReason = '';

  /// 打折原因列表（对齐 smdcapp reasonInfo typeid=03）
  static const List<String> _reasons = <String>[
    '会员折扣',
    '老顾客优惠',
    '员工餐',
    '活动促销',
    '抹零',
    '其他',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentDiscount < 100
          ? _formatNum(widget.currentDiscount)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  void _confirm() {
    final String text = _controller.text.trim();
    // 对齐 smdcapp：空输入/不打折 = 100%，恢复原价计算
    if (text.isEmpty) {
      Navigator.of(context).pop(const DiscountResult(discount: 100));
      return;
    }
    final double? discount = double.tryParse(text);
    if (discount == null || discount <= 0 || discount > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('输入的折扣只能是1~100'), duration: Duration(seconds: 1)),
      );
      return;
    }
    Navigator.of(context).pop(DiscountResult(discount: discount, remark: _selectedReason));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 标题栏（对齐 smdcapp: "菜品打折--${title}"）
            Row(
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
                    '菜品打折--${widget.dishName}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: isDark ? Colors.white70 : const Color(0xFF86909C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 快捷折扣按钮（对齐 smdcapp tv_no/tv_six/tv_seven/tv_eight/tv_nine）
            Row(
              children: <Widget>[
                _buildQuickBtn('不打折', '100', isDark),
                const SizedBox(width: 10),
                _buildQuickBtn('60%', '60', isDark),
                const SizedBox(width: 10),
                _buildQuickBtn('70%', '70', isDark),
                const SizedBox(width: 10),
                _buildQuickBtn('80%', '80', isDark),
                const SizedBox(width: 10),
                _buildQuickBtn('90%', '90', isDark),
              ],
            ),
            const SizedBox(height: 16),
            // 折扣输入
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                hintText: '请输入折扣（1~100）',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
                suffixText: '%',
                suffixStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : const Color(0xFF4E5969),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 打折原因（对齐 smdcapp 原因列表）
            Text(
              '打折原因：',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _reasons.map((String reason) {
                final bool selected = _selectedReason == reason;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedReason = selected ? '' : reason;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? _kBrandRed.withValues(alpha: 0.08)
                          : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5)),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: selected
                            ? _kBrandRed
                            : (isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB)),
                      ),
                    ),
                    child: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? _kBrandRed
                            : (isDark ? Colors.white70 : const Color(0xFF333333)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // 确定按钮
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                ),
                child: const Text('确定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickBtn(String label, String value, bool isDark) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _controller.text = value == '100' ? '' : value),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : const Color(0xFF333333),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 改价弹窗 ====================

/// 改价弹窗（对齐 smdcapp ChangePricePopup）
class DishChangePriceSheet extends StatefulWidget {
  const DishChangePriceSheet({
    super.key,
    required this.dishName,
    required this.currentPrice,
  });

  final String dishName;
  final double currentPrice;

  static Future<double?> show(
    BuildContext context, {
    required String dishName,
    required double currentPrice,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishChangePriceSheet(dishName: dishName, currentPrice: currentPrice),
    );
  }

  @override
  State<DishChangePriceSheet> createState() => _DishChangePriceSheetState();
}

class _DishChangePriceSheetState extends State<DishChangePriceSheet> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入价格'), duration: Duration(seconds: 1)),
      );
      return;
    }
    final double? price = double.tryParse(text);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('价格必须大于0'), duration: Duration(seconds: 1)),
      );
      return;
    }
    Navigator.of(context).pop(price);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 标题（对齐 smdcapp: "改价--${title}"）
            Row(
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
                    '改价--${widget.dishName}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: isDark ? Colors.white70 : const Color(0xFF86909C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '当前价格：¥${_formatPrice(widget.currentPrice)}',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                hintText: '请输入新价格',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
                prefixText: '¥ ',
                prefixStyle: const TextStyle(fontSize: 15, color: _kBrandRed),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                ),
                child: const Text('确定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatPrice(double price) {
    if (price == price.roundToDouble()) return price.toInt().toString();
    return price.toStringAsFixed(2);
  }
}

// ==================== 备注弹窗 ====================

/// 备注弹窗（对齐 smdcapp RemarkPopup）
///
/// 快捷备注标签（可多选拼接）+ 手动输入
class DishRemarkSheet extends StatefulWidget {
  const DishRemarkSheet({
    super.key,
    required this.dishName,
    this.currentRemark = '',
  });

  final String dishName;
  final String currentRemark;

  static Future<String?> show(
    BuildContext context, {
    required String dishName,
    String currentRemark = '',
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishRemarkSheet(dishName: dishName, currentRemark: currentRemark),
    );
  }

  @override
  State<DishRemarkSheet> createState() => _DishRemarkSheetState();
}

class _DishRemarkSheetState extends State<DishRemarkSheet> {
  late TextEditingController _controller;
  final Set<String> _selectedTags = <String>{};

  /// 快捷备注（对齐 smdcapp reasonInfo typeid=06 菜品备注）
  static const List<String> _quickRemarks = <String>[
    '不要辣',
    '微辣',
    '中辣',
    '特辣',
    '不要葱',
    '不要香菜',
    '少盐',
    '少油',
    '加急',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentRemark);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncTags() {
    final String text = _selectedTags.join(',');
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 标题（对齐 smdcapp: "备注--${title}"）
            Row(
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
                    '备注--${widget.dishName}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: isDark ? Colors.white70 : const Color(0xFF86909C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 快捷备注标签（对齐 smdcapp rv grid 多选拼接）
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickRemarks.map((String tag) {
                final bool selected = _selectedTags.contains(tag);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedTags.remove(tag);
                    } else {
                      _selectedTags.add(tag);
                    }
                    _syncTags();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? _kBrandRed.withValues(alpha: 0.08)
                          : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5)),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: selected
                            ? _kBrandRed
                            : (isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB)),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? _kBrandRed
                            : (isDark ? Colors.white70 : const Color(0xFF333333)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // 手动输入
            TextField(
              controller: _controller,
              maxLines: 2,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                hintText: '请输入备注内容',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(_controller.text.trim());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                ),
                child: const Text('确定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 赠送弹窗 ====================

/// 赠送弹窗（对齐 smdcapp GiveNumPopup）
///
/// 赠送原因 + 赠送数量
class DishGiveSheet extends StatefulWidget {
  const DishGiveSheet({
    super.key,
    required this.dishName,
    required this.maxNum,
    this.isGive = false,
  });

  final String dishName;

  /// 当前数量（赠送数量上限）
  final double maxNum;

  /// 是否已赠送（已赠送时显示取消原因）
  final bool isGive;

  static Future<GiveResult?> show(
    BuildContext context, {
    required String dishName,
    required double maxNum,
    bool isGive = false,
  }) {
    return showModalBottomSheet<GiveResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishGiveSheet(dishName: dishName, maxNum: maxNum, isGive: isGive),
    );
  }

  @override
  State<DishGiveSheet> createState() => _DishGiveSheetState();
}

class _DishGiveSheetState extends State<DishGiveSheet> {
  late TextEditingController _numController;
  late TextEditingController _remarkController;
  String _selectedReason = '';

  /// 赠送原因列表（对齐 smdcapp reasonInfo typeid=04）
  static const List<String> _reasons = <String>[
    '客户投诉',
    '老顾客赠送',
    '活动赠送',
    '老板赠送',
    '其他',
  ];

  @override
  void initState() {
    super.initState();
    _numController = TextEditingController(
      text: widget.maxNum == widget.maxNum.roundToDouble()
          ? widget.maxNum.toInt().toString()
          : widget.maxNum.toString(),
    );
    _remarkController = TextEditingController();
  }

  @override
  void dispose() {
    _numController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _confirm() {
    final String numText = _numController.text.trim();
    final double? num = double.tryParse(numText);
    if (num == null || num <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('赠送数量必须大于0'), duration: Duration(seconds: 1)),
      );
      return;
    }
    if (num > widget.maxNum) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('赠送数量不能超过${widget.maxNum}'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    final String remark = _remarkController.text.trim().isNotEmpty
        ? _remarkController.text.trim()
        : _selectedReason;
    Navigator.of(context).pop(GiveResult(remark: remark, num: num));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 标题
            Row(
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
                    '赠送--${widget.dishName}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: isDark ? Colors.white70 : const Color(0xFF86909C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 赠送数量（对齐 smdcapp et_num + 加减按钮）
            Text(
              '赠送数量：',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _buildNumBtn(Icons.remove, () {
                  final double cur = double.tryParse(_numController.text) ?? 1;
                  if (cur > 1) {
                    _numController.text = (cur - 1).toString();
                  }
                }, isDark),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _numController,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                    ],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                _buildNumBtn(Icons.add, () {
                  final double cur = double.tryParse(_numController.text) ?? 0;
                  if (cur < widget.maxNum) {
                    final double next = cur + 1;
                    _numController.text = next == next.roundToDouble()
                        ? next.toInt().toString()
                        : next.toString();
                  }
                }, isDark),
              ],
            ),
            const SizedBox(height: 12),
            // 赠送原因（对齐 smdcapp "*赠送原因："）
            Text(
              widget.isGive ? '*取消原因：' : '*赠送原因：',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _reasons.map((String reason) {
                final bool selected = _selectedReason == reason;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedReason = selected ? '' : reason;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? _kBrandRed.withValues(alpha: 0.08)
                          : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5)),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: selected
                            ? _kBrandRed
                            : (isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB)),
                      ),
                    ),
                    child: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? _kBrandRed
                            : (isDark ? Colors.white70 : const Color(0xFF333333)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remarkController,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                hintText: '或输入原因',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                ),
                child: const Text('确定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kBrandRed,
        ),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
}

// ==================== 打包弹窗 ====================

/// 打包弹窗（对齐 smdcapp BagPricePopup）
class DishBagSheet extends StatefulWidget {
  const DishBagSheet({
    super.key,
    required this.dishName,
    this.currentBagPrice = 0,
  });

  final String dishName;
  final double currentBagPrice;

  /// 返回打包费，null=取消，-1=取消打包
  static Future<double?> show(
    BuildContext context, {
    required String dishName,
    double currentBagPrice = 0,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishBagSheet(dishName: dishName, currentBagPrice: currentBagPrice),
    );
  }

  @override
  State<DishBagSheet> createState() => _DishBagSheetState();
}

class _DishBagSheetState extends State<DishBagSheet> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentBagPrice > 0
          ? (widget.currentBagPrice == widget.currentBagPrice.roundToDouble()
              ? widget.currentBagPrice.toInt().toString()
              : widget.currentBagPrice.toStringAsFixed(2))
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
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
                    '打包--${widget.dishName}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: isDark ? Colors.white70 : const Color(0xFF86909C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                hintText: '请输入打包费（0或清空=取消打包）',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
                prefixText: '¥ ',
                prefixStyle: const TextStyle(fontSize: 15, color: _kBrandRed),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                // 取消打包（对齐 smdcapp price <= -1 逻辑）
                if (widget.currentBagPrice > 0)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(-1),
                      child: Container(
                        height: 44,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '取消打包',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : const Color(0xFF666666),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () {
                        final String text = _controller.text.trim();
                        if (text.isEmpty) {
                          Navigator.of(context).pop(-1);
                          return;
                        }
                        final double? price = double.tryParse(text);
                        if (price == null || price < 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('打包费格式错误'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                          return;
                        }
                        Navigator.of(context).pop(price);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrandRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('确定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
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

// ==================== 改名弹窗 ====================

/// 改名弹窗（对齐 smdcapp ChangeNamePopup: 修改名称 + 价格）
class DishRenameSheet extends StatefulWidget {
  const DishRenameSheet({
    super.key,
    required this.dishName,
    required this.currentPrice,
  });

  final String dishName;
  final double currentPrice;

  static Future<RenameResult?> show(
    BuildContext context, {
    required String dishName,
    required double currentPrice,
  }) {
    return showModalBottomSheet<RenameResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishRenameSheet(dishName: dishName, currentPrice: currentPrice),
    );
  }

  @override
  State<DishRenameSheet> createState() => _DishRenameSheetState();
}

class _DishRenameSheetState extends State<DishRenameSheet> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.dishName);
    _priceController = TextEditingController(
      text: widget.currentPrice == widget.currentPrice.roundToDouble()
          ? widget.currentPrice.toInt().toString()
          : widget.currentPrice.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _confirm() {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能为空'), duration: Duration(seconds: 1)),
      );
      return;
    }
    final double? price = double.tryParse(_priceController.text.trim());
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('价格必须大于0'), duration: Duration(seconds: 1)),
      );
      return;
    }
    Navigator.of(context).pop(RenameResult(name: name, price: price));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
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
                    '改名--${widget.dishName}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: isDark ? Colors.white70 : const Color(0xFF86909C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '菜品名称：',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                hintText: '请输入新名称',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '价格：',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                hintText: '请输入价格',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
                prefixText: '¥ ',
                prefixStyle: const TextStyle(fontSize: 15, color: _kBrandRed),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                ),
                child: const Text('确定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 服务员选择弹窗 ====================

/// 服务员选择弹窗（对齐 smdcapp WaiterPopup）
///
/// 从 /YttSvr/app/user/getList 接口加载真实服务员数据，支持搜索。
class DishWaiterSheet extends StatefulWidget {
  const DishWaiterSheet({
    super.key,
    required this.dishName,
    this.currentWaiter = '',
  });

  final String dishName;
  final String currentWaiter;

  static Future<Waiter?> show(
    BuildContext context, {
    required String dishName,
    String currentWaiter = '',
  }) {
    return showModalBottomSheet<Waiter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishWaiterSheet(
        dishName: dishName,
        currentWaiter: currentWaiter,
      ),
    );
  }

  @override
  State<DishWaiterSheet> createState() => _DishWaiterSheetState();
}

class _DishWaiterSheetState extends State<DishWaiterSheet> {
  String _selected = '';
  bool _loading = true;
  List<Waiter> _waiters = <Waiter>[];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = widget.currentWaiter;
    _loadWaiters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 加载服务员列表（对齐 smdcapp WaiterPopup 查询 SysUser）
  Future<void> _loadWaiters({String cond = ''}) async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final List<Waiter> list = await OrderRepository.fetchWaiters(cond: cond);
      if (!mounted) return;
      setState(() {
        _waiters = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
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
                    '选择服务员--${widget.dishName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: isDark ? Colors.white70 : const Color(0xFF86909C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 搜索框（对齐 smdcapp WaiterPopup etInfo 搜索）
            TextField(
              controller: _searchController,
              onChanged: (String v) => _loadWaiters(cond: v.trim()),
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                hintText: '搜索服务员',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFF86909C),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBrandRed),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 服务员列表
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else if (_waiters.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Text(
                    '暂无服务员数据',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _waiters.map((Waiter waiter) {
                      final bool selected = _selected == waiter.name;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selected = waiter.name);
                          Navigator.of(context).pop(waiter);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                          decoration: BoxDecoration(
                            color: selected
                                ? _kBrandRed.withValues(alpha: 0.08)
                                : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? _kBrandRed
                                  : (isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB)),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.person_outline,
                                size: 16,
                                color: selected
                                    ? _kBrandRed
                                    : (isDark ? Colors.white70 : const Color(0xFF86909C)),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                waiter.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: selected
                                      ? _kBrandRed
                                      : (isDark ? Colors.white70 : const Color(0xFF333333)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== 退菜弹窗 ====================

/// 退菜结果（对齐 smdcapp ReturnDishesPopup 回调）
class ReturnDishResult {
  const ReturnDishResult({
    required this.num,
    required this.remark,
    required this.prnretflag,
  });

  /// 退菜数量
  final double num;

  /// 退菜原因
  final String remark;

  /// 是否打印退菜单 1=是 0=否
  final int prnretflag;
}

/// 退菜弹窗（对齐 smdcapp ReturnDishesPopup）
///
/// 显示菜品名称、可退数量、原因选择、打印开关。
/// 确认后返回 [ReturnDishResult]。
class DishReturnSheet extends StatefulWidget {
  const DishReturnSheet({
    super.key,
    required this.dishName,
    required this.maxQty,
    this.isWeigh = false,
    this.reasons = const <String>[],
  });

  final String dishName;

  /// 最大可退数量（qty - subqty）
  final double maxQty;

  /// 是否称重菜（称重菜不可调数量）
  final bool isWeigh;

  /// 退菜原因列表（对齐 smdcapp getReason typeid="02"）
  final List<String> reasons;

  /// 显示弹窗
  static Future<ReturnDishResult?> show(
    BuildContext context, {
    required String dishName,
    required double maxQty,
    bool isWeigh = false,
    List<String> reasons = const <String>[],
  }) {
    return showModalBottomSheet<ReturnDishResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishReturnSheet(
        dishName: dishName,
        maxQty: maxQty,
        isWeigh: isWeigh,
        reasons: reasons,
      ),
    );
  }

  @override
  State<DishReturnSheet> createState() => _DishReturnSheetState();
}

class _DishReturnSheetState extends State<DishReturnSheet> {
  late double _num;
  String _selectedReason = '';
  final TextEditingController _remarkCtrl = TextEditingController();
  bool _printTicket = true;

  @override
  void initState() {
    super.initState();
    _num = widget.maxQty;
    // 对齐 smdcapp: 如果设置了退菜原因必选，默认选中第一个
    if (widget.reasons.isNotEmpty) {
      _selectedReason = widget.reasons.first;
    }
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 拖拽指示条
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E6EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 标题
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '退菜 - ${widget.dishName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D2129),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 数量选择（对齐 smdcapp etNum + imgAdd/imgMinus）
              if (!widget.isWeigh)
                Row(
                  children: <Widget>[
                    const Text('退菜数量', style: TextStyle(fontSize: 14, color: Color(0xFF4E5969))),
                    const Spacer(),
                    IconButton(
                      onPressed: _num > 1
                          ? () => setState(() => _num--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline, size: 26),
                      color: _kBrandRed,
                    ),
                    SizedBox(
                      width: 50,
                      child: Text(
                        _num % 1 == 0 ? _num.toInt().toString() : _num.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: _num < widget.maxQty
                          ? () => setState(() => _num++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline, size: 26),
                      color: _kBrandRed,
                    ),
                  ],
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '称重菜退菜数量：${widget.maxQty}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF4E5969)),
                  ),
                ),
              const SizedBox(height: 12),
              // 退菜原因（对齐 smdcapp rv reason typeid=02）
              if (widget.reasons.isNotEmpty) ...<Widget>[
                const Text('退菜原因', style: TextStyle(fontSize: 14, color: Color(0xFF4E5969))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.reasons.map((String r) {
                    final bool selected = _selectedReason == r;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedReason = selected ? '' : r;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFFFEECEB) : const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? _kBrandRed : const Color(0xFFE5E6EB),
                          ),
                        ),
                        child: Text(
                          r,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected ? _kBrandRed : const Color(0xFF4E5969),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              // 自定义原因输入
              TextField(
                controller: _remarkCtrl,
                decoration: const InputDecoration(
                  hintText: '输入退菜原因（可选）',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              // 打印退菜单开关（对齐 smdcapp cbPrint）
              Row(
                children: <Widget>[
                  const Text('打印退菜单', style: TextStyle(fontSize: 14, color: Color(0xFF4E5969))),
                  const Spacer(),
                  Switch(
                    value: _printTicket,
                    onChanged: (bool v) => setState(() => _printTicket = v),
                    activeColor: _kBrandRed,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 确定按钮
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrandRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('确定退菜', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onConfirm() {
    // 对齐 smdcapp: 拼接原因 = 选中原因 + 手动输入
    final String input = _remarkCtrl.text.trim();
    final StringBuffer sb = StringBuffer();
    if (input.isNotEmpty) sb.write(input);
    if (_selectedReason.isNotEmpty) {
      if (sb.isNotEmpty) sb.write(',');
      sb.write(_selectedReason);
    }
    Navigator.pop(
      context,
      ReturnDishResult(
        num: _num,
        remark: sb.toString(),
        prnretflag: _printTicket ? 1 : 0,
      ),
    );
  }
}
