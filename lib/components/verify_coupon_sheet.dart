import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 团购核销弹窗（对齐 smdcapp DyVerifyPopup）
///
/// 支持扫码/输入券号 → 查询券信息 → 确认核销。
/// businesstype: 0=抖音, 1=美团, 3=快手
class VerifyCouponSheet extends StatefulWidget {
  const VerifyCouponSheet({
    super.key,
    required this.saleid,
    this.billno = '',
  });

  final String saleid;
  final String billno;

  /// 显示核销弹窗，返回核销金额（成功时 > 0）
  static Future<double> show(
    BuildContext context, {
    required String saleid,
    String billno = '',
  }) async {
    final double? result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VerifyCouponSheet(saleid: saleid, billno: billno),
    );
    return result ?? 0;
  }

  @override
  State<VerifyCouponSheet> createState() => _VerifyCouponSheetState();
}

class _VerifyCouponSheetState extends State<VerifyCouponSheet> {
  final TextEditingController _codeCtrl = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  bool _querying = false;
  bool _verifying = false;

  /// 查询到的券信息
  Map<String, dynamic>? _couponInfo;

  @override
  void initState() {
    super.initState();
    // 打开抽屉后自动聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _codeFocusNode.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFE5E6EB), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              // 标题栏
              Row(
                children: <Widget>[
                  Container(
                    width: 4, height: 18,
                    decoration: BoxDecoration(color: _kBrandRed, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('团购核销', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1D2129))),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: const Color(0xFFF2F3F5), shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF86909C)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 券号输入区域
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E6EB)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        focusNode: _codeFocusNode,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
                        decoration: InputDecoration(
                          hintText: '输入或扫描券号',
                          hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                          prefixIcon: const Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFF86909C)),
                          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _queryCoupon(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _querying ? null : _queryCoupon,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBrandRed,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFF5B8B2),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _querying
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                            : const Text('查询', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 券信息展示
              if (_couponInfo != null) _buildCouponInfo(),
              if (_couponInfo != null) const SizedBox(height: 16),
              // 核销按钮
              if (_couponInfo != null)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _verifying ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B42A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFAFF0B5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _verifying
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                        : const Text('确认核销', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCouponInfo() {
    final String name = _couponInfo!['marketname']?.toString() ?? _couponInfo!['couponname']?.toString() ?? '团购券';
    final String price = _couponInfo!['productprice']?.toString() ?? _couponInfo!['amount']?.toString() ?? '0';
    final String type = _couponInfo!['dytype']?.toString() == '2' ? '代金券' : '团购券';
    final String platform = _getPlatformName();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E6EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(4)),
                child: Text(platform, style: const TextStyle(fontSize: 11, color: Colors.green)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(4)),
                child: Text(type, style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('面值：¥$price', style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
        ],
      ),
    );
  }

  String _getPlatformName() {
    final String bt = _couponInfo!['businesstype']?.toString() ?? '0';
    switch (bt) {
      case '0': return '抖音';
      case '1': return '美团';
      case '3': return '快手';
      default: return '团购';
    }
  }

  /// 查询券信息（对齐 smdcapp getDyCoupunInfo / getTuanGouCoupunInfo）
  Future<void> _queryCoupon() async {
    final String code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      Toast.show('请输入券号');
      return;
    }
    setState(() {
      _querying = true;
      _couponInfo = null;
    });
    try {
      // 对齐 smdcapp: 先尝试自动识别（getTuanGouCoupunInfo）
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getTuanGouCoupunInfo,
        <String, dynamic>{'code': code},
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic> && data.isNotEmpty) {
        setState(() => _couponInfo = data);
      } else {
        Toast.show('未查询到券信息');
      }
    } catch (_) {
      Toast.show('查询失败，请检查券号');
    } finally {
      if (mounted) setState(() => _querying = false);
    }
  }

  /// 核销（对齐 smdcapp douyin/prepare）
  Future<void> _verify() async {
    if (_couponInfo == null) return;
    setState(() => _verifying = true);
    try {
      await requestForm(HttpApi.douyinPrepare, <String, dynamic>{
        'verify_token': _couponInfo!['verify_token']?.toString() ?? '',
        'order_id': _couponInfo!['order_id']?.toString() ?? '',
        'certificates': _couponInfo!['certificates']?.toString() ?? '',
        'saleid': widget.saleid,
        'billno': widget.billno,
        'cashid': '',
        'cashname': '',
        'marketcode': _couponInfo!['marketcode']?.toString() ?? '',
        'marketname': _couponInfo!['marketname']?.toString() ?? '',
        'dytype': _couponInfo!['dytype']?.toString() ?? '1',
        'productprice': _couponInfo!['productprice']?.toString() ?? '0',
        'businesstype': _couponInfo!['businesstype']?.toString() ?? '0',
      });
      if (!mounted) return;
      final double amt = double.tryParse(_couponInfo!['productprice']?.toString() ?? '0') ?? 0;
      Toast.show('核销成功');
      Navigator.pop(context, amt);
    } catch (_) {
      if (mounted) Toast.show('核销失败');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }
}
