import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/db/dao/reason_info_dao.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/user_helper.dart';

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

/// 打折弹窗（对齐 smdcapp DiscountPopup2）
///
/// 布局顺序与 smdcapp dialog_discount_bottom 一致：折扣输入 → 快捷折扣
/// （不打折/60/70/80/90）→ 内置数字键盘 → 打折原因 → 确定。
/// 折扣输入框只读，统一用内置键盘输入，避免系统键盘遮挡。
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
  /// 数字键高度
  static const double _kKeyHeight = 52;

  /// 按键间距
  static const double _kKeyGap = 8;

  /// 清空/退格键宽度
  static const double _kSideKeyWidth = 72;

  late TextEditingController _controller;
  final TextEditingController _reasonTextController = TextEditingController();
  String _selectedReason = '';

  /// 打折原因列表（对齐 smdcapp reasonInfo typeid=03，读取后台配置）
  List<String> _reasons = <String>[];

  /// 后台是否要求打折原因必填（对齐 smdcapp SpUtils.getRemarkMustTypes 含 03）
  bool get _reasonRequired => ParamsSpUtils.isRemarkMust('03');

  bool get _hasValue => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentDiscount < 100
          ? _formatNum(widget.currentDiscount)
          : '',
    );
    _loadReasons();
  }

  Future<void> _loadReasons() async {
    try {
      final List<Map<String, dynamic>> rows =
          await ReasonInfoDao.instance.queryByTypeid(
        '03',
        spid: UserHelper.getSpid(),
        sid: UserHelper.getSid(),
      );
      final List<String> list = rows
          .map((Map<String, dynamic> r) => r['value']?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
      if (list.isNotEmpty && mounted) {
        setState(() => _reasons = list);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    _reasonTextController.dispose();
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
    // R49：后台要求打折原因必填时必须选择/输入原因（不打折除外）
    if (discount < 100 &&
        _reasonRequired &&
        _selectedReason.isEmpty &&
        _reasonTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择打折原因'), duration: Duration(seconds: 1)),
      );
      return;
    }
    final String reason = _reasonTextController.text.trim().isNotEmpty
        ? _reasonTextController.text.trim()
        : _selectedReason;
    Navigator.of(context).pop(DiscountResult(discount: discount, remark: reason));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final MediaQueryData mq = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 内容区可滚动：小屏或系统键盘弹出时保证确定按钮始终可见
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildTitle(isDark),
                  const SizedBox(height: 16),
                  _buildDiscountField(isDark),
                  const SizedBox(height: 12),
                  _buildQuickRow(isDark),
                  const SizedBox(height: 14),
                  _buildNumpad(isDark),
                  const SizedBox(height: 18),
                  _buildReasonSection(isDark),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + mq.viewInsets.bottom),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(23),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '确定',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 标题栏（对齐 smdcapp: "菜品打折--${title}"）
  Widget _buildTitle(bool isDark) {
    return Row(
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
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(
              Icons.close,
              size: 20,
              color: isDark ? Colors.white70 : const Color(0xFF86909C),
            ),
          ),
        ),
      ],
    );
  }

  /// 折扣输入框（只读，由内置键盘写入；对齐 smdcapp et_discount 右对齐 + %）
  Widget _buildDiscountField(bool isDark) {
    final Color labelColor =
        isDark ? const Color(0xFF9AA0A6) : const Color(0xFF86909C);
    return Container(
      height: 54,
      padding: const EdgeInsets.only(left: 14, right: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2E2F30) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _hasValue
              ? _kBrandRed.withValues(alpha: 0.45)
              : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFEBEDF0)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text('折扣', style: TextStyle(fontSize: 13, color: labelColor)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              readOnly: true,
              showCursor: false,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '请输入',
                hintStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: isDark
                      ? const Color(0xFF6B6F76)
                      : const Color(0xFFC9CDD4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '%',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 快捷折扣按钮（对齐 smdcapp tv_no/tv_six/tv_seven/tv_eight/tv_nine）
  Widget _buildQuickRow(bool isDark) {
    return Row(
      children: <Widget>[
        _buildQuickBtn('不打折', '100', isDark),
        const SizedBox(width: _kKeyGap),
        _buildQuickBtn('60%', '60', isDark),
        const SizedBox(width: _kKeyGap),
        _buildQuickBtn('70%', '70', isDark),
        const SizedBox(width: _kKeyGap),
        _buildQuickBtn('80%', '80', isDark),
        const SizedBox(width: _kKeyGap),
        _buildQuickBtn('90%', '90', isDark),
      ],
    );
  }

  Widget _buildQuickBtn(String label, String value, bool isDark) {
    // R49：点击常用折扣后按钮保留选中底色，便于识别当前选择
    final bool selected =
        double.tryParse(_controller.text.trim()) == double.tryParse(value);
    return Expanded(
      child: GestureDetector(
        // 对齐 smdcapp DiscountPopup：tv_no 清空后 setValue("100")，输入框显示 100
        onTap: () => setState(() => _controller.text = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          decoration: BoxDecoration(
            color: selected
                ? _kBrandRed.withValues(alpha: 0.08)
                : (isDark ? const Color(0xFF333537) : const Color(0xFFF5F6F8)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? _kBrandRed
                  : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFEBEDF0)),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? _kBrandRed
                    : (isDark ? Colors.white70 : const Color(0xFF4E5969)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 内置数字键盘（对齐 smdcapp dialog_discount_bottom：3 列数字 +
  /// 右侧清空/退格两个跨两行的长按键）
  Widget _buildNumpad(bool isDark) {
    final Color digitBg =
        isDark ? const Color(0xFF333537) : const Color(0xFFF5F6F8);
    final Color sideBg =
        isDark ? const Color(0xFF2E3032) : const Color(0xFFF2F3F5);
    final Color digitColor = isDark ? Colors.white : const Color(0xFF1D2129);
    final Color sideColor =
        isDark ? const Color(0xFFC2C7CF) : const Color(0xFF4E5969);

    Widget keyButton({
      required Widget child,
      required VoidCallback onTap,
      required Color background,
      double? width,
      double? height,
    }) {
      return SizedBox(
        width: width,
        height: height,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      );
    }

    Widget digitKey(String label) {
      return Expanded(
        child: keyButton(
          height: _kKeyHeight,
          background: digitBg,
          onTap: () => _appendDigit(label),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: digitColor,
            ),
          ),
        ),
      );
    }

    Widget digitRow(List<String?> labels) {
      return Row(
        children: <Widget>[
          for (int i = 0; i < labels.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: _kKeyGap),
            if (labels[i] == null)
              const Expanded(child: SizedBox(height: _kKeyHeight))
            else
              digitKey(labels[i]!),
          ],
        ],
      );
    }

    Widget sideKey(String label, VoidCallback onTap) {
      return keyButton(
        width: _kSideKeyWidth,
        height: _kKeyHeight * 2 + _kKeyGap,
        background: sideBg,
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(fontSize: 14, color: sideColor),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                children: <Widget>[
                  digitRow(<String?>['1', '2', '3']),
                  const SizedBox(height: _kKeyGap),
                  digitRow(<String?>['4', '5', '6']),
                ],
              ),
            ),
            const SizedBox(width: _kKeyGap),
            sideKey('清空', _clearValue),
          ],
        ),
        const SizedBox(height: _kKeyGap),
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                children: <Widget>[
                  digitRow(<String?>['7', '8', '9']),
                  const SizedBox(height: _kKeyGap),
                  digitRow(<String?>[null, '0', '.']),
                ],
              ),
            ),
            const SizedBox(width: _kKeyGap),
            sideKey('退格', _backspace),
          ],
        ),
      ],
    );
  }

  /// 打折原因（对齐 smdcapp: *打折原因 + 原因列表 + 手输原因）
  Widget _buildReasonSection(bool isDark) {
    final Color subColor =
        isDark ? const Color(0xFF9AA0A6) : const Color(0xFF86909C);
    final Color borderColor =
        isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              if (_reasonRequired)
                const TextSpan(
                  text: '*',
                  style: TextStyle(
                    color: _kBrandRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const TextSpan(text: '打折原因：'),
            ],
            style: TextStyle(fontSize: 13, color: subColor),
          ),
        ),
        if (_reasons.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: _kKeyGap,
            runSpacing: _kKeyGap,
            children:
                _reasons.map((String reason) => _buildReasonChip(reason)).toList(),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _reasonTextController,
          textInputAction: TextInputAction.done,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF1D2129),
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: isDark ? const Color(0xFF2E2F30) : const Color(0xFFF7F8FA),
            hintText: '或输入打折原因',
            hintStyle: TextStyle(
              fontSize: 14,
              color: isDark ? const Color(0xFF6B6F76) : const Color(0xFFC9CDD4),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBrandRed),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReasonChip(String reason) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool selected = _selectedReason == reason;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedReason = selected ? '' : reason),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? _kBrandRed
              : (isDark ? const Color(0xFF333537) : const Color(0xFFF5F6F8)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _kBrandRed
                : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFEBEDF0)),
          ),
        ),
        child: Text(
          reason,
          style: TextStyle(
            fontSize: 13,
            color: selected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF4E5969)),
          ),
        ),
      ),
    );
  }

  void _appendDigit(String digit) {
    final String text = _controller.text;
    setState(() {
      if (digit == '.') {
        // 空输入不允许以小数点开头
        if (text.isEmpty || text.contains('.')) {
          return;
        }
        _controller.text = '$text.';
      } else {
        final String next = text == '0' ? digit : '$text$digit';
        if (next.length > 5) {
          return;
        }
        // 折扣上限 100%（输入过程中即可拦住超限值）
        final double? value = double.tryParse(next);
        if (value == null || value > 100) {
          return;
        }
        _controller.text = next;
      }
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  void _backspace() {
    final String text = _controller.text;
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _controller.text = text.substring(0, text.length - 1);
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  void _clearValue() {
    if (_controller.text.isEmpty) {
      return;
    }
    setState(() {
      _controller.clear();
      _controller.selection = const TextSelection.collapsed(offset: 0);
    });
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

  void _confirm() {
    final String text = _controller.text.trim();
    // 后台要求菜品备注必填时必须选择/输入（对齐 smdcapp ProductRemarkPopup2 typeid=06）
    if (ParamsSpUtils.isRemarkMust('06') && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择或填写备注原因'), duration: Duration(seconds: 1)),
      );
      return;
    }
    Navigator.of(context).pop(text);
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
    this.showNum = true,
  });

  final String dishName;

  /// 当前数量（赠送数量上限）
  final double maxNum;

  /// 是否已赠送（已赠送时显示取消原因）
  final bool isGive;

  /// 是否显示赠送数量（整单赠送对齐 smdcapp SingleGivePopup：只填原因）
  final bool showNum;

  static Future<GiveResult?> show(
    BuildContext context, {
    required String dishName,
    required double maxNum,
    bool isGive = false,
    bool showNum = true,
  }) {
    return showModalBottomSheet<GiveResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishGiveSheet(
        dishName: dishName,
        maxNum: maxNum,
        isGive: isGive,
        showNum: showNum,
      ),
    );
  }

  @override
  State<DishGiveSheet> createState() => _DishGiveSheetState();
}

class _DishGiveSheetState extends State<DishGiveSheet> {
  late TextEditingController _numController;
  late TextEditingController _remarkController;
  String _selectedReason = '';

  /// 赠送原因列表（对齐 smdcapp reasonInfo typeid=04，读取后台配置）
  List<String> _reasons = <String>[];

  @override
  void initState() {
    super.initState();
    _numController = TextEditingController(
      text: widget.maxNum == widget.maxNum.roundToDouble()
          ? widget.maxNum.toInt().toString()
          : widget.maxNum.toString(),
    );
    _remarkController = TextEditingController();
    _loadReasons();
  }

  Future<void> _loadReasons() async {
    try {
      final List<Map<String, dynamic>> rows =
          await ReasonInfoDao.instance.queryByTypeid(
        '04',
        spid: UserHelper.getSpid(),
        sid: UserHelper.getSid(),
      );
      final List<String> list = rows
          .map((Map<String, dynamic> r) => r['value']?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
      if (list.isNotEmpty && mounted) {
        setState(() => _reasons = list);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _numController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _confirm() {
    double num = 0;
    if (widget.showNum) {
      final String numText = _numController.text.trim();
      final double? parsed = double.tryParse(numText);
      if (parsed == null || parsed <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('赠送数量必须大于0'), duration: Duration(seconds: 1)),
        );
        return;
      }
      if (parsed > widget.maxNum) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('赠送数量不能超过${widget.maxNum}'),
            duration: const Duration(seconds: 1),
          ),
        );
        return;
      }
      num = parsed;
    }
    final String remark = _remarkController.text.trim().isNotEmpty
        ? _remarkController.text.trim()
        : _selectedReason;
    // R50：后台要求赠送原因必填时必须选择/输入原因
    if (ParamsSpUtils.isRemarkMust('04') && remark.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isGive ? '请选择取消原因' : '请选择赠送原因'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
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
                    '${widget.isGive ? '取消赠送' : '赠送'} - ${widget.dishName}',
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
            if (widget.showNum) ...<Widget>[
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
            ],
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
                hintText: '请输入打包费（0=免费打包）',
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
                // 取消打包（对齐 smdcapp BagPopup2 tv_cancel：常显，返回 price=-1）
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(-1.0),
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
                          Navigator.of(context).pop(-1.0);
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
    // R51：退菜原因不设默认值，由操作员主动选择
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
                    color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1D2129),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close,
                        size: 20,
                        color: isDark ? Colors.white54 : const Color(0xFFC9CDD4)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 数量选择（对齐 smdcapp etNum + imgAdd/imgMinus）
              if (!widget.isWeigh)
                Row(
                  children: <Widget>[
                    Text('退菜数量',
                        style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : const Color(0xFF4E5969))),
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
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : const Color(0xFF4E5969)),
                  ),
                ),
              const SizedBox(height: 12),
              // 退菜原因（对齐 smdcapp rv reason typeid=02）
              if (widget.reasons.isNotEmpty) ...<Widget>[
                Text('退菜原因',
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : const Color(0xFF4E5969))),
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
                          color: selected
                              ? (isDark ? const Color(0xFF3A2422) : const Color(0xFFFEECEB))
                              : (isDark ? const Color(0xFF2E2F30) : const Color(0xFFF7F8FA)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected
                                ? _kBrandRed
                                : (isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB)),
                          ),
                        ),
                        child: Text(
                          r,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected
                                ? _kBrandRed
                                : (isDark ? Colors.white70 : const Color(0xFF4E5969)),
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
                  hintText: '输入退菜原因',
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
                  Text('打印退菜单',
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : const Color(0xFF4E5969))),
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
    // 后台要求退菜原因必填时不能直接确认
    if (ParamsSpUtils.isRemarkMust('02') && sb.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择退菜原因'), duration: Duration(seconds: 1)),
      );
      return;
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

