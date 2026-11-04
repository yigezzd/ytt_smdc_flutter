import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/user_helper.dart';
import 'package:flutter_deer/widgets/barcode_scanner_page.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F26);

/// 团购核销结果（对齐 smdcapp DyVerifyBean）
class VerifyCouponResult {
  const VerifyCouponResult({
    required this.dealAmount,
    required this.eligibleAmount,
    required this.originalAmount,
    required this.name,
    required this.code,
    required this.verifyToken,
    required this.businesstype,
    required this.payId,
    required this.payName,
    required this.onlyId,
    required this.couponIds,
    this.voucher = '',
  });

  /// 券结算价（dy.dealprice，记账实收）
  final double dealAmount;

  /// 可核销金额（dy.productprice，按订单明细计算并封顶待收）
  final double eligibleAmount;

  /// 原价合计（dy.oldproductprice）
  final double originalAmount;

  final String name;

  /// 券号（marketcode）
  final String code;

  /// 验券标识（verify_token）
  final String verifyToken;

  /// 0=抖音 1=美团 3=快手
  final String businesstype;

  /// 收款记录使用的支付方式
  final String payId;
  final String payName;

  /// 核销批次唯一标识（querytoken）
  final String onlyId;

  /// 已核销商品 productid 列表（对齐 dy.ids）
  final List<String> couponIds;

  /// 核销返回的验券ID（对齐 dy.voucher = verify_id）
  final String voucher;

  /// 券面值与原价差额（平台优惠，对齐 productprice - dealprice）
  double get discount => eligibleAmount > dealAmount
      ? eligibleAmount - dealAmount
      : 0;
}

/// 结账页团购核销弹窗（对齐 smdcapp DyVerifyPopup）
///
/// 逻辑：
/// 1. 按平台 businesstype 调用 getDyCoupunInfo 查券；
/// 2. dytype=1 团购券按券商品组匹配订单明细计算可核销金额；
///    dytype=2 代金券按 usescope/itemlimit 计算可核销金额；
/// 3. 可核销金额封顶待收 dsMoney，调用 prepare 核销后返回记账数据。
class VerifyCouponSheet extends StatefulWidget {
  const VerifyCouponSheet({
    super.key,
    required this.saleid,
    required this.billno,
    required this.details,
    required this.dsMoney,
    this.memberPay = false,
    this.payId = '',
    this.payName = '',
  });

  final String saleid;
  final String billno;

  /// 订单明细（对齐 smdcapp PayDetailsLayout.dyVetify shopDetailsBean）
  final List<Map<String, dynamic>> details;

  /// 待收金额（对齐 smdcapp placedOrderBean.dsMoney）
  final double dsMoney;

  /// 是否已使用会员卡支付（代金券 usescope[8] 校验）
  final bool memberPay;

  /// 支付方式编码（13 / meituantuangou / kuaishou；为空时由弹窗选择平台）
  final String payId;
  final String payName;

  /// 显示核销弹窗，返回核销结果；null 表示取消
  static Future<VerifyCouponResult?> show(
    BuildContext context, {
    required String saleid,
    required String billno,
    required List<Map<String, dynamic>> details,
    required double dsMoney,
    bool memberPay = false,
    String payId = '',
    String payName = '',
  }) async {
    return showModalBottomSheet<VerifyCouponResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VerifyCouponSheet(
        saleid: saleid,
        billno: billno,
        details: details,
        dsMoney: dsMoney,
        memberPay: memberPay,
        payId: payId,
        payName: payName,
      ),
    );
  }

  @override
  State<VerifyCouponSheet> createState() => _VerifyCouponSheetState();
}

class _VerifyCouponSheetState extends State<VerifyCouponSheet> {
  final TextEditingController _codeCtrl = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  bool _busy = false;

  /// 核销类型：0=抖音 1=美团 3=快手
  late int _businesstype;

  bool get _platformFixed => _isDyPayId(widget.payId);

