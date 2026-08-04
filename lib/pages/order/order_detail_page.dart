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
import 'package:flutter_deer/util/theme_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
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
    // 初始化桌台已有的会员信息（对齐 smdcapp: tableInfo.tmp.vipid/vipname）
    final String existVipid = tmp?['vipid']?.toString() ?? '';
    if (existVipid.isNotEmpty) {
      _member = VipMember(
        vipid: existVipid,
        vipname: tmp?['vipname']?.toString() ?? '',
        vipno: tmp?['vipno']?.toString() ?? '',
        mobile: tmp?['vipmobile']?.toString() ?? '',
      );
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
        resp = await requestForm(
          HttpApi.getSaleTmpDetail,
          <String, dynamic>{'saleid': _saleid},
        );
      }

      if (!mounted) {
        return;
      }

      // 解析 data（主设备: Data, 云: data）
      final dynamic data = resp['Data'] ?? resp['data'];
      if (data is Map<String, dynamic>) {
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

    // ═══ 价格计算（对齐 smdcapp Arith.showAllPriceInfo 简化版） ═══
    // 菜品费：非退菜商品的 rramt 合计（rramt = 现单价 × 数量 - 已退金额）
    double dishTotal = 0;
    for (final Map<String, dynamic> item in _detailList) {
      final int presentflag = _toInt(item['presentflag']);
      if (presentflag == 2) {
        continue; // 退菜不计入
      }
      dishTotal += _toDouble(item['rramt']);
    }
    _dishAmt = dishTotal;

    // 服务费/低消：优先取接口返回值（PC模式返回 serviceamt/lowamt）
    _serviceAmt = _toDouble(data['serviceamt'] != null && data['serviceamt'] != 0
        ? data['serviceamt']
        : data['serviceMoney']);
    _lowAmt = _toDouble(data['lowamt'] != null && data['lowamt'] != 0
        ? data['lowamt']
        : data['minSalemoney']);

    // 优惠合计：dscamt（主单折扣金额）
    _disAmt = _toDouble(data['dscamt']);

    // 待支付：优先取 amt（主单实收），否则计算
    final double amt = _toDouble(data['amt']);
    _payAmt = amt > 0 ? amt : (_dishAmt + _serviceAmt + _lowAmt - _disAmt);
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
        // 主设备消台直接传桌台 JSON，不包裹 tableMasterTmpDto
        await requestForm(
          HttpApi.pcCancelTable,
          <String, dynamic>{
            'tablemaster': jsonEncode(widget.tableJson ?? <String, dynamic>{}),
          },
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
        final Map<String, dynamic> tableBean =
            Map<String, dynamic>.from(widget.tableJson ?? <String, dynamic>{});
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
  Future<void> _postOrderUpdate({String printtype = '-1'}) async {
    if (_detailList.isEmpty) {
      Toast.show('订单明细为空');
      return;
    }
    try {
      final bool useMaster = ConnectionManager.pcAlive;
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

      // 重新计算价格（对齐 smdcapp Arith.showAllPriceInfo）
      double dishTotal = 0;
      for (final Map<String, dynamic> item in _detailList) {
        if (_toInt(item['presentflag']) == 2) continue;
        dishTotal += _toDouble(item['rramt']);
      }

      final String sid = SpUtil.getString('sid') ?? '';
      final String spid = SpUtil.getString('spid') ?? '';

      final Map<String, dynamic> master = <String, dynamic>{
        'saleid': _saleid,
        'tableid': widget.tableId.isNotEmpty ? widget.tableId : (tmp?['tableid']?.toString() ?? ''),
        'tablename': widget.tableName,
        'tablecode': widget.tableCode.isNotEmpty ? widget.tableCode : (tmp?['tablecode']?.toString() ?? ''),
        'amt': dishTotal + _serviceAmt + _lowAmt - _disAmt,
        'retailamt': dishTotal,
        'dscamt': _disAmt,
        'serviceamt': _serviceAmt,
        'lowamt': _lowAmt,
        'addamt': addamt,
        'hangflag': hangflag,
        'sid': sid,
        'spid': spid,
        'remark': tmp?['remark']?.toString() ?? widget.remark,
        'personnum': tmp?['personnum']?.toString() ?? widget.persons.toString(),
        'serverid': widget.serverId.isNotEmpty ? widget.serverId : (tmp?['serverid']?.toString() ?? ''),
        'servername': _serverName,
        'vipid': _member?.vipid ?? (tmp?['vipid']?.toString() ?? ''),
        'vipno': _member?.vipno ?? (tmp?['vipno']?.toString() ?? ''),
        'vipname': _member?.vipname ?? (tmp?['vipname']?.toString() ?? ''),
        'localbillno': tmp?['localbillno']?.toString() ?? '',
      };

      if (useMaster) {
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
      }

      if (!mounted) return;
      // 刷新订单数据
      _loadOrderDetail();
      TableEventBus.fireTableChanged();
    } catch (e) {
      if (mounted) Toast.show('操作失败：$e');
    }
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
    _detailList[idx]['updateflag'] = 1;
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
    _detailList[idx]['updateflag'] = 1;
    Toast.show('起菜成功');
    _postOrderUpdate(printtype: '7');
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
    _detailList[idx]['cutflag'] = currentCut == 1 ? 0 : 1;
    _detailList[idx]['updateflag'] = 1;
    Toast.show(currentCut == 1 ? '取消划菜' : '划菜成功');
    _postOrderUpdate();
  }

  // ─────── 整单催菜（对齐 smdcapp updateAllDetailSign urgeflag=1） ───────

  void _allUrgeDish() {
    bool hasItem = false;
    for (final Map<String, dynamic> item in _detailList) {
      if (_toInt(item['presentflag']) == 2) continue;
      item['urgeflag'] = 1;
      item['callflag'] = 0;
      item['updateflag'] = 1;
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
    for (final Map<String, dynamic> item in _detailList) {
      if (_toInt(item['presentflag']) == 2) continue;
      if (_toInt(item['hangflag']) == 1) {
        item['callflag'] = 1;
        item['hangflag'] = 0;
        item['updateflag'] = 1;
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
    // 对齐 smdcapp: 每个可打折商品 rramt = rrprice * qty * discount/100
    for (final Map<String, dynamic> item in _detailList) {
      if (_toInt(item['presentflag']) == 2) continue;
      if (_toInt(item['presentflag']) == 1) continue; // 赠送不打折
      if (_toInt(item['dscflag']) == 0) continue; // 不允许打折
      final double rrprice = _toDouble(item['rrprice']);
      final double qty = _toDouble(item['qty']);
      final double cookaddamt = _toDouble(item['cookaddamt']);
      _detailList[_detailList.indexOf(item)]['rramt'] =
          rrprice * qty * discount / 100 + cookaddamt;
      _detailList[_detailList.indexOf(item)]['discount'] = discount;
      _detailList[_detailList.indexOf(item)]['updateflag'] = 1;
    }
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
      content: '确定要撤单吗？撤单后订单将回到待下单状态',
    );
    if (!confirmed || !mounted) return;
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      final Map<String, dynamic>? tmp =
          widget.tableJson?['tmp'] as Map<String, dynamic>?;
      if (useMaster) {
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMasterTmpDto': widget.tableJson ?? <String, dynamic>{},
        };
        await requestForm(
          HttpApi.pcWithdrawTable,
          <String, dynamic>{'tablemaster': jsonEncode(pcMaster)},
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

  // ─────── 转菜（对齐 smdcapp TableChangeProduct） ───────

  Future<void> _changeDishToTable() async {
    try {
      final List<Map<String, dynamic>> tables = await TableOpsHelper.fetchFreeTables();
      if (!mounted) return;
      if (tables.isEmpty) {
        Toast.show('没有可用的目标桌台');
        return;
      }
      final Map<String, dynamic>? selected =
          await TableSelectSheet.show(context, tables: tables, title: '选择转入桌台');
      if (selected == null || !mounted) return;
      final String newTableId = selected['tableid']?.toString() ?? selected['id']?.toString() ?? '';
      if (newTableId.isEmpty) return;
      // 对齐 smdcapp: 主设备调用 TableChangeProduct 转菜
      final Map<String, dynamic> changeData = <String, dynamic>{
        'saleid': _saleid,
        'tableid': widget.tableId,
        'newtableid': newTableId,
      };
      await requestForm(
        HttpApi.pcTableChangeProduct,
        <String, dynamic>{'data': jsonEncode(changeData)},
        masterDevice: true,
      );
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

  Future<void> _prePrint() async {
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      // 对齐 smdcapp: 更新预打印标识 tablestatus=5
      if (useMaster) {
        await requestForm(
          HttpApi.pcUpdateMasterTmpPrePrintFlag,
          <String, dynamic>{
            'saleid': _saleid,
            'preprintflag': '1',
            'spid': SpUtil.getString('spid') ?? '',
            'sid': SpUtil.getString('sid') ?? '',
          },
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.updateMasterTmpPrePrintFlag, <String, dynamic>{
          'saleid': _saleid,
          'preprintflag': '1',
          'spid': SpUtil.getString('spid') ?? '',
          'sid': SpUtil.getString('sid') ?? '',
        });
      }
      if (!mounted) return;
      // 对齐 smdcapp: 预打通过 postInfo("8") 上传
      _postOrderUpdate(printtype: '8');
      Toast.show('预打成功');
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
            'spid': SpUtil.getString('spid') ?? '',
            'sid': SpUtil.getString('sid') ?? '',
          },
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.restPrint, <String, dynamic>{
          'saleid': _saleid,
          'printtype': '15', // 客单
          'spid': SpUtil.getString('spid') ?? '',
          'sid': SpUtil.getString('sid') ?? '',
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

    // 有效商品数（非退菜）
    final List<Map<String, dynamic>> validItems = _detailList
        .where((Map<String, dynamic> e) => _toInt(e['presentflag']) != 2)
        .toList();
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
    final double rrprice = _toDouble(item['rrprice']);
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
    if (presentflag == 1) {
      tags.add(_tag('赠', const Color(0xFFFF8547)));
    }
    if (presentflag == 2) {
      tags.add(_tag('退', const Color(0xFF999999)));
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

    final bool isReturned = presentflag == 2;

    return InkWell(
      onTap: () => _showItemOperation(item),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
          color: isReturned
              ? (isDark ? const Color(0xFF2A2B2C) : const Color(0xFFF7F8FA))
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
                            color: isReturned ? const Color(0xFFC9CDD4) : textColor,
                            decoration: isReturned ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 价格
                Text(
                  '¥${_formatAmt(rrprice)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: isReturned ? const Color(0xFFC9CDD4) : textColor,
                    decoration: isReturned ? TextDecoration.lineThrough : null,
                  ),
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

  /// 订单信息卡片（对齐 smdcapp 订单信息 CardView：开台时间/服务员/最后下单/点菜员）
  /// 服务员行受 setting_ShowWaiter 控制，点菜员行受 setting_show_display_waiter 控制
  Widget _buildOrderInfoCard(bool isDark) {
    final Color lineColor = isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F6F8);
    // 对齐 smdcapp OrderDetailActivity: isShowWaiter() && !salesname.isNullOrEmpty()
    final bool showWaiter = (SpUtil.getBool('setting_ShowWaiter') ?? false) && _serverName.isNotEmpty;
    // 对齐 smdcapp: isDisplayWaiter() && !opername.isNullOrEmpty()
    final bool showOper = (SpUtil.getBool('setting_show_display_waiter') ?? false) && _operatorName.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle('订单信息', isDark),
          const SizedBox(height: 4),
          _infoRow(Icons.access_time_outlined, '开台时间', _openTime, isDark, lineColor),
          if (showWaiter)
            _infoRow(Icons.person_outline, '服务员', _serverName, isDark, lineColor),
          _infoRow(Icons.receipt_outlined, '最后下单', _lastOrderTime, isDark, lineColor,
              isLast: !showOper),
          if (showOper)
            _infoRow(Icons.badge_outlined, '点菜员', _operatorName, isDark, lineColor, isLast: true),
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
              const Spacer(),
              Flexible(
                child: Text(
                  value.isEmpty ? '--' : value,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
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
          children: <Widget>[
            // 拖拽指示条
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E6EB),
                borderRadius: BorderRadius.circular(2),
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
  const _SingleItemSheet({required this.itemName, required this.onAction});

  final String itemName;
  final ValueChanged<String> onAction;

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
          children: <Widget>[
            // 拖拽指示条
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E6EB),
                borderRadius: BorderRadius.circular(2),
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
                children: _actions
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
