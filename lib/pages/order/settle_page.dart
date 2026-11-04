import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/member_coupon_sheet.dart';
import 'package:flutter_deer/util/member_coupon_service.dart';
import 'package:flutter_deer/components/member_search_sheet.dart';
import 'package:flutter_deer/components/verify_coupon_sheet.dart';
import 'package:flutter_deer/db/sale_dao.dart';
import 'package:flutter_deer/db/vip_dao.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/pay_gateway.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/pages/login/login_router.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/pages/order/pay_scan_page.dart';
import 'package:flutter_deer/pages/order/scan_pay_dialog.dart';
import 'package:flutter_deer/pages/order/widgets/coupon_pay_dialog.dart';
import 'package:flutter_deer/pages/order/widgets/sms_verify_dialog.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/theme_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';
import 'package:flutter_deer/util/scan_pending_store.dart';
import 'package:flutter_deer/util/table_concurrency_guard.dart';
import 'package:flutter_deer/util/promotion_helper.dart';
import 'package:flutter_deer/util/amount_calc_utils.dart';
import 'package:flutter_deer/util/aux_business_service.dart';
import 'package:flutter_deer/util/coupon_amount_utils.dart';
import 'package:flutter_deer/util/order_price_calc.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/print_service.dart';
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
    this.memberDiscount = 100,
    this.autoZanjie = false,
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

  /// 会员折扣率（prefetype=1 时使用，10 表示 1 折）
  final int memberDiscount;

  /// 从订单确认页“暂结”按钮进入时直接开启暂结模式（R28）
  final bool autoZanjie;

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

  /// 当前结算金额（促销/会员重算后可变，初值取订单详情页传入）
  late double _dishAmt;
  late double _disAmt;
  late double _payAmt;
  late double _serviceAmt;
  late double _lowAmt;

  /// 已应用的促销活动ID（R20/R22：同一时间只允许一个场景促销）
  String _appliedPromoBillid = '';

  /// 订单明细基准快照（切换促销/会员时恢复，避免多次叠加）
  late List<Map<String, dynamic>> _baseDetails;

  /// 满减类整单优惠金额
  double _orderReduction = 0;

  /// 订单详情页传入的基准金额（促销/会员重算只在此基础上增减）
  late double _baseDishAmt;
  late double _baseDisAmt;
  late double _basePayAmt;
  late double _baseDishPay;

  /// 已选支付记录（对齐 smdcapp salePayWayList）
  final List<Map<String, dynamic>> _salePayWayList = <Map<String, dynamic>>[];

  /// 是否打印单据（对齐 smdcapp isDy）
  bool _isPrint = false;

  /// 整单暂结（对齐 smdcapp SettleActivity.llZj / SETTLE_ZJ）
  bool _isZanjie = false;

  /// 是否显示暂结开关（KQ_ZJ 开启 + 正餐模式）
  bool _canZanjie = false;

  /// 提交中
  bool _submitting = false;

  /// 加载支付方式中
  bool _loadingPayTypes = true;

  /// 可用促销活动列表（对齐 smdcapp PrometionBean）
  List<PromotionInfo> _promotions = <PromotionInfo>[];

  /// 是否有查看促销活动的权限（R40，对齐后台订单操作权限）
  bool _canViewPromotion = true;

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

  /// 锁台事件订阅（R2）
  StreamSubscription<Map<String, dynamic>>? _lockSubscription;

  /// 最近一次桌台状态校验时间（R3：结账前校验，短时间复用结果）
  DateTime? _lastTableCheckAt;

  String get _lockSaleid {
    final dynamic tmp = widget.tableJson?['tmp'];
    final String tmpSaleid =
        tmp is Map ? tmp['saleid']?.toString() ?? '' : '';
    return tmpSaleid.isNotEmpty ? tmpSaleid : widget.saleid;
  }

  @override
  void initState() {
    super.initState();
    _lockSubscription = TableConcurrencyGuard.listenLockEvent(
      context: context,
      saleid: _lockSaleid,
      tableName: widget.tableName,
      onExit: _onLockedByOtherExit,
    );
    // 初始化订单详情页传入的会员信息（对齐 smdcapp intent Member_DetailsBean）
    if (widget.memberVipid.isNotEmpty) {
      _member = VipMember(
        vipid: widget.memberVipid,
        vipname: widget.memberVipname,
        vipno: widget.memberVipno,
        mobile: widget.memberMobile,
        prefetype: widget.memberPrefetype,
        discount: widget.memberDiscount,
        nowmoney: widget.memberNowmoney,
        overflag: widget.memberOverflag,
        overmoney: widget.memberOvermoney,
        arrearages: widget.memberArrearages,
      );
    }
    // 金额字段先初始化，避免无权限弹回时 build 访问 late 字段崩溃
    _dishAmt = widget.dishAmt;
    _disAmt = widget.disAmt;
    _payAmt = widget.payAmt;
    _serviceAmt = widget.serviceAmt;
    _lowAmt = widget.lowAmt;
    _baseDishAmt = widget.dishAmt;
    _baseDisAmt = widget.disAmt;
    _basePayAmt = widget.payAmt;
    _baseDishPay = _rd2(widget.payAmt - widget.serviceAmt - widget.lowAmt);
    _baseDetails = _cloneDetails(widget.detailList);
    _dsMoney = _rd2(_payAmt);
    // R31：无结账权限禁止进入结账页
    if (!PermissionUtils.check(PermissionUtils.appCheckout, '结账')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _canViewPromotion =
        PermissionUtils.checkPermission(PermissionUtils.appTotalDiscount, showTip: false);
    // 打印单据开关记忆（对齐 smdcapp Constant.SETTLE_DY，默认关闭）
    _isPrint = SpUtil.getBool(Constant.settleDy, defValue: false) ?? false;
    // 暂结：参数开启且正餐模式（对齐 smdcapp kqzj && storemodel==2），开启参数时默认开启
    _canZanjie = widget.autoZanjie ||
        ((SpUtil.getBool('KQ_ZJ') ?? false) &&
            !StoreModeUtils.isFastMode() &&
            StoreModeUtils.getCurrentStoreModel() ==
                StoreModeUtils.storeModelNormal);
    _isZanjie = _canZanjie;
    // 会员价与促销/手工折扣取最优（对齐 smdcapp refreshAllPriceInfo）
    if (_member != null) {
      _applyMemberBest(clearMemberMark: true);
      _recalcTotals();
    }
    _applyRounding();
    _loadPayTypes();
    if (_canViewPromotion) _loadPromotions();
    // 桌台快照中的会员只有 vipid/vipname 等基础信息，按 vipid 回查完整会员
    // （含 prefetype/discount）后重算会员价
    if (_member?.vipid.isNotEmpty ?? false) _loadFullMemberInfo();
  }

  @override
  void dispose() {
    _lockSubscription?.cancel();
    super.dispose();
  }

  void _onLockedByOtherExit() {
    if (!mounted) return;
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    TableEventBus.fireTableChanged();
  }

  /// R3：支付/上传流水前确认桌台仍处于待结算且订单未被清台。
  ///
  /// 其他设备在结账过程中清台或换了订单时，禁止继续收款，
  /// 避免生成后台不存在的虚假单号；接口异常时放行（不阻断正常结账）。
  Future<bool> _ensureTableStillCheckoutable({bool force = false}) async {
    if (widget.tableJson == null && widget.tableId.isEmpty) return true;
    final DateTime now = DateTime.now();
    if (!force &&
        _lastTableCheckAt != null &&
        now.difference(_lastTableCheckAt!) < const Duration(seconds: 5)) {
      return true;
    }
    final dynamic tmp = widget.tableJson?['tmp'];
    final String areaid = widget.tableJson?['areaid']?.toString() ?? '';
    final TableInfo? latest = await TableConcurrencyGuard.fetchLatest(
      widget.tableId,
      areaid: areaid,
    );
    if (latest == null) return true;
    _lastTableCheckAt = now;

    final TableDetail? latestTmp = latest.tmp;
    final int latestStatus = latestTmp?.tablestatus ?? 0;
    final bool cleared = latestTmp == null ||
        latestStatus == 0 ||
        latestStatus == 4 ||
        latest.isIdle;
    final String currentSaleid = tmp is Map
        ? tmp['saleid']?.toString() ?? ''
        : '';
    final String latestSaleid = latestTmp?.saleid ?? '';
    final bool saleChanged = currentSaleid.isNotEmpty &&
        latestSaleid.isNotEmpty &&
        currentSaleid != latestSaleid;
    // R65：PC 加菜后桌台金额变化，禁止按旧金额继续支付
    final double latestAmt = latestTmp?.amt ?? 0;
    final double expectedAmt = widget.payAmt;
    final bool amountChanged = latestAmt > 0 &&
        expectedAmt > 0 &&
        (latestAmt - expectedAmt).abs() > 0.05;

    if (!cleared && !saleChanged && !amountChanged) return true;
    if (!mounted) return false;
    await ConfirmDialog.show(
      context,
      content: cleared
          ? '桌台已被清台或状态已变化，无法继续结账，请返回桌台刷新后重试'
          : amountChanged
              ? '订单金额已更新（当前¥${_formatAmt(latestAmt)}），请返回桌台重新进入结账'
              : '桌台订单已变化，请返回桌台后重新进入结账',
      singleButton: true,
    );
    if (mounted) {
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
      TableEventBus.fireTableChanged();
    }
    return false;
  }

  /// 应用币种抹零（对齐 smdcapp Arith.showAllPriceInfo: SmallChangeType==1 时
  /// bzmlPrice = payMoney - smallChangePrice(payMoney)，并作为"06"减免支付方式）
  ///
  /// 抹零设置：SmallChangeType 0=不抹零 1=币种抹零 2=单品抹零
  /// 仅币种抹零(1)在结账环节处理；单品抹零(2)在下单明细环节处理。
  ///
  /// 会员/促销变更导致应收金额变化时需重新计算（对齐 smdcapp 每次
  /// refreshAllPriceInfo 后都会重新 dealMlDate）。
  void _applyRounding() {
    // 先撤销上一次抹零，避免重复叠加
    final int oldIndex = _salePayWayList.indexWhere(
        (Map<String, dynamic> e) => e['payid'] == '06' && e['payname'] == '抹零');
    if (oldIndex >= 0) {
      _hasMoney = AmountCalcUtils.sub(
          _hasMoney, _toDouble(_salePayWayList[oldIndex]['payamt']));
      _salePayWayList.removeAt(oldIndex);
    }
    _roundAmt = 0;
    _dsMoney = _rd2(AmountCalcUtils.sub(_payAmt, _hasMoney));
    if (_dsMoney < 0) _dsMoney = 0;

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

  /// 加载可用促销活动（对齐 smdcapp SettleActivity.getSalesPromotionList）
  Future<void> _loadPromotions() async {
    final List<PromotionInfo> list = await PromotionHelper.fetchPromotions(
      details: widget.detailList,
      vipid: _member?.vipid ?? '',
      saleid: widget.saleid,
      amt: _dishAmt - _disAmt,
      qty: _detailQtyText,
      // 3=仅满量折扣/满减/满折，对齐 smdcapp 结账页促销弹窗口径
      // （分类折扣/菜品折扣等商品级活动已在下单时处理，不在此重复展示）
      promoflag: 3,
    );
    // R63：指定菜品/分类折扣属于商品级活动，结账页不展示
    final List<PromotionInfo> visibleList = list
        .where((PromotionInfo p) =>
            p.billtype != 1 && p.billtype != 2 && p.billtype != 3)
        .toList();
    if (mounted) {
      setState(() => _promotions = visibleList);
      // R20：结算页主动提示有可用促销
      if (visibleList.isNotEmpty && _appliedPromoBillid.isEmpty) {
        Toast.show(
            '本单有${visibleList.length}个可用促销，请在“促销活动”中选择应用');
      }
    }
  }

  /// 本单商品总数量（对齐 smdcapp downPrice.tempQty）
  String get _detailQtyText {
    double qty = 0;
    for (final Map<String, dynamic> d in widget.detailList) {
      if (_toInt(d['presentflag']) == 1 ||
          (d['combproductid']?.toString() ?? '').isNotEmpty) {
        continue;
      }
      qty += _toDouble(d['qty']);
    }
    return qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
  }

  /// 订单明细深拷贝（用于切换促销/会员时恢复基准价）
  List<Map<String, dynamic>> _cloneDetails(List<Map<String, dynamic>> src) {
    final List<dynamic> raw = jsonDecode(jsonEncode(src)) as List<dynamic>;
    return raw
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// 恢复订单明细基准价（避免多个活动叠加计算）
  void _restoreBaseDetails() {
    widget.detailList
      ..clear()
      ..addAll(_cloneDetails(_baseDetails));
    _orderReduction = 0;
    _promoDisAmt = 0;
    _appliedPromoBillid = '';
    _dishAmt = _baseDishAmt;
    _disAmt = _baseDisAmt;
    _payAmt = _basePayAmt;
    _dsMoney = _rd2(_payAmt - _hasMoney);
    if (_dsMoney < 0) _dsMoney = 0;
  }

  /// 按当前明细重算金额汇总（只把明细价差叠加到基准金额上，
  /// 避免套餐/退菜等特殊行因重新汇总产生口径偏差）
  void _recalcTotals() {
    double dishPay = 0;
    for (final Map<String, dynamic> d in widget.detailList) {
      if ((d['combproductid']?.toString() ?? '').isNotEmpty &&
          (d['combid']?.toString() ?? '').isNotEmpty) {
        continue;
      }
      dishPay += _toDouble(d['rramt']);
    }
    final double delta = _rd2(_baseDishPay - dishPay + _orderReduction);
    _dishAmt = _baseDishAmt;
    _payAmt = _rd2(_basePayAmt - delta);
    if (_payAmt < 0) _payAmt = 0;
    _disAmt = _rd2(_baseDisAmt + delta);
    if (_disAmt < 0) _disAmt = 0;
    _dsMoney = _rd2(_payAmt - _hasMoney);
    if (_dsMoney < 0) _dsMoney = 0;
  }

  /// 会员价与当前价取最优（对齐 smdcapp PriceEngine「取最优」：
  /// 促销/手工折扣/会员价都基于原价计算，最终取价格最低者）
  ///
  /// [clearMemberMark] 为 true 时先清除上次会员价标记再重算，
  /// 用于切换/退出会员，避免旧会员折扣残留。
  void _applyMemberBest({bool clearMemberMark = false}) {
    final VipMember? member = _member;
    final int prefetype = member?.prefetype ?? 0;
    final double memberDiscount = member?.discount.toDouble() ?? 100;
    for (final Map<String, dynamic> d in widget.detailList) {
      if (_toInt(d['presentflag']) == 1 || _toInt(d['presentflag']) == 2) {
        continue;
      }
      if ((d['fornowid']?.toString() ?? '').isNotEmpty) continue;
      if (_toInt(d['douyinflag']) == 1 && _toInt(d['id']) != 0) continue;
      OrderPriceCalc.applyMemberPrice(
        d,
        prefetype: prefetype,
        memberDiscount: memberDiscount,
        clearMemberMark: clearMemberMark,
      );
    }
  }

  /// 按 vipid 回查完整会员信息（对齐 smdcapp getVipData → VipListRequest.vipid）
  ///
  /// 订单详情页传入的会员可能只有基本字段，缺少 prefetype/discount，
  /// 无法计算会员价；取到完整信息后立即重算金额。
  Future<void> _loadFullMemberInfo() async {
    final String vipid = _member?.vipid ?? '';
    if (vipid.isEmpty) return;
    try {
      final VipMember? full = await OrderRepository.fetchVipByVipid(vipid);
      if (!mounted || full == null) return;
      // 请求期间已退出/切换会员时放弃回填
      if ((_member?.vipid ?? '') != vipid) return;
      setState(() {
        _member = full;
        _applyMemberBest(clearMemberMark: true);
        _recalcTotals();
        _applyRounding();
      });
      _loadPromotions();
    } catch (_) {}
  }

  /// 应用促销活动（对齐 smdcapp amountAfterDiscount）
  Future<void> _applyPromotion(PromotionInfo promo) async {
    if (_appliedPromoBillid == promo.billid) {
      Toast.show('该活动已应用');
      return;
    }
    // R22：已参加满赠活动时不可再享受整单优惠
    final bool hasFullGift = widget.detailList
        .any((Map<String, dynamic> d) => _toInt(d['bxxpxxflag']) == 4);
    if (hasFullGift) {
      Toast.show('已参加满赠活动，不能再享受整单优惠');
      return;
    }

    _restoreBaseDetails();
    // 先按会员价重算：促销与会员价取最优（对齐 smdcapp 取最优模式），
    // 且促销门槛按会员折后金额计算（对齐 getSalesPromotionList 传 tempRRPrice）
    _applyMemberBest(clearMemberMark: true);
    _recalcTotals();

    final PromotionApplyResult? result = await PromotionHelper.calcPromotion(
      details: widget.detailList,
      billid: promo.billid,
      vipid: _member?.vipid ?? '',
      saleid: widget.saleid,
      amt: _dishAmt - _disAmt,
      qty: _detailQtyText,
    );
    if (!mounted) return;
    if (result == null) {
      Toast.show('该活动未计算出优惠');
      return;
    }

    double disAmt = 0;
    if (result.details.isNotEmpty) {
      for (final Map<String, dynamic> row in result.details) {
        final Map<String, dynamic>? target = _findDetailForPromoRow(row);
        if (target == null) continue;
        final double sell = _toDouble(target['sellprice']);
        if (sell <= 0) continue;
        final double current = _toDouble(target['rrprice']) > 0
            ? _toDouble(target['rrprice'])
            : sell;
        double? newPrice;
        final double serverRr = _toDouble(row['rrprice']);
        final double rowDiscount = _toDouble(row['discount']);
        if (serverRr > 0 && serverRr < current) {
          newPrice = serverRr;
        } else if (rowDiscount > 0 && rowDiscount < 100) {
          newPrice = _rd2(sell * rowDiscount / 100);
        }
        if (newPrice == null || newPrice >= current) continue;
        // R21：会员价更优时保留会员价
        if (_member != null && _member!.prefetype != 0) {
          // 已在 _applyMemberBest 中写入更优会员价，此处只有活动更优才覆盖
          if (current <= newPrice) continue;
        }
        final double qty = _toDouble(target['qty']);
        target['rramt'] =
            _rd2(_toDouble(target['rramt']) + (newPrice - current) * qty);
        target['rrprice'] = newPrice;
        target['discount'] = rowDiscount > 0 && rowDiscount < 100
            ? rowDiscount
            : _rd2(newPrice / sell * 100);
        target['specpriceflag'] = promo.billtype;
        target['jcmbillid'] = promo.billid;
        disAmt += (current - newPrice) * qty;
      }
    }
    // 满减/无明细返回：按整单优惠处理（有明细时不再叠加整单优惠，
    // 避免会员价已更优的情况下重复优惠，R21）
    if (result.details.isEmpty && result.totalDiscount > 0) {
      _orderReduction = result.totalDiscount;
      disAmt = result.totalDiscount;
    }
    if (disAmt <= 0) {
      Toast.show('该活动未计算出优惠');
      _recalcTotals();
      _applyRounding();
      return;
    }
    setState(() {
      _promoDisAmt = _rd2(disAmt);
      _appliedPromoBillid = promo.billid;
      _recalcTotals();
      _applyRounding();
    });
    Toast.show('已应用促销：${promo.billname}，优惠¥${_rd2(disAmt)}');
  }

  Map<String, dynamic>? _findDetailForPromoRow(Map<String, dynamic> row) {
    final String onlyid = row['onlyid']?.toString() ?? '';
    if (onlyid.isNotEmpty) {
      for (final Map<String, dynamic> d in widget.detailList) {
        if (d['onlyid']?.toString() == onlyid) return d;
      }
    }
    final String productid = row['productid']?.toString() ?? '';
    if (productid.isEmpty) return null;
    for (final Map<String, dynamic> d in widget.detailList) {
      if (d['productid']?.toString() == productid) return d;
    }
    return null;
  }

  // ═══════════════════ 会员录入（对齐 smdcapp SettleActivity: tvManageTwo + onActivityResult + upMember） ═══════════════════

  /// 标题栏“会员”按钮点击（对齐 smdcapp tvManageTwo.onClick → MemberActivity）
  Future<void> _onMemberTap() async {
    if (!PermissionUtils.check(PermissionUtils.appMemberLogin, '会员操作')) return;
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
    final VipMember? selected = await MemberSearchSheet.show(context);
    if (selected == null || !mounted) return;
    // R46/R30：搜索接口可能不带 prefetype/discount/余额，回查完整会员信息
    final VipMember? full =
        await OrderRepository.fetchVipByVipid(selected.vipid);
    if (!mounted) return;
    _loginMember(full ?? selected);
  }

  /// 录入会员（对齐 smdcapp onActivityResult → memberBean = bean + upMember）
  Future<void> _loginMember(VipMember member) async {
    await _syncMemberToServer(member: member);
    if (!mounted) return;
    setState(() {
      _member = member;
      _selectedCoupon = null;
      // 切换会员后按基准价重算会员价（R21：会员价与活动价取最优）
      _restoreBaseDetails();
      _applyMemberBest(clearMemberMark: true);
      _recalcTotals();
      _applyRounding();
    });
    _loadPromotions();
  }

  /// 退出会员（对齐 smdcapp loginListener.onLogout → memberBean = null + upMember）
  Future<void> _logoutMember() async {
    await _syncMemberToServer(member: null);
    if (!mounted) return;
    setState(() {
      _member = null;
      _selectedCoupon = null;
      _restoreBaseDetails();
      // 退出会员后清除会员价标记，恢复原价/活动价（对齐 smdcapp 重新定价）
      _applyMemberBest(clearMemberMark: true);
      _recalcTotals();
      _applyRounding();
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
    bool synced = false;
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
      synced = true;
    } catch (_) {
      Toast.show('同步会员信息失败');
    } finally {
      // R30：同步成功后更新本地桌台快照并通知桌台页刷新，退出重进会员信息不丢
      if (synced && tmp != null) {
        tmp['vipid'] = member?.vipid ?? '';
        tmp['vipno'] = member?.vipno ?? '';
        tmp['vipname'] = member?.vipname ?? '';
        tmp['vipmobile'] = member?.mobile ?? '';
        TableEventBus.fireTableChanged();
      }
      if (mounted) {
        setState(() => _memberSyncing = false);
      }
    }
  }

  /// 选择会员优惠券（对齐 smdcapp CouponListActivity + PayDetailsLayout.couponDel）
  Future<void> _selectCoupon() async {
    if (_member == null) {
      Toast.show('请先录入会员');
      return;
    }
    final String billdate = DateTime.now().toString().substring(0, 19);
    final List<Map<String, dynamic>> details = _buildSaleDetail(billdate);
    final MemberCoupon? coupon = await MemberCouponSheet.show(
      context,
      vipid: _member!.vipid,
      master: jsonEncode(_buildSaleMaster(billdate)),
      projectlist: jsonEncode(details),
    );
    if (coupon == null || !mounted) return;
    // 项目券/礼品券面额为0，按适用商品金额抵扣（对齐 smdcapp dealCouponAmt）
    final double couponAmt = calcCouponDeductAmount(coupon.raw, details);
    if (couponAmt <= 0) {
      Toast.show('该券不适用于当前订单');
      return;
    }
    setState(() {
      // 替换旧券：先回退上一张券占用的金额
      final int oldIdx = _salePayWayList.indexWhere(
          (Map<String, dynamic> e) => e['payid']?.toString() == '07');
      if (oldIdx >= 0) {
        final double oldAmt = _toDouble(_salePayWayList[oldIdx]['payamt']);
        _salePayWayList.removeAt(oldIdx);
        _hasMoney = AmountCalcUtils.sub(_hasMoney, oldAmt);
        _dsMoney = AmountCalcUtils.add(_dsMoney, oldAmt);
      }
      final double userAmt = couponAmt < _dsMoney ? couponAmt : _dsMoney;
      _salePayWayList.add(<String, dynamic>{
        'saleid': widget.saleid,
        'payid': '07',
        'payname': '优惠券',
        'payamt': _rd2(userAmt),
        'rate': 1.0,
        'rramt': _rd2(userAmt),
        'changeamt': 0.0,
        'favid': coupon.favid,
        'fav': jsonEncode(coupon.raw),
      });
      _hasMoney = AmountCalcUtils.add(_hasMoney, userAmt);
      _dsMoney = AmountCalcUtils.sub(_dsMoney, userAmt);
      if (_dsMoney <= 0.005) _dsMoney = 0;
      _selectedCoupon = coupon;
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
    // R3：结算过程中桌台被其他设备清台/换单时，禁止继续收款
    if (!await _ensureTableStillCheckoutable()) return;
    if (!mounted) return;
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
    // 会员卡(02)：必须先录入会员才能支付
    // （对齐 smdcapp selectPay case "02"：memberBean == null 时引导登录会员）
    if (_payId == '02' && _member == null) {
      Toast.show('请先录入会员');
      return;
    }

    // 优惠券(15)：无需录入会员，直接弹券号搜索弹窗核销
    // （对齐 smdcapp selectPay case "15"：会员判断已注释，直接 YHQSearchPopup）
    if (_payId == '15') {
      await _onCouponPay();
      return;
    }

    // 抖音(13)/美团(meituantuangou)/快手(kuaishou)团购核销
    // （对齐 smdcapp selectPay case "13"/"meituantuangou"/"kuaishou" → dyVetify）
    if (_payId == '13' ||
        _payId == 'meituantuangou' ||
        _payId == 'kuaishou') {
      await _onVerifyCoupon(payId: _payId, payName: _payName);
      return;
    }
  
    // 移动支付：支付宝(08)/微信(09)/云闪付(10) → 扫码支付流程
    // （对齐 smdcapp clickWxAliPay → MipcaActivityCapture → disposeWxAliScanPay）
    if (_payId == '08' || _payId == '09' || _payId == '10') {
      await _onScanPay();
      return;
    }

    // R35：聚客一卡通必须先刷/查询会员再付款
    if (_payId == 'onecardpay') {
      await _onOneCardPay();
      return;
    }

    // 会员挂账(04)：额度校验后直接挂账（对齐 smdcapp selectPay case "04"）
    if (_payId == '04') {
      await _onMemberOverPay();
      return;
    }
    // R40：企业挂账等其他“挂账”支付方式必须选择挂账人（会员），不能按现金直接收款
    if (_payName.contains('挂账')) {
      if (_member == null) {
        Toast.show('请先选择挂账人');
        return;
      }
      await _onMemberOverPay();
      return;
    }

    // 会员卡(02)：余额校验在金额输入后处理（支持按余额部分支付，R50/R74）

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

    // R74：会员卡支付支持按余额部分支付，余额不足部分改用其他支付方式
    double maxPay = _dsMoney;
    if (_payId == '02') {
      final double balance = _member?.nowmoney ?? 0;
      if (balance <= 0) {
        Toast.show('会员余额不足，请使用其他支付方式');
        return;
      }
      if (balance < maxPay) maxPay = balance;
    }
    // 现金多收（对齐 smdcapp PricePopup 全支付分支 + getPayWayBean）：
    // 收款额记顾客递付金额，找零单列；主表 payment 含递付额、changeamt 为找零，
    // 这样完成页「实收」= 顾客实付、与 smdcapp 一致（原实现截到应收会少显示）
    final bool overpay = _payId != '02' && inputAmt > maxPay + 0.005;
    final double changeAmt = overpay ? _rd2(inputAmt - maxPay) : 0.0;
    final double payAmt = overpay
        ? _rd2(inputAmt)
        : _rd2(inputAmt > maxPay ? maxPay : inputAmt);
    final bool memberPartial = _payId == '02' && payAmt < _dsMoney - 0.005;

    // 记录支付方式
    _salePayWayList.add(<String, dynamic>{
      'saleid': widget.saleid,
      'payid': _payId,
      'payname': _payName,
      'payamt': payAmt,
      'rate': 1.0,
      // 对齐 smdcapp：rramt = 收款额 - 找零
      'rramt': AmountCalcUtils.sub(payAmt, changeAmt),
      'changeamt': changeAmt,
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
      if (memberPartial) {
        Toast.show('会员余额已支付¥${_formatAmt(payAmt)}，剩余¥${_formatAmt(_dsMoney)}请使用其他方式');
      }
    }
  }
  
  /// 优惠券支付（对齐 smdcapp TicketNumSearchPopup）
  ///
  /// 弹窗内扫码/输入券号并完成券号核销（voucherVerify），
  /// 核销成功后按券可抵扣金额付款（现金券取面额、项目券取适用商品金额；
  /// 可抵扣金额大于待收时取待收）。
  Future<void> _onCouponPay() async {
    final String billdate = DateTime.now().toString().substring(0, 19);
    final Map<String, dynamic> master = _buildSaleMaster(billdate);
    final CouponPayResult? result = await CouponPayDialog.show(
      context,
      master: jsonEncode(master),
      projectlist: jsonEncode(_buildSaleDetail(billdate)),
    );
    if (result == null || !mounted) return;

    // 券可抵扣金额大于待收时只收待收金额（对齐 smdcapp：payamt < dsMoney 部分支付）
    final double payAmt =
        _rd2(result.payAmount < _dsMoney ? result.payAmount : _dsMoney);
    if (payAmt <= 0) return;
    _salePayWayList.add(<String, dynamic>{
      'saleid': widget.saleid,
      'payid': _payId,
      'payname': _payName,
      'payamt': payAmt,
      'rate': 1.0,
      'rramt': payAmt,
      'changeamt': 0.0,
      'faceamt': payAmt,
      'voucher': result.code,
      'vipid': _member?.vipid ?? '',
      'vipno': _member?.vipno ?? '',
      'vipname': _member?.vipname ?? '',
      // 供撤销时反核销定位（对齐 smdcapp resetData unVerify(vipid, billno)）；
      // 必须与核销时 master.billno 一致，否则服务端定位不到已核销的券
      'billno': master['billno']?.toString() ?? _orderBillno(),
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

  /// 聚客一卡通支付（对齐 smdcapp PayDetailsLayout.onecardpay → JkCardPopup）
  Future<void> _onOneCardPay() async {
    final String? input = await InputDialog.show(
      context,
      title: _payName.isNotEmpty ? _payName : '聚客一卡通',
      hintText: '请刷卡或输入卡号',
      maxLines: 1,
      keyboardType: TextInputType.text,
    );
    if (input == null || input.trim().isEmpty || !mounted) return;
    final List<Map<String, dynamic>> list =
        await AuxBusinessService.instance.getJkCardVipInfo(input.trim());
    if (!mounted) return;
    if (list.isEmpty) {
      Toast.show('未查询到一卡通会员');
      return;
    }
    final Map<String, dynamic> vip = list.first;
    final String vipname = vip['vipname']?.toString() ?? '';
    final double balance = _toDouble(vip['nowmoney']);
    // 对齐 smdcapp JkCardPopup：储卡支付金额为0，无法支付
    if (balance <= 0) {
      Toast.show('储卡支付金额为0，无法支付');
      return;
    }
    // 消费校验方式：0不校验 1储卡密码 2短信验证 3强制持卡密码（对齐 smdcapp PwsPopup）
    final String cardPassword = vip['password']?.toString() ?? '';
    final String vipPassword = vip['vipPassword']?.toString() ??
        vip['VipPassword']?.toString() ??
        '0';
    if (cardPassword.isNotEmpty && vipPassword != '0') {
      final bool verified = await _verifyJkCardPassword(vip, vipPassword);
      if (!verified || !mounted) return;
    }
    // 余额不足时提示并按余额部分支付（对齐 smdcapp JkCardPay）
    double payAmt = _dsMoney;
    if (balance < _dsMoney) {
      final bool confirmed = await ConfirmDialog.show(
        context,
        content: '当前储卡余额【￥${_formatAmt(balance)}】不足,确认继续支付？',
        confirmText: '确认',
      );
      if (!confirmed || !mounted) return;
      payAmt = balance;
    }
    final String billno = _generateBillNo();
    final bool ok = await AuxBusinessService.instance.jkCardPay(
      vipid: vip['vipid']?.toString() ?? '',
      vipno: vip['vipno']?.toString() ?? '',
      payid: _payId,
      payname: _payName,
      saleid: widget.saleid,
      salename: _getUserName(),
      billno: billno,
      payamt: _rd2(payAmt).toString(),
    );
    if (!ok || !mounted) {
      Toast.show('一卡通支付失败');
      return;
    }
    _salePayWayList.add(<String, dynamic>{
      'saleid': widget.saleid,
      'payid': _payId,
      'payname': _payName,
      'payamt': _rd2(payAmt),
      'rate': 1.0,
      'rramt': _rd2(payAmt),
      'changeamt': 0.0,
      'faceamt': _rd2(payAmt),
      'vipid': vip['vipid']?.toString() ?? '',
      'vipno': vip['vipno']?.toString() ?? '',
      'vipname': vipname,
      // 撤销冲正需与支付时同一单号（对齐 smdcapp resetData → JkCardPay 负数冲正）
      'billno': billno,
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

  /// 一卡通消费密码/短信校验（对齐 smdcapp JkCardPopup → PwsPopup）
  ///
  /// vipPassword：1=储卡密码 3=强制持卡密码（本地比对随会员返回的 password），
  /// 2=短信验证（getcode/checkcode，smstype=7）。
  Future<bool> _verifyJkCardPassword(
      Map<String, dynamic> vip, String vipPassword) async {
    if (vipPassword == '2') {
      final String mobile = vip['mobile']?.toString() ?? '';
      if (mobile.isEmpty) {
        Toast.show('会员手机号为空，无法短信验证');
        return false;
      }
      return SmsVerifyDialog.show(context, mobile: mobile);
    }
    if (vipPassword != '1' && vipPassword != '3') {
      Toast.show('密码错误');
      return false;
    }
    final String? pwd = await InputDialog.show(
      context,
      title: '密码校验',
      hintText: '请输入消费密码',
      maxLines: 1,
      obscureText: true,
      keyboardType: TextInputType.number,
    );
    if (pwd == null || !mounted) return false;
    final String cardPassword = vip['password']?.toString() ?? '';
    if (cardPassword.isEmpty) {
      Toast.show('请前往后台设置储卡密码');
      return false;
    }
    if (pwd.trim() != cardPassword) {
      Toast.show('密码错误');
      return false;
    }
    return true;
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
      final String overBillno = _generateBillNo();
      await requestForm(HttpApi.vipOverPay, <String, dynamic>{
        'billno': overBillno,
        // R41：后台按 saleid 关联挂账明细（对齐 smdcapp billid=saleid）
        'billid': widget.saleid,
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
        // 供撤销时反向记账定位（对齐 smdcapp resetData 使用同一 billno）
        'billno': overBillno,
        'vipid': _member?.vipid ?? '',
        'vipno': _member?.vipno ?? '',
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
  /// 从收款记录移除该笔支付，恢复待收金额；挂账/优惠券已在支付时同步服务端，
  /// 撤销时需回退服务端（挂账反向记账、优惠券反核销），否则后台报表统计有误。
  Future<void> _cancelPayRecord(Map<String, dynamic> item) async {
    final double payAmt = _toDouble(item['payamt']);
    final String payid = item['payid']?.toString() ?? '';
    try {
      if (item['dyverify'] == true) {
        // 团购核销：服务端撤销验券（对齐 smdcapp HxVouchers → cancelPrepare）
        await requestForm(HttpApi.douyinCancelPrepare, <String, dynamic>{
          'saleid': widget.saleid,
          'businesstype': item['businesstype']?.toString() ?? '',
          'signinfo': '',
        });
        if (!mounted) return;
        final double deal =
            _toDouble(item['dy_dealprice'] ?? item['payamt']);
        final double eligible = _toDouble(item['dy_productprice']);
        final double diff = _rd2(eligible - deal);
        setState(() {
          _salePayWayList.remove(item);
          _hasMoney = AmountCalcUtils.sub(_hasMoney, deal);
          if (_hasMoney < 0) _hasMoney = 0;
          _dsMoney = AmountCalcUtils.add(_dsMoney, eligible);
          if (diff > 0) {
            _disAmt = AmountCalcUtils.sub(_disAmt, diff);
            _payAmt = AmountCalcUtils.add(_payAmt, diff);
          }
          _unmarkCouponDetails(item['querytoken']?.toString() ?? '');
        });
        Toast.show('撤销成功');
        return;
      }
      if (payid == '04') {
        // 会员挂账：反向记账（对齐 smdcapp resetData vipoverPay amt=-payamt）
        await requestForm(HttpApi.vipOverPay, <String, dynamic>{
          'billno': item['billno']?.toString() ?? _generateBillNo(),
          'billid': '',
          'vipid': item['vipid']?.toString() ?? _member?.vipid ?? '',
          'vipno': item['vipno']?.toString() ?? _member?.vipno ?? '',
          'payid': '04',
          'payname': '会员挂账',
          'saleid': widget.saleid,
          'salename': '',
          'amt': '-${_rd2(payAmt)}',
        });
      } else if (payid == '15') {
        // 优惠券：反核销（对齐 smdcapp resetData unVerify）
        await requestForm(HttpApi.vipUnVerify, <String, dynamic>{
          'vipid': item['vipid']?.toString() ?? _member?.vipid ?? '',
          'billno': item['billno']?.toString() ?? _orderBillno(),
        });
      } else if (payid == 'onecardpay') {
        // 聚客一卡通：负数反向记账（对齐 smdcapp resetData → JkCardPay("-payamt")）
        final bool reversed = await AuxBusinessService.instance.jkCardPay(
          vipid: item['vipid']?.toString() ?? '',
          vipno: item['vipno']?.toString() ?? '',
          payid: payid,
          payname: item['payname']?.toString() ?? '',
          saleid: widget.saleid,
          salename: _getUserName(),
          billno: item['billno']?.toString() ?? _generateBillNo(),
          payamt: '-${_rd2(payAmt)}',
        );
        if (!reversed) {
          if (mounted) Toast.show('一卡通冲正失败');
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        Toast.show('撤销失败：${e.toString().replaceFirst('Exception: ', '')}');
      }
      return;
    }
    if (!mounted) return;
    // 现金多收时收款额含递付额，撤销只恢复净额（对齐 smdcapp resetData）
    final double netAmt =
        AmountCalcUtils.sub(payAmt, _toDouble(item['changeamt']));
    setState(() {
      _salePayWayList.remove(item);
      _hasMoney = AmountCalcUtils.sub(_hasMoney, payAmt);
      _dsMoney = AmountCalcUtils.add(_dsMoney, netAmt);
      if (_hasMoney < 0) _hasMoney = 0;
    });
  }

  /// 订单本地单号（对齐 smdcapp placedOrderBean.billno）
  String _orderBillno() {
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String localbillno = tmp?['localbillno']?.toString() ?? '';
    return localbillno.isNotEmpty ? localbillno : widget.saleid;
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
    if (result == null) {
      // R61：支付中断/超时关闭弹窗时生成本地异常订单，便于后续交易查询
      ScanPendingStore.add(
        billno: payBillNo,
        amt: payAmt,
        payid: _payId,
        payname: _payName,
        tableName: widget.tableName,
        cashname: _getUserName(),
        payConfig: payConfig,
      );
      Toast.show('支付未完成，已生成异常订单，可在【异常订单】查询');
      return;
    }
    if (!mounted) return;

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
      // 输入大于应收时实时显示找零（对齐 smdcapp PricePopup tvChange）
      changeBaseAmount: _dsMoney,
    );
    if (result == null || result.isEmpty) return null;
    return double.tryParse(result);
  }

  /// 上传结账流水（对齐 smdcapp getSaleFlowData → saleflow）
  Future<void> _submitSaleFlow() async {
    // R45：存在未称重商品时禁止结算
    if (ParamsSpUtils.isReweigh() &&
        widget.detailList.any((Map<String, dynamic> d) =>
            _toInt(d['weighflag']) == 1 &&
            (d['combproductid']?.toString() ?? '').isEmpty &&
            _toDouble(d['confirmqty']) == 0)) {
      Toast.show('本单有未称重商品，请确认称重');
      return;
    }
    // R3：上传流水前强制再校验一次桌台状态，避免清台后生成虚假单号
    if (!await _ensureTableStillCheckoutable(force: true)) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      // 获取服务器时间（对齐 smdcapp getTime）
      String billdate = '';
      bool loginExpired = false;
      try {
        final Map<String, dynamic> timeResp =
            await requestForm(HttpApi.getTime, <String, dynamic>{});
        // 对齐 smdcapp SettleActivity.toPay：retcode == -2 表示登录态失效，
        // 继续结账会导致流水上传失败，必须先提示重新登录
        final dynamic rc = timeResp['retcode'] ?? timeResp['RetCode'];
        loginExpired = rc != null && int.tryParse(rc.toString()) == -2;
        final dynamic timeData = timeResp['data'] ?? timeResp['Data'];
        if (timeData is Map<String, dynamic>) {
          billdate = timeData['requesttime']?.toString() ?? '';
        }
        if (billdate.isEmpty && timeResp['requesttime'] != null) {
          billdate = timeResp['requesttime'].toString();
        }
      } catch (_) {}
      if (loginExpired) {
        if (!mounted) return;
        setState(() => _submitting = false);
        final bool relogin = await ConfirmDialog.show(
          context,
          content: '【登录信息失效】\n继续结账将导致上传流水失败，请重新登录',
          confirmText: '重新登录',
        );
        if (relogin && mounted) {
          NavigatorUtils.push(context, LoginRouter.loginPage, clearStack: true);
        }
        return;
      }
      if (billdate.isEmpty) {
        billdate = DateTime.now().toString().substring(0, 19);
      }

      // R12：整单暂结（对齐 smdcapp ZanjieModel.dealPayWay）
      if (_isZanjie) {
        await _submitZanjie(billdate);
        return;
      }

      // 会员支付处理（对齐 smdcapp saveFlowInDb → vipInfoPay）
      //
      // 必须遍历收款记录逐笔上报：凡 payid=="02" 的记录按其自身 payamt 扣会员款，
      // 任何一笔失败即中止整单上传。不可按"当前选中的支付方式"判断、按应收全额上报，
      // 否则「刷会员后改用现金结账」时 vipPay 被跳过（收款记录有会员卡、会员却没扣款），
      // 或会员+现金混合支付时按全额多扣会员款，导致后台报表/会员流水统计有误。
      for (final Map<String, dynamic> payWay in _salePayWayList) {
        if (payWay['payid']?.toString() != '02') continue;
        final Map<String, dynamic> payParams = <String, dynamic>{
          'billno': _generateBillNo(),
          'vipid': payWay['vipid']?.toString() ?? _member?.vipid ?? '',
          'vipno': payWay['vipno']?.toString() ?? _member?.vipno ?? '',
          'payid': '02',
          'payname': payWay['payname']?.toString() ?? '会员卡',
          'saleid': widget.saleid,
          'salename': '',
          'amt': _rd2(_toDouble(payWay['payamt'])).toString(),
        };
        // 失败时 requestForm 抛异常 → 中止结账上传（对齐 smdcapp return@launch）
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

      // R17/R29：会员优惠券核销（对齐 smdcapp verifyPay clienttype=4，核销失败中止结算）
      if (_selectedCoupon != null && _member != null) {
        final bool couponOk = await MemberCouponService.instance.verifyCouponPay(
          vipid: _member!.vipid,
          master: jsonEncode(_buildSaleMaster(billdate)),
          projectlist: jsonEncode(_buildSaleDetail(billdate)),
          clienttype: '4',
          fav: jsonEncode(_selectedCoupon!.raw),
        );
        if (!couponOk) {
          if (mounted) Toast.show('优惠券核销失败，请重新选择');
          return;
        }
      }

      // 构建 SaleBean 数据（对齐 smdcapp SaleBean 结构）
      final Map<String, dynamic> saleMaster = _buildSaleMaster(billdate);
      final List<Map<String, dynamic>> saleDetail = _buildSaleDetail(billdate);
      // 对齐 smdcapp PayDetailsLayout 上传前处理："多条支付方式，删除现金为0的支付方式"，
      // 否则后台收银明细报表会多出一条现金0元的错误记录
      if (_salePayWayList.length > 1) {
        _salePayWayList.removeWhere((Map<String, dynamic> e) =>
            e['payid']?.toString() == '01' && _toDouble(e['payamt']) == 0);
      }
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
        // 对齐 smdcapp SettleActivity 支付完成打印：结帐单打印
        final String settleBillno = saleMaster['billno']?.toString() ?? '';
        PrintService.instance.triggerSettlePrint(
          saleid: widget.saleid,
          billno: settleBillno,
          data: jsonEncode(saleMaster),
        );
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
        // 实收/找零取上传主表字段（对齐 smdcapp tvRealAmt=payment、tvZlAmt=changeamt）
        final double receivedAmt =
            (saleMaster['payment'] as num?)?.toDouble() ?? _hasMoney;
        final double changeAmt =
            (saleMaster['changeamt'] as num?)?.toDouble() ?? 0;
        // 支付方式（对齐 smdcapp：t_sale_payway 全部 payname 以 / 拼接）
        final String payNames = salePayway
            .map((Map<String, dynamic> e) => e['payname']?.toString() ?? '')
            .where((String n) => n.isNotEmpty)
            .join('/');
        // 收银员（对齐 smdcapp：有桌台取服务员，否则取当前登录人）
        final Map<String, dynamic>? finishTmp =
            widget.tableJson?['tmp'] as Map<String, dynamic>?;
        final String tmpServerName =
            finishTmp?['servername']?.toString() ?? '';
        final String cashierName = tmpServerName.isNotEmpty
            ? tmpServerName
            : (widget.serverName.isNotEmpty ? widget.serverName : _getUserName());
        NavigatorUtils.push(
          context,
          Routes.settleFinishPage,
          arguments: <String, dynamic>{
            'tableName': widget.tableName,
            'payAmt': _payAmt,
            'receivedAmt': receivedAmt,
            'changeAmt': changeAmt,
            'payName': payNames.isNotEmpty ? payNames : _payName,
            'takecode': takecode,
            'billno': settleBillno,
            'billdate': billdate,
            'detailCount': saleDetail.length,
            'cashierName': cashierName,
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

  /// 整单暂结（对齐 smdcapp ZanjieModel.dealPayWay）
  Future<void> _submitZanjie(String billdate) async {
    if (_salePayWayList.isEmpty) {
      Toast.show('请先选择支付方式');
      setState(() => _submitting = false);
      return;
    }
    final List<Map<String, dynamic>> pending = widget.detailList
        .where((Map<String, dynamic> d) =>
            (d['fornowid']?.toString() ?? '').isEmpty)
        .toList();
    if (pending.isEmpty) {
      Toast.show('不存在可暂结的商品');
      setState(() => _submitting = false);
      return;
    }

    final String machNo = SpUtil.getString(Constant.machNo) ?? '';
    final String datePart = _zanjieDatePart();
    final String fornowid = '$datePart$machNo${_randomStr(9)}';
    // 暂结支付流水统一走 _buildSalePayway 补齐 spid/sid/machno/createtime 等字段
    // （对齐 smdcapp DealSaleBeanUtil.getPayWayBean）：主设备 InsertPayawyFornow
    // 要求 spid 非空，缺失会报“不能将值 NULL 插入列 'spid'”
    final List<Map<String, dynamic>> paywayList = _buildSalePayway();
    for (final Map<String, dynamic> pay in paywayList) {
      pay['fornowid'] = fornowid;
      pay['onlyid'] = 'ZJ$datePart$machNo${_randomStr(7)}';
      pay['paystatus'] = 1;
      pay['serviceamt'] = _serviceAmt;
      pay['lowamt'] = _lowAmt;
    }
    final List<Map<String, dynamic>> zanjieDetails = pending
        .map((Map<String, dynamic> d) => <String, dynamic>{
              'saleid': d['saleid']?.toString() ?? widget.saleid,
              'onlyid': d['onlyid']?.toString() ?? '',
              'rrprice': _toDouble(d['rrprice']),
              'discount': _toDouble(d['discount']) == 0
                  ? 100
                  : _toDouble(d['discount']),
              'rramt': _toDouble(d['rramt']),
              'querytoken': d['querytoken']?.toString() ?? '',
            })
        .toList();
    paywayList.first['list'] = jsonEncode(zanjieDetails);

    try {
      if (ConnectionManager.pcAlive) {
        final Object? tmp = widget.tableJson?['tmp'];
        final Map<String, dynamic> data = <String, dynamic>{
          'master': tmp is Map ? tmp : <String, dynamic>{},
          'paywaylist': paywayList,
          'fornowid': fornowid,
        };
        final String dataJson = jsonEncode(data);
        await requestForm(
          HttpApi.pcInsertPayawyFornow,
          <String, dynamic>{'data': dataJson},
          masterDevice: true,
        );
        if (_isPrint) {
          // 暂结打印（对齐 smdcapp PayDetailsLayout：PrintTempPayInfo 入参为 PcPrintBean，
          // 含 master/paywaylist/detailList/printMode，master.printjzflag 标记出暂结单）
          final Map<String, dynamic> printMaster = _buildSaleMaster(billdate);
          double pendingRetail = 0;
          for (final Map<String, dynamic> d in pending) {
            pendingRetail = AmountCalcUtils.add(
              pendingRetail,
              _toDouble(d['oldrramt'] ?? d['rramt']),
            );
          }
          printMaster['retailamt'] = _rd2(pendingRetail);
          printMaster['printjzflag'] = 1;
          await PrintService.instance.printTempPayInfo(jsonEncode(<String, dynamic>{
            'master': printMaster,
            'paywaylist': paywayList,
            'detailList': pending,
            'printMode': 1,
          }));
        }
      } else {
        await requestForm(HttpApi.upPayInfo, <String, dynamic>{
          'saleid': widget.saleid,
          'payinfos': jsonEncode(paywayList),
          'printtype': _isPrint ? '1' : '-1',
        });
        if (widget.tableId.isNotEmpty) {
          try {
            await requestForm(HttpApi.updateMasterTmpStatus, <String, dynamic>{
              'tableid': widget.tableId,
              'saleid': widget.saleid,
              'tablestatus': '3',
            });
          } catch (_) {}
        }
      }
      Toast.show('暂结成功');
      TableEventBus.fireTableChanged();
      if (!mounted) return;
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    } catch (e) {
      if (mounted) Toast.show('暂结失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _zanjieDatePart() {
    final DateTime now = DateTime.now();
    return '${now.year % 100}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String _randomStr(int len) {
    const String chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final math.Random random = math.Random();
    return List<String>.generate(
        len, (_) => chars[random.nextInt(chars.length)]).join();
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
    double changeamt = 0;
    for (final Map<String, dynamic> pw in _salePayWayList) {
      if (pw['payid'] == '06') {
        reductionamt = AmountCalcUtils.add(reductionamt, _toDouble(pw['payamt']));
      }
      // R53：多收找零按收款记录累计（现金多付时输入金额-应收）
      changeamt = AmountCalcUtils.add(changeamt, _toDouble(pw['changeamt']));
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
          : (tmp?['tableid']?.toString() ?? (hasTable ? '' : '-1')),
      // 快餐/无桌台不上传桌台字段（对齐 smdcapp getSaleMasterBean tablebean==null 分支）
      if (hasTable) 'tablename': widget.tableName,
      if (hasTable) 'tableno': widget.tableCode,
      if (hasTable) 'personnum': widget.persons.toString(),
      'areaid': tmp?['areaid']?.toString() ?? '',
      'amt': _rd2(_payAmt),
      // 菜品原价（对齐 smdcapp dishesPrice，不含服务费/低消）
      'retailamt': _rd2(_dishAmt),
      'dscamt': _rd2(_disAmt),
      // R34：抹零/减免（payid=06）全部计入 roundamt，实收需剔除
      'roundamt': _rd2(reductionamt),
      // 实收金额不含抹零/减免（对齐 smdcapp CalcUtils.sub2(payment, roundAmt)）
      'payment': AmountCalcUtils.sub(_hasMoney, reductionamt),
      'changeamt': _rd2(changeamt),
      'serviceamt': _rd2(_serviceAmt),
      'lowamt': _rd2(_lowAmt),
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
      // 对齐 smdcapp SaleMasterBean 默认 0：交班统计按 billflag!=2 排除整单退/撤，
      // 落库 NULL 会被该条件误排除
      'billflag': 0,
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
      // 规格名称双向兜底：旧单据/部分接口只回传 spec 或 specname 其一，
      // 报表按不同列取值，结账落库前补齐，避免菜品销售明细表规格列为空
      final String spec = detail['spec']?.toString() ?? '';
      final String specname = detail['specname']?.toString() ?? '';
      if (spec.isEmpty && specname.isNotEmpty) {
        detail['spec'] = specname;
      } else if (specname.isEmpty && spec.isNotEmpty) {
        detail['specname'] = spec;
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
      // 剔除仅用于本地撤销/回退的团购核销内部字段，不上传服务端
      pw.remove('dyverify');
      pw.remove('dy_dealprice');
      pw.remove('dy_productprice');
      pw.remove('dy_oldproductprice');
      pw.remove('dy_ids');
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
        // 对齐 smdcapp getPayWayBean：实付/虚付 = 收款额 - 找零
        // （现金多收时收款额含递付额，找零需扣除；否则服务端三额一致性校验失败）
        final double total = AmountCalcUtils.sub(payamt, changeamt);
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
  /// 条件：商业模式==快餐(1) && 叫号开关 PickupCallSwitch==1 && 无桌台（桌台结账不产生取餐号）
  /// 返回取餐号（对齐 smdcapp TakeSnackcode），无叫号时返回空字符串
  Future<String> _triggerPickupCallIfNeeded(Map<String, dynamic> saleMaster) async {
    try {
      // storeMode 由 putInt 写入，getString 读取会类型强转异常，统一走 StoreModeUtils
      if (!StoreModeUtils.isFastMode()) return ''; // 仅快餐模式
      if (!ParamsSpUtils.getPickupCallSwitch()) return ''; // 叫号开关未开启
      // 桌台结账不需要取餐号（仅快餐无桌台结账叫号）
      if (widget.tableJson != null || widget.tableId.isNotEmpty) return '';
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getTakeSnackCodeBySet,
        <String, dynamic>{
          'saleid': widget.saleid,
          'billno': saleMaster['billno']?.toString() ?? '',
          'billdate': saleMaster['billdate']?.toString() ?? '',
          'amt': _rd2(_payAmt),
          'retailamt': saleMaster['retailamt'] ?? 0,
          'dscamt': _rd2(_disAmt),
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
        return userMap['name']?.toString() ?? userMap['username']?.toString() ?? '';
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
                    // 暂结开关在上、打印单据在下（对齐 smdcapp cv_zj + ll_dy）
                    if (_canZanjie) ...[
                      _buildZanjieSwitchCard(isDark),
                      const SizedBox(height: 10),
                    ],
                    _buildPrintSwitchCard(isDark),
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

  /// 订单明细行（套餐主行后跟缩进明细，对齐 smdcapp OrderDetailsLayout/订单确认页）
  List<Map<String, dynamic>> _orderDetailRows() {
    final List<Map<String, dynamic>> mains = <Map<String, dynamic>>[];
    final Map<String, List<Map<String, dynamic>>> children =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> d in widget.detailList) {
      final String combid = d['combid']?.toString() ?? '';
      final String onlyid = d['onlyid']?.toString() ?? '';
      final bool isChild = (d['combproductid']?.toString() ?? '').isNotEmpty &&
          combid.isNotEmpty &&
          combid != onlyid;
      if (isChild) {
        children.putIfAbsent(combid, () => <Map<String, dynamic>>[]).add(d);
      } else {
        mains.add(d);
      }
    }
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> m in mains) {
      rows.add(m);
      final List<Map<String, dynamic>>? kids =
          children[m['onlyid']?.toString() ?? ''];
      if (kids != null) rows.addAll(kids);
    }
    // 归组失败的明细兜底平铺，避免数据静默丢失
    for (final MapEntry<String, List<Map<String, dynamic>>> e in children.entries) {
      final bool grouped =
          mains.any((Map<String, dynamic> m) => m['onlyid']?.toString() == e.key);
      if (!grouped) rows.addAll(e.value);
    }
    return rows;
  }

  /// 订单明细卡片（对齐 smdcapp OrderDetailsLayout）
  Widget _buildOrderDetailCard(bool isDark) {
    final List<Map<String, dynamic>> rows = _orderDetailRows();
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
          // 菜品列表（最多显示15条）
          ...rows.take(15).map((Map<String, dynamic> item) {
            final String name = item['productname']?.toString() ?? '';
            final double price = _toDouble(item['rrprice']);
            final double qty = _toDouble(item['qty']);
            final double rramt = _toDouble(item['rramt']);
            // 套餐明细分行缩进展示（对齐 smdcapp dishes_item_set_meal_down）
            final bool isChild =
                (item['combproductid']?.toString() ?? '').isNotEmpty &&
                    (item['combid']?.toString() ?? '') !=
                        (item['onlyid']?.toString() ?? '');
            final List<Widget> tags = isChild ? const <Widget>[] : _promoTags(item);
            final Color nameColor = isDark
                ? (isChild ? Colors.white60 : Colors.white70)
                : (isChild ? const Color(0xFF86909C) : const Color(0xFF4E5969));
            return Padding(
              padding: EdgeInsets.only(bottom: 6, left: isChild ? 16 : 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          ...tags.map((Widget t) => WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: t,
                                ),
                              )),
                          TextSpan(
                            text: name,
                            style: TextStyle(
                              fontSize: isChild ? 12 : 13,
                              color: nameColor,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isChild)
                    Text(
                      '×${_formatAmt(qty)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : const Color(0xFF86909C),
                      ),
                    )
                  else ...<Widget>[
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
                ],
              ),
            );
          }),
          if (rows.length > 5)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '...共${rows.length}项',
                style: const TextStyle(fontSize: 12, color: Color(0xFF86909C)),
              ),
            ),
          const Divider(height: 16, color: Color(0xFFF2F3F5)),
          // 价格汇总
          _priceRow('菜品费', _dishAmt, isDark),
          _priceRow('服务费', _serviceAmt, isDark),
          _priceRow('低消', _lowAmt, isDark),
          _priceRow('优惠合计', _disAmt, isDark),
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
                '¥${_formatAmt(_payAmt)}',
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
    // R40：无促销活动权限时不展示活动
    if (!_canViewPromotion || _promotions.isEmpty) {
      return const SizedBox.shrink();
    }
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
                      onPressed: _appliedPromoBillid == p.billid
                          ? null
                          : () => _applyPromotion(p),
                      style: TextButton.styleFrom(
                        foregroundColor: _kBrandRed,
                        disabledForegroundColor: const Color(0xFF86909C),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _appliedPromoBillid == p.billid ? '已应用' : '应用',
                      ),
                    ),
                  ],
                ),
              )),
          if (_promoDisAmt > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '已优惠：¥${_rd2(_promoDisAmt)}',
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
      onTap: () => _onVerifyCoupon(),
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

  /// 团购核销操作（对齐 smdcapp PayDetailsLayout.dyVetify → DyVerifyPopup）
  ///
  /// [payId]/[payName] 为支付方式入口传入的平台（13/meituantuangou/kuaishou）；
  /// 从通用"团购核销"卡片进入时为空，由弹窗内选择平台。
  Future<void> _onVerifyCoupon({String payId = '', String payName = ''}) async {
    final bool memberPay = _salePayWayList
        .any((Map<String, dynamic> e) => e['payid']?.toString() == '02');
    final VerifyCouponResult? result = await VerifyCouponSheet.show(
      context,
      saleid: widget.saleid,
      billno: _generateBillNo(),
      details: widget.detailList,
      dsMoney: _dsMoney,
      memberPay: memberPay,
      payId: payId,
      payName: payName,
    );
    if (result == null || !mounted) return;
    final double deal = _rd2(result.dealAmount);
    final double eligible = _rd2(result.eligibleAmount);
    if (eligible <= 0) return;
    final double diff = _rd2(eligible - deal);
    // 对齐 smdcapp DyVerifyPopup 回调记账：
    // hasMoney += dealprice；dsMoney -= productprice；优惠增加 productprice - dealprice
    setState(() {
      _hasMoney = AmountCalcUtils.add(_hasMoney, deal);
      _dsMoney = AmountCalcUtils.sub(_dsMoney, eligible);
      if (_dsMoney < 0) _dsMoney = 0;
      if (diff > 0) {
        _disAmt = AmountCalcUtils.add(_disAmt, diff);
        _payAmt = AmountCalcUtils.sub(_payAmt, diff);
      }
      _markCouponDetails(result);
    });
    _salePayWayList.add(<String, dynamic>{
      'saleid': widget.saleid,
      'payid': result.payId,
      'payname': result.payName,
      'payamt': deal,
      'rate': 1.0,
      'rramt': deal,
      'changeamt': 0.0,
      'faceamt': deal,
      'voucher': result.voucher,
      'verify_token': result.verifyToken,
      'businesstype': result.businesstype,
      'querytoken': result.onlyId,
      'paystatus': 1,
      // 撤销定位与金额回退（对齐 smdcapp dybeanList + setDyOrMtFlag）
      'dyverify': true,
      'dy_dealprice': deal,
      'dy_productprice': eligible,
      'dy_oldproductprice': result.originalAmount,
      'dy_ids': result.couponIds,
    });
    Toast.show('团购核销抵扣 ¥${_formatAmt(deal)}');
    if (_dsMoney <= 0.005) {
      _dsMoney = 0;
      setState(() {});
      await _submitSaleFlow();
    }
  }

  /// 标记券核销商品（对齐 smdcapp setDyOrMtFlag(dy, true)）：
  /// 命中 ids 的明细打上 douyinflag/querytoken，并按券实付金额分摊 rramt/rrprice
  void _markCouponDetails(VerifyCouponResult result) {
    final List<String> pending = List<String>.from(result.couponIds);
    if (pending.isEmpty) return;
    for (final Map<String, dynamic> d in widget.detailList) {
      if (pending.isEmpty) break;
      if (d['isCouponHx'] == true) continue;
      final String pid = d['productid']?.toString() ?? '';
      final int idx = pending.indexOf(pid);
      if (idx < 0) continue;
      pending.removeAt(idx);
      d['isCouponHx'] = true;
      d['douyinflag'] = 1;
      d['querytoken'] = result.onlyId;
      final double qty = _toDouble(d['qty']);
      final double oldTotal = result.originalAmount;
      final double rramt = oldTotal > 0
          ? _rd2(qty *
              _toDouble(d['sellprice']) /
              oldTotal *
              result.dealAmount)
          : _toDouble(d['rramt']);
      d['rramt'] = rramt;
      if (qty > 0) {
        d['rrprice'] = _rd2(rramt / qty);
        d['dySellprice'] = _rd2(rramt / qty);
      }
      // 套餐子行同步核销标识（对齐 smdcapp itemList 逐条标记）
      if (_toInt(d['combflag']) == 1) {
        final String mainOnlyId = d['onlyid']?.toString() ?? '';
        for (final Map<String, dynamic> child in widget.detailList) {
          if ((child['combid']?.toString() ?? '') != mainOnlyId) continue;
          child['douyinflag'] = 1;
          child['querytoken'] = result.onlyId;
        }
      }
    }
  }

  /// 取消券核销标记（对齐 smdcapp setDyOrMtFlag(dy, false)）
  void _unmarkCouponDetails(String onlyId) {
    if (onlyId.isEmpty) return;
    final Map<String, Map<String, dynamic>> baseByOnlyId =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> b in _baseDetails) {
      baseByOnlyId[b['onlyid']?.toString() ?? ''] = b;
    }
    for (final Map<String, dynamic> d in widget.detailList) {
      if ((d['querytoken']?.toString() ?? '') != onlyId) continue;
      d['isCouponHx'] = false;
      d['douyinflag'] = 0;
      d['querytoken'] = '';
      final Map<String, dynamic>? base =
          baseByOnlyId[d['onlyid']?.toString() ?? ''];
      if (base != null) {
        d['rramt'] = base['rramt'];
        d['rrprice'] = base['rrprice'];
        if (base.containsKey('dySellprice')) {
          d['dySellprice'] = base['dySellprice'];
        }
      }
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
          // 找零（对齐 smdcapp 结账找到零：收款大于应收时展示）
          if (_totalChangeAmt > 0) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  '找零',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF86909C),
                  ),
                ),
                Text(
                  '¥${_formatAmt(_totalChangeAmt)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kBrandRed,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 当前所有收款记录的找零合计
  double get _totalChangeAmt {
    double sum = 0;
    for (final Map<String, dynamic> e in _salePayWayList) {
      sum = AmountCalcUtils.add(sum, _toDouble(e['changeamt']));
    }
    return _rd2(sum);
  }

  /// 开关行卡片（对齐 smdcapp cv_zj / ll_dy：暂结与打印单据各自独立卡片）
  Widget _buildSwitchCard({
    required bool isDark,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232425) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _kBrandRed,
          ),
        ],
      ),
    );
  }

  /// 暂结开关（对齐 smdcapp ll_zj：KQ_ZJ 开启且正餐模式时显示，默认开启）
  Widget _buildZanjieSwitchCard(bool isDark) {
    return _buildSwitchCard(
      isDark: isDark,
      title: '暂结',
      value: _isZanjie,
      onChanged: (bool val) => setState(() => _isZanjie = val),
    );
  }

  /// 打印单据开关（对齐 smdcapp ll_dy：SETTLE_DY 记忆，下次结账沿用）
  Widget _buildPrintSwitchCard(bool isDark) {
    return _buildSwitchCard(
      isDark: isDark,
      title: '打印单据',
      value: _isPrint,
      onChanged: (bool val) {
        setState(() => _isPrint = val);
        SpUtil.putBool(Constant.settleDy, val);
      },
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

  /// 明细行促销标签（对齐 smdcapp DishesTagHelper：specpriceflag 1/2/3/6/7 或
  /// jcmbillid 非空 → 红"促"；discount 1..99 → 绿"N折"）
  List<Widget> _promoTags(Map<String, dynamic> item) {
    final List<Widget> tags = <Widget>[];
    final int specpriceflag = _toInt(item['specpriceflag']);
    if (const <int>[1, 2, 3, 6, 7].contains(specpriceflag) ||
        (item['jcmbillid']?.toString() ?? '').isNotEmpty) {
      tags.add(_tag('促', _kBrandRed));
    }
    final double discount = _toDouble(item['discount']);
    if (discount > 0 && discount < 100) {
      final double zhe = discount / 10;
      final String text = zhe == zhe.roundToDouble()
          ? zhe.toInt().toString()
          : zhe.toStringAsFixed(1);
      tags.add(_tag('$text折', const Color(0xFF00C15A)));
    }
    return tags;
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

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

  int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }
}
