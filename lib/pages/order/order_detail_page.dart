import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/deposit_sheet.dart';
import 'package:flutter_deer/components/dish_operation_dialogs.dart';
import 'package:flutter_deer/components/edit_table_info_sheet.dart';
import 'package:flutter_deer/components/member_search_sheet.dart';
import 'package:flutter_deer/components/table_select_sheet.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/print_service.dart';
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

  /// 当前有效的 saleid（可能从接口响应中更新）
  String _saleid = '';

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
        final String name = userMap['username']?.toString() ?? '';
        if (name.isNotEmpty) {
          _operatorName = name;
        }
      }
    } catch (_) {}
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    _openTime = tmp?['billdate']?.toString() ?? '';
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
    _loadOrderDetail();
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
        resp = await requestForm(
          HttpApi.pcGetTableDetailList,
          <String, dynamic>{'tablemaster': jsonEncode(pcMasterBean)},
          masterDevice: true,
        );
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
            }
          }
        }
        _parseOrderData(data);
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
  void _parseOrderData(Map<String, dynamic> data) {
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
  }

  /// 按 vipid 获取完整会员信息（对齐 smdcapp CartGoodsModel.getVipData → OrderRepository.getVipInfo）
  ///
  /// 桌台 tmp 中的 vipid/vipname 只是基础信息，缺少 prefetype/discount 等定价字段，
  /// 需调 vip/getList 接口按 vipid 查询完整会员信息，否则录入会员后无法计算会员价。
  Future<void> _loadFullMemberInfo(String vipid) async {
    try {
      final List<VipMember> list = await OrderRepository.fetchVipList(vipid);
      if (!mounted) return;
      VipMember? full;
      for (final VipMember m in list) {
        if (m.vipid == vipid) {
          full = m;
          break;
        }
      }
      if (full == null) return;
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
  void _applyMemberPricing() {
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

      _calcDownMemberPrice(b, member);

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

  /// 单品价格重算（移植 smdcapp ShoppingCartUtil.getMemberPrice + getDownMemberPrice）
  void _calcDownMemberPrice(Map<String, dynamic> b, VipMember? member) {
    final double sellPrice = _toDouble(b['sellprice']);
    final double cookaddamt = _toDouble(b['cookaddamt']);
    final double combaddamt = _toDouble(b['combaddamt']);
    final int presentflag = _toInt(b['presentflag']);
    // 退菜行数量恒为负（对齐 smdcapp ReturnDishesPopup：qty = -退菜数量），
    // 服务端回传正数时按负数还原，否则退菜金额会被按正价计入
    double qty = _toDouble(b['qty']);
    if (presentflag == 2 && qty > 0) {
      qty = -qty;
    }
    final int dscflag = _toInt(b['dscflag']);
    double discount = _toDouble(b['discount']);
    if (discount == 0) discount = 100;
    final int origSpec = _toInt(b['specpriceflag']);

    // specpriceflag → disType 映射（对齐 smdcapp getMemberPrice）
    int disType;
    if (origSpec == 0) {
      disType = 0;
    } else if (origSpec < 4 || origSpec == 7) {
      disType = 3;
    } else if (origSpec == 5) {
      disType = 5;
    } else if (origSpec == 4) {
      disType = 1;
    } else {
      disType = 0;
    }
    final int startDisType = disType;

    // 不可打折但存在手工折扣 → 恢复原价（对齐 smdcapp getMemberPrice）
    if (dscflag != 1 && discount > 0 && discount < 100) {
      b['disType'] = 0;
      b['discount'] = 100;
      b['rrprice'] = sellPrice;
    } else {
      // 基础现价：原价与服务器现单价取低，手工折扣优先
      double tempPrice = sellPrice;
      final double serverRr = _toDouble(b['rrprice']);
      if (serverRr == 0 && origSpec != 0) tempPrice = serverRr;
      if (serverRr > 0 && serverRr < tempPrice) tempPrice = serverRr;
      if (dscflag == 1 && discount > 0 && discount < 100) {
        tempPrice = _round2(sellPrice * discount / 100);
      }
      // 会员价计算（对齐 smdcapp：仅当会员价低于当前价时生效）
      if (member != null) {
        switch (member.prefetype) {
          case 1:
            final double md = member.discount.toDouble();
            if (dscflag == 1 && md > 0 && md < 100) {
              final double p = _round2(sellPrice * md / 100);
              if (p < tempPrice) {
                tempPrice = p;
                b['discount'] = md;
                b['specpriceflag'] = 5;
                disType = 5;
              }
            }
            break;
          case 2:
          case 3:
          case 4:
            final double mp = _toDouble(b['mprice${member.prefetype - 1}']);
            if (mp != 0 && mp < tempPrice) {
              tempPrice = mp;
              b['specpriceflag'] = 5;
              disType = 5;
            }
            // 手工折扣更优时恢复原优惠类型
            if (discount > 0 && discount < 100) {
              final double p = _round2(sellPrice * discount / 100);
              if (p < tempPrice) {
                tempPrice = p;
                b['specpriceflag'] = origSpec;
                disType = startDisType;
              }
            }
            break;
        }
      }
      // 赠送商品现价为0（对齐 smdcapp）
      if (presentflag == 1) {
        disType = 2;
        b['rrprice'] = 0;
        tempPrice = 0;
      } else {
        b['rrprice'] = tempPrice;
      }
      b['disType'] = disType;
    }

    // ═══ 金额汇总（对齐 smdcapp getDownMemberPrice） ═══
    final double memberPrice = _toDouble(b['rrprice']);
    double tO = _round2(sellPrice * qty + combaddamt);
    double tR = _round2(memberPrice * qty + combaddamt);
    final int bxxpxxflag = _toInt(b['bxxpxxflag']);
    if (presentflag == 2) {
      // 退菜：赠送后退菜先归零，再退做法加价
      if (_toDouble(b['presentprice']) > 0) {
        tO = 0;
        tR = 0;
      }
      if (cookaddamt < 0) {
        tO = _round2(tO + cookaddamt);
        tR = _round2(tR + cookaddamt);
      } else {
        tO = _round2(tO - cookaddamt);
        tR = _round2(tR - cookaddamt);
      }
    } else if (presentflag == 1 ||
        bxxpxxflag == 1 ||
        bxxpxxflag == 2 ||
        bxxpxxflag == 6) {
      // 赠送：优惠金额为原价，现价仅含做法费
      tO = _round2(tO + cookaddamt);
      tR = cookaddamt;
      b['disType'] = 2;
    } else {
      tO = _round2(tO + cookaddamt);
      tR = _round2(tR + cookaddamt);
    }
    b['oldrramt'] = tO;
    b['rramt'] = tR;
  }

  /// 金额保留两位小数（避免浮点累计误差）
  double _round2(double v) => (v * 100).roundToDouble() / 100;

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
        'remark': widget.remark,
        'saleid': _saleid,
        'tableJson': widget.tableJson,
      },
    );
  }

  /// 去结账（对齐 smdcapp tvPay → SettleActivity）
  void _onSettle() {
    if (_detailList.isEmpty) {
      Toast.show('结账信息为空');
      return;
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
        'remark': widget.remark,
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
      },
    );
  }

  // ═══════════════════ 会员录入（对齐 smdcapp OrderDetailActivity: tvManageTwo + onActivityResult + upMember） ═══════════════════

  /// 标题栏“会员”按钮点击（对齐 smdcapp tvManageTwo.onClick → MemberActivity）
  Future<void> _onMemberTap() async {
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
    await _syncMemberToServer(
      vipid: member.vipid,
      vipno: member.vipno,
      vipname: member.vipname,
      vipmobile: member.mobile,
    );
    if (!mounted) return;
    setState(() => _member = member);
    // 对齐 smdcapp：会员录入成功后刷新订单数据（showData + postInfo）
    _loadOrderDetail();
  }

  /// 退出会员（对齐 smdcapp upMember(false)）
  Future<void> _logoutMember() async {
    await _syncMemberToServer(
      vipid: '',
      vipno: '',
      vipname: '',
      vipmobile: '',
    );
    if (!mounted) return;
    setState(() => _member = null);
    _loadOrderDetail();
  }

  /// 同步会员信息到后端桌台（对齐 smdcapp OrderModel.updateMasterTmp）
  Future<void> _syncMemberToServer({
    required String vipid,
    required String vipno,
    required String vipname,
    required String vipmobile,
  }) async {
    if (_memberSyncing) return;
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String saleid = tmp?['saleid']?.toString() ?? _saleid;
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
        remark: tmp?['remark']?.toString() ?? widget.remark,
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
    } catch (_) {
      Toast.show('同步会员信息失败');
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
    switch (type) {
      case '消台':
        _cancelTable();
        break;
      case '锁台':
        _lockTable();
        break;
      case '催菜':
        _allUrgeDish();
        break;
      case '起菜':
        _allStartDish();
        break;
      case '退菜':
        _allReturnDish();
        break;
      case '整单折扣':
        _allDiscount();
        break;
      case '赠送':
        _allGive();
        break;
      case '撤单':
        _withdrawOrder();
        break;
      case '转台':
        _changeTable();
        break;
      case '并台/拆台':
        _uniTable();
        break;
      case '转菜':
        _changeDishToTable();
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
      final bool useMaster = ConnectionManager.pcAlive;
      if (useMaster) {
        // 完整桌台 Bean 构造方式与消台/桌台操作弹窗入口保持一致
        final Map<String, dynamic> tableBean = TableDataUtils.buildFullTableBean(
          rawJson: widget.tableJson,
          fallback: <String, dynamic>{
            'tableid': widget.tableId,
            'name': widget.tableName,
            'code': widget.tableCode,
          },
        );
        tableBean['newtableid'] = widget.tableId;
        if (tableBean['tmp'] is Map) {
          (tableBean['tmp'] as Map<String, dynamic>)['lockflag'] = 1;
        }
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMasterTmpDto': tableBean,
          'flag': 1,
          'autoflag': 0,
        };
        await requestForm(
          HttpApi.pcTableLock,
          <String, dynamic>{'tablemaster': jsonEncode(pcMaster)},
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.lockFlagTable, <String, dynamic>{
          'tableid': widget.tableId,
          'lockflag': '1',
          'autoflag': '0',
        });
      }
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

      // 重新计算价格（对齐 smdcapp Arith.showAllPriceInfo：含会员价重算）
      _applyMemberPricing();

      // 对齐 smdcapp getMasterBean/getMasterBeanPC：组装主单
      final Map<String, dynamic> master = _buildOrderMaster();

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
        pcTmp['sendprintflag'] = printtype != '-1' ? '1' : '-1';
        // 主设备模式（对齐 smdcapp PCMasterBean）
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMaster': master,
          'detailList': _detailList,
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
          detail: jsonEncode(_detailList),
          printType: printtype,
          printAllType: printtype != '-1' ? 1 : -1,
          masterDevice: false,
        );
        // 对齐 smdcapp postTableInfo 云服务回调：sendPrint(createPrintInfo(p))
        if (printtype != '-1') {
          final String cloudBillno = master['billno']?.toString() ?? '';
          PrintService.instance.cloudPrintNotice(
            saleid: _saleid,
            billno: cloudBillno,
            opertype: printtype,
          );
        }
      }

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
    final String remark =
        remarkOverride ?? tmp?['remark']?.toString() ?? widget.remark;
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
      'amt': amtOverride ?? _payAmt,
      'retailamt': _dishAmt,
      'dscamt': _disAmt,
      'serviceamt': serviceamtOverride ?? _serviceAmt,
      'lowamt': _lowAmt,
      'addamt': addamt,
      'roundamt': 0,
      'payment': amtOverride ?? _payAmt,
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
    master['tmp'] = tmpCopy;
  }

  /// 单品操作分发（对齐 smdcapp showSingleOperation when(type)）
  void _handleSingleItemAction(String action, Map<String, dynamic> item) {
    switch (action) {
      case '退菜':
        _returnSingleDish(item);
        break;
      case '催菜':
        _urgeSingleDish(item);
        break;
      case '起菜':
        _startSingleDish(item);
        break;
      case '改价':
        _changePriceSingleDish(item);
        break;
      case '赠送':
        _giveSingleDish(item);
        break;
      case '取消赠送':
        _cancelGiveSingleDish(item);
        break;
      case '备注':
        _remarkSingleDish(item);
        break;
      case '打包':
        _bagSingleDish(item);
        break;
      case '划菜':
        _cutSingleDish(item);
        break;
      default:
        Toast.show('$action功能开发中');
    }
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
    returnItem['prnretflag'] = result.prnretflag;
    // 对齐 smdcapp showReturnPop：退菜明细 isPrint=true 且 seq 提升为最新，
    // 打印服务按 info.seq==bean.seq 过滤本次退菜单
    returnItem['isPrint'] = true;
    returnItem['seq'] = _nextDetailSeq();
    returnItem['hangflag'] = 0;
    returnItem['callflag'] = 0;
    returnItem['urgeflag'] = 0;
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
    }
    _detailList.add(returnItem);

    Toast.show('退菜成功');
    _postOrderUpdate(printtype: result.prnretflag == 1 ? '4' : '-1');
  }

  // ─────── 单品催菜（对齐 smdcapp OperationPopup.NAME_CC） ───────

  void _urgeSingleDish(Map<String, dynamic> item) {
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    _detailList[idx]['urgeflag'] = 1;
    _detailList[idx]['callflag'] = 0;
    // 对齐 smdcapp ACTION_REMIND_DISH：isPrint/hasurgeflag=99 标记 + seq 提升为最新
    // （打印过滤条件：qty>0 && urgeflag==1 && hasurgeflag==99 && info.seq==bean.seq）
    _detailList[idx]['isPrint'] = true;
    _detailList[idx]['hasurgeflag'] = 99;
    _detailList[idx]['updateflag'] = 1;
    _detailList[idx]['seq'] = _nextDetailSeq();
    Toast.show('催菜成功');
    _postOrderUpdate(printtype: '5');
  }

  // ─────── 单品起菜（对齐 smdcapp OperationPopup.NAME_QC） ───────

  void _startSingleDish(Map<String, dynamic> item) {
    if (_toInt(item['hangflag']) != 1) {
      Toast.show('商品未挂起，不能起菜');
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
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定将「${item['productname']}」设为赠送吗？',
    );
    if (!confirmed || !mounted) return;
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    _detailList[idx]['presentflag'] = 1;
    _detailList[idx]['rrprice'] = 0;
    _detailList[idx]['rramt'] = 0;
    _detailList[idx]['updateflag'] = 1;
    Toast.show('赠送成功');
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
    _detailList[idx]['rrprice'] = _toDouble(item['sellprice']);
    _calcDownMemberPrice(_detailList[idx], _member);
    _detailList[idx]['updateflag'] = 1;
    Toast.show('取消赠送成功');
    _postOrderUpdate();
  }

  // ─────── 单品备注（对齐 smdcapp RemarkPopup） ───────

  Future<void> _remarkSingleDish(Map<String, dynamic> item) async {
    final String? input = await InputDialog.show(
      context,
      title: '备注 - ${item['productname']?.toString() ?? ''}',
      hintText: '输入备注',
      initialValue: item['remark']?.toString() ?? '',
    );
    if (input == null || !mounted) return;
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    _detailList[idx]['remark'] = input;
    _detailList[idx]['updateflag'] = 1;
    Toast.show('备注成功');
    _postOrderUpdate();
  }

  // ─────── 单品打包（对齐 smdcapp BagPopup2） ───────

  void _bagSingleDish(Map<String, dynamic> item) {
    final int idx = _detailList.indexOf(item);
    if (idx < 0) return;
    final int currentBag = _toInt(item['bagflag']);
    _detailList[idx]['bagflag'] = currentBag == 1 ? 0 : 1;
    _detailList[idx]['updateflag'] = 1;
    Toast.show(currentBag == 1 ? '取消打包' : '打包成功');
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

  // ─────── 整单催菜（对齐 smdcapp updateAllDetailSign urgeflag=1） ───────

  void _allUrgeDish() {
    bool hasItem = false;
    // 对齐 smdcapp OperationPlacedActivity.CC：本次操作项统一提升 seq 为最新
    final int newSeq = _nextDetailSeq();
    for (final Map<String, dynamic> item in _detailList) {
      if (_toInt(item['presentflag']) == 2) continue;
      item['urgeflag'] = 1;
      item['callflag'] = 0;
      item['isPrint'] = true;
      item['hasurgeflag'] = 99;
      item['updateflag'] = 1;
      item['seq'] = newSeq;
      hasItem = true;
    }
    if (!hasItem) {
      Toast.show('无可催菜商品');
      return;
    }
    Toast.show('催菜成功');
    _postOrderUpdate(printtype: '5');
  }

  // ─────── 整单起菜（对齐 smdcapp updateAllDetailSign callflag=1, hangflag=0） ───────

  void _allStartDish() {
    bool hasItem = false;
    // 对齐 smdcapp OperationPlacedActivity.QC：本次操作项统一提升 seq 为最新
    final int newSeq = _nextDetailSeq();
    for (final Map<String, dynamic> item in _detailList) {
      if (_toInt(item['presentflag']) == 2) continue;
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
      Toast.show('没有挂起的商品，无需起菜');
      return;
    }
    Toast.show('起菜成功');
    _postOrderUpdate(printtype: '7');
  }

  // ─────── 整单退菜（对齐 smdcapp ReturnDishesPopup pos=-1） ───────

  Future<void> _allReturnDish() async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定要整单退菜吗？所有菜品将被退回',
    );
    if (!confirmed || !mounted) return;

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

    // 对齐 smdcapp: 整单退菜时给每个未退商品创建退菜明细
    final List<Map<String, dynamic>> returnItems = <Map<String, dynamic>>[];
    // 对齐 smdcapp OperationPlacedActivity.ZC2：本次操作项统一提升 seq 为最新
    final int newSeq = _nextDetailSeq();
    for (final Map<String, dynamic> item in _detailList) {
      if (_toInt(item['presentflag']) == 2) continue; // 已退的跳过
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
      returnItem['prnretflag'] = result.prnretflag;
      returnItem['isPrint'] = true;
      returnItem['seq'] = newSeq;
      returnItem['hangflag'] = 0;
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
    // 对齐 smdcapp changeDiscount(pos=-1)：逐行 updataDis，跳过不可打折/已退/已赠/团购行
    for (final Map<String, dynamic> item in _detailList) {
      final int presentflag = _toInt(item['presentflag']);
      final int tpdishflag = _toInt(item['tpdishflag']);
      final bool skipDsc = (_toInt(item['dscflag']) == 0 && tpdishflag != 1) ||
          (tpdishflag == 1 && _toInt(item['tpdscflag']) == 0);
      if (skipDsc ||
          _toDouble(item['subqty']) > 0 ||
          presentflag == 2 ||
          presentflag == 1 ||
          _toInt(item['douyinflag']) == 1) {
        continue;
      }
      final double sellprice = _toDouble(item['sellprice']);
      final double qty = _toDouble(item['qty']);
      // 对齐 smdcapp updataDis：>99 视为不打折恢复原价并清手工折扣标记，
      // 否则按折扣重算现价/金额并标记 specpriceflag=4/opertype=4（手工折扣）
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
      item['operremark'] = result.remark;
      item['opertime'] = _formatNow();
      item['updateflag'] = 1;
      _calcDownMemberPrice(item, _member);
    }
    // 对齐 smdcapp changeDiscount：整单折扣率同步 tmp.servicediscount 随主单上传
    _servicediscount = discount;
    // 对齐 smdcapp refresh()：先刷新本地 UI 再 postInfo，避免上传异常时页面无变化
    setState(() {});
    Toast.show('整单折扣成功');
    _postOrderUpdate();
  }

  // ─────── 整单赠送（对齐 smdcapp GiveNumPopup 整单） ───────

  Future<void> _allGive() async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定将整单所有菜品设为赠送吗？',
    );
    if (!confirmed || !mounted) return;
    for (final Map<String, dynamic> item in _detailList) {
      if (_toInt(item['presentflag']) == 2) continue;
      item['presentflag'] = 1;
      item['rrprice'] = 0;
      item['rramt'] = 0;
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

  // ─────── 转菜（对齐 smdcapp OrderDetailActivity.changeDishes 整桌转菜） ───────

  /// 获取转菜目标桌台（对齐 smdcapp ChangeDishesPopup：tablestatus="1,2" 已开台桌台，排除当前桌）
  Future<List<Map<String, dynamic>>> _fetchZcTargetTables() async {
    final bool useMaster = ConnectionManager.pcAlive;
    final Map<String, dynamic> resp = useMaster
        ? await requestForm(
            HttpApi.pcTableInfoList,
            <String, dynamic>{
              'is_page': 0,
              'page': 1,
              'pagesize': 100,
              'tablestatus': '1,2',
              'stopflag': '0',
            },
            masterDevice: true,
            showError: false,
          )
        : await requestForm(
            HttpApi.tableInfoList,
            <String, dynamic>{
              'is_page': '0',
              'page': '1',
              'pagesize': '100',
              'tablestatus': '1,2',
              'stopflag': '0',
            },
            showError: false,
          );
    final dynamic data = resp['Data'] ?? resp['data'];
    List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
    if (data is Map<String, dynamic>) {
      final dynamic rows =
          data['tableMasterTmpList'] ?? data['list'] ?? data['tableList'];
      if (rows is List) {
        list = rows.whereType<Map<String, dynamic>>().toList();
      }
    } else if (data is List) {
      list = data.whereType<Map<String, dynamic>>().toList();
    }
    // 排除当前桌台与无有效 saleid 的桌台（转菜目标必须为已开台桌台）
    return list.where((Map<String, dynamic> t) {
      final Map<String, dynamic>? tmp = t['tmp'] as Map<String, dynamic>?;
      final String tableid =
          tmp?['tableid']?.toString() ?? t['tableid']?.toString() ?? '';
      final String saleid = tmp?['saleid']?.toString() ?? '';
      return tableid != widget.tableId &&
          saleid.isNotEmpty &&
          saleid != _saleid;
    }).toList();
  }

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
      'amt': amt,
      'retailamt': oAmt,
      'dscamt': disAmt,
      'serviceamt': servermoney,
      'lowamt': minSalemoney,
      'addamt': addamt,
      'roundamt': 0,
      'payment': amt,
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

  /// 转菜（整桌转出，对齐 smdcapp changeDishes allDishes 分支）
  ///
  /// 主设备：组装 TableChangeProductRequestDto{inMasterTmpParmDto(新桌PCMasterBean),
  ///   outMasterTmpParmDto(老桌PCMasterBean), changelist(转出明细 dishzcflag=1/lssubqty=qty),
  ///   printFlag} → POST /api/table/TableChangeProduct（对齐 OrderModel.pcBatchPostTableInfo）
  /// 云服务：拉取新桌明细合并转出菜（对齐 yunAddDish）→ transProMaster 记录 →
  ///   upSaleMasterTmp 上传新桌（对齐 OrderModel.postInfo 云分支）→
  ///   老桌上传转出菜 deleteflag=1（对齐 zcPostInfo）
  Future<void> _changeDishToTable() async {
    try {
      if (_detailList.isEmpty) {
        Toast.show('无可转菜品');
        return;
      }
      final List<Map<String, dynamic>> tables = await _fetchZcTargetTables();
      if (!mounted) return;
      if (tables.isEmpty) {
        Toast.show('没有可用的目标桌台');
        return;
      }
      final Map<String, dynamic>? selected =
          await TableSelectSheet.show(context, tables: tables, title: '选择转入桌台');
      if (selected == null || !mounted) return;
      final Map<String, dynamic>? newTmp =
          selected['tmp'] as Map<String, dynamic>?;
      final String newSaleid = newTmp?['saleid']?.toString() ?? '';
      final String newTableId = newTmp?['tableid']?.toString() ??
          selected['tableid']?.toString() ??
          '';
      if (newSaleid.isEmpty || newTableId.isEmpty || newSaleid == _saleid) {
        Toast.show('目标桌台信息错误');
        return;
      }

      // 对齐 smdcapp changeDishes：转出明细 saleid=新桌、updateflag=1、remark=转菜，
      // prnretflag 取转菜打印开关（MMKV Constant.DISHES_ZC）
      final bool zcPrint = SpUtil.getBool('DISHES_ZC') ?? false;
      final int prnretflag = zcPrint ? 1 : 0;
      final List<Map<String, dynamic>> returnList = <Map<String, dynamic>>[];
      for (final Map<String, dynamic> item in _detailList) {
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

      final Map<String, dynamic> inMaster = _buildZcTargetMaster(
        target: selected,
        newTmp: newTmp ?? <String, dynamic>{},
        fastFoodBean: fastFoodBean,
        servermoney: servermoney,
        minSalemoney: minSalemoney,
      );

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

        // 老桌 PCMasterBean：整单转出后剩余菜品为空、金额归 0（对齐 getZcOutDishes）
        final Map<String, dynamic> outMaster = _buildOrderMaster(
          amtOverride: 0,
          serviceamtOverride: 0,
          addamtOverride: 0,
          remarkOverride: '',
        );
        outMaster['retailamt'] = 0;
        outMaster['dscamt'] = 0;
        outMaster['lowamt'] = 0;
        outMaster['payment'] = 0;
        outMaster['hangflag'] = 0;
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
            'detailList': <Map<String, dynamic>>[],
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
        // 老桌台更新（对齐 smdcapp zcPostInfo）：整单转出后剩余为空，
        // 转出明细带 deleteflag=1 一并上传
        final List<Map<String, dynamic>> oldFastFood =
            returnList.map((Map<String, dynamic> b) {
          final Map<String, dynamic> c = Map<String, dynamic>.from(b);
          c['updateflag'] = 1;
          c['deleteflag'] = 1;
          return c;
        }).toList();
        final Map<String, dynamic> outMaster = _buildOrderMaster(
          amtOverride: 0,
          serviceamtOverride: 0,
          addamtOverride: 0,
          remarkOverride: '',
        );
        outMaster['retailamt'] = 0;
        outMaster['dscamt'] = 0;
        outMaster['lowamt'] = 0;
        outMaster['payment'] = 0;
        outMaster['hangflag'] = 0;
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
      if (mounted) Toast.show('转菜失败，请重试');
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
        remark: widget.remark,
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
    final bool success = await EditTableInfoSheet.show(
      context,
      saleid: _saleid,
      tableId: widget.tableId,
      tableCode: widget.tableCode,
      tableName: widget.tableName,
      personnum: tmp?['personnum']?.toString() ?? widget.persons.toString(),
      remark: tmp?['remark']?.toString() ?? widget.remark,
      serverId: widget.serverId.isNotEmpty ? widget.serverId : (tmp?['serverid']?.toString() ?? ''),
      serverName: _serverName,
      tableJson: widget.tableJson,
    );
    if (success && mounted) {
      _loadOrderDetail();
      TableEventBus.fireTableChanged();
    }
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
    DepositSheet.showRecords(context, saleid: _saleid);
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
        // 对齐 smdcapp 云服务 postInfo("8")：printtype=8 上传主单与明细触发后台预打单
        final bool uploaded = await _postOrderUpdate(printtype: '8');
        printed = uploaded &&
            await PrintService.instance.prePrint(
              saleid: _saleid,
              billno: billno,
            );
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
        await requestForm(
          HttpApi.pcPrintKDInfo,
          <String, dynamic>{
            'saleid': _saleid,
            'spid': UserHelper.getSpidStr(),
            'sid': UserHelper.getSidStr(),
          },
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.restPrint, <String, dynamic>{
          'saleid': _saleid,
          'printtype': '15', // 客单
          'spid': UserHelper.getSpidStr(),
          'sid': UserHelper.getSidStr(),
        });
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
                Icon(Icons.group, size: 14, color: isDark ? Colors.white70 : const Color(0xFF86909C)),
                const SizedBox(width: 3),
                Text(
                  '${widget.persons}人',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF4E5969),
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
            ...showItems.map((Map<String, dynamic> item) => _buildItemRow(item, isDark)),
          // 共N件商品（展开/收起，对齐 smdcapp tvListNum）
          if (totalCount > 3)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
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
                        '共$totalCount件商品 ${_expanded ? "收起" : "展开"}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF86909C)),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 15,
                        color: const Color(0xFF86909C),
                      ),
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

    // 标签（对齐 smdcapp DishesTagHelper：赠/折/催/挂/退）
    final List<Widget> tags = <Widget>[];
    // 退完/退部分（原商品行）：退完后金额仍为本行原金额（退菜行以负数金额冲抵）
    if (subqty > 0 && presentflag != 2) {
      tags.add(_tag(
        subqty == qty ? '退完' : '退${_formatQty(subqty)}',
        const Color(0xFFE13426),
      ));
    }
    if (presentflag == 1) {
      tags.add(_tag('赠', const Color(0xFFFF8547)));
    }
    if (presentflag == 2) {
      tags.add(_tag('退', const Color(0xFFFFB300)));
    }
    if (discount > 0 && discount < 100) {
      tags.add(_tag('${(discount / 10.0).toStringAsFixed(1)}折', const Color(0xFF5672FF)));
    }
    if (_toInt(item['urgeflag']) == 1) {
      tags.add(_tag('催', const Color(0xFFFF8547)));
    }
    if (_toInt(item['hangflag']) == 1) {
      tags.add(_tag('挂', const Color(0xFF999999)));
    }
    // 划菜标签（对齐 smdcapp DishesTagHelper：cutflag==1 显示"划"）
    if (_toInt(item['cutflag']) == 1) {
      tags.add(_tag('划', const Color(0xFF00C15A)));
    }

    final bool isReturned = presentflag == 2;
    // 灰底（对齐 smdcapp OrderDetailActivity：退菜行、已退完的原商品行 → bg_gray_EAEEF6）
    final bool isGrayRow = isReturned || (subqty > 0 && qty - subqty == 0);

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
                          text: spec.isNotEmpty ? '($spec)$name' : name,
                          style: TextStyle(
                            fontSize: 14,
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
                      color: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF86909C),
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
                  style: const TextStyle(fontSize: 11, color: Color(0xFF86909C)),
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

  /// 单品操作弹窗（对齐 smdcapp showSingleOperation → OperationPopup）
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

  /// 价格行（标签灰色 + 金额深色）
  Widget _priceRow(String label, double value, bool isDark, {bool alignEnd = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$label:',
            style: const TextStyle(fontSize: 12, color: Color(0xFF86909C)),
          ),
          const SizedBox(width: 4),
          Text(
            '¥${_formatAmt(value)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : const Color(0xFF4E5969),
            ),
          ),
        ],
      ),
    );
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
          _infoRow(Icons.access_time_outlined, '开台时间', _openTime, isDark, lineColor),
          // 对齐 smdcapp initTabInfo: tvTableWaiter = "服务员：" + tmp.servername
          _infoRow(Icons.person_outline, '服务员', _serverName, isDark, lineColor),
          _infoRow(Icons.receipt_outlined, '最后下单', _lastOrderTime, isDark, lineColor),
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
              Icon(icon, size: 15, color: isDark ? Colors.white54 : const Color(0xFFC9CDD4)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF86909C)),
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
      return v.toStringAsFixed(2);
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

