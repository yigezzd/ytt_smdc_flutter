import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/db/dao/reason_info_dao.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/user_helper.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 减免结果（对齐 smdcapp ReducePopup 回调: mark + discount）
class ReducePayResult {
  const ReducePayResult({required this.amount, required this.remark});

  /// 减免金额
  final double amount;

  /// 减免原因
  final String remark;
}

/// 减免弹窗（对齐 smdcapp ReducePopup）
///
/// 减免金额 + 减免原因（typeid=07，单选）+ 手输原因。
/// 后台要求减免原因必填（mustTypes 含 07）时，未选/未填原因点确定会提示并阻止关闭。
class ReducePaySheet extends StatefulWidget {
  const ReducePaySheet({super.key, required this.dsMoney});

  /// 待收金额（减免金额上限）
  final double dsMoney;

  static Future<ReducePayResult?> show(
    BuildContext context, {
    required double dsMoney,
  }) {
    return showModalBottomSheet<ReducePayResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReducePaySheet(dsMoney: dsMoney),
    );
  }

  @override
  State<ReducePaySheet> createState() => _ReducePaySheetState();
}

class _ReducePaySheetState extends State<ReducePaySheet> {
  late final TextEditingController _amountController;
  final TextEditingController _remarkController = TextEditingController();
  String _selectedReason = '';

  /// 减免原因列表（对齐 smdcapp reasonInfo typeid=07，读取后台配置）
  List<String> _reasons = <String>[];

  /// 后台是否要求减免原因必填（对齐 smdcapp SpUtils.getRemarkMustTypes 含 07）
  bool get _reasonRequired => ParamsSpUtils.isRemarkMust('07');

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: _formatNum(widget.dsMoney));
    _loadReasons();
  }

  Future<void> _loadReasons() async {
    try {
      final List<Map<String, dynamic>> rows =
          await ReasonInfoDao.instance.queryByTypeid(
        '07',
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
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  static String _formatNum(double v) {
    if (v == v.roundToDouble()) {
      return v.toInt().toString();
    }
    return v.toStringAsFixed(2);
  }

  void _confirm() {
    final String text = _amountController.text.trim();
    final double? amount = double.tryParse(text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('减免金额必须大于0'), duration: Duration(seconds: 1)),
      );
      return;
    }
    if (amount > widget.dsMoney) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('减免金额不能大于待收金额'), duration: Duration(seconds: 1)),
      );
      return;
    }
    // 对齐 smdcapp：原因 = 手输原因 + 选中原因（逗号拼接）
    final String input = _remarkController.text.trim();
    final List<String> parts = <String>[
      if (input.isNotEmpty) input,
      if (_selectedReason.isNotEmpty) _selectedReason,
    ];
    final String remark = parts.join(',');
    // 后台要求减免原因必填时必须选择/输入原因
    if (_reasonRequired && remark.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择减免原因'), duration: Duration(seconds: 1)),
      );
      return;
    }
    Navigator.of(context).pop(ReducePayResult(amount: amount, remark: remark));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color subColor =
        isDark ? const Color(0xFF9AA0A6) : const Color(0xFF86909C);
    final Color borderColor =
        isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                    color: borderColor,
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
                      '减免',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1D2129),
                      ),
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
              // 待收金额
              Text(
                '待收金额：¥${_formatNum(widget.dsMoney)}',
                style: TextStyle(fontSize: 13, color: subColor),
              ),
              const SizedBox(height: 12),
              // 减免金额输入
              Text('减免金额：', style: TextStyle(fontSize: 13, color: subColor)),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
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
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2E2F30) : const Color(0xFFF7F8FA),
                  hintText: '输入减免金额',
                  hintStyle: TextStyle(fontSize: 14, color: subColor),
                  prefixText: '¥ ',
                  prefixStyle: const TextStyle(fontSize: 15, color: _kBrandRed),
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
              const SizedBox(height: 16),
              // 减免原因（对齐 smdcapp "*减免原因："）
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
                    const TextSpan(text: '减免原因：'),
                  ],
                  style: TextStyle(fontSize: 13, color: subColor),
                ),
              ),
              if (_reasons.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _reasons.map((String reason) {
                    final bool selected = _selectedReason == reason;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(
                          () => _selectedReason = selected ? '' : reason),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? _kBrandRed.withValues(alpha: 0.08)
                              : (isDark
                                  ? const Color(0xFF3A3C3D)
                                  : const Color(0xFFF5F5F5)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: selected ? _kBrandRed : borderColor,
                          ),
                        ),
                        child: Text(
                          reason,
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? _kBrandRed
                                : (isDark
                                    ? Colors.white70
                                    : const Color(0xFF333333)),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _remarkController,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1D2129),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2E2F30) : const Color(0xFFF7F8FA),
                  hintText: '或输入原因',
                  hintStyle: TextStyle(fontSize: 14, color: subColor),
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
                  child: const Text('确定',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
