import 'package:flutter/material.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 时价菜 / 称重菜输入弹窗（对齐 smdcapp TimePricePopup）
///
/// 业务逻辑对齐 smdcapp：
/// - type=0 时价菜：输入价格，校验 > 0，最大 999999.999，最多3位小数
/// - type=1 称重菜：输入重量，校验 > 0 且 ≤ 999.999，最多3位小数
///
/// 返回用户确认输入的数值；用户取消时返回 null。
class TimePriceSheet extends StatefulWidget {
  const TimePriceSheet({
    super.key,
    required this.title,
    required this.type,
    this.initValue = 0,
  });

  /// 标题（对齐 smdcapp：时价菜 "{name}-价格"，称重菜 "{name}-重量"）
  final String title;

  /// 类型：0=时价菜(价格)，1=称重菜(重量)（对齐 smdcapp proType）
  final int type;

  /// 初始值（时价菜默认为商品售价作为参考）
  final double initValue;

  /// 弹出弹窗，返回用户输入的数值（取消返回 null）
  static Future<double?> show(
    BuildContext context, {
    required String title,
    required int type,
    double initValue = 0,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TimePriceSheet(
        title: title,
        type: type,
        initValue: initValue,
      ),
    );
  }

  @override
  State<TimePriceSheet> createState() => _TimePriceSheetState();
}

class _TimePriceSheetState extends State<TimePriceSheet> {
  /// 当前输入的文本
  String _input = '';

  /// 最大允许值（对齐 smdcapp DecimalInputFilter maxValue）
  double get _maxValue => widget.type == 0 ? 999999.999 : 999.999;

  /// 最多小数位数（对齐 smdcapp DecimalInputFilter 3位）
  static const int _maxDecimal = 3;

  /// 追加字符（数字或小数点，对齐 smdcapp setValue）
  void _append(String value) {
    final String content = _input;
    if (value == '.') {
      // 已有小数点则忽略
      if (content.contains('.')) return;
      // 空串时补 0.
      _setInput(content.isEmpty ? '0.' : '$content.');
      return;
    }
    final String next = content.isEmpty ? value : content + value;
    _setInput(next);
  }

  /// 设置输入文本（带最大值与小数位校验，对齐 smdcapp DecimalInputFilter）
  void _setInput(String next) {
    // 校验小数位数不超过3位
    final int dotIndex = next.indexOf('.');
    if (dotIndex >= 0 && next.length - dotIndex - 1 > _maxDecimal) {
      return;
    }
    // 校验最大值
    final double? parsed = double.tryParse(next);
    if (parsed != null && parsed > _maxValue) {
      Toast.show(widget.type == 0 ? '价格超出范围' : '不能超过999.999');
      return;
    }
    setState(() => _input = next);
  }

  /// 退格（对齐 smdcapp setValue("-1")）
  void _backspace() {
    if (_input.isEmpty) return;
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  /// 清空（对齐 smdcapp setValue("-2")）
  void _clear() {
    setState(() => _input = '');
  }

  /// 确定（对齐 smdcapp tv_ok 校验逻辑）
  void _confirm() {
    final double? value = double.tryParse(_input.trim());
    if (value == null) {
      Toast.show('请输入');
      return;
    }
    if (widget.type == 0) {
      // 时价菜：价格必须大于0
      if (value <= 0) {
        Toast.show('不能为0');
        return;
      }
    } else {
      // 称重菜：重量必须大于0且不超过999.99
      if (value > 999.99) {
        Toast.show('不能超过999.99');
        return;
      }
      if (value <= 0) {
        Toast.show('输入的数量必须大于0');
        return;
      }
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildHeader(isDark),
          _buildInputArea(isDark),
          _buildKeyboard(isDark),
          _buildConfirmButton(),
        ],
      ),
    );
  }

  /// 标题栏（标题 + 关闭按钮，对齐 smdcapp tv_name + ll_close）
  Widget _buildHeader(bool isDark) {
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
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              Icons.close,
              size: 20,
              color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 输入展示区（只读展示 + 退格，对齐 smdcapp et_discount）
  Widget _buildInputArea(bool isDark) {
    final String hint = widget.type == 0
        ? (widget.initValue > 0 ? '原价¥${_fmt(widget.initValue)}，请输入价格' : '请输入价格')
        : '请输入重量';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _input.isEmpty ? hint : _input,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _input.isEmpty
                    ? (isDark ? const Color(0xFF666666) : const Color(0xFF9CA3AF))
                    : (isDark ? Colors.white : const Color(0xFF1D2129)),
              ),
            ),
          ),
          GestureDetector(
            onTap: _backspace,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.backspace_outlined,
                size: 22,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 数字键盘（对齐 smdcapp bt_1~bt_9/bt_0/bt_dian/bt_dishes/bt_table）
  Widget _buildKeyboard(bool isDark) {
    const List<List<String>> rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['清空', '0', '.'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows
            .map((List<String> row) => Row(
                  children: row
                      .map((String key) => Expanded(
                            child: _buildKey(key, isDark),
                          ))
                      .toList(),
                ))
            .toList(),
      ),
    );
  }

  /// 单个键盘按键
  Widget _buildKey(String key, bool isDark) {
    final bool isAction = key == '清空';
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Material(
        color: isAction
            ? (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF0F1F2))
            : (isDark ? const Color(0xFF333536) : const Color(0xFFF7F8FA)),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (key == '清空') {
              _clear();
            } else {
              _append(key);
            }
          },
          child: SizedBox(
            height: 52,
            child: Center(
              child: Text(
                key,
                style: TextStyle(
                  fontSize: isAction ? 15 : 20,
                  fontWeight: FontWeight.w600,
                  color: isAction
                      ? (isDark ? const Color(0xFFB8B8B8) : const Color(0xFF4E5969))
                      : (isDark ? Colors.white : const Color(0xFF1D2129)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 确定按钮（对齐 smdcapp tv_ok）
  Widget _buildConfirmButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GestureDetector(
        onTap: _confirm,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFFF0503F), _kBrandRed],
            ),
            borderRadius: BorderRadius.circular(23),
          ),
          child: const Center(
            child: Text(
              '确定',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }
}
