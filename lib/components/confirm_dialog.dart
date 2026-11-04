import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 品牌红（全局统一）
const Color _kBrandRed = Color(0xFFE63F31);

/// 居中弹窗内容容器：键盘弹起时弹窗整体上移，避免底部按钮被系统键盘遮挡；
/// 可用高度不足时内容可滚动，避免弹窗溢出屏幕。
///
/// 自绘居中卡片（非 Dialog/BottomSheet）必须用它包一层，否则系统键盘会盖住底部按钮。
class KeyboardAvoidingDialogBody extends StatelessWidget {
  const KeyboardAvoidingDialogBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Center(child: SingleChildScrollView(child: child)),
    );
  }
}

/// 统一弹窗外壳：16px 圆角卡片 + 轻阴影 + 白色/深色底
///
/// 所有居中自绘弹窗（确认、输入、明细列表等）统一使用它，禁止再使用系统默认
/// AlertDialog / Dialog 的默认外观。
class DialogCard extends StatelessWidget {
  const DialogCard({
    super.key,
    required this.child,
    this.width = 300,
    this.padding = const EdgeInsets.fromLTRB(24, 28, 24, 20),
  });

  final Widget child;
  final double width;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// 统一弹窗按钮：主按钮品牌红底白字，次按钮浅灰底深灰字
class DialogActionButton extends StatelessWidget {
  const DialogActionButton({
    super.key,
    required this.text,
    required this.onTap,
    this.primary = true,
    this.color,
    this.height = 42,
    this.loading = false,
    this.enabled = true,
  });

  final String text;
  final VoidCallback? onTap;
  final bool primary;

  /// 主按钮背景色，默认品牌红
  final Color? color;
  final double height;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool canTap = enabled && !loading && onTap != null;
    final Color primaryColor = color ?? _kBrandRed;
    final Color backgroundColor = primary
        ? (canTap ? primaryColor : primaryColor.withOpacity(0.6))
        : (isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F3F5));
    final Color textColor = primary
        ? Colors.white
        : (isDark ? const Color(0xFFCCCCCC) : const Color(0xFF4E5969));

    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: !primary && isDark
              ? Border.all(color: const Color(0xFF4A4A4C), width: 0.5)
              : null,
          boxShadow: primary && canTap
              ? [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
      ),
    );
  }
}