// ==================== 称重确认弹窗 ====================

/// 称重行（对齐 smdcapp ReweighPopup 列表项：名称/单价/金额/原数量/是否已称）
class ReweighEntry {
  const ReweighEntry({
    required this.name,
    required this.price,
    required this.amount,
    required this.qty,
    required this.confirmed,
  });

  final String name;
  final double price;
  final double amount;

  /// 原数量（称重菜为当前重量）
  final double qty;

  /// 是否已称过（对齐 smdcapp confirmqty > 0）
  final bool confirmed;
}

/// 称重结果（index=行下标，weight=新重量）
class ReweighResult {
  const ReweighResult(this.index, this.weight);

  final int index;
  final double weight;
}

/// 称重确认弹窗（对齐 smdcapp ReweighPopup）
///
/// 本次操作全部可称重菜品在一张弹窗里逐行录入重量（未称的排前面），
/// 留空的行不做修改。返回录入结果列表，null=取消。
class ReweighSheet extends StatefulWidget {
  const ReweighSheet({super.key, required this.entries});

  final List<ReweighEntry> entries;

  static Future<List<ReweighResult>?> show(
    BuildContext context, {
    required List<ReweighEntry> entries,
  }) {
    return showModalBottomSheet<List<ReweighResult>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReweighSheet(entries: entries),
    );
  }

  @override
  State<ReweighSheet> createState() => _ReweighSheetState();
}

