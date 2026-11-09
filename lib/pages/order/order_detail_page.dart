import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/change_dishes_sheet.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/deposit_sheet.dart';
import 'package:flutter_deer/components/dish_operation_dialogs.dart';
import 'package:flutter_deer/components/dish_operation_popup.dart';
import 'package:flutter_deer/components/dish_select_sheet.dart';
import 'package:flutter_deer/components/edit_table_info_sheet.dart';
import 'package:flutter_deer/components/member_search_sheet.dart';
import 'package:flutter_deer/components/table_select_sheet.dart';
import 'package:flutter_deer/db/dao/mp_master_dao.dart';
import 'package:flutter_deer/db/dao/mp_product_or_type_dao.dart';
import 'package:flutter_deer/db/dao/mp_rule_dao.dart';
import 'package:flutter_deer/db/dao/table_type_dao.dart';
import 'package:flutter_deer/db/entity/mp_master_entity.dart';
import 'package:flutter_deer/db/entity/mp_product_or_type_entity.dart';
import 'package:flutter_deer/db/entity/mp_rule_entity.dart';
import 'package:flutter_deer/db/entity/table_type_entity.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/pages/order/promotion_manager.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/amount_calc_utils.dart';
import 'package:flutter_deer/util/auth_limit_utils.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/order_log_utils.dart';
import 'package:flutter_deer/util/order_price_calc.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/print_service.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';
import 'package:flutter_deer/util/table_concurrency_guard.dart';
import 'package:flutter_deer/util/table_data_utils.dart';
import 'package:flutter_deer/util/theme_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/user_helper.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红（对齐 smdcapp red_e13426）
const Color _kBrandRed = Color(0xFFE13426);

