import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/barcode_scanner_page.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 品牌红（全局统一）
const Color _kBrandRed = Color(0xFFE63F31);

/// 优惠券核销结果
class CouponPayResult {
  const CouponPayResult({required this.code, required this.coupon});

  /// 券号（输入或扫码所得）
  final String code;

  /// 核销接口返回的券信息（对齐 smdcapp YhqBean：faceamt/fid/fno/name 等）
  final Map<String, dynamic> coupon;
}

/// 优惠券支付弹窗（对齐 smdcapp TicketNumSearchPopup）
///
/// 扫码/输入券号 → voucherVerify 券号核销（clienttype="1"）→ 返回券信息；
/// 核销失败只提示不关闭弹窗，可重新输入或扫码（对齐 smdcapp）。
class CouponPayDialog extends StatefulWidget {
  const CouponPayDialog({
    super.key,
    required this.master,
    required this.projectlist,
  });

  /// 销售主表 JSON（对齐 smdcapp getSaleMasterBean）
  final String master;

  /// 销售明细 JSON（对齐 smdcapp detailListBean）
  final String projectlist;

  /// 弹出弹窗，返回核销结果；返回 null 表示取消
  static Future<CouponPayResult?> show(
    BuildContext context, {
    required String master,
    required String projectlist,
  }) {
    return showDialog<CouponPayResult>(
      context: context,
      // 对齐 smdcapp XPopup dismissOnTouchOutside(false)
      barrierDismissible: false,
      builder: (_) => CouponPayDialog(master: master, projectlist: projectlist),
    );
  }

  @override
  State<CouponPayDialog> createState() => _CouponPayDialogState();
}

class _CouponPayDialogState extends State<CouponPayDialog> {
  final TextEditingController _codeCtrl = TextEditingController();
  bool _verifying = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  /// 扫码（对齐 smdcapp iv_scan → MipcaActivityCapture(payid="15")）
  ///
  /// 扫码结果只回填输入框（对齐 smdcapp setCode），点“确定”后再核销。
  Future<void> _scan() async {
    if (_verifying) return;
    if (!Device.isMobile) {
      Toast.show('当前平台暂不支持扫码');
      return;
    }
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute<Object>(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || !mounted) return;
    setState(() => _codeCtrl.text = code.toString());
  }

  /// 券号核销（对齐 smdcapp TicketNumSearchPopup.searchYhQData → voucherVerify）
  Future<void> _verify() async {
    if (_verifying) return;
    final String code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      Toast.show('请输入券号');
      return;
    }
    setState(() => _verifying = true);
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.voucherVerify,
        <String, dynamic>{
          'master': widget.master,
          'projectlist': widget.projectlist,
          // 对齐 smdcapp：clienttype="1" 表示券号核销
          'clienttype': '1',
          'fav': jsonEncode(<String, dynamic>{'fno': code}),
        },
      );
      if (!mounted) return;
      final Map<String, dynamic>? coupon =
          _parseCoupon(resp['data'] ?? resp['Data']);
      if (coupon == null || _toDouble(coupon['faceamt']) <= 0) {
        Toast.show('券号无效或面额为0');
        return;
      }
      // 对齐 smdcapp：核销成功提示接口 retmsg
      final String retmsg = resp['retmsg']?.toString() ?? '';
      if (retmsg.isNotEmpty) Toast.show(retmsg);
      Navigator.of(context).pop(CouponPayResult(code: code, coupon: coupon));
    } catch (_) {
      // 核销失败：requestForm 已提示 retmsg，弹窗保持打开可重输/重扫
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// 解析核销返回的券信息（对齐 smdcapp YhqBean，data 为列表时取第一条）
  Map<String, dynamic>? _parseCoupon(dynamic data) {
    if (data is List) {
      for (final dynamic e in data) {
        if (e is Map<String, dynamic>) return e;
      }
      return null;
    }
    if (data is Map<String, dynamic>) return data;
    return null;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      // 对齐 smdcapp XPopup dismissOnBackPressed(false)：只能通过取消关闭
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 300,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 标题
                Text(
                  '优惠券支付',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                ),
                const SizedBox(height: 16),
                // 券号输入 + 扫码图标（对齐 smdcapp et_discount + iv_scan）
                TextField(
                  controller: _codeCtrl,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                  onSubmitted: (_) => _verify(),
                  decoration: InputDecoration(
                    hintText: '请扫码或输入券号',
                    hintStyle:
                        const TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF3A3A3C)
                        : const Color(0xFFF7F8FA),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    suffixIcon: GestureDetector(
                      onTap: _scan,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SvgPicture.asset(
                          'assets/svg/scan.svg',
                          width: 20,
                          height: 20,
                        ),
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
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
                  children: <Widget>[
                    // 取消按钮
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_verifying) return;
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3A3A3C)
                                : const Color(0xFFF2F3F5),
                            borderRadius: BorderRadius.circular(8),
                            border: isDark
                                ? Border.all(
                                    color: const Color(0xFF4A4A4C), width: 0.5)
                                : null,
                          ),
                          child: Text(
                            '取消',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFFCCCCCC)
                                  : const Color(0xFF4E5969),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 确定按钮（核销中显示 loading）
                    Expanded(
                      child: GestureDetector(
                        onTap: _verify,
                        child: Container(
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _kBrandRed,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: _kBrandRed.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: _verifying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  '确定',
                                  style: TextStyle(
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
      ),
    );
  }
}
