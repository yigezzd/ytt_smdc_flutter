import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/member_coupon_sheet.dart';
import 'package:flutter_deer/components/member_search_sheet.dart';
import 'package:flutter_deer/components/verify_coupon_sheet.dart';
import 'package:flutter_deer/db/sale_dao.dart';
import 'package:flutter_deer/db/vip_dao.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/pay_gateway.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/pages/order/pay_scan_page.dart';
import 'package:flutter_deer/pages/order/scan_pay_dialog.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/theme_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';
import 'package:flutter_deer/util/promotion_helper.dart';
import 'package:flutter_deer/util/amount_calc_utils.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 结账页（对齐 smdcapp SettleActivity）
///
/// 从订单详情页"去结账"按钮进入，展示订单金额信息、选择支付方式、提交结账流水。
class SettlePage extends StatefulWidget {
  const SettlePage({
    super.key,
    this.tableName = '',
    this.persons = 0,
    this.tableId = '',
    this.tableCode = '',
    this.saleid = '',
    this.serverId = '',
    this.serverName = '',
    this.remark = '',
    this.tableJson,
    required this.detailList,
    this.dishAmt = 0,
    this.serviceAmt = 0,
    this.lowAmt = 0,
    this.disAmt = 0,
    this.payAmt = 0,
    this.memberVipid = '',
    this.memberVipname = '',
    this.memberVipno = '',
    this.memberMobile = '',
    this.memberOverflag = 0,
    this.memberOvermoney = 0,
    this.memberArrearages = 0,
    this.memberNowmoney = 0,
    this.memberPrefetype = 0,
  });

  final String tableName;
  final int persons;
  final String tableId;
  final String tableCode;
  final String saleid;
  final String serverId;
  final String serverName;
  final String remark;
  final Map<String, dynamic>? tableJson;

  /// 订单明细列表
  final List<Map<String, dynamic>> detailList;

  /// 价格信息
  final double dishAmt;
  final double serviceAmt;
  final double lowAmt;
  final double disAmt;
  final double payAmt;

  /// 会员信息（从订单详情页传入）
  final String memberVipid;
  final String memberVipname;
  final String memberVipno;
  final String memberMobile;

  /// 会员挂账信息（对齐 smdcapp MemberDetailsBean overflag/overmoney/arrearages）
  final int memberOverflag;
  final double memberOvermoney;
  final double memberArrearages;

  /// 会员余额（对齐 smdcapp MemberDetailsBean.nowmoney，会员支付余额校验用）
  final double memberNowmoney;

  /// 会员优惠类型（对齐 smdcapp MemberDetailsBean.prefetype）
  final int memberPrefetype;

  @override
  State<SettlePage> createState() => _SettlePageState();
}

class _SettlePageState extends State<SettlePage> {
  /// 支付方式列表（对齐 smdcapp PayTypeBean.list）
  List<Map<String, dynamic>> _payTypeList = <Map<String, dynamic>>[];

  /// 当前选中的支付方式
  String _payId = '01';
  String _payName = '现金';

  /// 已收金额（对齐 smdcapp placedOrderBean.hasMoney）
  double _hasMoney = 0;

  /// 待收金额（对齐 smdcapp placedOrderBean.dsMoney）
  double _dsMoney = 0;

  /// 已选支付记录（对齐 smdcapp salePayWayList）
  final List<Map<String, dynamic>> _salePayWayList = <Map<String, dynamic>>[];

  /// 是否打印单据（对齐 smdcapp isDy）
  bool _isPrint = false;

  /// 提交中
  bool _submitting = false;

  /// 加载支付方式中
  bool _loadingPayTypes = true;

  /// 可用促销活动列表（对齐 smdcapp PrometionBean）
  List<PromotionInfo> _promotions = <PromotionInfo>[];

  /// 已应用的促销优惠金额
  double _promoDisAmt = 0;

  /// 已选择的会员优惠券（对齐 smdcapp vipCoupon）
  MemberCoupon? _selectedCoupon;

  /// 抹零金额（对齐 smdcapp PlacedOrderBean.bzmlPrice / SaleMasterBean.roundamt）
  /// 正数=减免（顾客少付），负数=加收（顾客多付）
  double _roundAmt = 0;

  /// 当前录入的会员（对齐 smdcapp SettleActivity.memberBean）
  VipMember? _member;

  /// 会员同步中（防重复点击）
  bool _memberSyncing = false;

  @override
  void initState() {
    super.initState();
    // 初始化订单详情页传入的会员信息（对齐 smdcapp intent Member_DetailsBean）
    if (widget.memberVipid.isNotEmpty) {
      _member = VipMember(
        vipid: widget.memberVipid,
        vipname: widget.memberVipname,
        vipno: widget.memberVipno,
        mobile: widget.memberMobile,
        prefetype: widget.memberPrefetype,
        nowmoney: widget.memberNowmoney,
        overflag: widget.memberOverflag,
        overmoney: widget.memberOvermoney,
        arrearages: widget.memberArrearages,
      );
    }
    _dsMoney = _rd2(widget.payAmt);
    _applyRounding();
    _loadPayTypes();
    _loadPromotions();
  }

  /// 应用币种抹零（对齐 smdcapp Arith.showAllPriceInfo: SmallChangeType==1 时
  /// bzmlPrice = payMoney - smallChangePrice(payMoney)，并作为"06"减免支付方式）
  ///
  /// 抹零设置：SmallChangeType 0=不抹零 1=币种抹零 2=单品抹零
  /// 仅币种抹零(1)在结账环节处理；单品抹零(2)在下单明细环节处理。
  void _applyRounding() {
    final String smallChangeType = ParamsSpUtils.getSmallChangeType();
    if (smallChangeType != '1') return; // 仅币种抹零
    final double roundAmt = AmountCalcUtils.getEraseAmt(_dsMoney);
    if (roundAmt == 0) return;
    _roundAmt = roundAmt;
    // 抹零作为"06"减免支付方式（对齐 smdcapp dealMlDate: payid="06" payname="减免"）
    _salePayWayList.add(<String, dynamic>{
      'saleid': widget.saleid,
      'payid': '06',
      'payname': '抹零',
      'payamt': roundAmt,
      'rate': 1.0,
      'rramt': roundAmt,
      'changeamt': 0.0,
    });
    // 抹零抵扣后，顾客实际需付金额减少（对齐 smdcapp hasMoney += bzmlPrice）
    _hasMoney = AmountCalcUtils.add(_hasMoney, roundAmt);
    _dsMoney = AmountCalcUtils.sub(_dsMoney, roundAmt);
    if (_dsMoney < 0) _dsMoney = 0;
  }

  /// 加载可用促销活动（对齐 smdcapp getSalesPromotionList）
  Future<void> _loadPromotions() async {
    final List<PromotionInfo> list = await PromotionHelper.fetchPromotions(
      details: widget.detailList,
      vipid: _member?.vipid ?? '',
    );
    if (mounted) {
      setState(() => _promotions = list);
    }
  }

  /// 应用促销活动（对齐 smdcapp amountAfterDiscount）
  Future<void> _applyPromotion(PromotionInfo promo) async {
    final double disAmt = await PromotionHelper.calcDiscountAmt(
      details: widget.detailList,
      billid: promo.billid,
      vipid: _member?.vipid ?? '',
    );
    if (!mounted) return;
    if (disAmt <= 0) {
      Toast.show('该活动未计算出优惠');
      return;
    }
    setState(() {
      _promoDisAmt = disAmt;
      _dsMoney = AmountCalcUtils.sub(
          AmountCalcUtils.sub(widget.payAmt, _hasMoney), disAmt);
      if (_dsMoney < 0) _dsMoney = 0;
    });
    Toast.show('已应用促销：${promo.billname}，优惠¥$disAmt');
  }