/// 订单详情页（对齐 smdcapp OrderDetailActivity）
///
/// 从桌台页点击"待结算/已预结"状态桌台进入，
/// 通过 getSaleTmpDetail(云) / GetTableDetailList(主设备) 获取已落单数据展示。
class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
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

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  /// 加载中
  bool _loading = true;

  /// 订单明细列表（DetailListBean JSON 数组）
  List<Map<String, dynamic>> _detailList = <Map<String, dynamic>>[];

  /// 已在本地取消、待随下次更新上传删除的明细行（deleteflag=1）
  final List<Map<String, dynamic>> _deletedRows = <Map<String, dynamic>>[];

  /// 展示列表（对齐 smdcapp CombHelper.formatCombList：套餐子行挂在主行下，不平级展示）
  List<Map<String, dynamic>> _displayList = <Map<String, dynamic>>[];

  /// 套餐主行 onlyid → 明细子行映射（仅用于展示，不修改 _detailList 原始数据，避免上传时污染 payload）
  Map<String, List<Map<String, dynamic>>> _combChildrenMap =
      <String, List<Map<String, dynamic>>>{};

  /// 明细展开/收起（对齐 smdcapp tvListNum isOpen）
  bool _expanded = false;

  // ═══════ 价格信息（对齐 smdcapp showAllPriceInfo） ═══════
  double _dishAmt = 0; // 菜品费
  double _serviceAmt = 0; // 服务费
  double _lowAmt = 0; // 低消
  double _disAmt = 0; // 优惠合计
  double _payAmt = 0; // 待支付

  // ═══════ 订单信息（对齐 smdcapp initTabInfo） ═══════
  String _openTime = ''; // 开台时间
  String _serverName = ''; // 服务员
  String _lastOrderTime = ''; // 最后下单
  String _operatorName = ''; // 操作人
  int _personNum = 0; // 人数（修改开台信息后随之刷新）
  String _remark = ''; // 备注（修改开台信息后随之刷新）

  /// 当前有效的 saleid（可能从接口响应中更新）
  String _saleid = '';

  /// 锁台事件订阅（R2）
  StreamSubscription<Map<String, dynamic>>? _lockSubscription;

  /// 当前录入的会员（对齐 smdcapp OrderDetailActivity.memberBean）
  VipMember? _member;

  /// 会员同步中（防重复点击）
  bool _memberSyncing = false;

  /// 整单折扣率（对齐 smdcapp changeDiscount: tableInfo.tmp.servicediscount），
  /// 整单打折后随主单/内嵌 tmp 上传，null 表示未操作过沿用桌台 tmp 原值
  double? _servicediscount;

  @override
  void initState() {
    super.initState();
    _saleid = widget.saleid;
    _serverName = widget.serverName;
    // 操作人：当前登录用户（对齐 smdcapp SpUtils.getName()）
    _operatorName = '系统管理员';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        final String name = userMap['name']?.toString() ?? userMap['username']?.toString() ?? '';
        if (name.isNotEmpty) {
          _operatorName = name;
        }
      }
    } catch (_) {}
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    _openTime = tmp?['billdate']?.toString() ?? '';
    // 备注（对齐 smdcapp OrderDetailActivity: remark = tmp.remark）
    _remark = tmp?['remark']?.toString() ?? widget.remark;
    // 服务员兜底取桌台 tmp.servername（对齐 smdcapp initTabInfo: tvTableWaiter = tmp.servername）
    if (_serverName.isEmpty) {
      _serverName = tmp?['servername']?.toString() ?? '';
    }
    // 初始化桌台已有的会员信息（对齐 smdcapp: tableInfo.tmp.vipid/vipname）
    final String existVipid = tmp?['vipid']?.toString() ?? '';
    if (existVipid.isNotEmpty) {
      _member = VipMember(
        vipid: existVipid,
        vipname: tmp?['vipname']?.toString() ?? '',
        vipno: tmp?['vipno']?.toString() ?? '',
        mobile: tmp?['vipmobile']?.toString() ?? '',
      );
      // 对齐 smdcapp CartGoodsModel.getVipData：桌台仅存 vipid/vipname 基础信息，
      // 需按 vipid 调 vip/getList 取完整会员信息（含 prefetype/discount），否则无法计算会员价
      _loadFullMemberInfo(existVipid);
    }
    _lockSubscription = TableConcurrencyGuard.listenLockEvent(
      context: context,
      saleid: _saleid,
      tableName: widget.tableName,
      onExit: _onLockedByOtherExit,
    );
    _loadOrderDetail();
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

  // ═══════════════════ 数据加载 ═══════════════════

  /// 获取已下单数据（对齐 smdcapp OrderModel.getTableInfo）
  ///
  /// 主设备模式：POST /api/table/GetTableDetailList，参数 tablemaster = PCMasterBean JSON（含 tmp）
  /// 云服务模式：POST /YttSvr/app/sale/getSaleTmpDetail，参数 saleid
  Future<void> _loadOrderDetail() async {
    setState(() => _loading = true);
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      Map<String, dynamic> resp;

      if (useMaster) {
        // 对齐 smdcapp：PCMasterBean.tmp = tableInfo.tmp → Gson → map["tablemaster"]
        final Map<String, dynamic> tmp =
            (widget.tableJson?['tmp'] as Map<String, dynamic>?) ??
                <String, dynamic>{};
        final Map<String, dynamic> pcMasterBean = <String, dynamic>{
          'tmp': tmp,
        };
        try {
          resp = await requestForm(
            HttpApi.pcGetTableDetailList,
            <String, dynamic>{'tablemaster': jsonEncode(pcMasterBean)},
            masterDevice: true,
            showError: false,
          );
        } catch (e) {
          // 主设备详情接口异常（如 PC 端 sqlite 报 t_table_type 不存在等）时，
          // 双模式（不限/混合）下回退云服务读取订单详情，避免页面完全不可用；
          // 仅主设备模式无云服务兜底，直接抛出由外层统一提示
          FileLogWriter.instance.writeToFile(
            '主设备获取订单详情失败，回退云服务: $e',
            tag: '订单详情',
          );
          if (ConnectionManager.isMasterOnly) {
            rethrow;
          }
          final String fallbackSaleid =
              tmp['saleid']?.toString() ?? _saleid;
          if (fallbackSaleid.isEmpty) {
            rethrow;
          }
          resp = await requestForm(
            HttpApi.getSaleTmpDetail,
            <String, dynamic>{'saleid': fallbackSaleid},
          );
        }
      } else {
        // 对齐 smdcapp OrderDetailActivity: saleid 优先取桌台 tmp.saleid
        final Map<String, dynamic>? tmpJson =
            widget.tableJson?['tmp'] as Map<String, dynamic>?;
        final String saleid = tmpJson?['saleid']?.toString() ?? _saleid;
        if (saleid.isEmpty) {
          Toast.show('订单信息错误，请返回桌台重新进入');
          return;
        }
        _saleid = saleid;
        resp = await requestForm(
          HttpApi.getSaleTmpDetail,
          <String, dynamic>{'saleid': saleid},
        );
      }

      if (!mounted) {
        return;
      }

      // 解析 data（主设备: Data, 云: data）
      final dynamic data = resp['Data'] ?? resp['data'];
      if (data is Map<String, dynamic>) {
        // 对齐 smdcapp CartGoodsModel.initOrderInfo：明细接口（尤其主设备模式）
        // 可能不返回 combflag/dscflag/mprice1~3 等商品参数，按 productid 从本地商品库回填，
        // 避免套餐主/子行误判导致不展示（对齐 svn r132898），并为会员价/折扣计算提供数据
        final Map<String, Map<String, dynamic>> localFields =
            await OrderRepository.fetchLocalProductPriceFields();
        final dynamic combRawList = data['detailList'];
        if (combRawList is List) {
          for (final dynamic raw in combRawList) {
            if (raw is! Map<String, dynamic>) continue;
            final Map<String, dynamic>? lf =
                localFields[raw['productid']?.toString() ?? ''];
            if (lf != null) {
              raw['combflag'] = lf['combflag'];
              raw['dscflag'] = lf['dscflag'];
              raw['mprice1'] = lf['mprice1'];
              raw['mprice2'] = lf['mprice2'];
              raw['mprice3'] = lf['mprice3'];
              // 对齐 smdcapp initOrderInfo：是否可赠送以本地商品档案为准，
              // 避免旧单据明细缺失/误写 propresentflag 导致整单赠送被误判跳过
              raw['propresentflag'] = lf['presentflag'];
              // 对齐 smdcapp initOrderInfo：typeid 以本地商品为准，保证分类折扣能命中
              final String localTypeid = lf['typeid']?.toString() ?? '';
              if (localTypeid.isNotEmpty) raw['typeid'] = localTypeid;
              // 主设备/部分服务端明细不回传分类名与单位，按本地商品档案补齐，
              // 否则结账 t_sale_detail 落库为空，菜品销售明细表分类/单位列无数据
              final String localTypename = lf['typename']?.toString() ?? '';
              if ((raw['typename']?.toString() ?? '').isEmpty &&
                  localTypename.isNotEmpty) {
                raw['typename'] = localTypename;
              }
              final String localUnit = lf['unit']?.toString() ?? '';
              if ((raw['unit']?.toString() ?? '').isEmpty &&
                  localUnit.isNotEmpty) {
                raw['unit'] = localUnit;
              }
            }
            // 规格名称双向补齐（报表按 spec 或 specname 取值）
            final String spec = raw['spec']?.toString() ?? '';
            final String specname = raw['specname']?.toString() ?? '';
            if (spec.isEmpty && specname.isNotEmpty) {
              raw['spec'] = specname;
            } else if (specname.isEmpty && spec.isNotEmpty) {
              raw['specname'] = spec;
            }
          }
        }
        await _parseOrderData(data);
      } else {
        Toast.show('获取订单详情失败');
      }
    } catch (e) {
      if (mounted) {
        Toast.show('获取订单详情失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 解析 PlacedOrderBean 数据（对齐 smdcapp initObserve + showData + showAllPriceInfo）
  Future<void> _parseOrderData(Map<String, dynamic> data) async {
    // 明细列表
    final dynamic rawList = data['detailList'];
    if (rawList is List) {
      _detailList = rawList
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    // 退菜明细数量纠正为负（对齐 smdcapp：退菜行 qty 恒为负值）。
    // 主设备等数据源可能回传 presentflag=2 但 qty 为正的记录（rramt=-50 而 qty=1），
    // 不纠正会导致退菜金额被按正价重复计入，且回传时污染桌台/其他终端金额
    for (final Map<String, dynamic> b in _detailList) {
      if (_toInt(b['presentflag']) == 2) {
        final double q = _toDouble(b['qty']);
        if (q > 0) {
          b['qty'] = -q;
          b['updateflag'] = 1;
        }
      }
    }
    // 做法/打包金额按 cooklist 重算（对齐 smdcapp CookHelper.calculateOrderedCookAmt）：
    // 服务端 cookaddamt 缺失/为 0 时不重算会导致做法加价、打包费不计入单据金额
    for (final Map<String, dynamic> b in _detailList) {
      _applyCookListAmount(b);
    }
    // 已下单明细补套基础促销（对齐 smdcapp 价格引擎对全单重跑 checkPromotion123：
    // 单据在旧终端/促销数据缺失时以原价落库，进入详情与结账页仍应按后台活动价展示）
    await _applyBasicPromotions();
    // 套餐归组展示：明细子行挂到主行下（对齐 smdcapp CombHelper.formatCombList）
    _buildDisplayList();

    // 更新 saleid
    if (data['saleid'] != null && data['saleid'].toString().isNotEmpty) {
      _saleid = data['saleid'].toString();
    }

    // 服务员
    if (data['servername'] != null && data['servername'].toString().isNotEmpty) {
      _serverName = data['servername'].toString();
    }

    // 开台时间
    if (data['billdate'] != null && data['billdate'].toString().isNotEmpty) {
      _openTime = data['billdate'].toString();
    }

    // 备注（对齐 smdcapp OrderDetailActivity: remark = tmp.remark）
    // 进入页面时的桌台快照可能滞后于其他终端的修改，以详情响应为准刷新
    final dynamic remarkRaw = data['remark'];
    if (remarkRaw != null) {
      _remark = remarkRaw.toString();
    }

    // R45：以详情接口返回的会员为准。桌台列表快照可能滞后，
    // 仅靠进入页面时的 tmp.vipid 会丢失刚录入的会员（积分/余额为 0）
    String respVipid = data['vipid']?.toString() ?? '';
    if (respVipid.isEmpty && data['tmp'] is Map) {
      respVipid =
          (data['tmp'] as Map)['vipid']?.toString() ?? '';
    }
    if (respVipid.isNotEmpty && respVipid != (_member?.vipid ?? '')) {
      _member = VipMember(
        vipid: respVipid,
        vipname: data['vipname']?.toString() ?? '',
        vipno: data['vipno']?.toString() ?? '',
        mobile: data['vipmobile']?.toString() ?? '',
      );
      _loadFullMemberInfo(respVipid);
    }

    // 人数（对齐 smdcapp initTabInfo：tmp.personnum；改开台信息后随之刷新）
    final int personNum = _toInt(data['personnum']);
    if (personNum > 0) _personNum = personNum;

    // 最后下单时间（对齐 smdcapp：取 detailList 中 createtime 最大值）
    if (_detailList.isNotEmpty) {
      String maxTime = '';
      for (final Map<String, dynamic> item in _detailList) {
        final String ct = item['createtime']?.toString() ?? '';
        if (ct.isNotEmpty && ct.compareTo(maxTime) > 0) {
          maxTime = ct;
        }
      }
      _lastOrderTime = maxTime;
    }

    // ═══ 价格计算（对齐 smdcapp Arith.showAllPriceInfo） ═══
    // 服务费/低消：优先取接口返回值（PC模式返回 serviceamt/lowamt）
    _serviceAmt = _toDouble(data['serviceamt'] != null && data['serviceamt'] != 0
        ? data['serviceamt']
        : data['serviceMoney']);
    _lowAmt = _toDouble(data['lowamt'] != null && data['lowamt'] != 0
        ? data['lowamt']
        : data['minSalemoney']);

    // 单品重算（含会员价）+ 金额汇总（对齐 smdcapp ShoppingCartUtil.getDownPrice）
    _applyMemberPricing();

    // 服务端未返回服务费时按桌台类型本地计算（对齐 smdcapp calcTableServiceMoneyV2）；
    // R68：服务费只按开启“收服务费”的菜品金额计算，菜品关闭后不再收费
    {
      final Map<String, dynamic>? tmpRaw =
          widget.tableJson?['tmp'] as Map<String, dynamic>?;
      final String tableTypeId = tmpRaw?['tabletypeid']?.toString() ??
          widget.tableJson?['tabletypeid']?.toString() ??
          '';
      final TableTypeEntity? svcType =
          await AmountCalcUtils.resolveServiceConfig(
        tmp: tmpRaw,
        tableTypeId: tableTypeId,
      );
      final bool hasServiceFlag =
          AmountCalcUtils.hasServiceFeeFlag(_detailList);
      // R68：按消费金额时只统计开启“收服务费”的菜品，关闭的菜品不计入，
      // 全部关闭（如单菜桌台）时基数为 0，服务费为 0（对齐 smdcapp Arith.showAllPriceInfo）
      final double saleMoney = hasServiceFlag
          ? AmountCalcUtils.calcServiceBaseAmount(
              detailList: _detailList,
              serviceamtflag: svcType?.serviceamtflag ?? 1,
            )
          : _round2(_dishAmt - _disAmt);
      final double fee = await AmountCalcUtils.calcTableServiceFee(
        tmp: tmpRaw,
        tableTypeId: tableTypeId,
        saleMoney: saleMoney,
        tableType: svcType,
      );
      // 本地仅实现类型 1-4；5/6 依赖附加费时段表，沿用服务端金额
      final int svcTypeVal = svcType?.servicetype ?? 0;
      final bool locallyCalc =
          hasServiceFlag && svcTypeVal >= 1 && svcTypeVal <= 4;
      if (locallyCalc) {
        // 明细带服务费标志时以本地计算为准（含关闭后归零）
        _serviceAmt = fee;
        _payAmt = _round2(_dishAmt - _disAmt + _serviceAmt + _lowAmt);
      } else if (svcTypeVal >= 1 &&
          svcTypeVal <= 4 &&
          _serviceAmt == 0 &&
          fee > 0) {
        _serviceAmt = fee;
        _payAmt = _round2(_payAmt + fee);
      }
    }

    // R17/R78：低消按菜品 minsaleflag 过滤后本地重算，
    // 关闭“计入低消”的菜品不再计入，同时兼容服务端配置变更
    bool hasMinSaleFlag = false;
    double lowBase = 0;
    for (final Map<String, dynamic> b in _detailList) {
      if (!b.containsKey('minsaleflag')) continue;
      hasMinSaleFlag = true;
      if (_toInt(b['minsaleflag']) == 0) continue;
      if (_toInt(b['presentflag']) == 2) continue;
      if ((b['combproductid']?.toString() ?? '').isNotEmpty) continue;
      final double qty = _toDouble(b['qty']) - _toDouble(b['subqty']);
      if (qty == 0) continue;
      lowBase = _round2(lowBase + _toDouble(b['rramt']));
    }
    if (hasMinSaleFlag) {
      _lowAmt = await _calcLocalLowAmt(lowBase);
      _payAmt = _round2(_dishAmt - _disAmt + _serviceAmt + _lowAmt);
    } else if (_lowAmt == 0) {
      final double saleMoney = _round2(_dishAmt - _disAmt);
      final double localLow = await _calcLocalLowAmt(saleMoney);
      if (localLow > 0) {
        _lowAmt = localLow;
        _payAmt = _round2(_payAmt + localLow);
      }
    }
  }

  /// 计算低消差（对齐 smdcapp GetServiceAmountUtils.getMinSalemoney）
  Future<double> _calcLocalLowAmt(double totalMoney) async {
    try {
      if (StoreModeUtils.getCurrentStoreModel() != StoreModeUtils.storeModelNormal) {
        return 0;
      }
      final Map<String, dynamic>? tmp =
          widget.tableJson?['tmp'] as Map<String, dynamic>?;
      final String tableTypeId = tmp?['tabletypeid']?.toString() ??
          widget.tableJson?['tabletypeid']?.toString() ??
          '';
      final String additionId = tmp?['additionid']?.toString() ?? '';
      final String lookupId = ParamsSpUtils.getOpenTableAmtFlag() == '0'
          ? tableTypeId
          : (additionId.isNotEmpty ? additionId : tableTypeId);
      if (lookupId.isEmpty) return 0;
      final TableTypeEntity? type =
          await TableTypeDao.instance.getByCreateid(lookupId);
      if (type == null) return 0;
      final int personNum = tmp?['personnum'] != null
          ? _toInt(tmp!['personnum'])
          : _personNum;
      return AmountCalcUtils.getMinSalemoneyDiff(
        lowtype: type.lowtype,
        lowamt: type.lowamt,
        personnum: personNum > 0 ? personNum : 1,
        totalmoney: totalMoney,
        servicemoney: _serviceAmt,
        minsalesamtflag: type.minsalesamtflag,
      );
    } catch (_) {
      return 0;
    }
  }

  /// 按 vipid 获取完整会员信息（对齐 smdcapp CartGoodsModel.getVipData → OrderRepository.getVipInfo）
  ///
  /// 桌台 tmp 中的 vipid/vipname 只是基础信息，缺少 prefetype/discount 等定价字段，
  /// 需调 vip/getList 接口按 vipid 查询完整会员信息，否则录入会员后无法计算会员价。
  Future<void> _loadFullMemberInfo(String vipid) async {
    try {
      final VipMember? full = await OrderRepository.fetchVipByVipid(vipid);
      if (!mounted || full == null) return;
      // 请求期间已退出/切换会员时放弃回填
      if ((_member?.vipid ?? '') != vipid) return;
      setState(() {
        _member = full;
        // 订单明细已加载时立即重算会员价
        if (_detailList.isNotEmpty) {
          _applyMemberPricing();
        }
      });
    } catch (_) {}
  }

  /// 单品重算 + 订单金额汇总（对齐 smdcapp ShoppingCartUtil.getDownPrice + Arith.showAllPriceInfo）
  ///
  /// 服务端明细的 rramt 不含录入会员后的会员价，需本地重算：
  /// - 单品 getMemberPrice：prefetype=1 零售价折扣、2/3/4 取 mprice1/2/3，仅当低于现价且 dscflag=1 时生效；
  /// - 单品 getDownMemberPrice：rramt = 现单价 × 数量 + 做法/套餐加减价，退菜/赠送特殊处理；
  /// - 汇总：菜品费 = 总原价，优惠合计 = 总原价 - 总现价，待支付 = 总现价 + 服务费 + 低消。
  void _applyMemberPricing({bool clearMemberMark = false}) {
    final VipMember? member = _member;
    double tempOPrice = 0;
    double tempRRPrice = 0;
    double tempAllDisPrice = 0;

    for (final Map<String, dynamic> b in _detailList) {
      // 暂结商品不重算（对齐 smdcapp getDownPrice）
      if ((b['fornowid']?.toString() ?? '').isNotEmpty) continue;
      // 已落单团购商品不重算
      if (_toInt(b['douyinflag']) == 1 &&
          _toInt(b['id']) != 0 &&
          (b['saleid']?.toString() ?? '').isNotEmpty) {
        continue;
      }

      _calcDownMemberPrice(b, member, clearMemberMark: clearMemberMark);

      // 套餐明细行不统计汇总（做法金额已归入主套餐行）
      if ((b['combproductid']?.toString() ?? '').isNotEmpty &&
          (b['combid']?.toString() ?? '').isNotEmpty) {
        continue;
      }
      final double itemO = _toDouble(b['oldrramt']);
      final double itemR = _toDouble(b['rramt']);
      tempOPrice = _round2(tempOPrice + itemO);
      tempRRPrice = _round2(tempRRPrice + itemR);
      tempAllDisPrice = _round2(tempAllDisPrice + (itemO - itemR));
    }

    // 对齐 smdcapp showAllPriceInfo：菜品费=总原价；优惠合计=tempAllDisPrice；待支付=总现价+服务费+低消
    _dishAmt = tempOPrice;
    _disAmt = tempAllDisPrice;
    _payAmt = _round2(tempRRPrice + _serviceAmt + _lowAmt);
  }

  /// 已下单明细补套基础促销（分类折扣/菜品折扣/特价菜）
  ///
  /// 促销只在加购/确认页生效，已落库单据若由旧终端或促销数据缺失时下单，
  /// 服务端明细不带促销字段；进入详情页时按本地促销表补算，
  /// 保证详情与结账页的行价、「促/N折」标签与后台活动一致。
  Future<void> _applyBasicPromotions() async {
    try {
      await PromotionManager.instance.init();
      final int hit =
          PromotionManager.instance.applyToOrderedDetails(_detailList);
      if (hit > 0) {
        FileLogWriter.instance
            .writeToFile('订单详情补套基础促销 $hit 条', tag: '促销');
      }
    } catch (e) {
      FileLogWriter.instance.writeToFile('订单详情促销补算失败: $e', tag: '促销');
    }
  }

  /// 单品价格重算（移植 smdcapp ShoppingCartUtil.getMemberPrice + getDownMemberPrice）
  void _calcDownMemberPrice(
    Map<String, dynamic> b,
    VipMember? member, {
    bool clearMemberMark = false,
  }) {
    OrderPriceCalc.applyMemberPrice(
      b,
      prefetype: member?.prefetype ?? 0,
      memberDiscount: member?.discount.toDouble() ?? 100,
      clearMemberMark: clearMemberMark,
    );
  }

  /// 满赠赠品门槛复检（bxxpxxflag=4 + cxmbillid）
  ///
  /// 退菜/改价/折扣等操作后，若订单现价合计低于满赠活动档位金额，
  /// 自动取消对应赠品；仅低于更高档位时按档位削减赠品数量。
  /// 取消行转为 deleteflag=1 的待删除行，随本次更新上传。
  Future<bool> _pruneInvalidFullGiftRows() async {
    final List<Map<String, dynamic>> gifts =
        _detailList.where(_isActiveFullGiftRow).toList();
    if (gifts.isEmpty) {
      return false;
    }

    final Set<String> billidSet = <String>{};
    for (final Map<String, dynamic> gift in gifts) {
      final String billid = gift['cxmbillid']?.toString() ?? '';
      if (billid.isNotEmpty) {
        billidSet.add(billid);
      }
    }
    if (billidSet.isEmpty) {
      return false;
    }

    int spid = UserHelper.getSpid();
    if (spid == 0) {
      spid = int.tryParse(UserHelper.getSpidStr()) ?? 0;
    }
    if (spid == 0) {
      FileLogWriter.instance
          .writeToFile('满赠门槛校验跳过: spid=0', tag: '促销');
      return false;
    }

    final List<MpRuleEntity> rules;
    try {
      rules = await MpRuleDao.instance.byBillids(
        billids: billidSet.toList(),
        spid: spid,
      );
    } catch (e) {
      FileLogWriter.instance.writeToFile('满赠门槛校验失败: $e', tag: '促销');
      return false;
    }
    if (rules.isEmpty) {
      FileLogWriter.instance.writeToFile(
          '满赠门槛校验跳过: 未找到活动规则 bills=${billidSet.join(",")}',
          tag: '促销');
      return false;
    }

    final Map<String, List<MpRuleEntity>> rulesByBill =
        <String, List<MpRuleEntity>>{};
    for (final MpRuleEntity rule in rules) {
      if (rule.giveqty <= 0) {
        continue;
      }
      rulesByBill
          .putIfAbsent(rule.billid, () => <MpRuleEntity>[])
          .add(rule);
    }

    // 活动主表（applytype）与参与商品/分类：服务端按活动范围只统计参与菜品
    final List<MPMasterEntity> masters;
    final List<MpProductOrTypeEntity> promoItems;
    try {
      masters = await MPMasterDao.instance.byBillids(
        billids: billidSet.toList(),
        spid: spid,
      );
      promoItems = await MpProductOrTypeDao.instance.byBillids(
        billids: billidSet.toList(),
        spid: spid,
      );
    } catch (e) {
      FileLogWriter.instance
          .writeToFile('满赠门槛校验失败(活动/范围): $e', tag: '促销');
      return false;
    }
    final Map<String, MPMasterEntity> masterByBill =
        <String, MPMasterEntity>{};
    for (final MPMasterEntity master in masters) {
      masterByBill[master.billid] = master;
    }
    final Map<String, Set<String>> conditionTypeIds =
        <String, Set<String>>{};
    final Map<String, Set<String>> conditionProductIds =
        <String, Set<String>>{};
    for (final MpProductOrTypeEntity item in promoItems) {
      if (_toInt(item.saletype) != 1) {
        continue;
      }
      if (item.typeid.isNotEmpty) {
        conditionTypeIds
            .putIfAbsent(item.billid, () => <String>{})
            .add(item.typeid);
      }
      if (item.productid.isNotEmpty) {
        conditionProductIds
            .putIfAbsent(item.billid, () => <String>{})
            .add(item.productid);
      }
    }

    final List<Map<String, dynamic>> removed = <Map<String, dynamic>>[];
    final List<String> removedNames = <String>[];
    bool trimmed = false;

    for (final String billid in billidSet) {
      final List<MpRuleEntity> tiers =
          rulesByBill[billid] ?? const <MpRuleEntity>[];
      if (tiers.isEmpty) {
        continue;
      }
      final MPMasterEntity? master = masterByBill[billid];
      if (master == null || master.billtype != 7) {
        FileLogWriter.instance.writeToFile(
            '满赠门槛校验跳过: 活动$billid 主表缺失或非满赠', tag: '促销');
        continue;
      }
      final Set<String> typeIds =
          conditionTypeIds[billid] ?? const <String>{};
      final Set<String> productIds =
          conditionProductIds[billid] ?? const <String>{};
      final int applytype = master.applytype > 0 ? master.applytype : 0;
      if (applytype > 0 && typeIds.isEmpty && productIds.isEmpty) {
        FileLogWriter.instance.writeToFile(
            '满赠门槛校验跳过: 活动$billid 未找到参与商品/分类', tag: '促销');
        continue;
      }
      final double currentAmt = _calcFullGiftMatchAmt(
        applytype: applytype,
        typeIds: typeIds,
        productIds: productIds,
      );

      // 取当前金额满足的最高档位；无任何档位满足则不允许赠送
      double matchedAmt = -1;
      double allowedQty = 0;
      for (final MpRuleEntity tier in tiers) {
        // amt<=0 视为无金额门槛（始终满足）
        final double tierAmt = tier.amt > 0 ? tier.amt : 0;
        if (tierAmt > currentAmt + 0.005) {
          continue;
        }
        if (tierAmt > matchedAmt + 0.0001) {
          matchedAmt = tierAmt;
          allowedQty = tier.giveqty;
        } else if ((tierAmt - matchedAmt).abs() <= 0.0001 &&
            tier.giveqty > allowedQty) {
          allowedQty = tier.giveqty;
        }
      }

      final List<Map<String, dynamic>> activityGifts = gifts
          .where((Map<String, dynamic> gift) =>
              (gift['cxmbillid']?.toString() ?? '') == billid)
          .toList();
      double givenQty = 0;
      for (final Map<String, dynamic> gift in activityGifts) {
        final double net =
            _toDouble(gift['qty']) - _toDouble(gift['subqty']);
        if (net > 0) {
          givenQty += net;
        }
      }
      if (givenQty <= allowedQty + 0.0001) {
        continue;
      }

      double excess = givenQty - allowedQty;
      for (final Map<String, dynamic> gift in activityGifts.reversed) {
        if (excess <= 0.0001) {
          break;
        }
        final double qty = _toDouble(gift['qty']);
        final double subqty = _toDouble(gift['subqty']);
        final double net = qty - subqty;
        if (net <= 0) {
          continue;
        }
        if (net <= excess + 0.0001) {
          removed.add(gift);
          final String name = gift['productname']?.toString() ?? '';
          if (name.isNotEmpty) {
            removedNames.add(name);
          }
          excess -= net;
        } else {
          final double nextQty = qty - excess;
          gift['qty'] = nextQty > subqty ? nextQty : subqty;
          gift['rramt'] = 0;
          gift['updateflag'] = 1;
          trimmed = true;
          excess = 0;
        }
      }

      FileLogWriter.instance.writeToFile(
          '满赠门槛校验: 活动$billid 当前金额$currentAmt 满足档$matchedAmt '
          '可赠$allowedQty 已赠$givenQty',
          tag: '促销');
    }

    if (removed.isEmpty && !trimmed) {
      return false;
    }

    for (final Map<String, dynamic> row in removed) {
      _detailList.remove(row);
      _deletedRows.add(<String, dynamic>{
        ...row,
        'deleteflag': 1,
        'updateflag': 1,
        'productState': 1,
      });
    }
    _buildDisplayList();
    if (mounted) {
      setState(() {});
    }

    final String giftNames = removedNames.toSet().join('、');
    Toast.show(removed.isNotEmpty
        ? '订单金额已不满足满赠条件，已取消赠品${giftNames.isEmpty ? '' : '：$giftNames'}'
        : '订单金额已不满足满赠条件，赠品数量已调整');
    FileLogWriter.instance.writeToFile(
        '满赠条件不再满足: 取消$removedNames 调整数量$trimmed', tag: '促销');
    return true;
  }

  /// 满赠门槛统计金额（对齐服务端 getSalesPromotionList：
  /// applytype=0 统计全部明细；1/2 仅统计活动参与分类/商品；
  /// 买赠赠品行 bxxpxxflag=1 不计入）
  double _calcFullGiftMatchAmt({
    required int applytype,
    required Set<String> typeIds,
    required Set<String> productIds,
  }) {
    double amt = 0;
    for (final Map<String, dynamic> row in _detailList) {
      if (_toInt(row['deleteflag']) == 1) {
        continue;
      }
      if (_toInt(row['bxxpxxflag']) == 1) {
        continue;
      }
      if (applytype > 0) {
        final String typeid = row['typeid']?.toString() ?? '';
        final String productid = row['productid']?.toString() ?? '';
        if (!typeIds.contains(typeid) && !productIds.contains(productid)) {
          continue;
        }
      }
      amt += _toDouble(row['rramt']);
    }
    return _round2(amt);
  }

  /// 是否为仍有效的满赠赠品行
  bool _isActiveFullGiftRow(Map<String, dynamic> row) {
    if (_toInt(row['bxxpxxflag']) != 4) {
      return false;
    }
    if ((row['cxmbillid']?.toString() ?? '').isEmpty) {
      return false;
    }
    if (_toInt(row['deleteflag']) == 1) {
      return false;
    }
    if (_toInt(row['presentflag']) == 2) {
      return false;
    }
    return _toDouble(row['qty']) - _toDouble(row['subqty']) > 0;
  }

  /// 金额保留两位小数（避免浮点累计误差）
  double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// 主商品数量取整（对齐 smdcapp Arith.roundUpToYuan：有角位则进元，否则原值）
  double _roundUpQty(double v) {
    final int jiao = ((v * 10) % 10).round();
    return jiao > 0 ? v.ceilToDouble() : v;
  }

  /// 按 cooklist 重算做法/打包金额（对齐 smdcapp CookHelper.calculateOrderedCookAmt）
  ///
  /// 已下单明细的做法明细都在 cooklist 中；服务端 cookaddamt 缺失或为 0 时
  /// 不重算会导致做法加价、打包费不计入单据金额（菜品费/待支付偏小）。
  void _applyCookListAmount(Map<String, dynamic> b) {
    final dynamic raw = b['cooklist'] ?? b['cookList'];
    if (raw is! List || raw.isEmpty) return;
    double addAmt = 0; // ptype=2 数量加价
    double ptype1 = 0; // ptype=1 整份加价（含打包）
    double bagAmt = 0; // 打包费
    final List<String> texts = <String>[];
    for (final dynamic e in raw) {
      if (e is! Map) continue;
      final double price = _toDouble(e['price']);
      final int ptype = _toInt(e['ptype']);
      final int qty = _toInt(e['qty']);
      final double total = price * (qty > 0 ? qty : 1);
      final String code = e['code']?.toString() ?? '';
      final String name = e['name']?.toString() ?? '';
      final String text = e['cooktext']?.toString() ?? '';
      if (text.isNotEmpty) texts.add(text);
      if (code == kBagCookCode || name == '打包') bagAmt += total;
      if (ptype == 1) {
        ptype1 += total;
      } else if (ptype == 2) {
        addAmt += total;
      }
    }
    final bool isReturn = _toInt(b['presentflag']) == 2;
    double mainQty = _toDouble(b['qty']);
    if (mainQty < 0) mainQty = -mainQty;
    final double roundedQty = mainQty > 0 ? _roundUpQty(mainQty) : 1;
    double cookAmt = _round2(addAmt * roundedQty + ptype1);
    if (isReturn) cookAmt = -cookAmt;
    b['cookaddamt'] = cookAmt;
    if (bagAmt > 0) {
      b['bagamt'] = _round2(bagAmt);
      b['bagstatus'] = 1;
    }
    if (texts.isNotEmpty && (b['cooktext']?.toString() ?? '').isEmpty) {
      b['cooktext'] = texts.join('、');
    }
  }

  /// 当前时间格式化为 yyyy-MM-dd HH:mm:ss（对齐 smdcapp DateUtils.getTimeStamp）
  String _formatNow() {
    final DateTime dt = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  /// 构建展示列表（对齐 smdcapp CombHelper.formatCombList）：
  ///
  /// - 情况 A：套餐主行（combflag==1），其明细子行（combflag==0 且 combid==主行 onlyid
  ///   且 combproductid==主行 productid）挂到 [_combChildrenMap]，子行不平级展示；
  /// - 情况 B：独立单品（combid 为空且 combflag!=1），正常展示；
  /// - 情况 C：套餐子行，跳过（已挂到主行下）。
  void _buildDisplayList() {
    // 1. 预处理：子商品按 combid 分组（套餐主行 combid==自身onlyid 不算子行，
    // 对齐 CombHelper：主商品 combid == onlyid）
    final Map<String, List<Map<String, dynamic>>> childrenByParent =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> e in _detailList) {
      final String combid = e['combid']?.toString() ?? '';
      final String onlyid = e['onlyid']?.toString() ?? '';
      if (_toInt(e['combflag']) != 1 && combid.isNotEmpty && combid != onlyid) {
        childrenByParent
            .putIfAbsent(combid, () => <Map<String, dynamic>>[])
            .add(e);
      }
    }
    // 2. 遍历挑选套餐主体与独立单品
    _combChildrenMap = <String, List<Map<String, dynamic>>>{};
    final List<Map<String, dynamic>> newList = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> item in _detailList) {
      final String combid = item['combid']?.toString() ?? '';
      final String onlyid = item['onlyid']?.toString() ?? '';
      if (_toInt(item['combflag']) == 1 ||
          (combid.isNotEmpty && combid == onlyid)) {
        final String productid = item['productid']?.toString() ?? '';
        final List<Map<String, dynamic>> children =
            (childrenByParent[onlyid] ?? const <Map<String, dynamic>>[])
                .where((Map<String, dynamic> c) {
                  final String cpid = c['combproductid']?.toString() ?? '';
                  return cpid.isEmpty || cpid == productid;
                }).toList()
              ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
                  (a['createtime']?.toString() ?? '')
                      .compareTo(b['createtime']?.toString() ?? ''));
        if (children.isNotEmpty) {
          _combChildrenMap[onlyid] = children;
        }
        // 与 smdcapp 差异：无子行的套餐主行仍保留展示（避免整行丢失）
        newList.add(item);
      } else if (combid.isEmpty) {
        newList.add(item);
      }
      // 情况 C：套餐子行跳过
    }
    _displayList = newList;
  }

  // ═══════════════════ 按钮逻辑 ═══════════════════

  /// 加菜（对齐 smdcapp tvAddDishes → toDishesHomeActivity）
  void _onAddDishes() {
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final int tablestatus = _toInt(tmp?['tablestatus']);
    if (tablestatus < 2) {
      Toast.show('订单信息错误，请回到桌台重新进入');
      return;
    }
    NavigatorUtils.push(
      context,
      Routes.orderPage,
      arguments: <String, dynamic>{
        'tableId': widget.tableId,
        'tableName': widget.tableName,
        'tableCode': widget.tableCode,
        'persons': widget.persons,
        'serverId': widget.serverId,
        'serverName': widget.serverName,
        'remark': _remark,
        'saleid': _saleid,
        'tableJson': widget.tableJson,
      },
    );
  }

  /// 去结账（对齐 smdcapp tvPay → SettleActivity）
  Future<void> _onSettle() async {
    if (!PermissionUtils.check(PermissionUtils.appCheckout, '结账')) return;
    if (_detailList.isEmpty) {
      Toast.show('结账信息为空');
      return;
    }
    // R45：存在未称重商品时不允许进入结算（对齐 OrderDetailActivity isReweigh 校验）
    if (ParamsSpUtils.isReweigh()) {
      final bool hasUnweighed = _detailList.any((Map<String, dynamic> d) =>
          _toInt(d['weighflag']) == 1 &&
          (d['combproductid']?.toString() ?? '').isEmpty &&
          _toDouble(d['confirmqty']) == 0);
      if (hasUnweighed) {
        Toast.show('本单有未称重商品，请确认称重');
        return;
      }
    }
    NavigatorUtils.push(
      context,
      Routes.settlePage,
      arguments: <String, dynamic>{
        'tableName': widget.tableName,
        'persons': widget.persons,
        'tableId': widget.tableId,
        'tableCode': widget.tableCode,
        'saleid': _saleid,
        'serverId': widget.serverId,
        'serverName': widget.serverName,
        'remark': _remark,
        'tableJson': widget.tableJson,
        'detailList': _detailList,
        'dishAmt': _dishAmt,
        'serviceAmt': _serviceAmt,
        'lowAmt': _lowAmt,
        'disAmt': _disAmt,
        'payAmt': _payAmt,
        'memberVipid': _member?.vipid ?? '',
        'memberVipname': _member?.vipname ?? '',
        'memberVipno': _member?.vipno ?? '',
        'memberMobile': _member?.mobile ?? '',
        'memberOverflag': _member?.overflag ?? 0,
        'memberOvermoney': _member?.overmoney ?? 0,
        'memberArrearages': _member?.arrearages ?? 0,
        'memberNowmoney': _member?.nowmoney ?? 0,
        'memberPrefetype': _member?.prefetype ?? 0,
        'memberDiscount': _member?.discount ?? 100,
      },
    );
  }

  // ═══════════════════ 会员录入（对齐 smdcapp OrderDetailActivity: tvManageTwo + onActivityResult + upMember） ═══════════════════

  /// 标题栏“会员”按钮点击（对齐 smdcapp tvManageTwo.onClick → MemberActivity）
  Future<void> _onMemberTap() async {
    if (!PermissionUtils.check(PermissionUtils.appMemberLogin, '会员操作')) return;
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
    // 未录入会员：打开搜索弹窗
    final VipMember? member = await MemberSearchSheet.show(context);
    if (member == null || !mounted) return;
    _loginMember(member);
  }

  /// 录入会员（对齐 smdcapp onActivityResult → upMember(true, ...)）
  Future<void> _loginMember(VipMember member) async {
    final bool synced = await _syncMemberToServer(
      vipid: member.vipid,
      vipno: member.vipno,
      vipname: member.vipname,
      vipmobile: member.mobile,
    );
    if (!mounted || !synced) return;
    setState(() {
      _member = member;
      // 立即按会员价重算，避免等待详情接口期间仍显示原价
      if (_detailList.isNotEmpty) {
        _applyMemberPricing(clearMemberMark: true);
      }
    });
    await _postMemberPriceChange();
  }

  /// 退出会员（对齐 smdcapp upMember(false)）
  Future<void> _logoutMember() async {
    final bool synced = await _syncMemberToServer(
      vipid: '',
      vipno: '',
      vipname: '',
      vipmobile: '',
    );
    if (!mounted || !synced) return;
    setState(() {
      _member = null;
      if (_detailList.isNotEmpty) {
        _applyMemberPricing(clearMemberMark: true);
      }
    });
    await _postMemberPriceChange();
  }

  /// 会员变更后回传订单（对齐 smdcapp upMember onResult → postInfo）
  ///
  /// updateMasterTmp 只写会员字段，桌台金额仍在服务端保持原价；
  /// 需再上传按会员价重算后的主单与明细，桌台卡片 tmp.amt 才会更新。
  Future<void> _postMemberPriceChange() async {
    if (_detailList.isEmpty) {
      _loadOrderDetail();
      return;
    }
    await _postOrderUpdate();
  }

  /// 同步会员信息到后端桌台（对齐 smdcapp OrderModel.updateMasterTmp）
  Future<bool> _syncMemberToServer({
    required String vipid,
    required String vipno,
    required String vipname,
    required String vipmobile,
  }) async {
    if (_memberSyncing) return false;
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String saleid = tmp?['saleid']?.toString() ?? _saleid;
    if (saleid.isEmpty) {
      Toast.show('订单信息错误，无法同步会员');
      return false;
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
        remark: _remark,
        personnum: tmp?['personnum']?.toString() ?? widget.persons.toString(),
        serverid: widget.serverId.isNotEmpty
            ? widget.serverId
            : (tmp?['serverid']?.toString() ?? ''),
        servername: widget.serverName.isNotEmpty
            ? widget.serverName
            : (tmp?['servername']?.toString() ?? ''),
        vipid: vipid,
        vipno: vipno,
        vipname: vipname,
        vipmobile: vipmobile,
        masterDevice: ConnectionManager.pcAlive,
        tableJson: widget.tableJson,
      );
      // 同步成功后更新本地桌台快照并通知桌台页刷新（R45：返回再进入不丢会员）
      if (tmp != null) {
        tmp['vipid'] = vipid;
        tmp['vipno'] = vipno;
        tmp['vipname'] = vipname;
        tmp['vipmobile'] = vipmobile;
      }
      if (vipid.isEmpty) {
        _member = null;
      }
      TableEventBus.fireTableChanged();
      return true;
    } catch (_) {
      Toast.show('同步会员信息失败');
      return false;
    } finally {
      if (mounted) {
        setState(() => _memberSyncing = false);
      }
    }
  }

  /// 操作弹窗（对齐 smdcapp tvOperation → DetailOperationPopup）
  void _onOperation() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailOperationSheet(
        onAction: _handleOperation,
      ),
    );
  }

  /// 处理操作菜单回调（对齐 smdcapp showOperation when(type)）
  void _handleOperation(String type) {
    NavigatorUtils.goBack(context);
    _logAction('整单操作:$type');
    switch (type) {
      case '消台':
        if (!PermissionUtils.check(PermissionUtils.appCancelTable, '消台')) return;
        _cancelTable();
        break;
      case '锁台':
        _lockTable();
        break;
      case '催菜':
        if (!PermissionUtils.check(PermissionUtils.appUrge, '催菜')) return;
        _allUrgeDish();
        break;
      case '起菜':
        if (!PermissionUtils.check(PermissionUtils.appStartDish, '起菜')) return;
        _allStartDish();
        break;
      case '退菜':
        if (!PermissionUtils.check(PermissionUtils.appRefund, '退菜')) return;
        _allReturnDish();
        break;
      case '整单折扣':
        if (!PermissionUtils.check(PermissionUtils.appTotalDiscount, '整单折扣')) return;
        _allDiscount();
        break;
      case '赠送':
        if (!PermissionUtils.check(PermissionUtils.appGive, '赠送')) return;
        _allGive();
        break;
      case '撤单':
        if (!PermissionUtils.check(PermissionUtils.appCancelOrder, '撤单')) return;
        _withdrawOrder();
        break;
      case '转台':
        if (!PermissionUtils.check(PermissionUtils.appTransferTable, '转台')) return;
        _changeTable();
        break;
      case '并台/拆台':
        if (!PermissionUtils.check(PermissionUtils.appMergeTable, '并台/拆台')) return;
        _uniTable();
        break;
      case '转菜':
        if (!PermissionUtils.check(PermissionUtils.appTransferDish, '转菜')) return;
        _transferToTable();
        break;
      case '暂结记录':
        _showZanjieRecords();
        break;
      case '服务员':
        _selectWaiter();
        break;
      case '交押金':
        _showDepositPay();
        break;
      case '押金记录':
        _showDepositRecords();
        break;
      case '预打':
        if (!PermissionUtils.check(PermissionUtils.appPrePrint, '预打')) return;
        _prePrint();
        break;
      case '补打客单':
        _reprintKD();
        break;
      default:
        Toast.show('$type功能开发中');
    }
  }

  /// 消台（对齐 smdcapp DetailOperationPopup.xt → TableCancelBottomDialog）
  Future<void> _cancelTable() async {
    // 对齐 smdcapp DetailOperationPopup.xt：仅 tablestatus==1（待下单）可消台，
    // 否则 Toast "不能消台"。订单详情页桌台为待结算/已预结，云/主设备消台接口
    // 不处理该状态（返回成功但不生效），因此前端需拦截不发请求
    final dynamic tmpRaw = widget.tableJson?['tmp'];
    final int tablestatus = tmpRaw is Map
        ? _toInt(tmpRaw['tablestatus'])
        : 0;
    if (tablestatus != 1) {
      Toast.show('不能消台');
      return;
    }
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定要消台吗？消台后订单数据将被清除',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      if (useMaster) {
        // 对齐 smdcapp TableDao.cancelTable: PCTableHttpUtil.cancelTable(JSON.toJSONString(tableInfoBean))
        // tablemaster 传完整桌台 Bean（deepMerge 默认结构 + 字段白名单过滤，
        // 与 table_operation_dialog 入口一致），直传原始 JSON 会被服务端静默忽略
        final Map<String, dynamic> tableBean = TableDataUtils.buildFullTableBean(
          rawJson: widget.tableJson,
          fallback: <String, dynamic>{
            'tableid': widget.tableId,
            'name': widget.tableName,
            'code': widget.tableCode,
          },
        );
        await requestForm(
          HttpApi.pcCancelTable,
          <String, dynamic>{'tablemaster': jsonEncode(tableBean)},
          masterDevice: true,
        );
      } else {
        // 对齐 smdcapp TableApi: cancelTable(@Field("tableid") tableid)
        await requestForm(HttpApi.cancelTable, <String, dynamic>{
          'tableid': widget.tableId,
        });
      }
      if (!mounted) {
        return;
      }
      Toast.show('消台成功');
      TableEventBus.fireTableChanged();
      NavigatorUtils.goBack(context);
    } catch (_) {
      if (mounted) {
        Toast.show('消台失败，请重试');
      }
    }
  }

  /// 锁台（对齐 smdcapp DetailOperationPopup.st → lockFlagTable lockflag=1）
  Future<void> _lockTable() async {
    try {
      final bool ok = await TableConcurrencyGuard.postTableLock(
        tableId: widget.tableId,
        lock: true,
        tableJson: widget.tableJson,
        tableName: widget.tableName,
        autoflag: 0,
      );
      if (!ok) throw StateError('锁台失败');
      if (!mounted) {
        return;
      }
      Toast.show('锁台成功');
      TableEventBus.fireTableChanged();
      NavigatorUtils.goBack(context);
    } catch (_) {
      if (mounted) {
        Toast.show('锁台失败，请重试');
      }
    }
  }

  // ═══════════════════ 菜品操作（对齐 smdcapp OrderDetailActivity postInfo + 单品操作） ═══════════════════

  /// 上传修改后的订单数据（对齐 smdcapp postInfo）
  ///
  /// [printtype] 打印类型：-1不打印, 4退菜单, 5催菜单, 6挂起单, 7起菜单, 8预打单
  /// 返回是否上传成功
  Future<bool> _postOrderUpdate({String printtype = '-1'}) async {
    if (_detailList.isEmpty) {
      Toast.show('订单明细为空');
      return false;
    }
    try {
      final bool useMaster = ConnectionManager.pcAlive;

      for (final Map<String, dynamic> item in _detailList) {
        item['productState'] = 1;
      }

      // 重新计算价格（对齐 smdcapp Arith.showAllPriceInfo：含会员价重算）
      _applyMemberPricing();

      // 退货/改价等操作后，订单现价合计低于满赠门槛时自动取消赠品
      if (await _pruneInvalidFullGiftRows()) {
        _applyMemberPricing();
      }

      // 本次上传明细：当前明细 + 待删除行（deleteflag=1，服务端按 onlyid 删除）
      final List<Map<String, dynamic>> uploadDetailList =
          <Map<String, dynamic>>[..._detailList, ..._deletedRows];

      // 对齐 smdcapp getMasterBean/getMasterBeanPC：组装主单
      final Map<String, dynamic> master = _buildOrderMaster();

      // 称重标识（对齐 smdcapp postInfo）：0 无称重菜 / 1 存在未称重 / 2 全部已称
      int containweight = 0;
      final List<Map<String, dynamic>> weighRows = _detailList
          .where((Map<String, dynamic> b) =>
              _toInt(b['weighflag']) == 1 &&
              (b['combproductid']?.toString() ?? '').isEmpty)
          .toList();
      if (weighRows.isNotEmpty) {
        containweight = weighRows.any(
                (Map<String, dynamic> b) => _toDouble(b['confirmqty']) == 0)
            ? 1
            : 2;
      }
      master['containweight'] = containweight;

      if (useMaster) {
        // 对齐 smdcapp getMasterBeanPC：PC 模式 master 内嵌 tmp 并同步金额字段
        _attachPcTmp(master);
        // 对齐 smdcapp postInfo PC 分支：
        //   masterBean.tmp.sendprintflag = if (printtype != "-1") "1" else "-1"
        //   masterBean.tmp.printcpdflag = 1
        // PC 端按键值 + 明细标记（isPrint/hasurgeflag 等）决定出票
        final Map<String, dynamic> pcTmp =
            master['tmp'] as Map<String, dynamic>;
        pcTmp['printcpdflag'] = 1;
        // R43/R47：挂起单/起菜单同时出出品分单（受确认页出品分单开关控制）
        pcTmp['printcpdflag2'] =
            SpUtil.getBool('ENABLE_CPD_BRANCH') == true ? 1 : 0;
        pcTmp['sendprintflag'] = printtype != '-1' ? '1' : '-1';
        pcTmp['containweight'] = containweight;
        // 主设备模式（对齐 smdcapp PCMasterBean）
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMaster': master,
          'detailList': uploadDetailList,
          'isUnionFlag': false,
        };
        await OrderRepository.placeOrder(
          master: '',
          detail: '',
          masterDevice: true,
          pcMasterJson: jsonEncode(pcMaster),
        );
      } else {
        // 云服务模式
        await OrderRepository.placeOrder(
          master: jsonEncode(master),
          detail: jsonEncode(uploadDetailList),
          printType: printtype,
          printAllType: printtype != '-1' ? 1 : -1,
          masterDevice: false,
        );
        // 对齐 smdcapp postTableInfo 云服务回调：sendPrint(createPrintInfo(p))
        if (printtype != '-1') {
          final String cloudBillno = master['billno']?.toString() ?? '';
          // 服务端按 saleid+opertype 重建单据（退菜/催菜/起菜/挂起/预打/转菜）
          await PrintService.instance.cloudReprint(
            saleid: _saleid,
            billno: cloudBillno,
            opertype: printtype,
          );
          // R43/R47：挂起单/起菜单补发出品分单
          if ((printtype == '6' || printtype == '7') &&
              SpUtil.getBool('ENABLE_CPD_BRANCH') == true) {
            await PrintService.instance.cloudReprint(
              saleid: _saleid,
              billno: cloudBillno,
              opertype: '23',
            );
          }
        }
      }

      // 上传成功：待删除行已完成删除，清空墓碑避免重复提交
      _deletedRows.clear();

      if (!mounted) return true;
      // 刷新订单数据
      _loadOrderDetail();
      TableEventBus.fireTableChanged();
      return true;
    } catch (e) {
      if (mounted) Toast.show('操作失败：$e');
      return false;
    }
  }

  /// 组装主单 MasterBean（对齐 smdcapp getMasterBean/getMasterBeanPC 公共字段）
  ///
  /// 金额取当前页面汇总（_payAmt/_dishAmt/_disAmt/_serviceAmt/_lowAmt），
  /// 调用前应先执行 [_applyMemberPricing]。
  /// 覆写项用于对齐 smdcapp 撤单/转菜等场景 getMasterBeanPC(…, 0.0, 0.0, 0.0, "") 的传参。
  Map<String, dynamic> _buildOrderMaster({
    double? amtOverride,
    double? serviceamtOverride,
    double? addamtOverride,
    String? remarkOverride,
  }) {
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;

    // 对齐 smdcapp: 计算 hangflag、addamt
    int hangflag = 0;
    double addamt = 0;
    for (final Map<String, dynamic> item in _detailList) {
      if (_toInt(item['hangflag']) == 1) hangflag = 1;
      if ((item['combproductid']?.toString() ?? '').isEmpty) {
        addamt += _toDouble(item['cookaddamt']);
      }
    }
    if (addamtOverride != null) addamt = addamtOverride;

    // sid/spid 从 store JSON 解析（SP 独立键为 putInt 写入，getString 会类型强转异常）
    final String sid = UserHelper.getSidStr();
    final String spid = UserHelper.getSpidStr();

    // 对齐 smdcapp getMasterBean/getMasterBeanPC：tablestatus 等为主单必备字段，
    // 缺失时服务端报“tablestatus属性不存在”
    final String nowStr = _formatNow();
    final String localbillno = tmp?['localbillno']?.toString() ?? '';
    final int tmpBilltype = _toInt(tmp?['billtype']);
    final String remark = remarkOverride ?? _remark;
    return <String, dynamic>{
      'saleid': _saleid,
      'tableid': widget.tableId.isNotEmpty ? widget.tableId : (tmp?['tableid']?.toString() ?? ''),
      'tablename': widget.tableName,
      'tablecode': widget.tableCode.isNotEmpty ? widget.tableCode : (tmp?['tablecode']?.toString() ?? ''),
      'tablestatus': (tmp?['tablestatus'] ?? 2).toString(),
      'billdate': tmp?['billdate']?.toString() ?? _openTime,
      'id': _toInt(tmp?['id']),
      'billtype': tmpBilltype == 0 ? 7 : tmpBilltype,
      'lastbilltype': 7,
      'billno': localbillno,
      'amt': _round2(amtOverride ?? _payAmt),
      'retailamt': _round2(_dishAmt),
      'dscamt': _round2(_disAmt),
      'serviceamt': _round2(serviceamtOverride ?? _serviceAmt),
      'lowamt': _round2(_lowAmt),
      'addamt': _round2(addamt),
      'roundamt': 0,
      'payment': _round2(amtOverride ?? _payAmt),
      'hangflag': hangflag,
      'status': 1,
      'version': 180,
      'androidoperflag': 1,
      'cashid': UserHelper.getUserid(),
      'updatetime': nowStr,
      'tabletypeid': tmp?['tabletypeid']?.toString() ?? '',
      // 对齐 smdcapp MasterBean/tmp：servicediscount 为 double 类型
      'servicediscount':
          _servicediscount ?? _toDouble(tmp?['servicediscount']),
      'sid': sid,
      'spid': spid,
      'remark': remark,
      'personnum': tmp?['personnum']?.toString() ?? widget.persons.toString(),
      'serverid': widget.serverId.isNotEmpty ? widget.serverId : (tmp?['serverid']?.toString() ?? ''),
      'servername': _serverName,
      'vipid': _member?.vipid ?? (tmp?['vipid']?.toString() ?? ''),
      'vipno': _member?.vipno ?? (tmp?['vipno']?.toString() ?? ''),
      'vipname': _member?.vipname ?? (tmp?['vipname']?.toString() ?? ''),
      'vipmobile': _member?.mobile ?? (tmp?['vipmobile']?.toString() ?? ''),
      'localbillno': localbillno,
    };
  }

  /// 主设备模式：master 内嵌 tmp 并同步金额字段（对齐 smdcapp getMasterBeanPC 的 tmp 处理）
  void _attachPcTmp(Map<String, dynamic> master) {
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String localbillno = master['localbillno']?.toString() ?? '';
    final Map<String, dynamic> tmpCopy =
        Map<String, dynamic>.from(tmp ?? <String, dynamic>{});
    tmpCopy['amt'] = master['amt'];
    tmpCopy['serviceamt'] = master['serviceamt'];
    tmpCopy['retailamt'] = master['retailamt'];
    tmpCopy['addamt'] = master['addamt'];
    tmpCopy['lowamt'] = master['lowamt'];
    tmpCopy['dscamt'] = master['dscamt'];
    tmpCopy['servicediscount'] = master['servicediscount'];
    tmpCopy['remark'] = master['remark'];
    tmpCopy['lastbilltype'] = 7;
    tmpCopy['updatetime'] = master['updatetime'];
    tmpCopy['billno'] = localbillno;
    tmpCopy['localbillno'] = localbillno;
    // 桌台快照可能早于本次会员录入，tmp 以当前会员为准，
    // 避免订单操作上传时用旧快照把主设备上的会员清空
    tmpCopy['vipid'] = master['vipid'];
    tmpCopy['vipno'] = master['vipno'];
    tmpCopy['vipname'] = master['vipname'];
    tmpCopy['vipmobile'] = master['vipmobile'];
    master['tmp'] = tmpCopy;
  }

  /// 记录敏感操作日志并上传（R24，对齐 smdcapp saveOrderLog）
  void _logAction(String memo) {
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    OrderLogUtils.instance.saveOrderLog(
      saleid: _saleid,
      billno: tmp?['localbillno']?.toString() ?? '',
      memo: memo,
      isUpload: true,
    );
  }

  /// 单品操作分发（对齐 smdcapp OrderDetailActivity.openAction when(result)）
  void _handleSingleItemAction(String action, Map<String, dynamic> item) {
    _logAction('单品$action:${item['productname'] ?? ''}');
    switch (action) {
      case '打折':
        if (!PermissionUtils.check(PermissionUtils.appDishDiscount, '打折')) return;
        _discountSingleDish(item);
        break;
      case '退菜':
        if (!PermissionUtils.check(PermissionUtils.appRefund, '退菜')) return;
        _returnSingleDish(item);
        break;
      case '催菜':
        if (!PermissionUtils.check(PermissionUtils.appUrge, '催菜')) return;
        _urgeSingleDish(item);
        break;
      case '起菜':
        if (!PermissionUtils.check(PermissionUtils.appStartDish, '起菜')) return;
        _startSingleDish(item);
        break;
      case '改价':
        if (!PermissionUtils.check(PermissionUtils.appChangePrice, '改价')) return;
        _changePriceSingleDish(item);
        break;
      case '赠送':
        if (!PermissionUtils.check(PermissionUtils.appGive, '赠送')) return;
        // 已赠送时菜单显示"取消赠送"，动作类型同为赠送（对齐 smdcapp presentflag 分支）
        if (_toInt(item['presentflag']) == 1) {
          _cancelGiveSingleDish(item);
        } else {
          _giveSingleDish(item);
        }
        break;
      case '转菜':
        if (!PermissionUtils.check(PermissionUtils.appTransferDish, '转菜')) return;
        _transferSingleDish(item);
        break;
      case '称重':
        _reweighDishes();
        break;
      case '划菜':
        if (!PermissionUtils.check(PermissionUtils.appServeDish, '划菜')) return;
        // 已划菜时菜单显示"取消划菜"，动作同为划菜（按 cutflag 切换）
        _cutSingleDish(item);
        break;
      case '服务员':
        _waiterSingleDish(item);
        break;
      default:
        Toast.show('$action功能开发中');
    }
  }

  /// 单品服务员修改（对齐 smdcapp CartActionHandler.handleWaiterClick）
  Future<void> _waiterSingleDish(Map<String, dynamic> item) async {
    final Waiter? waiter = await DishWaiterSheet.show(
      context,
      dishName: item['productname']?.toString() ?? '',
      currentWaiter: item['salesname']?.toString() ?? '',
    );
    if (waiter == null || !mounted) return;
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    _detailList[idx]['salesid'] = waiter.userid;
    _detailList[idx]['salesname'] = waiter.name;
    _detailList[idx]['updateflag'] = 1;
    Toast.show('服务员已修改');
    _postOrderUpdate();
  }

  // ─────── 单品退菜（对齐 smdcapp showReturnPop + ReturnDishesPopup） ───────

  Future<void> _returnSingleDish(Map<String, dynamic> item) async {
    final double qty = _toDouble(item['qty']);
    final double subqty = _toDouble(item['subqty']);
    final int weighflag = _toInt(item['weighflag']);
    final int presentflag = _toInt(item['presentflag']);

    if (qty - subqty <= 0) {
      Toast.show('当前菜品已退完');
      return;
    }
    if (presentflag == 1) {
      Toast.show('赠送商品不能退菜');
      return;
    }

    // 获取退菜原因列表（对齐 smdcapp PublicHelper.getReason("02")）
    List<String> reasons = <String>[];
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getReasonList,
        <String, dynamic>{'typeid': '02', 'page': '1', 'pagesize': '50'},
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          reasons = list
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> e) => e['value']?.toString() ?? '')
              .where((String s) => s.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}

    if (!mounted) return;
    final double maxQty = weighflag == 1 ? qty : qty - subqty;
    final ReturnDishResult? result = await DishReturnSheet.show(
      context,
      dishName: item['productname']?.toString() ?? '',
      maxQty: maxQty,
      isWeigh: weighflag == 1,
      reasons: reasons,
    );
    if (result == null || !mounted) return;

    // 对齐 smdcapp: 创建退菜明细（负数量 + presentflag=2）
    final Map<String, dynamic> returnItem = Map<String, dynamic>.from(item);
    final double returnNum = weighflag == 1 ? qty : result.num;
    returnItem['qty'] = -returnNum;
    returnItem['subqty'] = 0;
    returnItem['presentflag'] = 2;
    returnItem['returnonlyid'] = item['onlyid']?.toString() ?? '';
    returnItem['kdsreturnonlyid'] = item['onlyid']?.toString() ?? '';
    returnItem['opertype'] = 2;
    returnItem['operremark'] = result.remark;
    returnItem['remark'] = result.remark;
    _markReturnRow(returnItem, result.prnretflag);
    returnItem['seq'] = _nextDetailSeq();
    returnItem['updateflag'] = 1;
    returnItem['id'] = 0;
    returnItem['onlyid'] = _generateOnlyId();
    returnItem['createtime'] = DateTime.now().toString().substring(0, 23);
    returnItem['refundtime'] = DateTime.now().toString().substring(0, 23);
    returnItem['operid'] = SpUtil.getString('userid') ?? '';
    returnItem['opername'] = _operatorName;
    returnItem['opertime'] = DateTime.now().toString().substring(0, 19);
    // 对齐 smdcapp: rramt = rrprice * num + cookaddamt
    final double rrprice = _toDouble(item['rrprice']);
    final double cookaddamt = _toDouble(item['cookaddamt']);
    returnItem['rramt'] = -(rrprice * returnNum + cookaddamt);
    returnItem['cookaddamt'] = -cookaddamt;
    returnItem['operamt'] = returnItem['rramt'];
    // 赠送商品退菜时价格为0
    if (presentflag == 1) {
      returnItem['rrprice'] = 0;
      returnItem['rramt'] = 0;
      returnItem['operamt'] = 0;
    }

    // 更新原商品的 subqty
    final int idx = _detailList.indexOf(item);
    if (idx >= 0) {
      _detailList[idx]['subqty'] = subqty + returnNum;
      _detailList[idx]['updateflag'] = 1;
      // 原行非新增菜品，清掉打印标记，否则会出出品单/出品分单或补催菜单
      _clearOriginalRowPrintFlags(_detailList[idx]);
    }
    _detailList.add(returnItem);

    Toast.show('退菜成功');
    _postOrderUpdate(printtype: result.prnretflag == 1 ? '4' : '-1');
  }

  // ─────── 单品催菜（对齐 smdcapp OperationPopup.NAME_CC） ───────

  void _urgeSingleDish(Map<String, dynamic> item) {
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    _markUrged(_detailList[idx], _nextDetailSeq());
    Toast.show('催菜成功');
    _postOrderUpdate(printtype: '5');
  }

  /// 标记催菜（对齐 smdcapp ACTION_REMIND_DISH：isPrint/hasurgeflag=99 + seq 提升为最新）
  ///
  /// 套餐主行需同步全部明细，否则催菜单只出套餐主行、不带明细。
  void _markUrged(Map<String, dynamic> item, int seq) {
    item['urgeflag'] = 1;
    item['callflag'] = 0;
    item['isPrint'] = true;
    item['hasurgeflag'] = 99;
    item['updateflag'] = 1;
    item['seq'] = seq;
    if (_toInt(item['combflag']) == 1) {
      final String parentId = item['onlyid']?.toString() ?? '';
      for (final Map<String, dynamic> child in _detailList) {
        if ((child['combproductid']?.toString() ?? '').isEmpty) continue;
        if (child['combid']?.toString() != parentId) continue;
        child['urgeflag'] = 1;
        child['callflag'] = 0;
        child['isPrint'] = true;
        child['hasurgeflag'] = 99;
        child['updateflag'] = 1;
        child['seq'] = seq;
      }
    }
  }

  /// 退菜行（新建负数量行）标记（对齐 smdcapp ReturnDishesPopup2 + showReturnPop 回调）
  ///
  /// ⚠️ 主设备（PC打印）出票时会优先采信明细里的「显示串/金额缓存」字段：
  /// 我们的退菜行是从被退原行整份复制出来的，若带上原行的 `Displayqty="1"`、
  /// `DisplayPriceQty`、`sellamt`、`rramtorg` 等正值缓存，主设备会把退菜行落库成
  /// `qty=+N`（实测：麻婆豆腐退 1 份 → 主设备存 qty=1、rramt=-15），
  /// 进而按"出品"渲染出一张**出品单**（R17/R30 现场复现，2026-09-19）。
  /// smdcapp 的退菜行本身不带这些字段，所以它能正常出退菜单。
  void _markReturnRow(Map<String, dynamic> item, int prnretflag) {
    item['prnretflag'] = prnretflag;
    // 对齐 smdcapp ReturnDishesPopup2 新行：isPrint=false（主设备/服务端均按 qty 与标记自行推导出票）
    item['isPrint'] = false;
    item['urgeflag'] = 0;
    item['hasurgeflag'] = 0;
    item['callflag'] = 0;
    item['hascallflag'] = 0;
    item['hangflag'] = 0;
    item['hashangflag'] = 0;
    // 清掉从原行复制来的显示串/金额缓存，交由主设备按新的负数量重新生成
    for (final String key in _staleRowCacheKeys) {
      item.remove(key);
    }
  }

  /// 主设备按 qty 重新推演的显示串与金额缓存字段
  /// （退菜行必须清除，smdcapp 报文里本来就不带这些字段）
  static const List<String> _staleRowCacheKeys = <String>[
    'Displayqty',
    'DisplayPriceQty',
    'Displaysubqty',
    'subqtyText',
    'sellamt',
    'sellamtorg',
    'rramtorg',
    'ramt',
    'oldqty',
    'oldrramt',
    'newcreatetime',
    'showallreturnflag',
    'weightconfirmqty',
    'scanbarcodetype',
    'scanelecbarcode',
  ];

  /// 清掉「原商品行」的打印标记（对齐 smdcapp showReturnPop：原行只更新 subqty，
  /// 不再携带出票标记，否则退菜后会补出出品单/出品分单或催菜单）。
  ///
  /// 只用于被退的原商品行；新建的退菜行必须走 [_markReturnRow] 统一处理。
  void _clearOriginalRowPrintFlags(Map<String, dynamic> item) {
    item['isPrint'] = false;
    item['urgeflag'] = 0;
    item['hasurgeflag'] = 0;
    item['callflag'] = 0;
    item['hascallflag'] = 0;
    item['hangflag'] = 0;
    item['hashangflag'] = 0;
  }

  // ─────── 单品起菜（对齐 smdcapp OperationPopup.NAME_QC） ───────

  void _startSingleDish(Map<String, dynamic> item) {
    if (_toInt(item['hangflag']) != 1) {
      Toast.show('商品未${ParamsSpUtils.getHangUpName()}，不能起菜');
      return;
    }
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    _detailList[idx]['callflag'] = 1;
    _detailList[idx]['hangflag'] = 0;
    // 对齐 smdcapp ACTION_START_DISH：isPrint/hascallflag=99 标记 + seq 提升为最新
    // （打印过滤条件：qty>0 && callflag==1 && hascallflag==99 && info.seq==bean.seq && isPrint）
    _detailList[idx]['isPrint'] = true;
    _detailList[idx]['hascallflag'] = 99;
    _detailList[idx]['updateflag'] = 1;
    _detailList[idx]['seq'] = _nextDetailSeq();
    Toast.show('起菜成功');
    _postOrderUpdate(printtype: '7');
  }

  /// 打印标识序号（对齐 smdcapp placedOrderBean.seq）
  ///
  /// 初始化 = 已加载明细最大 seq，之后每次操作 +1 赋给操作项；
  /// 打印服务按 info.seq == bean.seq（明细最大 seq）过滤本次操作单据，
  /// 未提升 seq 会导致催菜单/起菜单/退菜单/挂起单不出票。
  /// 单调递增：即使刷新后服务端回传旧 seq，也不会与上次操作重号。
  int _detailSeq = 0;

  int _nextDetailSeq() {
    for (final Map<String, dynamic> d in _detailList) {
      final int s = _toInt(d['seq']);
      if (s > _detailSeq) _detailSeq = s;
    }
    _detailSeq += 1;
    return _detailSeq;
  }

  // ─────── 单品改价（对齐 smdcapp ChangePricePopup2） ───────

  Future<void> _changePriceSingleDish(Map<String, dynamic> item) async {
    if (_toDouble(item['subqty']) > 0) {
      Toast.show('该商品已有退菜记录，不能改价');
      return;
    }
    if (_toInt(item['presentflag']) == 1) {
      Toast.show('该商品已赠送，不能改价');
      return;
    }
    final String? input = await InputDialog.show(
      context,
      title: '改价 - ${item['productname']?.toString() ?? ''}',
      hintText: '输入新单价',
      initialValue: _toDouble(item['rrprice']).toString(),
    );
    if (input == null || !mounted) return;
    final double newPrice = double.tryParse(input) ?? 0;
    if (newPrice <= 0) {
      Toast.show('请输入有效价格');
      return;
    }
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    final double qty = _toDouble(item['qty']);
    _detailList[idx]['rrprice'] = newPrice;
    // 对齐 smdcapp showChangePricePop：改价同步更新 sellprice，避免重算时被原价覆盖
    _detailList[idx]['sellprice'] = newPrice;
    _detailList[idx]['rramt'] = newPrice * qty + _toDouble(item['cookaddamt']);
    // 改价即最终价，清除折扣/促销标记，避免改价后再次被打折（R14）
    _detailList[idx]['discount'] = 100;
    _detailList[idx]['specpriceflag'] = 0;
    _detailList[idx]['jcmbillid'] = '';
    // R46：Web 订单明细报表按 opertype 显示【改】标识
    _detailList[idx]['opertype'] = 5;
    _detailList[idx]['updateflag'] = 1;
    Toast.show('改价成功');
    _postOrderUpdate();
  }

  // ─────── 单品赠送（对齐 smdcapp GiveNumPopup） ───────

  Future<void> _giveSingleDish(Map<String, dynamic> item) async {
    if (_toDouble(item['subqty']) > 0) {
      Toast.show('退菜商品不能赠送');
      return;
    }
    // R62：菜品档案未开启可赠送时禁止赠送
    if (item.containsKey('propresentflag') &&
        _toInt(item['propresentflag']) == 0 &&
        _toInt(item['presentflag']) != 1) {
      Toast.show('该菜品不允许赠送');
      return;
    }
    final double qty = _toDouble(item['qty']);
    final bool isWeigh = _toInt(item['weighflag']) == 1;
    // 对齐 smdcapp handleGiveaway → GiftReasonValidator：需选择赠送数量与赠送原因
    final GiveResult? give = await DishGiveSheet.show(
      context,
      dishName: item['productname']?.toString() ?? '',
      maxNum: qty,
      isGive: _toInt(item['presentflag']) == 1,
    );
    if (give == null || !mounted) return;
    final double giveNum = isWeigh ? qty : give.num;
    // R44：赠送金额超出角色免密额度时要求经理授权
    final bool allowed = await AuthLimitUtils.ensureGiftAmt(
      context,
      dishName: item['productname']?.toString() ?? '',
      amt: _toDouble(item['rrprice']) * giveNum,
    );
    if (!allowed || !mounted) return;

    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    final Map<String, dynamic> target = _detailList[idx];
    if (giveNum >= qty) {
      target['presentflag'] = 1;
      target['rrprice'] = 0;
      target['rramt'] = 0;
      target['remark'] = give.remark;
      // 敏感操作备注：Web 菜品敏感操作明细的「原因」列取 operremark
      target['operremark'] = give.remark;
      // R46：Web 订单明细报表按 opertype 显示【赠】标识
      target['opertype'] = 3;
      target['updateflag'] = 1;
    } else {
      // 部分赠送：原行扣减数量，拆出一条赠送行（对齐 smdcapp ProductBusiness.processGiveaway）
      final Map<String, dynamic> giveItem = Map<String, dynamic>.from(target);
      target['qty'] = qty - giveNum;
      target['updateflag'] = 1;
      giveItem['qty'] = giveNum;
      giveItem['subqty'] = 0;
      giveItem['presentflag'] = 1;
      giveItem['rrprice'] = 0;
      giveItem['rramt'] = 0;
      giveItem['opertype'] = 3;
      giveItem['remark'] = give.remark;
      giveItem['operremark'] = give.remark;
      giveItem['isPrint'] = true;
      giveItem['seq'] = _nextDetailSeq();
      giveItem['updateflag'] = 1;
      giveItem['id'] = 0;
      giveItem['onlyid'] = _generateOnlyId();
      giveItem['createtime'] = DateTime.now().toString().substring(0, 23);
      _detailList.insert(idx + 1, giveItem);
    }
    // R26：手动赠送后满赠条件变化，取消原满赠赠品，避免继续保留赠送状态
    final int beforeGift = _detailList.length;
    _detailList.removeWhere((Map<String, dynamic> d) =>
        _toInt(d['bxxpxxflag']) == 4);
    if (_detailList.length != beforeGift) {
      Toast.show('满赠条件已变化，满赠赠品已取消');
    } else {
      Toast.show('赠送成功');
    }
    _postOrderUpdate();
  }

  // ─────── 单品取消赠送（已赠送菜品的逆向操作） ───────

  Future<void> _cancelGiveSingleDish(Map<String, dynamic> item) async {
    if (_toInt(item['presentflag']) != 1) {
      Toast.show('该商品未赠送');
      return;
    }
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定取消「${item['productname']}」的赠送吗？',
    );
    if (!confirmed || !mounted) return;
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    _detailList[idx]['presentflag'] = 0;
    _detailList[idx]['opertype'] = 0;
    _detailList[idx]['rrprice'] = _toDouble(item['sellprice']);
    _calcDownMemberPrice(_detailList[idx], _member);
    _detailList[idx]['updateflag'] = 1;
    Toast.show('取消赠送成功');
    _postOrderUpdate();
  }

  // ─────── 单品打折（对齐 smdcapp showDiscountPopup(pos) → changeDiscount） ───────

  Future<void> _discountSingleDish(Map<String, dynamic> item) async {
    final int tpdishflag = _toInt(item['tpdishflag']);
    // 前置校验与提示对齐 smdcapp OrderDetailActivity.ACTION_DISCOUNT 分支
    if (_toInt(item['dscflag']) == 0 && tpdishflag != 1) {
      Toast.show('当前菜品不能打折');
      return;
    }
    if (_toDouble(item['subqty']) > 0) {
      Toast.show('退菜商品不能打折');
      return;
    }
    if (_toInt(item['presentflag']) == 1) {
      Toast.show('赠送商品不能打折');
      return;
    }
    if (tpdishflag == 1 && _toInt(item['tpdscflag']) != 1) {
      Toast.show('当前临时菜不可以打折');
      return;
    }
    if (_toInt(item['douyinflag']) == 1) {
      Toast.show('当前菜品不能打折');
      return;
    }

    final DiscountResult? result = await DishDiscountSheet.show(
      context,
      dishName: item['productname']?.toString() ?? '',
      currentDiscount:
          _toDouble(item['discount']) == 0 ? 100 : _toDouble(item['discount']),
    );
    if (result == null || !mounted) return;
    // R44：折扣超出角色免密额度时要求经理授权
    if (!await AuthLimitUtils.ensureSingleDiscount(
      context,
      dishName: item['productname']?.toString() ?? '',
      discount: result.discount,
    )) {
      return;
    }
    if (!mounted) return;
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    if (!_applyDishDiscount(_detailList[idx], result.discount, result.remark)) {
      Toast.show('当前菜品不能打折');
      return;
    }
    setState(() {});
    Toast.show('打折成功');
    _postOrderUpdate();
  }

  // ─────── 二次称重（对齐 smdcapp reWeigh + ReweighPopup） ───────

  Future<void> _reweighDishes() async {
    // 可称重行：称重菜 + 已开启称重二次确认 + 未退完无退菜记录 + 非套餐明细
    // （对齐 smdcapp: weighflag==1 && isReweigh() && presentflag!=2 && subqty==0 && combproductid 为空）
    final List<Map<String, dynamic>> weighList = _detailList
        .where((Map<String, dynamic> i) =>
            _toInt(i['weighflag']) == 1 &&
            ParamsSpUtils.isReweigh() &&
            _toInt(i['presentflag']) != 2 &&
            _toDouble(i['subqty']) == 0 &&
            (i['combproductid']?.toString() ?? '').isEmpty)
        .toList();
    if (weighList.isEmpty) {
      Toast.show('没有可称重的商品');
      return;
    }
    // 未称的排前面（对齐 smdcapp ReweighPopup: list.sortBy { it.confirmqty }）
    weighList.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
        _toDouble(a['confirmqty']).compareTo(_toDouble(b['confirmqty'])));

    final List<ReweighResult>? results = await ReweighSheet.show(
      context,
      entries: weighList
          .map((Map<String, dynamic> i) => ReweighEntry(
                name: i['productname']?.toString() ?? '',
                price: _toDouble(i['rrprice']),
                amount: _toDouble(i['rramt']),
                qty: _toDouble(i['qty']),
                confirmed: _toDouble(i['confirmqty']) > 0,
              ))
          .toList(),
    );
    if (results == null || !mounted) return;

    // 对齐 smdcapp ReweighPopup 回调：qty/confirmqty 置为录入重量后整单上传
    for (final ReweighResult r in results) {
      if (r.index < 0 || r.index >= weighList.length) continue;
      final Map<String, dynamic> target = weighList[r.index];
      final int idx = _detailList.indexOf(target);
      if (idx < 0) continue;
      _detailList[idx]['confirmqty'] = r.weight;
      _detailList[idx]['qty'] = r.weight;
      _detailList[idx]['updateflag'] = 1;
    }
    setState(() {});
    Toast.show('称重成功');
    _postOrderUpdate();
  }

  // ─────── 单品划菜（对齐 smdcapp CartActionHandler 划菜 cutflag 切换） ───────

  void _cutSingleDish(Map<String, dynamic> item) {
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    final int currentCut = _toInt(item['cutflag']);
    final int newCut = currentCut == 1 ? 0 : 1;
    final String onlyid = item['onlyid']?.toString() ?? '';
    _detailList[idx]['cutflag'] = newCut;
    _detailList[idx]['updateflag'] = 1;

    // 对齐 smdcapp handleServeDish 套餐联动：
    // 主行 → 同步全部明细子行；明细子行 → 全部划菜后同步主行
    if (_toInt(item['combflag']) == 1 && onlyid.isNotEmpty) {
      for (final Map<String, dynamic> it in _detailList) {
        if ((it['combid']?.toString() ?? '') == onlyid &&
            (it['combproductid']?.toString() ?? '').isNotEmpty) {
          it['cutflag'] = newCut;
          it['updateflag'] = 1;
        }
      }
    } else if ((item['combproductid']?.toString() ?? '').isNotEmpty &&
        (item['combid']?.toString() ?? '').isNotEmpty) {
      final String parentId = item['combid'].toString();
      final List<Map<String, dynamic>> siblings = _detailList
          .where((Map<String, dynamic> it) =>
              (it['combid']?.toString() ?? '') == parentId &&
              (it['combproductid']?.toString() ?? '').isNotEmpty)
          .toList();
      final bool allServed = siblings.isNotEmpty &&
          siblings.every((Map<String, dynamic> it) =>
              _toInt(it['cutflag']) == 1);
      for (final Map<String, dynamic> it in _detailList) {
        if ((it['onlyid']?.toString() ?? '') == parentId &&
            _toInt(it['combflag']) == 1) {
          final int target = allServed ? 1 : 0;
          if (_toInt(it['cutflag']) != target) {
            it['cutflag'] = target;
            it['updateflag'] = 1;
          }
        }
      }
    }

    Toast.show(newCut == 1 ? '划菜成功' : '取消划菜');
    _postOrderUpdate();
  }

  // ─────── 整单催菜（对齐 smdcapp OperationPopup pos=-1 → 先选菜品再执行） ───────

  Future<void> _allUrgeDish() async {
    final List<Map<String, dynamic>>? picked = await _pickDishes(
      title: '整单催菜',
      enabled: (Map<String, dynamic> i) {
        final double qty = _toDouble(i['qty']);
        return qty > 0 && qty - _toDouble(i['subqty']) > 0;
      },
      disabledHint: '已退完',
    );
    if (picked == null || !mounted) return;
    // 对齐 smdcapp OperationPlacedActivity.CC：本次操作项统一提升 seq 为最新
    final int newSeq = _nextDetailSeq();
    for (final Map<String, dynamic> item in picked) {
      _markUrged(item, newSeq);
    }
    Toast.show('催菜成功');
    _postOrderUpdate(printtype: '5');
  }

  // ─────── 整单起菜（对齐 smdcapp updateAllDetailSign callflag=1, hangflag=0） ───────

  Future<void> _allStartDish() async {
    final List<Map<String, dynamic>>? picked = await _pickDishes(
      title: '整单起菜',
      enabled: (Map<String, dynamic> i) => _toInt(i['hangflag']) == 1,
      disabledHint: '未${ParamsSpUtils.getHangUpName()}',
    );
    if (picked == null || !mounted) return;
    bool hasItem = false;
    // 对齐 smdcapp OperationPlacedActivity.QC：本次操作项统一提升 seq 为最新
    final int newSeq = _nextDetailSeq();
    for (final Map<String, dynamic> item in picked) {
      if (_toInt(item['hangflag']) == 1) {
        item['callflag'] = 1;
        item['hangflag'] = 0;
        item['isPrint'] = true;
        item['hascallflag'] = 99;
        item['updateflag'] = 1;
        item['seq'] = newSeq;
        hasItem = true;
      }
    }
    if (!hasItem) {
      Toast.show('没有${ParamsSpUtils.getHangUpName()}的商品，无需起菜');
      return;
    }
    Toast.show('起菜成功');
    _postOrderUpdate(printtype: '7');
  }

  /// 整单操作前的菜品勾选（对齐 smdcapp 整桌操作需先选择菜品）
  ///
  /// 返回选中的明细行；null 表示取消。
  Future<List<Map<String, dynamic>>?> _pickDishes({
    required String title,
    bool Function(Map<String, dynamic> item)? enabled,
    String disabledHint = '',
  }) async {
    final List<Map<String, dynamic>> candidates = _detailList
        .where((Map<String, dynamic> i) =>
            _toInt(i['presentflag']) != 2 &&
            (i['combproductid']?.toString() ?? '').isEmpty)
        .toList();
    if (candidates.isEmpty) {
      Toast.show('没有可操作的菜品');
      return null;
    }
    final List<DishSelectEntry> entries = candidates.map((Map<String, dynamic> i) {
      final bool ok = enabled?.call(i) ?? true;
      return DishSelectEntry(
        key: i['onlyid']?.toString() ?? '',
        name: _dishLabel(i),
        subtitle: ok ? _dishSubtitle(i) : disabledHint,
        disabled: !ok,
      );
    }).toList();
    final List<String>? picked =
        await DishSelectSheet.show(context, title: title, entries: entries);
    if (picked == null || picked.isEmpty) return null;
    final Set<String> keys = picked.toSet();
    return candidates
        .where((Map<String, dynamic> i) => keys.contains(i['onlyid']?.toString() ?? ''))
        .toList();
  }

  /// 菜品展示名（名称(规格)，对齐 smdcapp 明细行文案）
  String _dishLabel(Map<String, dynamic> i) {
    final String name = i['productname']?.toString() ?? '';
    final String spec = i['spec']?.toString() ?? '';
    return spec.isEmpty ? name : '$name($spec)';
  }

  /// 菜品副标题（已退数量/做法/备注）
  String _dishSubtitle(Map<String, dynamic> i) {
    final List<String> parts = <String>[];
    final double subqty = _toDouble(i['subqty']);
    if (subqty > 0) parts.add('已退${subqty.toStringAsFixed(subqty == subqty.roundToDouble() ? 0 : 1)}');
    final String cook = i['cooktext']?.toString() ?? '';
    if (cook.isNotEmpty) parts.add('做法:$cook');
    final String remark = i['remark']?.toString() ?? '';
    if (remark.isNotEmpty) parts.add('备注:$remark');
    return parts.join(' | ');
  }

  // ─────── 整单退菜（对齐 smdcapp ReturnDishesPopup pos=-1 → 先选菜品再执行） ───────

  Future<void> _allReturnDish() async {
    final List<Map<String, dynamic>>? picked = await _pickDishes(
      title: '整单退菜',
      enabled: (Map<String, dynamic> i) {
        final double qty = _toDouble(i['qty']);
        final double subqty = _toDouble(i['subqty']);
        return qty - subqty > 0 && _toInt(i['presentflag']) != 1;
      },
      disabledHint: '不可退',
    );
    if (picked == null || !mounted) return;

    // 获取退菜原因
    List<String> reasons = <String>[];
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getReasonList,
        <String, dynamic>{'typeid': '02', 'page': '1', 'pagesize': '50'},
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          reasons = list
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> e) => e['value']?.toString() ?? '')
              .where((String s) => s.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}

    if (!mounted) return;
    final ReturnDishResult? result = await DishReturnSheet.show(
      context,
      dishName: '整单退菜',
      maxQty: 0,
      isWeigh: true,
      reasons: reasons,
    );
    if (result == null || !mounted) return;

    // 对齐 smdcapp: 整单退菜时给每个选中商品创建退菜明细
    final List<Map<String, dynamic>> returnItems = <Map<String, dynamic>>[];
    // 对齐 smdcapp OperationPlacedActivity.ZC2：本次操作项统一提升 seq 为最新
    final int newSeq = _nextDetailSeq();
    for (final Map<String, dynamic> item in picked) {
      final double qty = _toDouble(item['qty']);
      final double subqty = _toDouble(item['subqty']);
      if (qty - subqty <= 0) continue;

      final Map<String, dynamic> returnItem = Map<String, dynamic>.from(item);
      final double returnNum = qty - subqty;
      returnItem['qty'] = -returnNum;
      returnItem['subqty'] = 0;
      returnItem['presentflag'] = 2;
      returnItem['returnonlyid'] = item['onlyid']?.toString() ?? '';
      returnItem['opertype'] = 2;
      returnItem['operremark'] = result.remark;
      returnItem['remark'] = result.remark;
      _markReturnRow(returnItem, result.prnretflag);
      returnItem['seq'] = newSeq;
      returnItem['updateflag'] = 1;
      returnItem['id'] = 0;
      returnItem['onlyid'] = _generateOnlyId();
      returnItem['createtime'] = DateTime.now().toString().substring(0, 23);
      returnItem['refundtime'] = DateTime.now().toString().substring(0, 23);
      returnItem['operid'] = SpUtil.getString('userid') ?? '';
      returnItem['opername'] = _operatorName;
      final double rrprice = _toDouble(item['rrprice']);
      final double cookaddamt = _toDouble(item['cookaddamt']);
      returnItem['rramt'] = -(rrprice * returnNum + cookaddamt);
      returnItem['cookaddamt'] = -cookaddamt;
      returnItem['operamt'] = returnItem['rramt'];
      returnItems.add(returnItem);

      item['subqty'] = qty;
      item['updateflag'] = 1;
      // 原行非新增菜品，清掉打印标记，否则会出出品单/出品分单或补催菜单
      _clearOriginalRowPrintFlags(item);
    }

    if (returnItems.isEmpty) {
      Toast.show('没有可退的菜品');
      return;
    }
    _detailList.addAll(returnItems);
    Toast.show('整单退菜成功');
    _postOrderUpdate(printtype: result.prnretflag == 1 ? '4' : '-1');
  }

  // ─────── 整单折扣（对齐 smdcapp FastPrometionDiscountPopup） ───────

  Future<void> _allDiscount() async {
    final DiscountResult? result = await DishDiscountSheet.show(
      context,
      dishName: '整单折扣',
    );
    if (result == null || !mounted) return;

    final double discount = result.discount;
    if (discount <= 0 || discount > 100) {
      Toast.show('请输入有效折扣');
      return;
    }
    // R22：已参加满赠活动（含赠品）时不可再整单折扣
    final bool hasFullGift = _detailList
        .any((Map<String, dynamic> i) => _toInt(i['bxxpxxflag']) == 4);
    if (hasFullGift) {
      Toast.show('已参加满赠活动，不能再操作整单折扣');
      return;
    }
    // R44：超出角色整单折扣免密额度时要求经理授权
    if (!await AuthLimitUtils.ensureOrderDiscount(context, discount: discount)) {
      return;
    }
    if (!mounted) return;
    // 对齐 smdcapp changeDiscount(pos=-1)：逐行 updataDis，跳过不可打折/已退/已赠/团购行
    int skipped = 0;
    for (final Map<String, dynamic> item in _detailList) {
      final bool applied = _applyDishDiscount(item, discount, result.remark);
      if (!applied &&
          _toInt(item['dscflag']) == 0 &&
          _toInt(item['tpdishflag']) == 0 &&
          _toInt(item['presentflag']) == 0 &&
          _toInt(item['subqty']) == 0 &&
          _toInt(item['douyinflag']) != 1) {
        skipped++;
      }
    }
    // 对齐 smdcapp changeDiscount：整单折扣率同步 tmp.servicediscount 随主单上传
    _servicediscount = discount;
    // 对齐 smdcapp refresh()：先刷新本地 UI 再 postInfo，避免上传异常时页面无变化
    setState(() {});
    // R60：不可打折菜品被跳过时给出提示
    Toast.show(skipped > 0 ? '整单折扣成功，$skipped道不可打折菜品已跳过' : '整单折扣成功');
    _postOrderUpdate();
  }

  /// 应用手工折扣（对齐 smdcapp updataDis）
  ///
  /// 单品打折与整单打折共用：>99 视为不打折恢复原价并清手工折扣标记，
  /// 否则按折扣重算现价/金额并标记 specpriceflag=4/opertype=4（手工折扣）。
  /// 不可打折/已退/已赠/团购行返回 false，不做修改。
  bool _applyDishDiscount(
      Map<String, dynamic> item, double discount, String remark) {
    final int presentflag = _toInt(item['presentflag']);
    final int tpdishflag = _toInt(item['tpdishflag']);
    final bool skipDsc = (_toInt(item['dscflag']) == 0 && tpdishflag != 1) ||
        (tpdishflag == 1 && _toInt(item['tpdscflag']) == 0);
    if (skipDsc ||
        _toDouble(item['subqty']) > 0 ||
        presentflag == 2 ||
        presentflag == 1 ||
        _toInt(item['douyinflag']) == 1) {
      return false;
    }
    final double sellprice = _toDouble(item['sellprice']);
    final double qty = _toDouble(item['qty']);
    if (discount > 99) {
      item['discount'] = 100;
      item['rrprice'] = sellprice;
      item['rramt'] = _round2(sellprice * qty);
      item['specpriceflag'] = 0;
      item['opertype'] = 1;
      item['operamt'] = item['rramt'];
    } else {
      final double rrprice = _round2(sellprice * discount / 100);
      final double rramt = _round2(rrprice * qty);
      item['discount'] = discount;
      item['rrprice'] = rrprice;
      item['rramt'] = rramt;
      item['specpriceflag'] = 4;
      item['opertype'] = 4;
      item['operamt'] = _round2(sellprice * qty - rramt);
    }
    item['operremark'] = remark;
    item['opertime'] = _formatNow();
    item['updateflag'] = 1;
    _calcDownMemberPrice(item, _member);
    return true;
  }

  // ─────── 整单赠送（对齐 smdcapp showGiveAllPop → SingleGivePopup） ───────

  /// 菜品是否可参与整单赠送（对齐 smdcapp OperationPlacedActivity2 赠送勾选禁用条件：
  /// 档案不可赠送 / 已赠送 / 促销赠品 / 超出单次赠送金额上限 / 已退完）
  bool _canGiveDish(Map<String, dynamic> item) {
    if (_toInt(item['propresentflag']) != 1) return false;
    if (_toInt(item['presentflag']) == 1) return false;
    final int bxxpxxflag = _toInt(item['bxxpxxflag']);
    if (bxxpxxflag == 1 || bxxpxxflag == 2 || bxxpxxflag == 6) return false;
    if (AuthLimitUtils.exceedGiftAmt(
        _toDouble(item['sellprice']) * _toDouble(item['qty']))) {
      return false;
    }
    return _toDouble(item['qty']) - _toDouble(item['subqty']) > 0;
  }

  Future<void> _allGive() async {
    final List<Map<String, dynamic>>? picked = await _pickDishes(
      title: '整单赠送',
      enabled: _canGiveDish,
      disabledHint: '不可赠送',
    );
    if (picked == null || !mounted) return;
    // 对齐 smdcapp：选菜后先弹出赠送原因（SingleGivePopup），再执行整单赠送
    final GiveResult? give = await DishGiveSheet.show(
      context,
      dishName: '整单赠送',
      maxNum: 0,
      showNum: false,
    );
    if (give == null || !mounted) return;
    final String operTime = _formatNow();
    for (final Map<String, dynamic> item in picked) {
      item['presentflag'] = 1;
      item['rrprice'] = 0;
      item['rramt'] = 0;
      // R46：整单赠送同样标记赠送操作，供 Web 报表显示【赠】
      item['opertype'] = 3;
      item['operremark'] = give.remark;
      item['opertime'] = operTime;
      item['updateflag'] = 1;
    }
    Toast.show('整单赠送成功');
    _postOrderUpdate();
  }

  // ─────── 撤单（对齐 smdcapp WithdrawDialog） ───────

  Future<void> _withdrawOrder() async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定要撤单吗？撤单后数据不可恢复，请谨慎操作！',
    );
    if (!confirmed || !mounted) return;
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      final Map<String, dynamic>? tmp =
          widget.tableJson?['tmp'] as Map<String, dynamic>?;
      if (useMaster) {
        // 对齐 smdcapp TableDao.withdrawTable(pcAlive分支):
        // masterBean = getMasterBeanPC(tableInfo, downPrice, 0.0, 0.0, 0.0, "")
        //   → amt=已落单现价合计(不含服务费/低消), serviceamt/addamt=0
        // tmp.cdflag=1、tmp.printcpdflag=0(printflag="-1"不打印)、tmp.remark=撤单备注，
        // POST /api/table/TableWithdraw @Field("tablemaster") = MasterBean JSON（内嵌 tmp）
        _applyMemberPricing();
        final Map<String, dynamic> master = _buildOrderMaster(
          amtOverride: _round2(_payAmt - _serviceAmt - _lowAmt),
          serviceamtOverride: 0,
          addamtOverride: 0,
          remarkOverride: '',
        );
        _attachPcTmp(master);
        final Map<String, dynamic> masterTmp =
            master['tmp'] as Map<String, dynamic>;
        masterTmp['cdflag'] = 1;
        masterTmp['printcpdflag'] = 0;
        masterTmp['withdrawmemo'] = '';
        await requestForm(
          HttpApi.pcWithdrawTable,
          <String, dynamic>{'tablemaster': jsonEncode(master)},
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.withdrawTable, <String, dynamic>{
          'saleid': _saleid,
          'tmp': jsonEncode(tmp ?? <String, dynamic>{}),
          'printtype': '-1',
        });
      }
      if (!mounted) return;
      Toast.show('撤单成功');
      TableEventBus.fireTableChanged();
      NavigatorUtils.goBack(context);
    } catch (_) {
      if (mounted) Toast.show('撤单失败，请重试');
    }
  }

  // ─────── 转台（对齐 smdcapp transProMaster） ───────

  Future<void> _changeTable() async {
    try {
      final List<Map<String, dynamic>> tables = await TableOpsHelper.fetchFreeTables();
      if (!mounted) return;
      if (tables.isEmpty) {
        Toast.show('没有可用的空闲桌台');
        return;
      }
      final Map<String, dynamic>? selected =
          await TableSelectSheet.show(context, tables: tables, title: '选择转入桌台');
      if (selected == null || !mounted) return;
      await TableOpsHelper.doChangeTable(
        tableId: widget.tableId,
        saleid: _saleid,
        target: selected,
        tableJson: widget.tableJson,
      );
      if (!mounted) return;
      Toast.show('转台成功');
      TableEventBus.fireTableChanged();
      NavigatorUtils.goBack(context);
    } catch (_) {
      if (mounted) Toast.show('转台失败，请重试');
    }
  }

  // ─────── 并台/拆台（对齐 smdcapp uniTable） ───────

  Future<void> _uniTable() async {
    try {
      // 对齐 smdcapp: 若桌台已并台（unitableid非空），则传 unitableid
      final Map<String, dynamic>? tmp =
          widget.tableJson?['tmp'] as Map<String, dynamic>?;
      final String unitableid = tmp?['unitableid']?.toString() ?? '';
      final List<Map<String, dynamic>> tables =
          await TableOpsHelper.fetchCanUniTables(widget.tableId,
              unitableid: unitableid);
      if (!mounted) return;
      if (tables.isEmpty) {
        Toast.show('没有可并台的桌台');
        return;
      }
      // 对齐 smdcapp TableUnitBottomDialog: 多选弹窗（已合并显示徽章，选中后确定）
      final List<Map<String, dynamic>>? selectedList =
          await TableSelectSheet.showUniTable(context, tables: tables);
      if (selectedList == null || selectedList.isEmpty || !mounted) return;
      await TableOpsHelper.doUniTableBatch(
          tableId: widget.tableId,
          selectedList: selectedList,
          unitableid: unitableid);
      if (!mounted) return;
      Toast.show('桌台拆并成功');
      TableEventBus.fireTableChanged();
      NavigatorUtils.goBack(context);
    } catch (_) {
      if (mounted) Toast.show('桌台拆并失败，请重试');
    }
  }

  // ─────── 转菜（对齐 smdcapp OrderDetailActivity.changeDishes / ChangeDishesPopup） ───────

  /// 解析明细行列表（深拷贝，避免污染源数据）
  List<Map<String, dynamic>> _parseZcDetailRows(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  /// 组装转入桌台主单 MasterBean（对齐 smdcapp getMasterBeanPC(newTable, downPrice,
  /// minSalemoney, servermoney, addamt, "转入菜品")）
  Map<String, dynamic> _buildZcTargetMaster({
    required Map<String, dynamic> target,
    required Map<String, dynamic> newTmp,
    required List<Map<String, dynamic>> fastFoodBean,
    required double servermoney,
    required double minSalemoney,
  }) {
    // 汇总转入桌台合并后的明细金额（对齐 smdcapp ShoppingCartUtil.getDownPrice，
    // 套餐明细行不统计汇总）
    double rrAmt = 0;
    double oAmt = 0;
    double disAmt = 0;
    double addamt = 0;
    int hangflag = 0;
    for (final Map<String, dynamic> b in fastFoodBean) {
      final String combproductid = b['combproductid']?.toString() ?? '';
      if (combproductid.isEmpty) {
        addamt = _round2(addamt + _toDouble(b['cookaddamt']));
      }
      if (_toInt(b['hangflag']) == 1) hangflag = 1;
      if (combproductid.isNotEmpty && (b['combid']?.toString() ?? '').isNotEmpty) {
        continue;
      }
      final double itemO = b['oldrramt'] != null
          ? _toDouble(b['oldrramt'])
          : _round2(_toDouble(b['sellprice']) * _toDouble(b['qty']) +
              _toDouble(b['combaddamt']));
      final double itemR = _toDouble(b['rramt']);
      oAmt = _round2(oAmt + itemO);
      rrAmt = _round2(rrAmt + itemR);
      disAmt = _round2(disAmt + (itemO - itemR));
    }
    // 对齐 smdcapp getMasterBeanPC：minSalemoney==0 时 amt=现价合计+服务费
    final double amt = minSalemoney == 0
        ? _round2(rrAmt + servermoney)
        : _round2(minSalemoney + servermoney);

    final String nowStr = _formatNow();
    final String localbillno = newTmp['localbillno']?.toString() ?? '';
    final int tmpBilltype = _toInt(newTmp['billtype']);
    return <String, dynamic>{
      'saleid': newTmp['saleid']?.toString() ?? '',
      'tableid':
          newTmp['tableid']?.toString() ?? target['tableid']?.toString() ?? '',
      'tablename':
          newTmp['tablename']?.toString() ?? target['name']?.toString() ?? '',
      'tablecode':
          newTmp['tablecode']?.toString() ?? target['code']?.toString() ?? '',
      'tablestatus': (newTmp['tablestatus'] ?? 2).toString(),
      'billdate': newTmp['billdate']?.toString() ?? '',
      'id': _toInt(newTmp['id']),
      'billtype': tmpBilltype == 0 ? 7 : tmpBilltype,
      'lastbilltype': 7,
      'billno': localbillno,
      'amt': _round2(amt),
      'retailamt': _round2(oAmt),
      'dscamt': _round2(disAmt),
      'serviceamt': _round2(servermoney),
      'lowamt': _round2(minSalemoney),
      'addamt': _round2(addamt),
      'roundamt': 0,
      'payment': _round2(amt),
      'hangflag': hangflag,
      'status': 1,
      'version': 180,
      'androidoperflag': 1,
      'cashid': UserHelper.getUserid(),
      'updatetime': nowStr,
      'tabletypeid': newTmp['tabletypeid']?.toString() ?? '',
      'sid': UserHelper.getSidStr(),
      'spid': UserHelper.getSpidStr(),
      'remark': '转入菜品',
      'personnum': newTmp['personnum']?.toString() ?? '',
      'serverid': newTmp['serverid']?.toString() ?? '',
      'servername': newTmp['servername']?.toString() ?? '',
      'vipid': newTmp['vipid']?.toString() ?? '',
      'vipno': newTmp['vipno']?.toString() ?? '',
      'vipname': newTmp['vipname']?.toString() ?? '',
      'localbillno': localbillno,
    };
  }

  /// 记录转菜数据（对齐 smdcapp OrderModel.transProMaster → /YttSvr/app/sale/transProMaster）
  ///
  /// [inMaster] 转入桌台主单，[newTmp] 转入桌台 tmp，[transList] 转出明细
  Future<void> _postTransProMaster({
    required Map<String, dynamic> inMaster,
    required Map<String, dynamic> newTmp,
    required List<Map<String, dynamic>> transList,
  }) async {
    final Map<String, dynamic>? oldTmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final Map<String, dynamic> transMaster = <String, dynamic>{
      'spid': inMaster['spid'],
      'sid': inMaster['sid'],
      'saleid': inMaster['saleid'],
      'billdate': inMaster['billdate'],
      'personnum': oldTmp?['personnum'],
      'tableid': oldTmp?['tableid'],
      'tablecode': oldTmp?['tablecode'],
      'tablename': oldTmp?['tablename'],
      'vipid': oldTmp?['vipid'],
      'vipno': oldTmp?['vipno'],
      'vipname': oldTmp?['vipname'],
      'vipmobile': oldTmp?['vipmobile'],
      'amt': oldTmp?['amt'],
      'dscamt': inMaster['dscamt'],
      'addamt': inMaster['addamt'],
      'payment': inMaster['payment'],
      'billtype': inMaster['billtype'],
      'cashid': inMaster['cashid'],
      'cashname': inMaster['cashid'],
      'serverid': inMaster['serverid'],
      'servername': inMaster['servername'],
      'createtime': newTmp['createtime'],
      'updatetime': newTmp['updatetime'],
      'status': inMaster['status'],
      'localbillno': inMaster['localbillno'],
      'remark': inMaster['remark'],
      'operid': UserHelper.getUserid(),
      'opername': _operatorName,
      'operamt': inMaster['payment'],
      'opertime': inMaster['updatetime'],
      'retailamt': inMaster['retailamt'],
      'changeamt': 0.0,
      'paytime': _formatNow(),
      'qty': transList.length.toDouble(),
      'newtableid': newTmp['tableid'],
      'newtablename': newTmp['tablename'],
      'newtablecode': newTmp['tablecode'],
    };
    // 对齐 smdcapp SaleTransDetail 字段（同名直传，combflag/opertype 转字符串）
    const List<String> detailKeys = <String>[
      'spid', 'sid', 'saleid', 'onlyid', 'productid', 'productcode',
      'productno', 'productname', 'typeid', 'typename', 'unit', 'specid',
      'spec', 'qty', 'subqty', 'sellprice', 'discount', 'rrprice', 'rramt',
      'presentflag', 'presentprice', 'remark', 'combid', 'combgroupid',
      'combproductid', 'operamt', 'saleductamt', 'hangflag', 'callflag',
      'urgeflag', 'cooktext', 'cookaddamt', 'specpriceflag', 'bxxpxxflag',
      'cxmbillid', 'salesid', 'salesname', 'operid', 'opername', 'createtime',
      'seq', 'fornowid', 'operremark', 'costprice', 'opertime', 'jcmbillid',
      'tpdishid', 'tpdishflag', 'tableid', 'mustflag', 'tpdishidzd',
      'tpdscflag',
    ];
    final List<Map<String, dynamic>> transDetails =
        transList.map((Map<String, dynamic> tt) {
      final Map<String, dynamic> d = <String, dynamic>{
        for (final String k in detailKeys) k: tt[k],
      };
      d['combflag'] = _toInt(tt['combflag']).toString();
      d['opertype'] = (tt['opertype'] ?? 0).toString();
      d['saleductamt'] = _toDouble(tt['saleductamt']);
      return d;
    }).toList();
    await requestForm(
      HttpApi.transProMaster,
      <String, dynamic>{
        'transmaster': jsonEncode(transMaster),
        'transdetail': jsonEncode(transDetails),
        'newtableid': newTmp['tableid']?.toString() ?? '',
        'newtablecode': newTmp['tablecode']?.toString() ?? '',
        'newtablename': newTmp['tablename']?.toString() ?? '',
      },
      showError: false,
    );
  }

  /// 单品转菜（对齐 smdcapp zcOperat → ChangeDishesListener.onCallBack → changeDishes(list, [bean])）
  ///
  /// 选中菜品整份转入目标桌台，老桌剩余菜品继续保留。
  Future<void> _transferSingleDish(Map<String, dynamic> item) async {
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[item];
    // 套餐主行转出时带出全部明细子行（对齐 smdcapp changeDishes 的 itemList 组装）
    final String onlyid = item['onlyid']?.toString() ?? '';
    if (_toInt(item['combflag']) == 1 && onlyid.isNotEmpty) {
      for (final Map<String, dynamic> it in _detailList) {
        if ((it['combid']?.toString() ?? '') == onlyid &&
            (it['combproductid']?.toString() ?? '').isNotEmpty) {
          rows.add(it);
        }
      }
    }
    await _transferToTable(singleRows: rows);
  }

  /// 转菜（对齐 smdcapp OrderDetailActivity → ChangeDishesPopup）
  ///
  /// [singleRows] 非空=单品转菜（转出明细已确定）；为空=整单操作入口，
  /// 转出范围由弹窗按钮决定：确定→勾选菜品部分转出（对齐 OperationPlacedActivity 选菜页），
  /// 整桌转菜→二次确认后整桌转出（对齐 ChangeDishesPopup.tv_table_change）。
  ///
  /// 主设备：组装 TableChangeProductRequestDto{inMasterTmpParmDto(新桌PCMasterBean),
  ///   outMasterTmpParmDto(老桌PCMasterBean), changelist(转出明细 dishzcflag=1/lssubqty=qty),
  ///   printFlag} → POST /api/table/TableChangeProduct（对齐 OrderModel.pcBatchPostTableInfo）
  /// 云服务：拉取新桌明细合并转出菜（对齐 yunAddDish）→ transProMaster 记录 →
  ///   upSaleMasterTmp 上传新桌（对齐 OrderModel.postInfo 云分支）→
  ///   老桌上传剩余菜品 + 转出菜 deleteflag=1（对齐 zcPostInfo）
  Future<void> _transferToTable({List<Map<String, dynamic>>? singleRows}) async {
    bool isPartial = false;
    try {
      if (_detailList.isEmpty) {
        Toast.show('无可转菜品');
        return;
      }
      final ChangeDishesResult? result = await ChangeDishesSheet.show(
        context,
        excludeTableId: widget.tableId,
        excludeSaleid: _saleid,
      );
      if (result == null || !mounted) return;
      final Map<String, dynamic> selected =
          result.table.rawJson ?? result.table.toJson();
      final Map<String, dynamic>? newTmp =
          selected['tmp'] as Map<String, dynamic>?;
      // R54：待下单桌台可能尚未生成 saleid，转菜时补一个，避免直接提示失败
      String newSaleid = newTmp?['saleid']?.toString() ?? '';
      if (newSaleid.isEmpty && newTmp != null) {
        newSaleid = StoreModeUtils.generateSaleId();
        newTmp['saleid'] = newSaleid;
      }
      final String newTableId = newTmp?['tableid']?.toString() ??
          selected['tableid']?.toString() ??
          '';
      if (newSaleid.isEmpty || newTableId.isEmpty || newSaleid == _saleid) {
        Toast.show('目标桌台信息错误');
        return;
      }

      List<Map<String, dynamic>>? rows = singleRows;
      if (result.action == ChangeDishesAction.all) {
        // 整桌转菜二次确认（对齐 smdcapp ChangeDishesPopup TipDialog 文案）
        final String fromCode = widget.tableCode.isNotEmpty
            ? widget.tableCode
            : (widget.tableJson?['tmp'] as Map?)?['tablecode']?.toString() ??
                '';
        final String toCode = newTmp?['tablecode']?.toString() ?? '';
        final bool confirmed = await ConfirmDialog.show(
          context,
          content: '请确认整桌转菜\n转出桌台【$fromCode】\n转入桌台【$toCode】\n是否继续',
          confirmText: '确认',
        );
        if (!confirmed || !mounted) return;
        rows = null;
      } else if (rows == null) {
        // 部分转菜：勾选转出菜品（对齐 smdcapp 确定 → OperationPlacedActivity 选菜页）
        rows = await _pickDishes(
          title: '转菜',
          enabled: (Map<String, dynamic> i) => _toDouble(i['subqty']) == 0,
          disabledHint: '不可转',
        );
        if (rows == null || rows.isEmpty || !mounted) return;
      }
      isPartial = rows != null;

      // 对齐 smdcapp changeDishes：转出明细 saleid=新桌、updateflag=1、remark=转菜，
      // prnretflag 取转菜打印开关（MMKV Constant.DISHES_ZC）
      final bool zcPrint = SpUtil.getBool('DISHES_ZC') ?? false;
      final int prnretflag = zcPrint ? 1 : 0;
      final List<Map<String, dynamic>> returnList = <Map<String, dynamic>>[];
      for (final Map<String, dynamic> item in (rows ?? _detailList)) {
        final Map<String, dynamic> b = Map<String, dynamic>.from(item);
        b['prnretflag'] = prnretflag;
        b['updateflag'] = 1;
        b['saleid'] = newSaleid;
        b['remark'] = '转菜';
        b['operremark'] = '转菜';
        for (final String key in <String>['cookList', 'eatlist']) {
          final dynamic subs = b[key];
          if (subs is List) {
            for (final dynamic sub in subs) {
              if (sub is Map) sub['saleid'] = newSaleid;
            }
          }
        }
        returnList.add(b);
      }

      final bool useMaster = ConnectionManager.pcAlive;
      // 拉取新桌台已落单明细并合并转入菜品（对齐 getPcAddDish / yunAddDish）
      List<Map<String, dynamic>> newDetails = <Map<String, dynamic>>[];
      double servermoney = 0;
      double minSalemoney = 0;
      if (useMaster) {
        final Map<String, dynamic> resp = await requestForm(
          HttpApi.pcGetTableDetailList,
          <String, dynamic>{
            'tablemaster': jsonEncode(<String, dynamic>{'tmp': newTmp}),
          },
          masterDevice: true,
        );
        final dynamic data = resp['Data'] ?? resp['data'];
        if (data is Map<String, dynamic>) {
          newDetails = _parseZcDetailRows(data['detailList']);
          servermoney = _toDouble(data['serviceMoney'] ?? data['serviceamt']);
          minSalemoney = _toDouble(data['minSalemoney'] ?? data['lowamt']);
        }
      } else {
        final Map<String, dynamic> resp = await requestForm(
          HttpApi.getSaleTmpDetail,
          <String, dynamic>{'saleid': newSaleid},
        );
        final dynamic data = resp['data'] ?? resp['Data'];
        if (data is Map<String, dynamic>) {
          newDetails = _parseZcDetailRows(data['detailList']);
          servermoney = _toDouble(data['serviceMoney'] ?? data['serviceamt']);
          minSalemoney = _toDouble(data['minSalemoney'] ?? data['lowamt']);
        }
        // 对齐 smdcapp yunAddDish：转入菜 seq=新桌最大seq+1
        int maxSeq = 0;
        for (final Map<String, dynamic> d in newDetails) {
          if (_toInt(d['seq']) > maxSeq) maxSeq = _toInt(d['seq']);
        }
        for (final Map<String, dynamic> b in returnList) {
          b['seq'] = maxSeq + 1;
          b['updateflag'] = 1;
        }
      }
      if (!mounted) return;
      final List<Map<String, dynamic>> fastFoodBean = <Map<String, dynamic>>[
        ...newDetails,
        ...returnList,
      ];
      if (fastFoodBean.isEmpty) {
        Toast.show('获取明细数据失败，请返回桌台重新进入');
        return;
      }

      // 部分转出：老桌主单金额需按剔除转出菜品后的剩余明细重算
      // （对齐 smdcapp changeDishes：placedOrderBean.newList = oldList）
      List<Map<String, dynamic>> outRemain = <Map<String, dynamic>>[];
      if (isPartial) {
        final Set<String> zcOnlyIds = returnList
            .map((Map<String, dynamic> b) => b['onlyid']?.toString() ?? '')
            .where((String s) => s.isNotEmpty)
            .toSet();
        _detailList.removeWhere((Map<String, dynamic> r) =>
            zcOnlyIds.contains(r['onlyid']?.toString() ?? ''));
        // 剩余明细价格按会员/促销重算后再取快照，保证老桌上传金额与展示一致
        _applyMemberPricing();
        outRemain = _detailList
            .map((Map<String, dynamic> r) =>
                Map<String, dynamic>.from(r)..['updateflag'] = 1)
            .toList();
      }

      final Map<String, dynamic> inMaster = _buildZcTargetMaster(
        target: selected,
        newTmp: newTmp ?? <String, dynamic>{},
        fastFoodBean: fastFoodBean,
        servermoney: servermoney,
        minSalemoney: minSalemoney,
      );

      /// 老桌主单：整桌转出后剩余菜品为空、金额归 0（对齐 getZcOutDishes 整单分支）；
      /// 部分转出保留剩余菜品，金额按剩余明细重算
      Map<String, dynamic> buildOutMaster() {
        if (isPartial) {
          return _buildOrderMaster();
        }
        final Map<String, dynamic> m = _buildOrderMaster(
          amtOverride: 0,
          serviceamtOverride: 0,
          addamtOverride: 0,
          remarkOverride: '',
        );
        m['retailamt'] = 0;
        m['dscamt'] = 0;
        m['lowamt'] = 0;
        m['payment'] = 0;
        m['hangflag'] = 0;
        return m;
      }

      if (useMaster) {
        // 对齐 smdcapp pcBatchPostTableInfo：changelist 明细 dishzcflag=1、lssubqty=qty
        // （returnList 与 fastFoodBean 共享对象，序列化后两处同时携带，与 smdcapp 一致）
        for (final Map<String, dynamic> b in returnList) {
          b['dishzcflag'] = 1;
          b['lssubqty'] = b['qty'];
        }
        // 新桌 PCMasterBean：master 内嵌 tmp（对齐 batchPcZc：printcpdflag=1、
        // roundamt、tablestatus==1 时置 2）
        final Map<String, dynamic> inTmp =
            Map<String, dynamic>.from(newTmp ?? <String, dynamic>{});
        inTmp['amt'] = inMaster['amt'];
        inTmp['serviceamt'] = inMaster['serviceamt'];
        inTmp['retailamt'] = inMaster['retailamt'];
        inTmp['lastbilltype'] = 7;
        inTmp['updatetime'] = inMaster['updatetime'];
        inTmp['remark'] = '转入菜品';
        inTmp['printcpdflag'] = 1;
        inTmp['roundamt'] = 0;
        if (_toInt(inTmp['tablestatus']) == 1) inTmp['tablestatus'] = 2;
        inMaster['tmp'] = inTmp;

        // 老桌 PCMasterBean（对齐 getZcOutDishes：剩余菜品 + 剩余明细金额）
        final Map<String, dynamic> outMaster = buildOutMaster();
        _attachPcTmp(outMaster);

        // 对齐 smdcapp TableChangeProductRequestDto →
        // POST /api/table/TableChangeProduct @Field("data")=json
        final Map<String, dynamic> changeDto = <String, dynamic>{
          'inMasterTmpParmDto': <String, dynamic>{
            'tableMaster': inMaster,
            'detailList': fastFoodBean,
          },
          'outMasterTmpParmDto': <String, dynamic>{
            'tableMaster': outMaster,
            'detailList': isPartial ? outRemain : <Map<String, dynamic>>[],
          },
          'changelist': returnList,
          'printFlag': zcPrint ? 1 : 0,
        };
        await requestForm(
          HttpApi.pcTableChangeProduct,
          <String, dynamic>{'data': jsonEncode(changeDto)},
          masterDevice: true,
        );
        // 对齐 smdcapp pcBatchPostTableInfo 成功后 transProMaster 记录转菜数据
        // （云端接口，失败不影响转菜结果）
        try {
          await _postTransProMaster(
            inMaster: inMaster,
            newTmp: newTmp ?? <String, dynamic>{},
            transList: returnList,
          );
        } catch (_) {}
      } else {
        // 云服务（对齐 smdcapp OrderModel.postInfo 云分支）：
        // 先 transProMaster 记录转菜，成功后再上传新桌主单与明细
        await _postTransProMaster(
          inMaster: inMaster,
          newTmp: newTmp ?? <String, dynamic>{},
          transList: returnList,
        );
        await OrderRepository.placeOrder(
          master: jsonEncode(inMaster),
          detail: jsonEncode(fastFoodBean),
          printType: zcPrint ? '21' : '-1',
          printAllType: 1,
        );
        // R27：云服务模式补发转菜单（服务端按 saleid+opertype 重建）
        if (zcPrint) {
          await PrintService.instance.cloudReprint(
            saleid: newSaleid,
            billno: inMaster['billno']?.toString() ??
                inMaster['localbillno']?.toString() ??
                '',
            opertype: '21',
          );
        }
        // 老桌台更新（对齐 smdcapp zcPostInfo）：剩余菜品 updateflag=1、
        // 转出明细带 deleteflag=1 一并上传
        final List<Map<String, dynamic>> oldFastFood = <Map<String, dynamic>>[
          if (isPartial) ...outRemain,
          ...returnList.map((Map<String, dynamic> b) {
            final Map<String, dynamic> c = Map<String, dynamic>.from(b);
            c['updateflag'] = 1;
            c['deleteflag'] = 1;
            return c;
          }),
        ];
        final Map<String, dynamic> outMaster = buildOutMaster();
        await OrderRepository.placeOrder(
          master: jsonEncode(outMaster),
          detail: jsonEncode(oldFastFood),
          printType: '',
          printAllType: 1,
        );
      }
      if (!mounted) return;
      Toast.show('转菜成功');
      TableEventBus.fireTableChanged();
      _loadOrderDetail();
    } catch (_) {
      if (mounted) {
        Toast.show('转菜失败，请重试');
        // 部分转出已在本地移除菜品，失败时重新拉取以与服务端保持一致
        if (isPartial) _loadOrderDetail();
      }
    }
  }

  // ─────── 服务员选择（对齐 smdcapp WaiterPopup） ───────

  Future<void> _selectWaiter() async {
    try {
      // 获取服务员列表（对齐 smdcapp user/getList）
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getUserList,
        <String, dynamic>{
          'is_page': '0',
          'page': '1',
          'pagesize': '100',
          'stopflag': '0',
        },
        showError: false,
      );
      if (!mounted) return;
      final dynamic data = resp['data'] ?? resp['Data'];
      List<Map<String, dynamic>> waiters = <Map<String, dynamic>>[];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          waiters = list.whereType<Map<String, dynamic>>().toList();
        }
      }
      if (waiters.isEmpty) {
        Toast.show('没有可选的服务员');
        return;
      }
      // 弹出选择
      final Map<String, dynamic>? selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        builder: (BuildContext ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('选择服务员', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: waiters.length,
                  itemBuilder: (BuildContext c, int i) {
                    final Map<String, dynamic> w = waiters[i];
                    final String name = w['name']?.toString() ?? w['username']?.toString() ?? '';
                    return ListTile(
                      title: Text(name),
                      onTap: () => Navigator.pop(ctx, w),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final String serverId = selected['userid']?.toString() ?? selected['id']?.toString() ?? '';
      final String serverName = selected['name']?.toString() ?? selected['username']?.toString() ?? '';
      // 更新本地服务员并上传（对齐 smdcapp updateMasterTmp serverid/servername）
      await OrderRepository.updateMasterTmpVip(
        saleid: _saleid,
        tableid: widget.tableId,
        tablecode: widget.tableCode,
        remark: _remark,
        personnum: widget.persons.toString(),
        serverid: serverId,
        servername: serverName,
        vipid: _member?.vipid ?? '',
        vipno: _member?.vipno ?? '',
        vipname: _member?.vipname ?? '',
        vipmobile: _member?.mobile ?? '',
        masterDevice: ConnectionManager.pcAlive,
        tableJson: widget.tableJson,
      );
      if (!mounted) return;
      setState(() => _serverName = serverName);
      Toast.show('服务员已更新为：$serverName');
    } catch (_) {
      if (mounted) Toast.show('服务员更新失败');
    }
  }

  // ─────── 修改开台信息（对齐 smdcapp TableOpenBottomDialog 修改模式） ───────

  Future<void> _editOpenTableInfo() async {
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final int oldPersonnum = _personNum > 0
        ? _personNum
        : _toInt(tmp?['personnum']);
    final bool success = await EditTableInfoSheet.show(
      context,
      saleid: _saleid,
      tableId: widget.tableId,
      tableCode: widget.tableCode,
      tableName: widget.tableName,
      personnum: _personNum > 0
          ? '$_personNum'
          : (tmp?['personnum']?.toString() ?? widget.persons.toString()),
      remark: _remark,
      serverId: widget.serverId.isNotEmpty ? widget.serverId : (tmp?['serverid']?.toString() ?? ''),
      serverName: _serverName,
      // 附加费（对齐 smdcapp：tmp.additionid 关联桌台类型名称）
      additionId: tmp?['additionid']?.toString() ?? '',
      tableJson: widget.tableJson,
    );
    if (success && mounted) {
      await _loadOrderDetail();
      if (mounted) {
        // R42：人数变化后同步按人必点菜数量（对齐 smdcapp checkMust）
        await _syncMustQtyAfterPersonChange(oldPersonnum, _personNum);
        TableEventBus.fireTableChanged();
      }
    }
  }

  /// 人数变更后同步按人必点菜数量（R42）
  Future<void> _syncMustQtyAfterPersonChange(
      int oldPersonnum, int newPersonnum) async {
    if (oldPersonnum <= 0 ||
        newPersonnum <= 0 ||
        oldPersonnum == newPersonnum) {
      return;
    }
    try {
      final Map<String, dynamic>? tmp =
          widget.tableJson?['tmp'] as Map<String, dynamic>?;
      final String areaid = widget.tableJson?['areaid']?.toString() ?? '';
      List<Map<String, dynamic>> groups =
          await OrderRepository.fetchMustDishesFromLocal(areaid: areaid);
      // 本地已有必点菜表数据时不回退云接口（云接口返回方案不带区域信息，
      // 会导致区域限定方案在未指定区域生效）
      if (groups.isEmpty && !await OrderRepository.hasLocalMustData()) {
        groups = await OrderRepository.fetchMustDishes(areaid: areaid);
      }
      if (groups.isEmpty || !mounted) return;
      bool changed = false;
      for (final Map<String, dynamic> group in groups) {
        if (_toInt(group['mustrule']) != 0 ||
            _toInt(group['musttype']) != 0) {
          continue;
        }
        final dynamic rawList = group['mustproductlist'];
        if (rawList is! List) continue;
        for (final dynamic raw in rawList) {
          if (raw is! Map) continue;
          final String pid = raw['productid']?.toString() ?? '';
          if (pid.isEmpty) continue;
          final double baseQty = _toDouble(raw['mustqty']) < 1
              ? 1
              : _toDouble(raw['mustqty']);
          final double required = baseQty * newPersonnum;
          final List<Map<String, dynamic>> mustRows = _detailList
              .where((Map<String, dynamic> d) =>
                  d['productid']?.toString() == pid &&
                  _toInt(d['mustflag']) == 1 &&
                  _toInt(d['presentflag']) != 2)
              .toList();
          // 服务端未回传 mustflag 时按商品匹配已下单明细兜底，避免人数变更不生效
          final List<Map<String, dynamic>> rows = mustRows.isNotEmpty
              ? mustRows
              : _detailList
                  .where((Map<String, dynamic> d) =>
                      d['productid']?.toString() == pid &&
                      _toInt(d['id']) != 0 &&
                      _toInt(d['presentflag']) != 1 &&
                      _toInt(d['presentflag']) != 2)
                  .toList();
          if (rows.isEmpty) continue;
          double current = rows.fold<double>(
              0, (double s, Map<String, dynamic> d) => s + _toDouble(d['qty']));
          if ((current - required).abs() < 0.0001) continue;
          final double delta = required - current;
          final Map<String, dynamic> target = rows.first;
          final double nextQty = _toDouble(target['qty']) + delta;
          target['qty'] = nextQty;
          target['rramt'] = _round2(
              _toDouble(target['rrprice']) * nextQty +
                  _toDouble(target['cookaddamt']));
          target['updateflag'] = 1;
          if (nextQty <= 0) {
            target['deleteflag'] = 1;
          }
          changed = true;
          current = required;
        }
      }
      if (changed && mounted) {
        setState(() {});
        Toast.show('人数已变更，必点菜数量已同步');
        await _postOrderUpdate();
      }
    } catch (_) {}
  }

  // ─────── 暂结记录（对齐 smdcapp ZjOrderActivity） ───────

  void _showZanjieRecords() {
    NavigatorUtils.push(
      context,
      Routes.zanjieOrderPage,
      arguments: <String, dynamic>{'saleid': _saleid},
    );
  }

  // ─────── 交押金（对齐 smdcapp JYJPopup） ───────

  void _showDepositPay() {
    DepositSheet.showPay(
      context,
      saleid: _saleid,
      tableId: widget.tableId,
      tableName: widget.tableName,
      serverId: widget.serverId,
      serverName: widget.serverName,
    );
  }

  // ─────── 押金记录（对齐 smdcapp YJOrderActivity） ───────

  void _showDepositRecords() {
    DepositSheet.showRecords(
      context,
      saleid: _saleid,
      tableId: widget.tableId,
      tableName: widget.tableName,
      serverId: widget.serverId,
      serverName: widget.serverName,
    );
  }

  // ─────── 预打（对齐 smdcapp DetailOperationPopup.NAME_YD） ───────

  /// 预打流程（对齐 smdcapp NAME_YD → updateMasterTmpPrePrintFlag + postInfo("8")）：
  ///
  /// 1. 更新预打印标识（对齐 OrderModel.updateMasterTmpPrePrintFlag）
  /// 2. 触发预打单打印：
  ///    - 主设备：对齐 OrderModel.ydPC → POST /api/print/RePrint，
  ///      tablemaster = PCMasterBean JSON（tableMaster + detailList）
  ///    - 云服务：对齐 postInfo("8") 云分支 → upSaleMasterTmp printtype=8 printalltype=1，
  ///      再推送云打印任务（对齐 sendPrint → printMsgNotice，预打单 opertype=8）
  Future<void> _prePrint() async {
    if (_detailList.isEmpty) {
      Toast.show('订单明细为空');
      return;
    }
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      // 1. 更新预打印标识
      if (useMaster) {
        await requestForm(
          HttpApi.pcUpdateMasterTmpPrePrintFlag,
          <String, dynamic>{
            'saleid': _saleid,
            'preprintflag': '1',
            'spid': UserHelper.getSpidStr(),
            'sid': UserHelper.getSidStr(),
          },
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.updateMasterTmpPrePrintFlag, <String, dynamic>{
          'saleid': _saleid,
          'preprintflag': '1',
          'spid': UserHelper.getSpidStr(),
          'sid': UserHelper.getSidStr(),
        });
      }
      if (!mounted) return;

      // 2. 触发预打单打印
      final Map<String, dynamic>? tmp =
          widget.tableJson?['tmp'] as Map<String, dynamic>?;
      final String billno = tmp?['localbillno']?.toString() ?? '';
      bool printed;
      if (useMaster) {
        // 对齐 smdcapp ydPC：组装 PCMasterBean 后调 /api/print/RePrint，
        // master.tmp.printcpdflag=1、sendprintflag="1"（对齐 postInfo("8", isPcYD=true)）
        _applyMemberPricing();
        final Map<String, dynamic> master = _buildOrderMaster();
        _attachPcTmp(master);
        final Map<String, dynamic> masterTmp =
            master['tmp'] as Map<String, dynamic>;
        masterTmp['printcpdflag'] = 1;
        masterTmp['sendprintflag'] = '1';
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMaster': master,
          'detailList': _detailList,
        };
        printed = await PrintService.instance.prePrint(
          saleid: _saleid,
          billno: billno,
          pcMasterJson: jsonEncode(pcMaster),
        );
      } else {
        // 云服务：_postOrderUpdate(printtype=8) 内部已调 restPrint(opertype=8)，
        // 这里不再重复调用，避免预打单打两次
        printed = await _postOrderUpdate(printtype: '8');
      }
      if (!mounted) return;
      Toast.show(printed ? '预打成功' : '预打失败');
    } catch (_) {
      if (mounted) Toast.show('预打失败');
    }
  }

  // ─────── 补打客单（对齐 smdcapp DetailOperationPopup.NAME_REPRINT_KD） ───────

  Future<void> _reprintKD() async {
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      if (useMaster) {
        // 对齐 smdcapp OrderModel 补打客单 PC 分支：PrintKDInfo 需要
        // tablemaster = PCMasterBean{tableMaster, detailList}，
        // 不是 saleid/billno；否则 PC 端 parm 为空、返回成功但不出票。
        _applyMemberPricing();
        final Map<String, dynamic> master = _buildOrderMaster();
        _attachPcTmp(master);
        final Map<String, dynamic> masterTmp =
            master['tmp'] as Map<String, dynamic>;
        masterTmp['sendprintflag'] = '1';
        masterTmp['printcpdflag'] = 0;
        masterTmp['printkdflag'] = 1;
        masterTmp['roundamt'] = 0;
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMaster': master,
          'detailList': _detailList,
        };
        await requestForm(
          HttpApi.pcPrintKDInfo,
          <String, dynamic>{'tablemaster': jsonEncode(pcMaster)},
          masterDevice: true,
        );
      } else {
        final Map<String, dynamic>? tmp =
            widget.tableJson?['tmp'] as Map<String, dynamic>?;
        final String billno = tmp?['localbillno']?.toString() ?? '';
        final bool printed = await PrintService.instance.reprintCustomerTicket(
          billno: billno,
          opertype: '15',
          jobcontent: _saleid,
        );
        if (!printed) {
          if (mounted) Toast.show('补打客单失败');
          return;
        }
      }
      if (!mounted) return;
      Toast.show('补打客单成功');
    } catch (_) {
      if (mounted) Toast.show('补打客单失败');
    }
  }

  /// 生成唯一标识（对齐 smdcapp OrderModel.getonlyId）
  String _generateOnlyId() {
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    final int random = (timestamp % 100000) + (identityHashCode(Object()) % 10000);
    return '$timestamp$random';
  }

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
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _kBrandRed))
                    : RefreshIndicator(
                        onRefresh: _loadOrderDetail,
                        color: _kBrandRed,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                          children: <Widget>[
                            _buildTableInfoCard(isDark),
                            const SizedBox(height: 10),
                            if (_member != null) ...<Widget>[
                              _buildMemberCard(isDark),
                              const SizedBox(height: 10),
                            ],
                            _buildDetailCard(isDark),
                            const SizedBox(height: 10),
                            _buildOrderInfoCard(isDark),
                          ],
                        ),
                      ),
              ),
            ),
            _buildBottomBar(isDark),
          ],
        ),
      ),
    );
  }

  /// 卡片通用装饰
  BoxDecoration _cardDecoration(bool isDark) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF242526) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: isDark
          ? null
          : <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF1D2129).withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }

  /// 标题栏（对齐 smdcapp include_title：返回 + 订单详情 + 会员）
  Widget _buildAppBar(bool isDark) {
    return ColoredBox(
      color: isDark ? const Color(0xFF242526) : Colors.white,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF0F0F0),
                width: 0.5,
              ),
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    size: 17,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                  onPressed: () => NavigatorUtils.goBack(context),
                ),
              ),
              Center(
                child: Text(
                  '订单详情',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _memberSyncing ? null : _onMemberTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
                              : (isDark ? Colors.white : const Color(0xFF1D2129)),
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
                                  : (isDark ? Colors.white : const Color(0xFF1D2129)),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 桌台信息卡片（对齐 smdcapp layout_change_tabinfo：桌台名 + N人 + 编辑图标）
  Widget _buildTableInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: _cardDecoration(isDark),
      child: Row(
        children: <Widget>[
          // 桌台图标（红色渐变圆角方块）
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFF0503F), _kBrandRed],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.table_restaurant, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.tableName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 人数胶囊
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.group, size: 14, color: isDark ? Colors.white70 : const Color(0xFF4E5969)),
                const SizedBox(width: 3),
                Text(
                  '${_personNum > 0 ? _personNum : widget.persons}人',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _editOpenTableInfo,
            child: Icon(
              Icons.edit_outlined,
              size: 18,
              color: isDark ? Colors.white60 : const Color(0xFFC9CDD4),
            ),
          ),
        ],
      ),
    );
  }

  /// 会员信息卡片（对齐 smdcapp MemberLayout：VIP徽章 + 会员名|卡号|手机 + 退出按钮 + 余额/积分/优惠券）
  Widget _buildMemberCard(bool isDark) {
    final VipMember m = _member!;
    // 手机号脱敏（对齐 smdcapp desensitizedPhoneNumber）
    final String maskedPhone = _maskPhone(m.mobile);
    // 拼接会员信息文本（对齐 smdcapp: vipname | vipno | mobile）
    final List<String> parts = <String>[];
    if (m.vipname.isNotEmpty) parts.add(m.vipname);
    if (m.vipno.isNotEmpty) parts.add(m.vipno);
    if (maskedPhone.isNotEmpty) parts.add(maskedPhone);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFF7F0E4), Color(0xFFF0E6D2)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8D9BE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // VIP 徽章（对齐 smdcapp vip2 背景 + vip1 图标 + tvmemberType）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2C),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'VIP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDFBD8C),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 70),
                  child: Text(
                    m.typename.isNotEmpty ? m.typename : '会员',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFDFBD8C),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 会员名 | 卡号 | 手机号 + 退出按钮（对齐 smdcapp tv_memberNO + tv_mermber_out）
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  parts.join(' | '),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF502E00),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _memberSyncing ? null : _onMemberTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0D5C0)),
                  ),
                  child: const Text(
                    '退出会员',
                    style: TextStyle(fontSize: 12, color: Color(0xFF86909C)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 余额/积分/优惠券四列（对齐 smdcapp tv_VipYe/tv_ZsYe/tv_vipJf/tv_vipYhq）
          Row(
            children: <Widget>[
              _memberMetricItem('¥${_formatMemberAmt(m.capitalmoney)}', '本金余额'),
              _memberMetricItem('¥${_formatMemberAmt(m.givemoney)}', '赠送余额'),
              _memberMetricItem('¥${_formatMemberAmt(m.nowpoint)}', '积分'),
              _memberMetricItem(m.favcount, '优惠券'),
            ],
          ),
        ],
      ),
    );
  }

  /// 会员卡片指标列（对齐 smdcapp 四列布局：金额 + 标签）
  Widget _memberMetricItem(String value, String label) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2F2B29),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8C7A5B)),
          ),
        ],
      ),
    );
  }

  /// 手机号脱敏（对齐 smdcapp desensitizedPhoneNumber：173****1773）
  String _maskPhone(String phone) {
    if (phone.isEmpty || phone.length != 11) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(7)}';
  }

  /// 会员卡片金额格式化（对齐 smdcapp 显示风格：去掉末尾多余的0）
  String _formatMemberAmt(double v) {
    if (v == v.truncateToDouble()) {
      return v.toStringAsFixed(1);
    }
    return v.toStringAsFixed(1);
  }

  /// 订单明细卡片（对齐 smdcapp 订单明细 CardView）
  Widget _buildDetailCard(bool isDark) {
    final Color textColor = isDark ? Colors.white : const Color(0xFF1D2129);
    final Color subColor = isDark ? const Color(0xFFB8B8B8) : const Color(0xFF86909C);

    // 展示列表含退菜明细（负数量行），保证退菜后能看到一行负数记录
    final List<Map<String, dynamic>> validItems = _displayList;
    final int totalCount = validItems.length;
    // R16：菜品合计数按数量统计（退菜负数量冲抵），而不是行数
    final double totalQty = validItems.fold<double>(
        0, (double s, Map<String, dynamic> i) => s + _toDouble(i['qty']));

    // 收起时只显示前3条（对齐 smdcapp dp2px(70)*3 限高）
    final List<Map<String, dynamic>> showItems =
        (_expanded || totalCount <= 3) ? validItems : validItems.sublist(0, 3);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 区块标题（对齐 smdcapp：红色竖线 + 订单明细）
          _sectionTitle('订单明细', isDark),
          const SizedBox(height: 6),
          // 商品列表
          if (showItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: <Widget>[
                    Icon(Icons.receipt_long_outlined, size: 36,
                        color: textColor.withValues(alpha: 0.15)),
                    const SizedBox(height: 6),
                    Text('暂无订单数据', style: TextStyle(fontSize: 13, color: subColor)),
                  ],
                ),
              ),
            )
          else
            ..._buildDetailRows(showItems, isDark),
          // 菜品合计数（R16，按数量统计；超过3行时可展开/收起）
          GestureDetector(
            onTap: totalCount > 3
                ? () => setState(() => _expanded = !_expanded)
                : null,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E2F30) : const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '共${_formatQty(totalQty)}件商品'
                      '${totalCount > 3 ? (_expanded ? ' 收起' : ' 展开') : ''}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF86909C)),
                    ),
                    if (totalCount > 3) ...[
                      const SizedBox(width: 2),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 15,
                        color: const Color(0xFF86909C),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 分割线
          Container(
            height: 0.5,
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF0F0F0),
          ),
          const SizedBox(height: 12),
          // 价格汇总（对齐 smdcapp 布局：左列菜品费/服务费/低消，右列费用合计/优惠合计/待支付）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 左列
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _priceRow('菜品费', _dishAmt, isDark),
                    _priceRow('服务费', _serviceAmt, isDark),
                    _priceRow('低消', _lowAmt, isDark),
                  ],
                ),
              ),
              // 右列
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _priceRow('费用合计', _dishAmt + _serviceAmt + _lowAmt, isDark, alignEnd: true),
                    _priceRow('优惠合计', _disAmt, isDark, alignEnd: true),
                    const SizedBox(height: 8),
                    // 待支付（红色强调）
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          '待支付',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : const Color(0xFF1D2129),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '¥${_formatAmt(_payAmt)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _kBrandRed,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 区块标题（红色圆角竖线 + 文字）
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

  /// 明细行列表：相邻两行都是灰底（退菜行/已退完行）时插入间隔，
  /// 灰底与正常行交替时不加间隔。
  List<Widget> _buildDetailRows(List<Map<String, dynamic>> items, bool isDark) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0 && _isGrayDetailRow(items[i]) && _isGrayDetailRow(items[i - 1])) {
        rows.add(const SizedBox(height: 6));
      }
      rows.add(_buildItemRow(items[i], isDark));
    }
    return rows;
  }

  /// 明细行是否灰底（对齐 smdcapp OrderDetailActivity：退菜行、已退完的原商品行）
  bool _isGrayDetailRow(Map<String, dynamic> item) {
    final bool isReturned = _toInt(item['presentflag']) == 2;
    final double qty = _toDouble(item['qty']);
    final double subqty = _toDouble(item['subqty']);
    return isReturned || (subqty > 0 && qty - subqty == 0);
  }

  /// 商品行（对齐 smdcapp item_drder_detail：名称(规格) + 标签 | 价格 | x数量）
  Widget _buildItemRow(Map<String, dynamic> item, bool isDark) {
    final Color textColor = isDark ? Colors.white : const Color(0xFF1D2129);
    final String name = item['productname']?.toString() ?? '';
    final String spec = item['spec']?.toString() ?? '';
    final double qty = _toDouble(item['qty']);
    final double subqty = _toDouble(item['subqty']);
    final double rramt = _toDouble(item['rramt']);
    final double oldrramt = _toDouble(item['oldrramt']);
    final int presentflag = _toInt(item['presentflag']);
    final double discount = _toDouble(item['discount']);
    final String cooktext = item['cooktext']?.toString() ?? '';
    final String eattext = item['eattext']?.toString() ?? '';
    final String remark = item['remark']?.toString() ?? '';

    // 做法/吃法/备注拼接（对齐 smdcapp remarkParts 构建逻辑）
    final List<String> remarkParts = <String>[];
    if (cooktext.isNotEmpty) {
      remarkParts.add('做法：$cooktext');
    }
    if (eattext.isNotEmpty) {
      remarkParts.add('吃法：$eattext');
    }
    if (remark.isNotEmpty) {
      remarkParts.add('备注：$remark');
    }
    // R11：临时菜/明细的服务员、点菜员信息在明细行展示
    final String salesname = item['salesname']?.toString() ?? '';
    final String opername = item['opername']?.toString() ?? '';
    if (salesname.isNotEmpty) {
      remarkParts.add('服务员：$salesname');
    }
    if (opername.isNotEmpty) {
      remarkParts.add('点菜员：$opername');
    }

    // 标签（对齐 smdcapp DishesTagHelper：赠/折/催/挂/退 + 二次称重未称/已称）
    final List<Widget> tags = <Widget>[];
    // 二次称重标签（对齐 smdcapp：isReweigh && weighflag==1 && 非套餐子行，
    // confirmqty==0 显示"未称"红色，否则"已称"绿色）
    if (ParamsSpUtils.isReweigh() &&
        _toInt(item['weighflag']) == 1 &&
        (item['combproductid']?.toString() ?? '').isEmpty) {
      final bool weighed = _toDouble(item['confirmqty']) != 0;
      tags.add(_tag(
        weighed ? '已称' : '未称',
        weighed ? const Color(0xFF00C15A) : const Color(0xFFE13426),
      ));
    }
    // 团购标签（对齐 smdcapp DishesTagHelper）
    if (_toInt(item['douyinflag']) == 1) {
      tags.add(_tag('团', const Color(0xFF1D2129)));
    }
    // 暂结标签（对齐 smdcapp：fornowid 非空）
    if ((item['fornowid']?.toString() ?? '').isNotEmpty) {
      tags.add(_tag('暂结', const Color(0xFF00C15A)));
    }
    // 退完/退部分（原商品行）：退完后金额仍为本行原金额（退菜行以负数金额冲抵）
    if (subqty > 0 && presentflag != 2) {
      tags.add(_tag(
        subqty == qty ? '退完' : '退${_formatQty(subqty)}',
        const Color(0xFFE13426),
      ));
    }
    // 促销标签（对齐 smdcapp：非套餐子行，specpriceflag 1/2/3/6/7 或 jcmbillid 非空）
    final bool isComboChild = (item['combproductid']?.toString() ?? '').isNotEmpty;
    final int specpriceflag = _toInt(item['specpriceflag']);
    if (!isComboChild &&
        (const <int>[1, 2, 3, 6, 7].contains(specpriceflag) ||
            (item['jcmbillid']?.toString() ?? '').isNotEmpty)) {
      tags.add(_tag('促', _kBrandRed));
    }
    if (presentflag == 1) {
      tags.add(_tag('赠', const Color(0xFFFF8547)));
    }
    if (presentflag == 2) {
      tags.add(_tag('退', const Color(0xFFFFB300)));
    }
    if (discount > 0 && discount < 100) {
      // 折扣标签（对齐 smdcapp DishesTagHelper：绿色 + "N折"/"N.5折"）
      tags.add(_tag('${_formatQty(discount / 10)}折', const Color(0xFF00C15A)));
    }
    if (_toInt(item['urgeflag']) == 1) {
      tags.add(_tag('催', const Color(0xFFFF8547)));
    }
    // R53：挂起标签使用后台参数配置的别名（挂/等）
    if (_toInt(item['hangflag']) == 1 && _toInt(item['callflag']) == 0) {
      tags.add(_tag(ParamsSpUtils.getHangUpLabelName(), const Color(0xFFA0522D)));
    }
    // 打包标签（对齐 smdcapp：bagstatus==1）
    if (_toInt(item['bagstatus']) == 1) {
      tags.add(_tag('包', const Color(0xFF0055FF)));
    }
    // 划菜标签（对齐 smdcapp DishesTagHelper：cutflag==1 显示"划"）
    if (_toInt(item['cutflag']) == 1) {
      tags.add(_tag('划', const Color(0xFF00C15A)));
    }
    // R41：必点菜标签
    if (_toInt(item['mustflag']) == 1) {
      tags.add(_tag('必', _kBrandRed));
    }

    final bool isReturned = presentflag == 2;
    // 灰底（对齐 smdcapp OrderDetailActivity：退菜行、已退完的原商品行 → bg_gray_EAEEF6）
    final bool isGrayRow = _isGrayDetailRow(item);

    final Widget mainRow = InkWell(
      onTap: () => _showItemOperation(item),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
          color: isGrayRow
              ? (isDark ? const Color(0xFF2A2B2C) : const Color(0xFFEAEEF6))
              : null,
          borderRadius: BorderRadius.circular(8),
          // R9：菜品之间增加灰色分隔线
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF2A2B2C) : const Color(0xFFE5E6EB),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                // 名称 + 规格 + 标签
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        ...tags.map((Widget t) => WidgetSpan(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4, top: 1),
                                child: t,
                              ),
                            )),
                        TextSpan(
                          // 规格信息跟在菜名之后（对齐 smdcapp dishes_item：名称(规格)）
                          text: spec.isNotEmpty ? '$name($spec)' : name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: isReturned ? const Color(0xFF86909C) : textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 价格（对齐 smdcapp getPriceText：主显本行金额 rramt，退菜行金额为负；
                // 原价更高时展示划线原价 oldrramt）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '¥${_formatAmt(rramt)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isReturned ? const Color(0xFF86909C) : textColor,
                      ),
                    ),
                    if (!isReturned && oldrramt > 0 && oldrramt > rramt)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '¥${_formatAmt(oldrramt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9C9C9C),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                // 数量
                SizedBox(
                  width: 38,
                  child: Text(
                    'x${_formatQty(qty)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF1D2129),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            if (remarkParts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 2),
                child: Text(
                  remarkParts.join('  |  '),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF1D2129),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (_toInt(item['combflag']) != 1) {
      return mainRow;
    }
    // 套餐主行：明细子行展示在主行下方（对齐 smdcapp rvInfo.models = bean.itemList）
    final List<Map<String, dynamic>> children =
        _combChildrenMap[item['onlyid']?.toString() ?? ''] ??
            const <Map<String, dynamic>>[];
    if (children.isEmpty) {
      return mainRow;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        mainRow,
        for (final Map<String, dynamic> child in children)
          _buildCombChildRow(child, item, isDark),
      ],
    );
  }

  /// 套餐明细子行（对齐 smdcapp dishes_item_set_meal_down：名称(规格) | ￥cookaddamt | x数量，12sp 灰色缩进）
  Widget _buildCombChildRow(
      Map<String, dynamic> child, Map<String, dynamic> parent, bool isDark) {
    final String name = child['productname']?.toString() ?? '';
    final String spec = child['spec']?.toString() ?? '';
    final double qty = _toDouble(child['qty']);
    final double cookaddamt = _toDouble(child['cookaddamt']);
    // 赠送/退菜状态与套餐主行同步（对齐 smdcapp CombHelper: child.presentflag = item.presentflag）
    final int presentflag = _toInt(parent['presentflag']);
    final bool isReturned = presentflag == 2;
    final Color grayColor =
        isReturned ? const Color(0xFFC9CDD4) : const Color(0xFF86909C);

    // 做法/备注（对齐 smdcapp tvSku：cooktext，备注：remark）
    final String cooktext = child['cooktext']?.toString() ?? '';
    final String remark = child['remark']?.toString() ?? '';
    final List<String> skuParts = <String>[
      if (cooktext.isNotEmpty) cooktext,
      if (remark.isNotEmpty) '备注：$remark',
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  spec.isNotEmpty ? '$name($spec)' : name,
                  style: TextStyle(
                    fontSize: 12,
                    color: grayColor,
                    decoration:
                        isReturned ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '¥${_formatAmt(cookaddamt)}',
                style: TextStyle(
                  fontSize: 12,
                  color: grayColor,
                  decoration:
                      isReturned ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 38,
                child: Text(
                  'x${_formatQty(qty)}',
                  style: TextStyle(fontSize: 12, color: grayColor),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          if (skuParts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 2),
              child: Text(
                skuParts.join('，'),
                style: TextStyle(fontSize: 11, color: grayColor),
              ),
            ),
        ],
      ),
    );
  }

  /// 单品操作弹窗（已下单菜品，对齐 smdcapp OrderDetailActivity.openAction）
  void _showItemOperation(Map<String, dynamic> item) {
    final int presentflag = _toInt(item['presentflag']);
    final double qty = _toDouble(item['qty']);
    final double subqty = _toDouble(item['subqty']);
    if (qty - subqty == 0.0 && presentflag != 2) {
      Toast.show('商品已退完不可以操作');
      return;
    }
    if (presentflag == 2) {
      return; // 退菜商品不显示操作
    }
    final String name = item['productname']?.toString() ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SingleItemSheet(
        itemName: name,
        isGiven: presentflag == 1,
        isCut: _toInt(item['cutflag']) == 1,
        // 称重菜单仅称重菜 + 开启"称重二次确认"时出现（对齐 smdcapp buildOrderedActions）
        showWeigh: _toInt(item['weighflag']) == 1 && ParamsSpUtils.isReweigh(),
        onAction: (String action) {
          NavigatorUtils.goBack(context);
          _handleSingleItemAction(action, item);
        },
      ),
    );
  }

  /// 小标签
  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// 价格行（标签与金额均为深色，金额字号略大）
  Widget _priceRow(String label, double value, bool isDark, {bool alignEnd = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF1D2129),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '¥${_formatAmt(value)}',
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
        ],
      ),
    );
  }

  /// 时间文本截断到秒（"2026-09-14 19:54:52.000" → "2026-09-14 19:54:52"）
  String _toSecondText(String v) {
    if (v.isEmpty) return v;
    final int dot = v.indexOf('.');
    return dot > 0 ? v.substring(0, dot) : v;
  }

  /// 订单信息卡片（对齐 smdcapp 订单信息 CardView：开台时间/服务员/最后下单/操作人，固定四行无条件展示）
  Widget _buildOrderInfoCard(bool isDark) {
    final Color lineColor = isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F6F8);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle('订单信息', isDark),
          const SizedBox(height: 4),
          _infoRow(Icons.access_time_outlined, '开台时间', _toSecondText(_openTime), isDark, lineColor),
          // 对齐 smdcapp initTabInfo: tvTableWaiter = "服务员：" + tmp.servername
          _infoRow(Icons.person_outline, '服务员', _serverName, isDark, lineColor),
          _infoRow(Icons.receipt_outlined, '最后下单', _toSecondText(_lastOrderTime), isDark, lineColor),
          // 对齐 smdcapp initTabInfo: tvOperationName = "操作人：" + SpUtils.getName()
          _infoRow(Icons.badge_outlined, '操作人', _operatorName, isDark, lineColor,
              isLast: true),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, bool isDark, Color lineColor,
      {bool isLast = false}) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 15, color: isDark ? Colors.white54 : const Color(0xFF4E5969)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : const Color(0xFF1D2129),
                ),
              ),
              const SizedBox(width: 12),
              // 值占满剩余宽度右对齐，避免 Spacer 平分空间导致时间被省略号截断
              Expanded(
                child: Text(
                  value.isEmpty ? '--' : value,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (!isLast) Container(height: 0.5, color: lineColor),
      ],
    );
  }

  /// 底部操作栏（对齐 smdcapp：操作(...) | 加菜 | 去结账(红色)）
  Widget _buildBottomBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1D2129).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: <Widget>[
              // 操作（对齐 smdcapp tv_operation）
              Expanded(
                child: GestureDetector(
                  onTap: _onOperation,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(
                        color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          '操作',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : const Color(0xFF4E5969),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.more_horiz,
                          size: 16,
                          color: isDark ? Colors.white70 : const Color(0xFF4E5969),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 加菜（对齐 smdcapp tv_add_dishes）
              Expanded(
                child: GestureDetector(
                  onTap: _onAddDishes,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(
                        color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '加菜',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : const Color(0xFF4E5969),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 去结账（对齐 smdcapp tv_pay：红色渐变背景白字）
              Expanded(
                child: GestureDetector(
                  onTap: _onSettle,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                      ),
                      borderRadius: BorderRadius.circular(21),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: _kBrandRed.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '去结账',
                        style: TextStyle(
                          fontSize: 14,
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
        ),
      ),
    );
  }

  // ═══════════════════ 工具方法 ═══════════════════

  String _formatAmt(double v) {
    if (v == v.truncateToDouble()) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(2);
  }

  String _formatQty(double qty) {
    if (qty == qty.truncateToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toString();
  }
}

int _toInt(dynamic v) {
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is num) {
    return v.toDouble();
  }
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

// ═══════════════════ 操作弹窗组件 ═══════════════════

/// 整单操作底部弹窗（对齐 smdcapp DetailOperationPopup：桌台操作/菜品操作/打印操作三组）
/// 暂结记录选项受 KQ_ZJ 参数控制（对齐 smdcapp: KQ_ZJ && storemodel==2 时显示）
class _DetailOperationSheet extends StatelessWidget {
  const _DetailOperationSheet({required this.onAction});

  final ValueChanged<String> onAction;

  /// 动态构建操作组（对齐 smdcapp DetailOperationPopup.getTabItem）
  List<_OpGroup> _buildGroups() {
    // 对齐 smdcapp: KQ_ZJ && getCurrentStoremodel()==2 时显示"暂结记录"
    final bool kqZj = SpUtil.getBool('KQ_ZJ') ?? false;
    final List<_OpItem> tableOps = <_OpItem>[
      const _OpItem('转台', Icons.swap_horiz),
      const _OpItem('并台/拆台', Icons.merge),
      const _OpItem('消台', Icons.delete_outline),
      const _OpItem('锁台', Icons.lock_outline),
      const _OpItem('交押金', Icons.account_balance_wallet_outlined),
      const _OpItem('押金记录', Icons.receipt_long_outlined),
    ];
    if (kqZj) {
      tableOps.add(const _OpItem('暂结记录', Icons.pause_circle_outline));
    }
    return <_OpGroup>[
      _OpGroup('桌台操作', tableOps),
      const _OpGroup('菜品操作', <_OpItem>[
        _OpItem('整单折扣', Icons.percent),
        _OpItem('赠送', Icons.card_giftcard_outlined),
        _OpItem('催菜', Icons.notifications_active_outlined),
        _OpItem('起菜', Icons.play_circle_outline),
        _OpItem('转菜', Icons.compare_arrows),
        _OpItem('退菜', Icons.undo),
        _OpItem('撤单', Icons.cancel_outlined),
        _OpItem('服务员', Icons.person_outline),
      ]),
      const _OpGroup('打印操作', <_OpItem>[
        _OpItem('预打', Icons.print_outlined),
        _OpItem('补打客单', Icons.print_outlined),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 拖拽指示条（保持居中）
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E6EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '整单操作',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D2129),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4)),
                  ),
                ],
              ),
            ),
            // 分组操作项
            ..._buildGroups().map((_OpGroup group) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        group.name,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF86909C)),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        runSpacing: 14,
                        children: group.items
                            .map((_OpItem item) => SizedBox(
                                  width: (MediaQuery.of(context).size.width - 32) / 4,
                                  child: InkWell(
                                    onTap: () => onAction(item.name),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF7F8FA),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: const Color(0xFFF2F3F5)),
                                          ),
                                          child: Icon(item.icon, size: 22, color: const Color(0xFF4E5969)),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          item.name,
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF4E5969)),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _OpGroup {
  const _OpGroup(this.name, this.items);
  final String name;
  final List<_OpItem> items;
}

