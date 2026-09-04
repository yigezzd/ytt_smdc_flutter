import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/barcode_scanner_page.dart';

/// 品牌红（对齐本项目 spec_cook_sheet 等较新弹窗组件）
const Color _kBrandRed = Color(0xFFE63F31);

/// 团券核销结果（对齐 smdcapp VerifyDishesEvent2：券信息 + 选中商品明细）
class VerifyDishesResult {
  const VerifyDishesResult({
    required this.coupon,
    required this.selectedDetails,
  });

  /// 券信息（getTuanGouCoupunInfo 返回的 data，对齐 VerifyDishesBean.DataBean）
  final Map<String, dynamic> coupon;

  /// 选中的商品明细（对齐 VerifyDishesPopup3 确认后 list，元素为 prolist[].detail[] 原始 Map）
  final List<Map<String, dynamic>> selectedDetails;
}

/// 点菜页团券核销弹窗（对齐 smdcapp DishesVerifyPopup + VerifyDishesPopup3 核心流程）
///
/// 流程：输入/扫描券号 → getTuanGouCoupunInfo 查询券信息 →
/// 展示商品组（signtype!=1 全部核销；signtype==1 单选部分核销）→ 确定返回选中明细。
/// 核销(prepare)与加购由调用方按 smdcapp onVerifyDishesEvent 处理。
class VerifyDishesSheet extends StatefulWidget {
  const VerifyDishesSheet({super.key});

  /// 显示团券核销弹窗，返回核销选择结果（取消返回 null）
  static Future<VerifyDishesResult?> show(BuildContext context) {
    return showModalBottomSheet<VerifyDishesResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VerifyDishesSheet(),
    );
  }

  @override
  State<VerifyDishesSheet> createState() => _VerifyDishesSheetState();
}

class _VerifyDishesSheetState extends State<VerifyDishesSheet> {
  final TextEditingController _codeCtrl = TextEditingController();
  bool _querying = false;

  /// 券信息（对齐 smdcapp VerifyDishesBean.DataBean）
  Map<String, dynamic>? _coupon;

  /// 商品组列表（对齐 smdcapp prolist）
  final List<_VerifyGroup> _groups = <_VerifyGroup>[];

  @override
  void initState() {
    super.initState();
    // 监听券号输入变化以刷新清空按钮显隐
    _codeCtrl.addListener(_onCodeChanged);
  }