/// 单品操作底部弹窗（对齐 smdcapp OperationPopup 单品操作菜单）
class _SingleItemSheet extends StatelessWidget {
  const _SingleItemSheet({
    required this.itemName,
    required this.onAction,
    this.isGiven = false,
  });

  final String itemName;
  final ValueChanged<String> onAction;

  /// 当前菜品是否已赠送（已赠送时"赠送"显示为"取消赠送"）
  final bool isGiven;

  static const List<_OpItem> _actions = <_OpItem>[
    _OpItem('退菜', Icons.undo),
    _OpItem('赠送', Icons.card_giftcard_outlined),
    _OpItem('催菜', Icons.notifications_active_outlined),
    _OpItem('起菜', Icons.play_circle_outline),
    _OpItem('打包', Icons.shopping_bag_outlined),
    _OpItem('备注', Icons.note_alt_outlined),
    _OpItem('改价', Icons.price_change_outlined),
    _OpItem('划菜', Icons.check_circle_outline),
  ];

  /// 已赠送时把"赠送"替换为"取消赠送"
  List<_OpItem> get _effectiveActions => _actions
      .map((_OpItem e) =>
          (isGiven && e.name == '赠送') ? const _OpItem('取消赠送', Icons.card_giftcard_outlined) : e)
      .toList();

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
                children: _effectiveActions
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