class _OpItem {
  const _OpItem(this.name, this.icon);
  final String name;
  final IconData icon;
}

/// 单品操作底部弹窗（已下单菜品，菜单对齐 smdcapp OperationAction.buildOrderedActions）
class _SingleItemSheet extends StatelessWidget {
  const _SingleItemSheet({
    required this.itemName,
    required this.onAction,
    this.isGiven = false,
    this.isCut = false,
    this.showWeigh = false,
  });

  final String itemName;
  final ValueChanged<String> onAction;

  /// 是否已赠送（"赠送"显示为"取消赠送"）
  final bool isGiven;

  /// 是否已划菜（"划菜"显示为"取消划菜"）
  final bool isCut;

  /// 是否显示"称重"（称重菜 + 已开启"称重二次确认"）
  final bool showWeigh;

  /// 菜单与订单确认页已下单标签共用 buildOrderedOperations，保证两页菜品操作一致
  List<DishOperation> get _operations =>
      buildOrderedOperations(isGift: isGiven, isCut: isCut, showWeigh: showWeigh);

  /// 菜单图标（action → 图标）
  static const Map<String, IconData> _icons = <String, IconData>{
    DishOperationType.discount: Icons.percent,
    DishOperationType.gift: Icons.card_giftcard_outlined,
    DishOperationType.changePrice: Icons.price_change_outlined,
    DishOperationType.refund: Icons.undo,
    DishOperationType.urge: Icons.notifications_active_outlined,
    DishOperationType.startDish: Icons.play_circle_outline,
    DishOperationType.waiter: Icons.person_outline,
    DishOperationType.transferDish: Icons.compare_arrows,
    DishOperationType.reweigh: Icons.scale,
    DishOperationType.serveDish: Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 拖拽指示条（保持居中）
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E6EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      itemName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D2129),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: Wrap(
                runSpacing: 14,
                children: _operations
                    .map((DishOperation op) => SizedBox(
                          width: (MediaQuery.of(context).size.width - 32) / 4,
                          child: InkWell(
                            onTap: () => onAction(op.action),
                            borderRadius: BorderRadius.circular(10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F8FA),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFF2F3F5)),
                                  ),
                                  child: Icon(
                                    _icons[op.action] ?? Icons.circle_outlined,
                                    size: 22,
                                    color: const Color(0xFF4E5969),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  op.label.replaceAll('\n', ''),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF4E5969)),
                                ),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