class _ReweighSheetState extends State<ReweighSheet> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      widget.entries.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _confirm() {
    final List<ReweighResult> results = <ReweighResult>[];
    for (int i = 0; i < _controllers.length; i++) {
      final String text = _controllers[i].text.trim();
      if (text.isEmpty) continue;
      double? weight = double.tryParse(text);
      if (weight == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重量格式错误'), duration: Duration(seconds: 1)),
        );
        return;
      }
      // 对齐 smdcapp ReweighPopup: 最大数量 999.999
      if (weight > 999.999) weight = 999.999;
      if (weight <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重量需大于0'), duration: Duration(seconds: 1)),
        );
        return;
      }
      results.add(ReweighResult(i, weight));
    }
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入新的重量'), duration: Duration(seconds: 1)),
      );
      return;
    }
    Navigator.of(context).pop(results);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color titleColor = isDark ? Colors.white : const Color(0xFF1D2129);
    final Color subColor = isDark ? const Color(0xFFB8B8B8) : const Color(0xFF86909C);

    return Container(
      constraints: BoxConstraints(
        // 对齐 smdcapp ReweighPopup.getMaxHeight()：弹窗最高 70% 屏高
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  '称重确认',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
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
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Text('菜品', style: TextStyle(fontSize: 12, color: subColor)),
              ),
              Expanded(
                flex: 2,
                child: Text('原数量',
                    style: TextStyle(fontSize: 12, color: subColor),
                    textAlign: TextAlign.center),
              ),
              Expanded(
                flex: 2,
                child: Text('新重量',
                    style: TextStyle(fontSize: 12, color: subColor),
                    textAlign: TextAlign.center),
              ),
            ],
          ),
          const Divider(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: List<Widget>.generate(
                  widget.entries.length,
                  (int i) => _buildRow(i, isDark),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
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
                        '取消',
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
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrandRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('确定',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int index, bool isDark) {
    final ReweighEntry e = widget.entries[index];
    final Color textColor = isDark ? Colors.white : const Color(0xFF1D2129);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
                const SizedBox(width: 4),
                // 已称/未称徽标（对齐 smdcapp tv_weigh_one / tv_weigh_zero）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: e.confirmed ? const Color(0xFF00B42A) : _kBrandRed,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    e.confirmed ? '已称' : '未称',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _fmt(e.qty),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: textColor),
            ),
          ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _controllers[index],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: textColor),
                decoration: InputDecoration(
                  hintText: '重量',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
            ),
          ),
        ],
      ),
    );
  }
}