  void _onCodeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _codeCtrl.removeListener(_onCodeChanged);
    _codeCtrl.dispose();
    super.dispose();
  }

  /// 扫码（对齐 smdcapp DishesVerifyPopup iv_scan → MipcaActivityCapture）
  Future<void> _scan() async {
    if (!Device.isMobile) {
      Toast.show('当前平台暂不支持扫码');
      return;
    }
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute<Object>(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || !mounted) return;
    _codeCtrl.text = code.toString();
    await _query();
  }

  /// 查询券信息（对齐 smdcapp DishesVerifyPopup.getDyCoupunInfo → getTuanGouCoupunInfo）
  Future<void> _query() async {
    final String code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      Toast.show('请输入券号');
      return;
    }
    setState(() {
      _querying = true;
    });
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getTuanGouCoupunInfo,
        <String, dynamic>{'code': code},
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (!mounted) return;
      if (data is Map<String, dynamic> && data.isNotEmpty) {
        setState(() {
          _coupon = data;
          _groups
            ..clear()
            ..addAll(_parseGroups(data));
        });
      } else {
        Toast.show('查询券信息失败');
      }
    } catch (_) {
      if (mounted) Toast.show('查询券信息失败');
    } finally {
      if (mounted) setState(() => _querying = false);
    }
  }

  /// 解析商品组（对齐 smdcapp prolist：signtype 0=全部核销 1=部分核销单选）
  List<_VerifyGroup> _parseGroups(Map<String, dynamic> data) {
    final List<_VerifyGroup> result = <_VerifyGroup>[];
    final dynamic prolist = data['prolist'];
    if (prolist is! List) return result;
    for (final dynamic g in prolist) {
      if (g is! Map<String, dynamic>) continue;
      final dynamic detail = g['detail'];
      final List<Map<String, dynamic>> details = detail is List
          ? detail.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      result.add(_VerifyGroup(
        productgroupname: g['productgroupname']?.toString() ?? '',
        signtype: g['signtype']?.toString() ?? '0',
        details: details,
      ));
    }
    return result;
  }

  /// 确定（对齐 smdcapp VerifyDishesPopup3 tvAddCart 选择逻辑）
  void _confirm() {
    final Map<String, dynamic>? coupon = _coupon;
    if (coupon == null) {
      Toast.show('请先查询券信息');
      return;
    }
    if (_groups.isEmpty) {
      Toast.show('没有商品信息');
      return;
    }
    final List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
    for (final _VerifyGroup g in _groups) {
      if (g.details.isEmpty) continue;
      if (g.signtype != '1') {
        // 全部核销（对齐 smdcapp signtype != "1" → addAll）
        list.addAll(g.details);
      } else {
        // 部分核销：必须单选一项（对齐 smdcapp find == null → "${groupname}组未选择商品"）
        if (g.selectedIndex < 0) {
          Toast.show('${g.productgroupname}组未选择商品');
          return;
        }
        list.add(g.details[g.selectedIndex]);
      }
    }
    if (list.isEmpty) {
      Toast.show('没有有效的商品信息');
      return;
    }
    Navigator.of(context)
        .pop(VerifyDishesResult(coupon: coupon, selectedDetails: list));
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
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildHeader(isDark),
            const SizedBox(height: 12),
            // 券号输入 + 清空 + 扫码（对齐 smdcapp et_discount + iv_scan）
            Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            isDark ? Colors.white : const Color(0xFF1D2129),
                      ),
                      decoration: const InputDecoration(
                        hintText: '请输入券号',
                        hintStyle: TextStyle(
                            fontSize: 14, color: Color(0xFFC9CDD4)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _query(),
                    ),
                  ),
                  if (_codeCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () => _codeCtrl.clear(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.cancel,
                            size: 16,
                            color: isDark
                                ? const Color(0xFF666666)
                                : const Color(0xFFC9CDD4)),
                      ),
                    ),
                  GestureDetector(
                    onTap: _scan,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.qr_code_scanner,
                          size: 22, color: _kBrandRed),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 券信息 + 商品组选择
            if (_coupon != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildCouponHeader(isDark),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildGroupList(isDark),
                ),
              ),
              const SizedBox(height: 10),
            ],
            // 底部按钮（对齐 smdcapp tv_qx 取消 + tv_ok 确定）
            _buildBottomBar(isDark),
          ],
        ),
      ),
    );
  }

  /// 标题栏（红条 + 团券核销 + 圆形关闭，对齐本项目统一弹窗风格）
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
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
              '团券核销',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 18,
                color: isDark ? Colors.white70 : const Color(0xFF86909C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏（次按钮取消 + 主按钮查询/确定，对齐 spec_cook_sheet 按钮风格）
  Widget _buildBottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3C3D)
                      : const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _kBrandRed),
                ),
                alignment: Alignment.center,
                child: const Text('取消',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kBrandRed)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _querying ? null : (_coupon == null ? _query : _confirm),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kBrandRed.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _querying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : Text(_coupon == null ? '查询' : '确定',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 券信息头（名称 + 面额 + 数量，对齐 VerifyDishesBean.DataBean 展示）
  Widget _buildCouponHeader(bool isDark) {
    final Map<String, dynamic> c = _coupon!;
    final String name = c['name']?.toString() ?? '团购券';
    final String price = c['dealprice']?.toString() ??
        c['productprice']?.toString() ??
        '0';
    final String count =
        c['realcount']?.toString() ?? c['count']?.toString() ?? '1';
    final String platform = _platformName(c['businesstype']?.toString() ?? '0');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2E3B2E) : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(platform,
                style: const TextStyle(fontSize: 11, color: Colors.green)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF1D2129)),
                overflow: TextOverflow.ellipsis),
          ),
          Text('¥$price x $count',
              style: const TextStyle(fontSize: 13, color: _kBrandRed)),
        ],
      ),
    );
  }

  String _platformName(String bt) {
    switch (bt) {
      case '0':
        return '抖音';
      case '1':
        return '美团';
      case '3':
        return '快手';
      default:
        return '团购';
    }
  }

  /// 商品组列表（对齐 smdcapp VerifyDishesPopup3 分组展示）
  Widget _buildGroupList(bool isDark) {
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        for (final _VerifyGroup g in _groups) ...<Widget>[
          // 组标题（部分核销组提示单选）
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Container(
                  width: 3.5,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _kBrandRed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(g.productgroupname,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Colors.white : const Color(0xFF1D2129))),
                const SizedBox(width: 6),
                Text(
                  g.signtype == '1' ? '(单选)' : '(全部)',
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF999999)
                          : const Color(0xFF86909C)),
                ),
              ],
            ),
          ),
          for (int i = 0; i < g.details.length; i++)
            _buildDetailRow(g, i, isDark),
        ],
      ],
    );
  }

  /// 商品行（名称 + 价格x数量 + 选择态）
  Widget _buildDetailRow(_VerifyGroup g, int index, bool isDark) {
    final Map<String, dynamic> d = g.details[index];
    final String name =
        d['productname']?.toString() ?? d['name']?.toString() ?? '';
    final String price = d['price']?.toString() ?? '0';
    final String qty = d['qty']?.toString() ?? '1';
    final bool selectable = g.signtype == '1';
    final bool checked = !selectable || g.selectedIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selectable
          ? () => setState(() => g.selectedIndex = index)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: checked && selectable
              ? (isDark ? const Color(0xFF3D2826) : const Color(0xFFFFF1F0))
              : null,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? const Color(0xFF3A3C3D)
                  : const Color(0xFFF2F3F5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selectable
                  ? (checked
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked)
                  : Icons.check_circle,
              size: 18,
              color: checked ? _kBrandRed : const Color(0xFFC9CDD4),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Colors.white : const Color(0xFF1D2129)),
                  overflow: TextOverflow.ellipsis),
            ),
            Text('¥$price x $qty',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF999999)
                        : const Color(0xFF86909C))),
          ],
        ),
      ),
    );
  }
}

/// 商品组（对齐 smdcapp VerifyDishesBean.ProlistBean 核心字段）
class _VerifyGroup {
  _VerifyGroup({
    required this.productgroupname,
    required this.signtype,
    required this.details,
  });

  final String productgroupname;

  /// 核销类型：0=全部核销 1=部分核销（单选）
  final String signtype;
  final List<Map<String, dynamic>> details;

  /// 部分核销组当前选中下标（-1=未选）
  int selectedIndex = -1;
}
