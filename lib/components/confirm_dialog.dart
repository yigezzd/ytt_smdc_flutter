import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 品牌红（全局统一）
const Color _kBrandRed = Color(0xFFE63F31);

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
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
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
                _buildConfirmButton(context, isDark, width: double.infinity)
              else
                Row(
                  children: [
                    // 取消按钮
                    Expanded(
                      child: _buildCancelButton(context, isDark),
                    ),
                    const SizedBox(width: 12),
                    // 确定按钮
                    Expanded(
                      child: _buildConfirmButton(context, isDark),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 取消按钮：浅灰底 + 深灰文字
  Widget _buildCancelButton(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(false),
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(8),
          border: isDark
              ? Border.all(color: const Color(0xFF4A4A4C), width: 0.5)
              : null,
        ),
        child: Text(
          cancelText,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF4E5969),
          ),
        ),
      ),
    );
  }

  /// 确定按钮：品牌红底 + 白色文字
  Widget _buildConfirmButton(BuildContext context, bool isDark, {double? width}) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(true),
      child: Container(
        height: 42,
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: confirmColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: confirmColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          confirmText,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
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

  /// 弹出输入弹窗，返回输入的文本；返回 null 表示取消
  static Future<String?> show(
    BuildContext context, {
    String title = '请输入',
    String hintText = '',
    String initialValue = '',
    String cancelText = '取消',
    String confirmText = '确定',
    int maxLines = 3,
    bool barrierDismissible = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
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
      ),
    );
  }

  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
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
                autofocus: true,
                maxLines: widget.maxLines,
                keyboardType: widget.keyboardType,
                inputFormatters: widget.inputFormatters,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1D2129),
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
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
              const SizedBox(height: 24),
              // 按钮区域
              Row(
                children: [
                  // 取消按钮
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F3F5),
                          borderRadius: BorderRadius.circular(8),
                          border: isDark
                              ? Border.all(color: const Color(0xFF4A4A4C), width: 0.5)
                              : null,
                        ),
                        child: Text(
                          widget.cancelText,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF4E5969),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 确定按钮
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(_controller.text.trim()),
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _kBrandRed,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: _kBrandRed.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          widget.confirmText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