  // ═══════════════════ 会员录入（对齐 smdcapp SettleActivity: tvManageTwo + onActivityResult + upMember） ═══════════════════

  /// 标题栏“会员”按钮点击（对齐 smdcapp tvManageTwo.onClick → MemberActivity）
  Future<void> _onMemberTap() async {
    if (_memberSyncing) return;
    // 已使用会员卡支付时禁止切换会员（对齐 smdcapp isVipPay("02") 校验）
    if (_salePayWayList.any((Map<String, dynamic> e) => e['payid'] == '02')) {
      Toast.show('请先撤销当前会员相关的支付方式');
      return;
    }
    if (_member != null) {
      // 已录入会员：询问是否退出（对齐 smdcapp MemberLayout.loginListener → “是否退出会员？”）
      final bool logout = await ConfirmDialog.show(
        context,
        content: '是否退出会员？',
      );
      if (logout && mounted) {
        _logoutMember();
      }
      return;
    }
    // 未录入会员：提示后打开搜索弹窗（对齐 smdcapp TipDialog“切换会员将清除之前选择的促销”）
    final bool cont = await ConfirmDialog.show(
      context,
      content: '录入会员后，之前选择的促销活动可能失效，是否继续？',
    );
    if (!cont || !mounted) return;
    final VipMember? member = await MemberSearchSheet.show(context);
    if (member == null || !mounted) return;
    _loginMember(member);
  }

  /// 录入会员（对齐 smdcapp onActivityResult → memberBean = bean + upMember）
  Future<void> _loginMember(VipMember member) async {
    await _syncMemberToServer(member: member);
    if (!mounted) return;
    setState(() {
      _member = member;
      // 切换会员后清除已选促销/优惠券（对齐 smdcapp isUpdataMember 重算逻辑）
      _promoDisAmt = 0;
      _selectedCoupon = null;
    });
    _loadPromotions();
  }

  /// 退出会员（对齐 smdcapp loginListener.onLogout → memberBean = null + upMember）
  Future<void> _logoutMember() async {
    await _syncMemberToServer(member: null);
    if (!mounted) return;
    setState(() {
      _member = null;
      _promoDisAmt = 0;
      _selectedCoupon = null;
    });
    _loadPromotions();
  }

  /// 同步会员信息到后端桌台（对齐 smdcapp SettleActivity.upMember → OrderModel.updateMasterTmp）
  Future<void> _syncMemberToServer({required VipMember? member}) async {
    // 对齐 smdcapp：仅正餐模式（storemodel==2）同步桌台会员，快餐无桌台跳过
    if (StoreModeUtils.isFastMode()) return;
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String saleid = widget.saleid.isNotEmpty
        ? widget.saleid
        : (tmp?['saleid']?.toString() ?? '');
    if (saleid.isEmpty) {
      Toast.show('订单信息错误，无法同步会员');
      return;
    }
    setState(() => _memberSyncing = true);
    try {
      await OrderRepository.updateMasterTmpVip(
        saleid: saleid,
        tableid: widget.tableId.isNotEmpty
            ? widget.tableId
            : (tmp?['tableid']?.toString() ?? ''),
        tablecode: widget.tableCode.isNotEmpty
            ? widget.tableCode
            : (tmp?['tablecode']?.toString() ?? ''),
        remark: widget.remark.isNotEmpty
            ? widget.remark
            : (tmp?['remark']?.toString() ?? ''),
        personnum: widget.persons > 0
            ? widget.persons.toString()
            : (tmp?['personnum']?.toString() ?? ''),
        serverid: widget.serverId.isNotEmpty
            ? widget.serverId
            : (tmp?['serverid']?.toString() ?? ''),
        servername: widget.serverName.isNotEmpty
            ? widget.serverName
            : (tmp?['servername']?.toString() ?? ''),
        vipid: member?.vipid ?? '',
        vipno: member?.vipno ?? '',
        vipname: member?.vipname ?? '',
        vipmobile: member?.mobile ?? '',
        masterDevice: ConnectionManager.pcAlive,
        tableJson: widget.tableJson,
      );
    } catch (_) {
      Toast.show('同步会员信息失败');
    } finally {
      if (mounted) {
        setState(() => _memberSyncing = false);
      }
    }
  }

  /// 选择会员优惠券（对齐 smdcapp CouponListActivity）
  Future<void> _selectCoupon() async {
    if (_member == null) {
      Toast.show('请先录入会员');
      return;
    }
    final MemberCoupon? coupon = await MemberCouponSheet.show(
      context,
      vipid: _member!.vipid,
    );
    if (coupon == null || !mounted) return;
    setState(() {
      _selectedCoupon = coupon;
      // 代金券直接抵扣金额
      if (coupon.favtype == 1 && coupon.favamt > 0) {
        _dsMoney = AmountCalcUtils.sub(
            AmountCalcUtils.sub(
                AmountCalcUtils.sub(widget.payAmt, _hasMoney), _promoDisAmt),
            coupon.favamt);
        if (_dsMoney < 0) _dsMoney = 0;
      }
    });
    Toast.show('已选择优惠券：${coupon.favname}');
  }

  // ═══════════════════ 数据加载 ═══════════════════