/// 通用确认弹窗组件（对齐图二样式：居中标题 + 居中内容 + 双按钮并排）
///
/// 使用方式：
/// ```dart
/// final bool confirmed = await ConfirmDialog.show(
///   context,
///   content: '确定要清空购物车吗？',
/// );
/// if (confirmed) { ... }
/// ```
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    this.title = '提示',
    required this.content,
    this.cancelText = '取消',
    this.confirmText = '确定',
    this.singleButton = false,
    this.confirmColor = _kBrandRed,
  });

  /// 弹窗标题，默认"提示"
  final String title;

  /// 弹窗内容文字
  final String content;

  /// 取消按钮文字，默认"取消"
  final String cancelText;

  /// 确定按钮文字，默认"确定"
  final String confirmText;

  /// 是否只显示确定按钮（单按钮模式）
  final bool singleButton;

  /// 确定按钮颜色，默认品牌红
  final Color confirmColor;

  /// 弹出确认弹窗，返回 true 表示点击了确定，false/ null 表示取消
  static Future<bool> show(
    BuildContext context, {
    String title = '提示',
    required String content,
    String cancelText = '取消',
    String confirmText = '确定',
    bool singleButton = false,
    Color confirmColor = _kBrandRed,
    bool barrierDismissible = true,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => ConfirmDialog(
        title: title,
        content: content,
        cancelText: cancelText,
        confirmText: confirmText,
        singleButton: singleButton,
        confirmColor: confirmColor,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: DialogCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
            const SizedBox(height: 16),
            // 内容
            Text(
              content,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF4E5969),
              ),
            ),
            const SizedBox(height: 24),
            // 按钮区域
            if (singleButton)
              SizedBox(
                width: double.infinity,
                child: DialogActionButton(
                  text: confirmText,
                  color: confirmColor,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              )
            else
              Row(
                children: [
                  // 取消按钮
                  Expanded(
                    child: DialogActionButton(
                      text: cancelText,
                      primary: false,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 确定按钮
                  Expanded(
                    child: DialogActionButton(
                      text: confirmText,
                      color: confirmColor,
                      onTap: () => Navigator.of(context).pop(true),
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

/// 通用输入弹窗组件（与 ConfirmDialog 同风格：圆角卡片 + 品牌红按钮 + 聚焦边框输入框）
///
/// 使用方式：
/// ```dart
/// final String? result = await InputDialog.show(
///   context,
///   title: '整单备注',
///   hintText: '输入整单备注…',
///   initialValue: _orderRemark,
/// );
/// if (result != null) { ... }
/// ```
class InputDialog extends StatefulWidget {
  const InputDialog({
    super.key,
    this.title = '请输入',
    this.hintText = '',
    this.initialValue = '',
    this.cancelText = '取消',
    this.confirmText = '确定',
    this.maxLines = 3,
    this.keyboardType,
    this.inputFormatters,
    this.changeBaseAmount,
    this.suffixText,
    this.autoSelectAll = false,
    this.submitOnEnter = false,
    this.obscureText = false,
  });

  /// 弹窗标题
  final String title;

  /// 输入框占位提示文字
  final String hintText;

  /// 输入框初始值
  final String initialValue;

  /// 取消按钮文字
  final String cancelText;

  /// 确定按钮文字
  final String confirmText;

  /// 输入框最大行数
  final int maxLines;

  /// 键盘类型（金额输入弹窗传数字键盘，对齐 smdcapp PricePopup 数字键盘）
  final TextInputType? keyboardType;

  /// 输入格式化器（如仅允许数字和小数点）
  final List<TextInputFormatter>? inputFormatters;

  /// 应收金额：设置后输入值大于该值时实时显示找零（对齐 smdcapp PricePopup tvChange）
  final double? changeBaseAmount;

  /// 输入框右侧单位/后缀文字（如"份""kg"）
  final String? suffixText;

  /// 获得焦点时自动全选文本（数字输入等需要快速覆盖输入的场景）
  final bool autoSelectAll;

  /// 按键盘完成键直接提交（单行输入场景）
  final bool submitOnEnter;

  /// 密码输入（消费密码等敏感内容以圆点显示）
  final bool obscureText;

  /// 弹出输入弹窗，返回输入的文本；返回 null 表示取消
  ///
  /// [barrierDismissible] 默认 false：输入框弹窗点遮罩不关闭，
  /// 避免误触遮罩丢失已输入内容（取消请点"取消"按钮或系统返回键）。
  static Future<String?> show(
    BuildContext context, {
    String title = '请输入',
    String hintText = '',
    String initialValue = '',
    String cancelText = '取消',
    String confirmText = '确定',
    int maxLines = 3,
    bool barrierDismissible = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    double? changeBaseAmount,
    String? suffixText,
    bool autoSelectAll = false,
    bool submitOnEnter = false,
    bool obscureText = false,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => InputDialog(
        title: title,
        hintText: hintText,
        initialValue: initialValue,
        cancelText: cancelText,
        confirmText: confirmText,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        changeBaseAmount: changeBaseAmount,
        suffixText: suffixText,
        autoSelectAll: autoSelectAll,
        submitOnEnter: submitOnEnter,
        obscureText: obscureText,
      ),
    );
  }

  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_onChanged);
    _focusNode = FocusNode();
    if (widget.autoSelectAll) {
      _focusNode.addListener(_onFocusChanged);
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) return;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _onChanged() {
    // 输入金额大于应收时实时显示找零（对齐 smdcapp PricePopup tvChange）
    if (widget.changeBaseAmount == null) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (widget.autoSelectAll) _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  /// 找零金额（未超出应收时为 null）
  double? get _changeAmt {
    final double? base = widget.changeBaseAmount;
    if (base == null) return null;
    final double input = double.tryParse(_controller.text.trim()) ?? 0;
    return input > base ? input - base : null;
  }

  /// 少收差额（输入小于应收且大于0时显示，R54）
  double? get _shortfallAmt {
    final double? base = widget.changeBaseAmount;
    if (base == null) return null;
    final double input = double.tryParse(_controller.text.trim()) ?? 0;
    return input > 0 && input < base ? base - input : null;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardAvoidingDialogBody(child: _buildCard(context));
  }

  /// 弹窗卡片
  Widget _buildCard(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return DialogCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
          const SizedBox(height: 16),
          // 输入框
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            maxLines: widget.maxLines,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction:
                widget.submitOnEnter ? TextInputAction.done : null,
            inputFormatters: widget.inputFormatters,
            onSubmitted: widget.submitOnEnter ? (_) => _submit() : null,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
              suffixText: widget.suffixText,
              suffixStyle: TextStyle(
                fontSize: 14,
                color: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF4E5969),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF7F8FA),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E6EB), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBrandRed, width: 1.2),
              ),
            ),
          ),
          // 找零提示（对齐 smdcapp PricePopup tvChange：输入 > 应收时显示）
          if (_changeAmt != null) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '找零：¥${_changeAmt!.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kBrandRed,
                ),
              ),
            ),
          ],
          // 少收提示（输入 < 应收时显示差额，R54）
          if (_shortfallAmt != null) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '还差：¥${_shortfallAmt!.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFF7D00),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          // 按钮区域
          Row(
            children: [
              // 取消按钮
              Expanded(
                child: DialogActionButton(
                  text: widget.cancelText,
                  primary: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              // 确定按钮
              Expanded(
                child: DialogActionButton(
                  text: widget.confirmText,
                  onTap: () => Navigator.of(context).pop(_controller.text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