  @override
  void initState() {
    super.initState();
    _businesstype = _businesstypeOf(widget.payId);
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

  /// 券号去空格（复制券号常带空格/换行）
  String get _cleanCode => _codeCtrl.text.replaceAll(RegExp(r'\s+'), '');

  /// R76：调用摄像头扫描团购券码
  Future<void> _scanCode() async {
    final Object? code = await Navigator.push<Object>(
      context,
      MaterialPageRoute<Object>(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || !mounted) return;
    _codeCtrl.text = code.toString().replaceAll(RegExp(r'\s+'), '');
    await _verify();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF4A4C4D)
                        : const Color(0xFFE5E6EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildHeader(isDark),
              const SizedBox(height: 16),
              if (!_platformFixed) ...<Widget>[
                _buildPlatformChips(isDark),
                const SizedBox(height: 12),
              ],
              _buildCodeInput(isDark),
              const SizedBox(height: 10),
              Text(
                _platformFixed
                    ? '请输入${_platformName(_businesstype)}团购券号，核销金额按本单可核销商品计算'
                    : '支持抖音 / 美团 / 快手团购券，核销金额按本单可核销商品计算',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color:
                      isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                ),
              ),
              const SizedBox(height: 18),
              _buildBottomBar(isDark),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题栏
  Widget _buildHeader(bool isDark) {
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
            _platformFixed && widget.payName.isNotEmpty
                ? widget.payName
                : '团购核销',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF86909C),
            ),
          ),
        ),
      ],
    );
  }

  /// 平台选择（通用入口时使用；对齐 smdcapp 按支付方式区分核销类型）
  Widget _buildPlatformChips(bool isDark) {
    const List<String> names = <String>['抖音', '美团', '快手'];
    const List<int> types = <int>[0, 1, 3];
    return Row(
      children: List<Widget>.generate(names.length, (int index) {
        final int type = types[index];
        final bool selected = _businesstype == type;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _businesstype = type),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark
                        ? const Color(0xFF3D2826)
                        : const Color(0xFFFFF1F0))
                    : (isDark
                        ? const Color(0xFF2C2D2E)
                        : const Color(0xFFF7F8FA)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? _kBrandRed
                      : (isDark
                          ? const Color(0xFF3A3C3D)
                          : const Color(0xFFE5E6EB)),
                ),
              ),
              child: Text(
                names[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? _kBrandRed
                      : (isDark
                          ? Colors.white70
                          : const Color(0xFF4E5969)),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// 券号输入 + 扫码
  Widget _buildCodeInput(bool isDark) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              focusNode: _codeFocusNode,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: const InputDecoration(
                hintText: '请扫码或输入券号',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) => _verify(),
            ),
          ),
          GestureDetector(
            onTap: _scanCode,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child:
                  Icon(Icons.qr_code_scanner, size: 22, color: _kBrandRed),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部按钮（取消 + 确定，对齐 dialog_dy_vetify tv_qx/tv_ok）
  Widget _buildBottomBar(bool isDark) {
    return Row(
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF3A3C3D) : const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kBrandRed),
              ),
              alignment: Alignment.center,
              child: const Text(
                '取消',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _kBrandRed),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _busy ? null : _verify,
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
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '确定',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// 查券 + 计算可核销金额 + 核销（对齐 DyVerifyPopup getDyCoupunInfo/dealFinallyDate）
  Future<void> _verify() async {
    final String code = _cleanCode;
    if (code.isEmpty) {
      Toast.show('请输入券号');
      return;
    }
    if (_codeCtrl.text != code) {
      _codeCtrl.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      // 1. 查券（对齐 getDyCoupunInfo(code, businesstype)）
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getDyCoupunInfo,
        <String, dynamic>{
          'code': code,
          'businesstype': '$_businesstype',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is! Map || data.isEmpty) {
        final String msg = resp['retmsg']?.toString() ??
            resp['Message']?.toString() ??
            resp['message']?.toString() ??
            '';
        throw _VerifyException(msg.isNotEmpty ? msg : '查询券信息失败');
      }
      final Map<String, dynamic> coupon = Map<String, dynamic>.from(data);

      // 2. 计算可核销金额（对齐 dealGroupBuyDate / isCouponUser）
      final _DyAmountCalc calc = _computeAmount(coupon);
      if (calc.eligible <= 0) {
        throw const _VerifyException('该券没有可以核销的商品');
      }

      // 3. 核销（对齐 dealFinallyDate → prepare）
      final List<String> certificates = <String>[];
      final dynamic rawCerts = coupon['certificates'];
      if (rawCerts is List) {
        for (final dynamic c in rawCerts) {
          final String v = c?.toString() ?? '';
          if (v.isNotEmpty) certificates.add(v);
        }
      }
      final Map<String, dynamic> prepareResp = await requestForm(
        HttpApi.douyinPrepare,
        <String, dynamic>{
          'verify_token': coupon['verify_token']?.toString() ?? '',
          'order_id': coupon['order_id']?.toString() ?? '',
          'certificates': certificates.isNotEmpty ? certificates.first : '',
          'saleid': widget.saleid,
          'billno': widget.billno,
          'cashid': UserHelper.getUserid(),
          'cashname': UserHelper.getName(),
          'marketcode': coupon['code']?.toString() ?? '',
          'marketname': coupon['name']?.toString() ?? '',
          'dytype': coupon['dytype']?.toString() ?? '1',
          'productprice': calc.eligible.toStringAsFixed(2),
          'businesstype': '$_businesstype',
        },
        showError: false,
      );
      final dynamic prepareData = prepareResp['data'] ?? prepareResp['Data'];
      if (prepareData is! List || prepareData.isEmpty) {
        throw const _VerifyException('核销失败：券核销id为空');
      }
      final dynamic firstPrepared = prepareData.first;
      final String voucher = firstPrepared is Map
          ? (firstPrepared['verify_id']?.toString() ?? '')
          : '';
      if (!mounted) return;
      Navigator.pop(
        context,
        VerifyCouponResult(
          dealAmount: _toDouble(coupon['dealprice']),
          eligibleAmount: calc.eligible,
          originalAmount: calc.original,
          name: coupon['name']?.toString() ?? '团购券',
          code: coupon['code']?.toString() ?? code,
          verifyToken: coupon['verify_token']?.toString() ?? '',
          businesstype: '$_businesstype',
          payId: _payIdOf(_businesstype),
          payName:
              _platformFixed && widget.payName.isNotEmpty
                  ? widget.payName
                  : _payNameOf(_businesstype),
          onlyId: _genOnlyId(),
          couponIds: calc.ids,
          voucher: voucher,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final String msg = e.toString().replaceFirst('Exception: ', '');
      Toast.show(msg.isNotEmpty ? msg : '核销失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 可核销金额计算（对齐 smdcapp DyVerifyPopup）
  _DyAmountCalc _computeAmount(Map<String, dynamic> coupon) {
    final List<Map<String, dynamic>> usable =
        widget.details.where(_isUsableDetail).toList();
    final String dytype = coupon['dytype']?.toString() ?? '1';
    if (dytype == '1') {
      return _computeGroupBuy(coupon, usable);
    }
    return _computeVoucher(coupon, usable);
  }

  /// 下单明细是否参与核销（对齐 dyVetify：赠品/买赠/退菜/已核销/套餐子行排除）
  bool _isUsableDetail(Map<String, dynamic> d) {
    final int presentflag = _toInt(d['presentflag']);
    final int bxxpxxflag = _toInt(d['bxxpxxflag']);
    if (presentflag == 1 || presentflag == 2) return false;
    if (bxxpxxflag == 1 || bxxpxxflag == 2 || bxxpxxflag == 6) return false;
    if (d['isCouponHx'] == true || _toInt(d['isCouponHx']) == 1) return false;
    if (_toInt(d['douyinflag']) == 1) return false;
    // 套餐子行金额已计入主行，不单独参与核销（对齐 smdcapp 一级商品 list）
    if ((d['combproductid']?.toString() ?? '').isNotEmpty) return false;
    // 暂结商品不参与本次结账核销
    if ((d['fornowid']?.toString() ?? '').isNotEmpty) return false;
    return true;
  }

  /// 团购券：按券商品组匹配订单明细（对齐 dealGroupBuyDate）
  _DyAmountCalc _computeGroupBuy(
      Map<String, dynamic> coupon, List<Map<String, dynamic>> usable) {
    final dynamic prolist = coupon['prolist'];
    if (prolist is! List || prolist.isEmpty) {
      return const _DyAmountCalc(0, 0, <String>[]);
    }
    double allAmt = 0;
    double allAmtAny = 0;
    double oldAmt = 0;
    double oldAmtAny = 0;
    final List<String> ids = <String>[];

    for (final dynamic g in prolist) {
      if (g is! Map) continue;
      final String signtype = g['signtype']?.toString() ?? '0';
      final dynamic detail = g['detail'];
      if (detail is! List || detail.isEmpty) continue;

      if (signtype == '0') {
        // 核销全部：逐券商品取订单中匹配商品的最大可核销金额
        for (final dynamic p in detail) {
          if (p is! Map) continue;
          bool matched = false;
          double maxAmt = 0;
          for (final Map<String, dynamic> d in usable) {
            if (!_sameProduct(d, p)) continue;
            matched = true;
            final double amt = _noCookAmt(d);
            if (amt > maxAmt) maxAmt = amt;
            oldAmt += _toDouble(d['qty']) * _toDouble(d['sellprice']);
            ids.add(d['productid']?.toString() ?? '');
          }
          if (matched) allAmt += maxAmt;
        }
      } else {
        // 核销任意一项：取订单中匹配商品的最大可核销金额
        for (final Map<String, dynamic> d in usable) {
          bool matched = false;
          for (final dynamic p in detail) {
            if (p is! Map) continue;
            if (_sameProduct(d, p)) {
              matched = true;
              break;
            }
          }
          if (!matched) continue;
          final double amt = _noCookAmt(d);
          if (amt > allAmtAny) allAmtAny = amt;
          oldAmtAny += _toDouble(d['qty']) * _toDouble(d['sellprice']);
          ids.add(d['productid']?.toString() ?? '');
        }
      }
    }

    double maxAmt = allAmt + allAmtAny;
    if (maxAmt >= widget.dsMoney) maxAmt = widget.dsMoney;
    return _DyAmountCalc(
      maxAmt,
      oldAmt + oldAmtAny,
      _dedup(ids),
    );
  }

  /// 代金券：按 usescope / itemlimit 筛选商品（对齐 isCouponUser）
  _DyAmountCalc _computeVoucher(
      Map<String, dynamic> coupon, List<Map<String, dynamic>> usable) {
    final String usescope = coupon['usescope']?.toString() ?? '';
    final List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[];
    void addWhere(bool Function(Map<String, dynamic>) test) {
      for (final Map<String, dynamic> d in usable) {
        if (test(d) && !candidates.any((Map<String, dynamic> c) => identical(c, d))) {
          candidates.add(d);
        }
      }
    }

    // 没有任何促销的商品先筛选出来
    addWhere((Map<String, dynamic> d) => _toInt(d['specpriceflag']) == 0);
    if (usescope.isNotEmpty) {
      if (usescope.length >= 9) {
        if (usescope[0] == '1') addWhere((Map<String, dynamic> d) => _toInt(d['specpriceflag']) == 1);
        if (usescope[1] == '1') addWhere((Map<String, dynamic> d) => _toInt(d['specpriceflag']) == 2);
        if (usescope[2] == '1') addWhere((Map<String, dynamic> d) => _toInt(d['specpriceflag']) == 3);
        if (usescope[3] == '1') addWhere((Map<String, dynamic> d) => _toInt(d['bxxpxxflag']) == 1);
        if (usescope[4] == '1') addWhere((Map<String, dynamic> d) => _toInt(d['bxxpxxflag']) == 2);
        if (usescope[5] == '1') addWhere((Map<String, dynamic> d) => _toInt(d['bxxpxxflag']) == 3);
        if (usescope[6] == '1') addWhere((Map<String, dynamic> d) => _toInt(d['bxxpxxflag']) == 4);
        if (usescope[7] == '1') addWhere((Map<String, dynamic> d) => _toInt(d['bxxpxxflag']) == 5);
        if (usescope[8] == '0' && widget.memberPay) {
          throw const _VerifyException('该券不能和会员卡同时支付使用');
        }
      }
      if (candidates.isEmpty) {
        throw const _VerifyException('未找到可核销的商品');
      }
    }

    if (candidates.isEmpty) {
      throw const _VerifyException('未找到可核销的商品');
    }

    final double faceAmt = _toDouble(coupon['productprice']);
    final int itemlimit = _toInt(coupon['itemlimit']);
    double maxCoupAmt = 0;
    final List<String> ids = <String>[];

    void addCandidate(Map<String, dynamic> d) {
      ids.add(d['productid']?.toString() ?? '');
      maxCoupAmt += _noCookAmt(d);
    }

    if (itemlimit == 0) {
      // 全部商品：直接按券面额与待收取小
      maxCoupAmt = faceAmt < widget.dsMoney ? faceAmt : widget.dsMoney;
      for (final Map<String, dynamic> d in candidates) {
        ids.add(d['productid']?.toString() ?? '');
      }
    } else if (itemlimit == 1) {
      // 指定分类
      final dynamic prolist = coupon['prolist'];
      for (final Map<String, dynamic> d in candidates) {
        if (_matchListId(d, prolist, byType: true)) addCandidate(d);
      }
    } else {
      // 指定商品
      final dynamic prolist = coupon['prolist'];
      for (final Map<String, dynamic> d in candidates) {
        if (_matchListId(d, prolist, byType: false)) addCandidate(d);
      }
    }

    if (maxCoupAmt >= faceAmt) maxCoupAmt = faceAmt;
    if (maxCoupAmt >= widget.dsMoney) maxCoupAmt = widget.dsMoney;
    return _DyAmountCalc(
      maxCoupAmt,
      maxCoupAmt,
      _dedup(ids),
    );
  }

  bool _matchListId(Map<String, dynamic> d, dynamic prolist,
      {required bool byType}) {
    if (prolist is! List) return false;
    final String value =
        (byType ? d['typeid'] : d['productid'])?.toString() ?? '';
    for (final dynamic p in prolist) {
      if (p is! Map) continue;
      if ((p['itemid']?.toString() ?? '') == value) return true;
    }
    return false;
  }

  /// 商品匹配（对齐 smdcapp：productid + specid）
  bool _sameProduct(Map<String, dynamic> d, dynamic p) {
    if (p is! Map) return false;
    final String id = (d['productid']?.toString() ?? '') +
        (d['specid']?.toString() ?? '');
    final String pid = (p['productid']?.toString() ?? '') +
        (p['specid']?.toString() ?? '');
    return id == pid;
  }

  /// 不含做法的可核销金额（对齐 noCookRrpriceAmt）
  double _noCookAmt(Map<String, dynamic> d) {
    final double rrprice = _toDouble(d['rrprice']);
    final double qty = _toDouble(d['qty']);
    if (rrprice > 0 && qty > 0) return rrprice * qty;
    return _toDouble(d['rramt']) - _toDouble(d['cookaddamt']);
  }

  /// 保留重复 productid（同一菜品多行时用于逐行标记，对齐 smdcapp ids 拼接）
  List<String> _dedup(List<String> ids) {
    final List<String> out = <String>[];
    for (final String id in ids) {
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  String _platformName(int type) {
    switch (type) {
      case 0:
        return '抖音';
      case 1:
        return '美团';
      case 3:
        return '快手';
      default:
        return '团购';
    }
  }

  /// 团购核销批次唯一ID（对齐 smdcapp BillUtils.getRandomString(20)）
  String _genOnlyId() {
    const String base =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final DateTime now = DateTime.now();
    final String ts = now.microsecondsSinceEpoch.toString();
    final int seed = ts.hashCode.abs();
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 20; i++) {
      sb.write(base[(seed + i * 7 + (ts.codeUnitAt(i % ts.length))) %
          base.length]);
    }
    return sb.toString();
  }
}

/// 金额计算结果
class _DyAmountCalc {
  const _DyAmountCalc(this.eligible, this.original, this.ids);

  final double eligible;
  final double original;
  final List<String> ids;
}

class _VerifyException implements Exception {
  const _VerifyException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool _isDyPayId(String payId) =>
    payId == '13' || payId == 'meituantuangou' || payId == 'kuaishou';

int _businesstypeOf(String payId) {
  if (payId == 'meituantuangou') return 1;
  if (payId == 'kuaishou') return 3;
  return 0;
}

String _payIdOf(int businesstype) {
  switch (businesstype) {
    case 1:
      return 'meituantuangou';
    case 3:
      return 'kuaishou';
    default:
      return '13';
  }
}

String _payNameOf(int businesstype) {
  switch (businesstype) {
    case 0:
      return '抖音团购';
    case 1:
      return '美团团购';
    case 3:
      return '快手';
    default:
      return '团购核销';
  }
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}