  /// 获取支付方式列表（对齐 smdcapp getData → getPayInfoList）
  Future<void> _loadPayTypes() async {
    setState(() => _loadingPayTypes = true);
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getPayInfoList,
        <String, dynamic>{
          'cond': '',
          'stopflag': '0',
          'pagesize': '100',
          'field': 'isort',
          'type': 'asc',
        },
      );
      if (!mounted) return;
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          _payTypeList = list.whereType<Map<String, dynamic>>().toList();
        }
      }
      // 默认选中现金
      if (_payTypeList.isNotEmpty) {
        _payId = _payTypeList[0]['payid']?.toString() ?? '01';
        _payName = _payTypeList[0]['name']?.toString() ?? '现金';
      }
    } catch (_) {
      // 加载失败使用默认现金
    } finally {
      if (mounted) {
        setState(() => _loadingPayTypes = false);
      }
    }
  }

  // ═══════════════════ 支付逻辑 ═══════════════════

  /// 点击“去支付”（对齐 smdcapp tvTopay.onClick → toPay）
  Future<void> _onPay() async {
    // 待收金额为0：直接完成0元结账（对齐 smdcapp clickWxAliPay dsMoney==0 分支：
    // 补一条"01"现金 0元 收款记录后走 getSaleFlowData 结账流程；
    // 现金路径 PricePopup 输入0元全付同样 add payway(0) → getSaleFlowData）
    if (_dsMoney <= 0) {
      if (_submitting) return;
      final bool hasZeroCash = _salePayWayList.any((Map<String, dynamic> e) =>
          e['payid'] == '01' && _toDouble(e['payamt']) == 0);
      if (!hasZeroCash) {
        _salePayWayList.add(<String, dynamic>{
          'saleid': widget.saleid,
          'payid': '01',
          'payname': '现金',
          'payamt': 0.0,
          'rate': 1.0,
          'rramt': 0.0,
          'changeamt': 0.0,
        });
      }
      await _submitSaleFlow();
      return;
    }
    if (_payId == '02' && _member == null) {
      Toast.show('请先录入会员');
      return;
    }
  
    // 移动支付：支付宝(08)/微信(09)/云闪付(10) → 扫码支付流程
    // （对齐 smdcapp clickWxAliPay → MipcaActivityCapture → disposeWxAliScanPay）
    if (_payId == '08' || _payId == '09' || _payId == '10') {
      await _onScanPay();
      return;
    }

    // 会员挂账(04)：额度校验后直接挂账（对齐 smdcapp selectPay case "04"）
    if (_payId == '04') {
      await _onMemberOverPay();
      return;
    }

    // 会员卡支付(02)：余额校验（对齐 smdcapp MemberDateilsActivity.menberPay: price > nowmoney 余额不足）
    if (_payId == '02') {
      final double memberNowmoney = _member?.nowmoney ?? 0;
      if (memberNowmoney > 0 && _dsMoney > memberNowmoney) {
        Toast.show('会员余额不足（余额¥${_formatAmt(memberNowmoney)}），请使用其他支付方式');
        return;
      }
    }

    // 减免(06)：手动减免/抹零（对齐 smdcapp selectPay case "06" → showReducePopup）
    if (_payId == '06') {
      await _onReducePay();
      return;
    }
  
    // 面额支付：自定义支付方式启用面额(faceflag=1)时直接抵扣面额
    // （对齐 smdcapp selectPay else 分支: faceflag=="1" → faceValuePay）
    final Map<String, dynamic>? selectedPayType = _getSelectedPayType();
    if (selectedPayType != null &&
        (selectedPayType['faceflag']?.toString() == '1')) {
      await _onFaceValuePay(selectedPayType);
      return;
    }

    // 现金/其他支付：弹金额输入框（对齐 smdcapp showChangePricePop → PricePopup）
    final double? inputAmt = await _showPriceInput();
    if (inputAmt == null || inputAmt <= 0 || !mounted) return;
  
    final double payAmt = _rd2(inputAmt > _dsMoney ? _dsMoney : inputAmt);
  
    // 记录支付方式
    _salePayWayList.add(<String, dynamic>{
      'saleid': widget.saleid,
      'payid': _payId,
      'payname': _payName,
      'payamt': payAmt,
      'rate': 1.0,
      'rramt': payAmt,
      'changeamt':
          inputAmt > _dsMoney ? AmountCalcUtils.sub(inputAmt, _dsMoney) : 0.0,
    });
  
    _hasMoney = AmountCalcUtils.add(_hasMoney, payAmt);
    _dsMoney = AmountCalcUtils.sub(_dsMoney, payAmt);
  
    if (_dsMoney <= 0.005) {
      // 全部支付完成 → 上传流水
      _dsMoney = 0;
      setState(() {});
      await _submitSaleFlow();
    } else {
      setState(() {});
    }
  }
  
  /// 会员挂账支付（对齐 smdcapp OverHangmemberPay + selectPay case "04"）
  Future<void> _onMemberOverPay() async {
    if (_member == null) {
      Toast.show('请先录入会员');
      return;
    }
    // 校验是否支持挂账（对齐 smdcapp overflag == 0 不支持）
    if ((_member?.overflag ?? 0) == 0) {
      Toast.show('当前会员未启用【欠款消费】功能');
      return;
    }
    // 校验挂账额度（对齐 smdcapp dsMoney > overmoney - arrearages）
    final double available = (_member?.overmoney ?? 0) - (_member?.arrearages ?? 0);
    if (_dsMoney > available) {
      Toast.show('剩余额度不足本次挂账，请使用其他支付方式！');
      return;
    }
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定挂账¥${_formatAmt(_dsMoney)}到会员账上？',
    );
    if (!confirmed || !mounted) return;
    try {
      final double payAmt = _rd2(_dsMoney);
      await requestForm(HttpApi.vipOverPay, <String, dynamic>{
        'billno': _generateBillNo(),
        'billid': '',
        'vipid': _member?.vipid ?? '',
        'vipno': _member?.vipno ?? '',
        'payid': '04',
        'payname': '会员挂账',
        'saleid': widget.saleid,
        'salename': '',
        'amt': payAmt.toString(),
      });
      if (!mounted) return;
      _salePayWayList.add(<String, dynamic>{
        'saleid': widget.saleid,
        'payid': '04',
        'payname': '会员挂账',
        'payamt': payAmt,
        'rate': 1.0,
        'rramt': payAmt,
        'changeamt': 0.0,
      });
      _hasMoney = AmountCalcUtils.add(_hasMoney, payAmt);
      _dsMoney = AmountCalcUtils.sub(_dsMoney, payAmt);
      if (_dsMoney <= 0.005) {
        _dsMoney = 0;
        setState(() {});
        await _submitSaleFlow();
      } else {
        setState(() {});
      }
    } catch (e) {
      if (mounted) Toast.show('挂账失败：$e');
    }
  }

  /// 减免支付（对齐 smdcapp selectPay case "06" → showReducePopup）
  ///
  /// 手动输入减免金额，作为"06"减免支付方式记录。
  Future<void> _onReducePay() async {
    final String? result = await InputDialog.show(
      context,
      title: '减免金额',
      hintText: '输入减免金额',
      maxLines: 1,
      // 金额输入默认数字键盘（对齐 smdcapp ReducePopup 数字键盘）
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
    );
    if (result == null || result.isEmpty || !mounted) return;
    final double reduceAmt = _rd2(double.tryParse(result) ?? 0);
    if (reduceAmt <= 0) {
      Toast.show('减免金额必须大于0');
      return;
    }
    if (reduceAmt > _dsMoney) {
      Toast.show('减免金额不能大于待收金额');
      return;
    }
    _salePayWayList.add(<String, dynamic>{
      'saleid': widget.saleid,
      'payid': '06',
      'payname': '减免',
      'payamt': reduceAmt,
      'rate': 1.0,
      'rramt': reduceAmt,
      'changeamt': 0.0,
    });
    _hasMoney = AmountCalcUtils.add(_hasMoney, reduceAmt);
    _dsMoney = AmountCalcUtils.sub(_dsMoney, reduceAmt);
    if (_dsMoney <= 0.005) {
      _dsMoney = 0;
      setState(() {});
      await _submitSaleFlow();
    } else {
      setState(() {});
    }
  }

  /// 撤销已选支付方式（对齐 smdcapp resetData）
  ///
  /// 从收款记录移除该笔支付，恢复待收金额。
  void _cancelPayRecord(Map<String, dynamic> item) {
    final double payAmt = _toDouble(item['payamt']);
    setState(() {
      _salePayWayList.remove(item);
      _hasMoney = AmountCalcUtils.sub(_hasMoney, payAmt);
      _dsMoney = AmountCalcUtils.add(_dsMoney, payAmt);
      if (_hasMoney < 0) _hasMoney = 0;
    });
  }

  /// 获取当前选中的支付方式配置（从 _payTypeList 中按 payid 查找）
  Map<String, dynamic>? _getSelectedPayType() {
    for (final Map<String, dynamic> pt in _payTypeList) {
      final String code = pt['payid']?.toString() ?? pt['code']?.toString() ?? '';
      if (code == _payId) return pt;
    }
    return null;
  }

  /// 面额支付（对齐 smdcapp faceValuePay）
  ///
  /// 启用面额的支付方式直接按面额抵扣：
  /// faceamt=面额金额，actulamt=实付金额，virtualamt=虚付金额
  Future<void> _onFaceValuePay(Map<String, dynamic> payType) async {
    final double faceamt =
        double.tryParse(payType['faceamt']?.toString() ?? '') ?? 0;
    final double actulamt =
        double.tryParse(payType['actulamt']?.toString() ?? '') ?? 0;
    final double virtualamt =
        double.tryParse(payType['virtualamt']?.toString() ?? '') ?? 0;
    // 面额抵扣金额：优先用 faceamt，其次待收金额
    final double deductAmt = faceamt > 0 ? faceamt : _dsMoney;
    final double payAmt = _rd2(deductAmt > _dsMoney ? _dsMoney : deductAmt);
    _salePayWayList.add(<String, dynamic>{
      'saleid': widget.saleid,
      'payid': _payId,
      'payname': _payName,
      'payamt': payAmt,
      'rate': 1.0,
      'rramt': payAmt,
      'changeamt': 0.0,
      'faceamt': faceamt,
      'actulamt': actulamt,
      'virtualamt': virtualamt,
    });
    _hasMoney = AmountCalcUtils.add(_hasMoney, payAmt);
    _dsMoney = AmountCalcUtils.sub(_dsMoney, payAmt);
    if (_dsMoney <= 0.005) {
      _dsMoney = 0;
      setState(() {});
      await _submitSaleFlow();
    } else {
      setState(() {});
    }
  }

  /// 微信/支付宝/云闪付扫码支付（对齐 smdcapp clickWxAliPay → disposeWxAliScanPay → wantToPay）
  Future<void> _onScanPay() async {
    // 1. 打开扫码页扫描客户付款码（对齐 smdcapp MipcaActivityCapture）
    final Object? scanResult = await Navigator.push<Object>(
      context,
      MaterialPageRoute<Object>(builder: (_) => const PayScanPage()),
    );
    if (scanResult == null || scanResult.toString().isEmpty || !mounted) return;
    final String authCode = scanResult.toString();

    // 2. 构建支付网关（对齐 smdcapp: MMKV 中读取 payType/terminalsn/terminalkey）
    final Map<String, String> payConfig = _getStorePayConfig();
    if (payConfig['terminalsn']!.isEmpty || payConfig['terminalkey']!.isEmpty) {
      Toast.show('支付配置不完整，请使用其他支付方式');
      return;
    }
    final PayGateway gateway = PayGateway(
      terminalsn: payConfig['terminalsn']!,
      terminalkey: payConfig['terminalkey']!,
      payType: payConfig['paytype']!,
      shopId: payConfig['shopid']!,
      operator: _getUserName(),
    );

    // 3. 生成支付订单号（对齐 smdcapp lesBillNo = billNo + geSuffixNum: "A"+HHmmss）
    final String payBillNo = _generateBillNo() + _getPaySuffix();

    // 4. 弹出支付弹窗，提交付款码并轮询结果
    // （对齐 smdcapp BoYouPayDialog/ReceiveMoneyPayDialog:
    //   金额传 CalcUtils.add2(dsMoney, 0.0)，即2位小数精度）
    final double payAmt = _rd2(_dsMoney);
    final ScanPayResult? result = await ScanPayDialog.show(
      context,
      payid: _payId,
      amt: payAmt,
      billNo: payBillNo,
      authCode: authCode,
      gateway: gateway,
    );
    if (result == null || !mounted) return;

    if (result.success) {
      // 支付成功 → 记录支付方式（对齐 smdcapp wantToPay → getPayWayBean）
      // trade 格式（优支付）: "leshua_order_id,third_order_id"
      String trade = result.trade;
      String sn = '';
      if (trade.contains(',')) {
        final List<String> parts = trade.split(',');
        trade = parts[0];
        sn = parts.length > 1 ? parts[1] : '';
      }
      _salePayWayList.add(<String, dynamic>{
        'saleid': widget.saleid,
        'payid': _payId,
        'payname': _payName,
        'payamt': payAmt,
        'rate': 1.0,
        'rramt': payAmt,
        'changeamt': 0.0,
        'faceamt': payAmt,
        'wxtrade': trade,
        'wxclientid': sn,
        'sn': sn,
        'third_order_id': sn,
        'payno': payBillNo,
        'paytype': payConfig['paytype'],
        'terminalkey': payConfig['terminalkey'],
        'terminalsn': payConfig['terminalsn'],
      });

      _hasMoney = AmountCalcUtils.add(_hasMoney, payAmt);
      _dsMoney = AmountCalcUtils.sub(_dsMoney, payAmt);

      if (_dsMoney <= 0.005) {
        // 全部支付完成 → 上传流水（对齐 smdcapp getSaleFlowData）
        _dsMoney = 0;
        setState(() {});
        await _submitSaleFlow();
      } else {
        setState(() {});
      }
    } else {
      // 支付失败（对齐 smdcapp yeahKaPayResult failure 分支）
      Toast.show(result.errorMsg.isNotEmpty ? result.errorMsg : '支付失败');
    }
  }

  /// 获取门店支付配置（对齐 smdcapp SpUtils.saveStoreData 保存的 paytype/terminalsn/terminalkey）
  Map<String, String> _getStorePayConfig() {
    Map<String, dynamic> storeMap = <String, dynamic>{};
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
      }
    } catch (_) {}

    // 如果 store 中没有支付配置，尝试从完整登录数据中获取
    if (storeMap['terminalsn'] == null ||
        (storeMap['terminalsn']?.toString() ?? '').isEmpty) {
      try {
        final String allDataStr = SpUtil.getString(Constant.allLoginData) ?? '';
        if (allDataStr.isNotEmpty) {
          final Map<String, dynamic> allData =
              jsonDecode(allDataStr) as Map<String, dynamic>;
          final dynamic storeRaw = allData['store'];
          if (storeRaw is Map) {
            final Map<String, dynamic> loginStore =
                Map<String, dynamic>.from(storeRaw);
            // 合并（不覆盖已有值）
            loginStore.forEach((String key, dynamic value) {
              storeMap.putIfAbsent(key, () => value);
            });
          }
        }
      } catch (_) {}
    }

    return <String, String>{
      'paytype': storeMap['paytype']?.toString() ?? '4',
      'terminalsn': storeMap['terminalsn']?.toString() ?? '',
      'terminalkey': storeMap['terminalkey']?.toString() ?? '',
      'shopid': storeMap['shopid']?.toString() ?? '',
    };
  }

  /// 生成支付订单号后缀（对齐 smdcapp geSuffixNum: "A" + HHmmss）
  String _getPaySuffix() {
    final DateTime now = DateTime.now();
    return 'A${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  /// 金额输入弹窗（对齐 smdcapp PricePopup）
  /// full_payment 参数控制是否默认填充满全款金额
  Future<double?> _showPriceInput() async {
    // 对齐 smdcapp: if(full_payment) etDiscount.setText(price.toString())
    final bool fullPayment = SpUtil.getBool('full_payment', defValue: true) ?? true;
    final String? result = await InputDialog.show(
      context,
      title: '$_payName支付',
      hintText: '输入金额',
      initialValue: fullPayment ? _dsMoney.toStringAsFixed(2) : '',
      maxLines: 1,
      // 金额输入默认数字键盘（对齐 smdcapp PricePopup 内置数字键盘）
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
    );
    if (result == null || result.isEmpty) return null;
    return double.tryParse(result);
  }

  /// 上传结账流水（对齐 smdcapp getSaleFlowData → saleflow）
  Future<void> _submitSaleFlow() async {
    setState(() => _submitting = true);
    try {
      // 获取服务器时间（对齐 smdcapp getTime）
      String billdate = '';
      try {
        final Map<String, dynamic> timeResp =
            await requestForm(HttpApi.getTime, <String, dynamic>{});
        final dynamic timeData = timeResp['data'] ?? timeResp['Data'];
        if (timeData is Map<String, dynamic>) {
          billdate = timeData['requesttime']?.toString() ?? '';
        }
        if (billdate.isEmpty && timeResp['requesttime'] != null) {
          billdate = timeResp['requesttime'].toString();
        }
      } catch (_) {}
      if (billdate.isEmpty) {
        billdate = DateTime.now().toString().substring(0, 19);
      }

      // 会员支付处理（对齐 smdcapp saveFlowInDb → vipInfoPay）
      if (_payId == '02' && (_member?.vipid.isNotEmpty ?? false)) {
        final Map<String, dynamic> payParams = <String, dynamic>{
          'billno': _generateBillNo(),
          'vipid': _member?.vipid ?? '',
          'vipno': _member?.vipno ?? '',
          'payid': '02',
          'payname': '会员卡',
          'saleid': widget.saleid,
          'salename': '',
          'amt': _rd2(widget.payAmt).toString(),
        };
        await requestForm(HttpApi.vipPay, payParams);
        // 双写本地会员流水（非 Web；失败静默，不阻断结账流程）
        if (!kIsWeb) {
          try {
            await VipDao.instance.saveVipFlow(payParams);
          } catch (e) {
            debugPrint('本地会员流水写入失败: $e');
          }
        }
      }

      // 构建 SaleBean 数据（对齐 smdcapp SaleBean 结构）
      final Map<String, dynamic> saleMaster = _buildSaleMaster(billdate);
      final List<Map<String, dynamic>> saleDetail = _buildSaleDetail(billdate);
      final List<Map<String, dynamic>> salePayway = _buildSalePayway();

      final Map<String, dynamic> saleBean = <String, dynamic>{
        // 顶层 id 为服务端必需字段（对齐 smdcapp bean.id = payFlowBean.id.toString()）：
        // 服务端 SaleflowService 用 JsonUtils.getJsonStr(js, "id") 强制提取，
        // 缺失会抛"id不存在"并返回"数据转成json失败"。
        // 本项目无本地流水表，用秒级时间戳生成唯一 id。
        'id': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
        't_sale_master': <Map<String, dynamic>>[saleMaster],
        't_sale_detail': saleDetail,
        't_sale_payway': salePayway,
        't_sale_cook': _buildSaleCook(),
        'billno': saleMaster['billno'],
      };

      // 打印类型（对齐 smdcapp saveFlowInDb：printtype 2=结账单；
      // 扫码点菜单 billtype==3 时 newprinttype=2）
      final String printtype = _isPrint ? '2' : '-1';
      String newprinttype = printtype;
      if (newprinttype != '-1' &&
          saleMaster['billtype']?.toString() == '3') {
        newprinttype = '2';
      }

      // 上传流水（对齐 smdcapp SettleHttpUtil.api.saleflow）
      final List<Map<String, dynamic>> saleList = <Map<String, dynamic>>[saleBean];
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.saleflow,
        <String, dynamic>{
          'data': jsonEncode(saleList),
          'printtype': printtype,
          'printalltype': _isPrint ? '1' : '-1',
          'newprinttype': newprinttype,
          'seq': '1',
        },
      );

      if (!mounted) return;

      // 解析响应（对齐 smdcapp：以 data[0].retcode 为逐条上传结果）
      // 注意：requestForm 已保证顶层 retcode==0 才会返回到这里，但顶层只是
      // BaseData 外壳，真正的落库结果在 data 数组每条记录的 retcode 中。
      // 绝不能以顶层 retcode 兜底判成功，否则服务端落库失败时仍会清台进完成页，
      // 导致后台报表查不到数据（对齐 smdcapp it.size>0 && it[0].retcode==0）。
      final dynamic data = resp['data'] ?? resp['Data'];
      bool success = false;
      String recordRetmsg = '';
      if (data is List && data.isNotEmpty) {
        final dynamic first = data[0];
        if (first is Map<String, dynamic>) {
          success = (first['retcode'] == 0);
          recordRetmsg = first['retmsg']?.toString() ?? '';
        }
      }

      if (success) {
        // 双写本地结账流水（非 Web：t_sale_master/t_sale_payway/t_sale_detail/
        // t_sale_cook，失败静默不阻断，对齐计划：本地写失败不影响结账流程）
        if (!kIsWeb) {
          try {
            await SaleDao.instance.saveSaleFlow(saleBean);
          } catch (e) {
            debugPrint('本地结账流水写入失败: $e');
          }
        }
        // 清台（对齐 smdcapp cancelOrder → clearTable）
        await _clearTable();
        if (!mounted) return;
        TableEventBus.fireTableChanged();
        // 快餐模式叫号（对齐 smdcapp PayDetailsLayout: storemodel==1 && PickupCallSwitch==1）
        final String takecode = await _triggerPickupCallIfNeeded(saleMaster);
        if (!mounted) return;
        // 跳转结算完成页（对齐 smdcapp SettleFinishActivity）
        final double receivedAmt = _hasMoney;
        final double changeAmt = receivedAmt > widget.payAmt ? receivedAmt - widget.payAmt : 0;
        NavigatorUtils.push(
          context,
          Routes.settleFinishPage,
          arguments: <String, dynamic>{
            'tableName': widget.tableName,
            'payAmt': widget.payAmt,
            'receivedAmt': receivedAmt,
            'changeAmt': changeAmt,
            'payName': _payName,
            'takecode': takecode,
          },
        );
      } else {
        // 失败时透出服务端逐条 retmsg，便于定位落库失败原因
        Toast.show(
            recordRetmsg.isNotEmpty ? '结账失败：$recordRetmsg' : '结账失败，请重试');
      }
    } catch (e) {
      if (mounted) {
        Toast.show('结账失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// 构建销售主表（对齐 smdcapp DealSaleBeanUtil.getSaleMasterBean）
  Map<String, dynamic> _buildSaleMaster(String billdate) {
    final String userName = _getUserName();
    final String userId = _getUserId();
    final String sid = _getStoreField('id');
    final String spid = _getStoreField('spid');
    final String machNo = SpUtil.getString(Constant.machNo) ?? '';
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    // 对齐 smdcapp getSaleMasterBean：tablebean==null（快餐）时服务员取当前登录人
    final bool hasTable = widget.tableJson != null || widget.tableId.isNotEmpty;
    final String serverId = widget.serverId.isNotEmpty
        ? widget.serverId
        : (tmp?['serverid']?.toString() ?? (hasTable ? '' : userId));
    final String serverName = widget.serverName.isNotEmpty
        ? widget.serverName
        : (tmp?['servername']?.toString() ?? (hasTable ? '' : userName));

    // 减免金额合计（payid=06，对齐 smdcapp reductionamt=operamt）
    double reductionamt = 0;
    for (final Map<String, dynamic> pw in _salePayWayList) {
      if (pw['payid'] == '06') {
        reductionamt = AmountCalcUtils.add(reductionamt, _toDouble(pw['payamt']));
      }
    }
    // 订单商品总数量（对齐 smdcapp qty=allqty）
    double qty = 0;
    for (final Map<String, dynamic> d in widget.detailList) {
      qty += _toDouble(d['qty']);
    }

    return <String, dynamic>{
      'saleid': widget.saleid,
      'billno': _generateBillNo(),
      'billdate': billdate,
      'sid': sid,
      'spid': spid,
      'machno': machNo,
      'tableid': widget.tableId.isNotEmpty
          ? widget.tableId
          : (tmp?['tableid']?.toString() ?? ''),
      // 快餐/无桌台不上传桌台字段（对齐 smdcapp getSaleMasterBean tablebean==null 分支）
      if (hasTable) 'tablename': widget.tableName,
      if (hasTable) 'tableno': widget.tableCode,
      if (hasTable) 'personnum': widget.persons.toString(),
      'areaid': tmp?['areaid']?.toString() ?? '',
      'amt': _rd2(widget.payAmt),
      'retailamt': AmountCalcUtils.add(
          AmountCalcUtils.add(widget.dishAmt, widget.serviceAmt), widget.lowAmt),
      'dscamt': _rd2(widget.disAmt),
      'roundamt': _rd2(_roundAmt),
      // 实收金额不含抹零（对齐 smdcapp CalcUtils.sub2(payment, roundAmt)）
      'payment': AmountCalcUtils.sub(_hasMoney, _roundAmt),
      'changeamt': _hasMoney > widget.payAmt
          ? AmountCalcUtils.sub(_hasMoney, widget.payAmt)
          : 0.0,
      'serviceamt': _rd2(widget.serviceAmt),
      'lowamt': _rd2(widget.lowAmt),
      'reductionamt': _rd2(reductionamt),
      'qty': qty,
      'cashid': userId,
      'cashname': userName,
      'serverid': serverId,
      'servername': serverName,
      'vipid': _member?.vipid ?? '',
      'vipno': _member?.vipno ?? '',
      'vipname': _member?.vipname ?? '',
      'vipmobile': _member?.mobile ?? '',
      'billtype': tmp?['billtype']?.toString() ?? '7',
      'mealtype': '1',
      'personnum': widget.persons.toString(),
      'memo': widget.remark,
      'remark': widget.remark,
      'opertype': '1',
      'saletype': 3,
      'status': 1,
      'makedataflag': 0,
      'upflag': 0,
      'createtime': tmp?['createtime']?.toString() ?? _nowStr(),
      'updatetime': _nowStr(),
    };
  }

  /// 构建销售明细表（对齐 smdcapp detailListBean + getSaleFlowData 逐条补齐）
  List<Map<String, dynamic>> _buildSaleDetail(String billdate) {
    final String sid = _getStoreField('id');
    final String spid = _getStoreField('spid');
    final String billno = _generateBillNo();
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String serverId = widget.serverId.isNotEmpty
        ? widget.serverId
        : (tmp?['serverid']?.toString() ?? '');
    final String serverName = widget.serverName.isNotEmpty
        ? widget.serverName
        : (tmp?['servername']?.toString() ?? '');
    // 明细开单时间：有桌台取开台时间，否则取当前（对齐 smdcapp bean.createtime）
    final String createtime = tmp?['billdate']?.toString() ?? _nowStr();

    return widget.detailList.map((Map<String, dynamic> item) {
      final Map<String, dynamic> detail = Map<String, dynamic>.from(item);
      detail['saleid'] = widget.saleid;
      detail['billno'] = billno;
      detail['sid'] = sid;
      detail['spid'] = spid;
      detail['billdate'] = billdate;
      detail['createtime'] = createtime;
      detail['servername'] = serverName;
      detail['serverid'] = serverId;
      // 点菜员为空时取服务员（对齐 smdcapp salesid isNullOrEmpty 分支）
      if ((detail['salesid']?.toString() ?? '').isEmpty) {
        detail['salesid'] = serverId;
        detail['salesname'] = serverName;
      }
      return detail;
    }).toList();
  }

  /// 构建支付方式表（对齐 smdcapp DealSaleBeanUtil.getPayWayBean 公共字段）
  List<Map<String, dynamic>> _buildSalePayway() {
    final String sid = _getStoreField('id');
    final String spid = _getStoreField('spid');
    final String machNo = SpUtil.getString(Constant.machNo) ?? '';
    final String createtime = _nowStr();

    return _salePayWayList.map((Map<String, dynamic> item) {
      final Map<String, dynamic> pw = Map<String, dynamic>.from(item);
      // 金额字段统一保留2位小数（对齐 smdcapp CalcUtils.add2/sub2，
      // 防止 payamt 等因 double 精度尾差超出服务端16字符长度限制）
      for (final String key in <String>[
        'payamt', 'rramt', 'changeamt', 'faceamt',
        'actulamt', 'virtualamt', 'vipnowmoney',
      ]) {
        if (pw[key] != null) pw[key] = _rd2(_toDouble(pw[key]));
      }
      final double payamt = _toDouble(pw['payamt']);
      final double changeamt = _toDouble(pw['changeamt']);
      pw['spid'] = spid;
      pw['sid'] = sid;
      pw['machno'] = machNo;
      pw['clienttype'] = '2';
      pw['createtime'] = createtime;
      pw['rate'] = pw['rate'] ?? 1.0;
      pw.putIfAbsent('faceamt', () => payamt);
      // 实付/虚付划分（对齐 smdcapp：payid=06 均为0；
      // handoverflag==1 交班支付方式计实付，否则计虚付）
      if (pw['payid'] == '06') {
        pw['actulamt'] = 0.0;
        pw['virtualamt'] = 0.0;
      } else if (!pw.containsKey('actulamt') && !pw.containsKey('virtualamt')) {
        int handoverflag = 1;
        for (final Map<String, dynamic> pt in _payTypeList) {
          final String code =
              pt['payid']?.toString() ?? pt['code']?.toString() ?? '';
          if (code == pw['payid']) {
            handoverflag =
                int.tryParse(pt['handoverflag']?.toString() ?? '') ?? 1;
            break;
          }
        }
        final double total = AmountCalcUtils.add(payamt, changeamt);
        if (handoverflag == 1) {
          pw['actulamt'] = total;
          pw['virtualamt'] = 0.0;
        } else {
          pw['actulamt'] = 0.0;
          pw['virtualamt'] = total;
        }
      }
      // 会员支付补充会员标识（对齐 smdcapp memberBean != null 分支）
      if (pw['payid'] == '02' && _member != null) {
        pw['vipid'] = _member!.vipid;
        pw['vipno'] = _member!.vipno;
        pw['vipname'] = _member!.vipname;
        pw['vipnowmoney'] = _member!.nowmoney;
      }
      return pw;
    }).toList();
  }

  /// 构建做法表（对齐 smdcapp getSaleFlowData detailcookListBean）
  List<Map<String, dynamic>> _buildSaleCook() {
    final List<Map<String, dynamic>> cooks = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> d in widget.detailList) {
      final dynamic raw = d['cooklist'] ?? d['cookList'];
      if (raw is! List) continue;
      for (final dynamic c in raw) {
        if (c is! Map<String, dynamic>) continue;
        final Map<String, dynamic> cook = Map<String, dynamic>.from(c);
        cook['saleid'] = widget.saleid;
        cook['onlyid'] = d['onlyid'] ?? '';
        cooks.add(cook);
      }
    }
    return cooks;
  }

  /// 清台（对齐 smdcapp cancelOrder → clearTable / PcClearTable）
  Future<void> _clearTable() async {
    // 快餐/无桌台结账无需清台（对齐 smdcapp：clearTable 仅 tablebean != null 时调用）
    if (widget.tableJson == null && widget.tableId.isEmpty) return;
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      if (useMaster) {
        await requestForm(
          HttpApi.pcClearTable,
          <String, dynamic>{
            'tablemaster': jsonEncode(widget.tableJson ?? <String, dynamic>{}),
          },
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.clearTable, <String, dynamic>{
          'saleid': widget.saleid,
          'tableid': widget.tableId,
          'tableno': widget.tableCode,
        });
      }
    } catch (_) {
      // 清台失败不阻断结账成功流程
    }
  }

  /// 快餐模式结账后触发叫号（对齐 smdcapp PayDetailsLayout line 2376-2389）
  ///
  /// 条件：商业模式==快餐(1) && 叫号开关 PickupCallSwitch==1
  /// 返回取餐号（对齐 smdcapp TakeSnackcode），无叫号时返回空字符串
  Future<String> _triggerPickupCallIfNeeded(Map<String, dynamic> saleMaster) async {
    try {
      // storeMode 由 putInt 写入，getString 读取会类型强转异常，统一走 StoreModeUtils
      if (!StoreModeUtils.isFastMode()) return ''; // 仅快餐模式
      if (!ParamsSpUtils.getPickupCallSwitch()) return ''; // 叫号开关未开启
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getTakeSnackCodeBySet,
        <String, dynamic>{
          'saleid': widget.saleid,
          'billno': saleMaster['billno']?.toString() ?? '',
          'billdate': saleMaster['billdate']?.toString() ?? '',
          'amt': _rd2(widget.payAmt),
          'retailamt': saleMaster['retailamt'] ?? 0,
          'dscamt': _rd2(widget.disAmt),
        },
        showError: false,
      );
      // 解析取餐号（对齐 smdcapp date.takecode）
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        return data['takecode']?.toString() ?? data['takeSnackcode']?.toString() ?? '';
      }
      return data?.toString() ?? '';
    } catch (_) {
      // 叫号失败不阻断结账成功流程
      return '';
    }
  }

  // ═══════════════════ 支付方式选择 ═══════════════════

  /// 弹出支付方式选择（对齐 smdcapp PayTypeDialog）
  void _showPayTypeSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E6EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('选择支付方式',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _payTypeList.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFF2F3F5)),
                  itemBuilder: (BuildContext ctx, int index) {
                    final Map<String, dynamic> item = _payTypeList[index];
                    final String payid = item['payid']?.toString() ?? '';
                    final String name = item['name']?.toString() ?? '';
                    final bool selected = payid == _payId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Image.asset(
                        _payIconAsset(payid),
                        width: 24,
                        height: 24,
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          color: selected ? _kBrandRed : const Color(0xFF1D2129),
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check_circle, size: 20, color: _kBrandRed)
                          : null,
                      onTap: () {
                        setState(() {
                          _payId = payid;
                          _payName = name;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════ 工具方法 ═══════════════════

  String _billNoCache = '';

  /// 生成单号（对齐 smdcapp BillUtils.createNewBillNo：门店编号+机号+yyMMdd+4位流水）
  ///
  /// 本项目无本地流水库无法按上一单递增，末4位由秒级时间戳派生，保证同店同机当天不重复。
  String _generateBillNo() {
    if (_billNoCache.isNotEmpty) return _billNoCache;
    final String storeCode = SpUtil.getString(Constant.storeCode) ?? '';
    final String machNo = SpUtil.getString(Constant.machNo) ?? '';
    final DateTime now = DateTime.now();
    final String yyMMdd = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final String seq = ((now.millisecondsSinceEpoch ~/ 1000) % 10000)
        .toString()
        .padLeft(4, '0');
    _billNoCache = '$storeCode$machNo$yyMMdd$seq';
    return _billNoCache;
  }

  /// 当前时间 yyyy-MM-dd HH:mm:ss（对齐 smdcapp DateUtils.getTimeStamp）
  String _nowStr() {
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  String _getUserName() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        return userMap['username']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  String _getUserId() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        return userMap['id']?.toString() ?? userMap['userid']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  String _getStoreField(String field) {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap[field]?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  String _formatAmt(double amt) {
    if (amt == amt.roundToDouble()) return amt.toInt().toString();
    return amt.toStringAsFixed(2);
  }

  /// 金额四舍五入保留2位小数（对齐 smdcapp CalcUtils.add2/sub2 HALF_UP 保留2位，
  /// 防止 double 精度尾差（如 26.200000000000003）导致 payamt 超出服务端16字符限制）
  double _rd2(double v) => double.parse(v.toStringAsFixed(2));

  // ═══════════════════ UI构建 ═══════════════════

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? ThemeUtils.light : ThemeUtils.dark,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            _buildAppBar(isDark),
            Expanded(
              child: ColoredBox(
                color: isDark ? const Color(0xFF18191A) : const Color(0xFFF5F6F8),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    // 对齐 smdcapp SettleActivity：桌台信息为 null（快餐模式）不显示桌台卡片
                    if (widget.tableJson != null ||
                        widget.tableId.isNotEmpty) ...[
                      _buildTableCard(isDark),
                      const SizedBox(height: 10),
                    ],
                    _buildOrderDetailCard(isDark),
                    const SizedBox(height: 10),
                    _buildPromotionCard(isDark),
                    const SizedBox(height: 10),
                    _buildCouponCard(isDark),
                    const SizedBox(height: 10),
                    _buildPayTypeCard(isDark),
                    const SizedBox(height: 10),
                    _buildVerifyCouponCard(isDark),
                    const SizedBox(height: 10),
                    _buildPayRecordCard(isDark),
                    const SizedBox(height: 10),
                    _buildOptionCard(isDark),
                  ],
                ),
              ),
            ),
            _buildBottomBar(isDark),
          ],
        ),
      ),
    );
  }

  /// 顶部导航栏
  Widget _buildAppBar(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF232425) : Colors.white,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios,
                size: 18,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              onPressed: () => _onBack(),
            ),
            const Expanded(
              child: Text(
                '结账',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            // 会员录入入口（对齐 smdcapp tvManageTwo：未录入显示“会员”，录入后显示会员名）
            GestureDetector(
              onTap: _onMemberTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _member != null
                          ? Icons.badge
                          : Icons.person_search_outlined,
                      size: 18,
                      color: _member != null
                          ? _kBrandRed
                          : (isDark ? Colors.white70 : const Color(0xFF4E5969)),
                    ),
                    const SizedBox(width: 3),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(
                        _member != null ? _member!.vipname : '会员',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              _member != null ? FontWeight.w500 : FontWeight.normal,
                          color: _member != null
                              ? _kBrandRed
                              : (isDark ? Colors.white70 : const Color(0xFF4E5969)),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 返回确认（对齐 smdcapp backImageView → TipDialog "退出将不保存结账数据"）
  Future<void> _onBack() async {
    if (_salePayWayList.isNotEmpty) {
      final bool confirmed = await ConfirmDialog.show(
        context,
        content: '退出将不保存结账数据，是否继续？',
      );
      if (!confirmed || !mounted) return;
    }
    if (mounted) NavigatorUtils.goBack(context);
  }

  /// 桌台信息卡片（对齐 smdcapp cardView_table）
  Widget _buildTableCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232425) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.people_outline,
              size: 20, color: isDark ? Colors.white70 : const Color(0xFF4E5969)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.tableName,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          Text(
            '${widget.persons}人',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF86909C),
            ),
          ),
        ],
      ),
    );
  }

  /// 订单明细卡片（对齐 smdcapp OrderDetailsLayout）
  Widget _buildOrderDetailCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232425) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle('订单明细', isDark),
          const SizedBox(height: 10),
          // 菜品列表（最多显示5条）
          ...widget.detailList.take(5).map((Map<String, dynamic> item) {
            final String name = item['productname']?.toString() ?? '';
            final double price = _toDouble(item['rrprice']);
            final double qty = _toDouble(item['qty']);
            final double rramt = _toDouble(item['rramt']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : const Color(0xFF4E5969),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '¥${_formatAmt(price)} ×${qty.toInt()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : const Color(0xFF86909C),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '¥${_formatAmt(rramt)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (widget.detailList.length > 5)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '...共${widget.detailList.length}项',
                style: const TextStyle(fontSize: 12, color: Color(0xFF86909C)),
              ),
            ),
          const Divider(height: 16, color: Color(0xFFF2F3F5)),
          // 价格汇总
          _priceRow('菜品费', widget.dishAmt, isDark),
          _priceRow('服务费', widget.serviceAmt, isDark),
          _priceRow('低消', widget.lowAmt, isDark),
          _priceRow('优惠合计', widget.disAmt, isDark),
          if (_roundAmt != 0)
            _priceRow('抹零', -_roundAmt, isDark),
          const Divider(height: 16, color: Color(0xFFF2F3F5)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '应收金额',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1D2129),
                ),
              ),
              Text(
                '¥${_formatAmt(widget.payAmt)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kBrandRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 支付方式卡片（对齐 smdcapp ll_payType）
  Widget _buildPayTypeCard(bool isDark) {
    return GestureDetector(
      onTap: _loadingPayTypes ? null : _showPayTypeSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF232425) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Text(
              '支付方式',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
            const Spacer(),
            if (_loadingPayTypes)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kBrandRed),
              )
            else ...<Widget>[
              _payTypeIcon(),
              const SizedBox(width: 6),
              Text(
                _payName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF1D2129),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC9CDD4)),
            ],
          ],
        ),
      ),
    );
  }

  /// 支付方式图标（对齐 smdcapp SettleActivity: 01=pay_xj 02=pay_hyk 08=pay_zfb 09=pay_wx 10=pay_ysf）
  Widget _payTypeIcon() {
    return Image.asset(_payIconAsset(_payId), width: 22, height: 22);
  }

  /// 根据 payid 获取图标资源路径（对齐 smdcapp PayTypeDialog 图标映射）
  String _payIconAsset(String payid) {
    switch (payid) {
      case '01':
        return 'assets/images/pay/pay_xj.png';
      case '02':
        return 'assets/images/pay/pay_hyk.png';
      case '08':
        return 'assets/images/pay/pay_zfb.png';
      case '09':
        return 'assets/images/pay/pay_wx.png';
      case '10':
        return 'assets/images/pay/pay_ysf.png';
      default:
        return 'assets/images/pay/pay_xj.png';
    }
  }

  /// 会员优惠券卡片（对齐 smdcapp CouponListActivity 入口）
  Widget _buildCouponCard(bool isDark) {
    if (_member == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _selectCoupon,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF232425) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Text(
              '会员优惠券',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
            const Spacer(),
            Text(
              _selectedCoupon != null ? _selectedCoupon!.favname : '选择优惠券',
              style: TextStyle(
                fontSize: 13,
                color: _selectedCoupon != null ? _kBrandRed : const Color(0xFF86909C),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: isDark ? Colors.white38 : const Color(0xFFC9CDD4)),
          ],
        ),
      ),
    );
  }

  /// 促销活动卡片（对齐 smdcapp PrometionDiscountPopup）
  Widget _buildPromotionCard(bool isDark) {
    if (_promotions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232425) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle('促销活动', isDark),
          const SizedBox(height: 8),
          ..._promotions.map((PromotionInfo p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(p.typeText, style: const TextStyle(fontSize: 11, color: Color(0xFFFF9800))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.billname,
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : const Color(0xFF4E5969)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _applyPromotion(p),
                      style: TextButton.styleFrom(
                        foregroundColor: _kBrandRed,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('应用'),
                    ),
                  ],
                ),
              )),
          if (_promoDisAmt > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '已优惠：¥$_promoDisAmt',
                style: const TextStyle(fontSize: 13, color: _kBrandRed, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  /// 团购核销卡片（对齐 smdcapp DyVerifyPopup 入口）
  Widget _buildVerifyCouponCard(bool isDark) {
    return GestureDetector(
      onTap: _onVerifyCoupon,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF232425) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Text(
              '团购核销',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
            const Spacer(),
            const Icon(Icons.qr_code_scanner, size: 22, color: Color(0xFFFF9800)),
            const SizedBox(width: 6),
            Text(
              '抖音/美团/快手',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF86909C),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: isDark ? Colors.white38 : const Color(0xFFC9CDD4)),
          ],
        ),
      ),
    );
  }

  /// 团购核销操作（对齐 smdcapp DyVerifyPopup）
  Future<void> _onVerifyCoupon() async {
    final double amt = await VerifyCouponSheet.show(
      context,
      saleid: widget.saleid,
    );
    if (amt > 0 && mounted) {
      // 核销成功，抵扣金额
      final double verifyAmt = _rd2(amt);
      setState(() {
        _hasMoney = AmountCalcUtils.add(_hasMoney, verifyAmt);
        _dsMoney = AmountCalcUtils.sub(_dsMoney, verifyAmt);
        if (_dsMoney < 0) _dsMoney = 0;
      });
      _salePayWayList.add(<String, dynamic>{
        'saleid': widget.saleid,
        'payid': '99',
        'payname': '团购核销',
        'payamt': verifyAmt,
        'rate': 1.0,
        'rramt': verifyAmt,
        'changeamt': 0.0,
      });
      Toast.show('团购核销抵扣 ¥$verifyAmt');
    }
  }

  /// 已选支付记录卡片（对齐 smdcapp payDetailsLayout 收款记录）
  Widget _buildPayRecordCard(bool isDark) {
    if (_salePayWayList.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232425) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle('收款记录', isDark),
          const SizedBox(height: 8),
          ..._salePayWayList.map((Map<String, dynamic> item) {
            // 抹零记录不可撤销（对齐 smdcapp: 自动抹零不提供撤销）
            final bool isAutoRound =
                item['payid']?.toString() == '06' && item['payname']?.toString() == '抹零';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Text(
                    item['payname']?.toString() ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : const Color(0xFF4E5969),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '¥${_formatAmt(_toDouble(item['payamt']))}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                  if (!isAutoRound) ...<Widget>[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _cancelPayRecord(item),
                      child: const Text(
                        '撤销',
                        style: TextStyle(fontSize: 12, color: _kBrandRed),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          const Divider(height: 14, color: Color(0xFFF2F3F5)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '已收',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : const Color(0xFF86909C),
                ),
              ),
              Text(
                '¥${_formatAmt(_hasMoney)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 选项卡片：打印单据（对齐 smdcapp ll_dy）
  Widget _buildOptionCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232425) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '打印单据',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
          const Spacer(),
          Switch(
            value: _isPrint,
            onChanged: (bool val) => setState(() => _isPrint = val),
            activeColor: _kBrandRed,
          ),
        ],
      ),
    );
  }

  /// 底部操作栏（对齐 smdcapp 底部：待收 + 去支付）
  Widget _buildBottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 10, 16, MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232425) : Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          // 待收金额
          Text(
            '待收：',
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
          Text(
            '¥${_formatAmt(_dsMoney)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _kBrandRed,
            ),
          ),
          const SizedBox(width: 16),
          // 去支付按钮
          Expanded(
            child: GestureDetector(
              onTap: _submitting ? null : _onPay,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kBrandRed.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '去支付',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════ 通用小组件 ═══════════════════

  Widget _sectionTitle(String title, bool isDark) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: _kBrandRed,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1D2129),
          ),
        ),
      ],
    );
  }

  Widget _priceRow(String label, double value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF86909C),
            ),
          ),
          Text(
            '¥${_formatAmt(value)}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
        ],
      ),
    );
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }
}
