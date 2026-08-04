import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/dish_operation_dialogs.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/dish_operation_popup.dart';
import 'package:flutter_deer/components/spec_cook_sheet.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/theme_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红（对齐 smdcapp red_e13426）
const Color _kBrandRed = Color(0xFFE13426);

/// 订单确认页（对齐 smdcapp OrderConfirmationActivity2 排版）
class OrderConfirmPage extends StatefulWidget {
  const OrderConfirmPage({
    super.key,
    this.tableName = 'A01',
    this.persons = 5,
    this.cartItems = const <CartItem>[],
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
  final List<CartItem> cartItems;
  final String tableId;
  final String tableCode;
  final String saleid;
  final String serverId;
  final String serverName;
  final String remark;
  final Map<String, dynamic>? tableJson;

  @override
  State<OrderConfirmPage> createState() => _OrderConfirmPageState();
}

class _OrderConfirmPageState extends State<OrderConfirmPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// 待下单(来自购物车, 可编辑数量)
  late List<CartItem> _pendingItems;

  /// 已下单(从桌台已有订单数据)
  final List<CartItem> _orderedItems = <CartItem>[];

  /// 出品单开关（对齐 smdcapp cb_print_cpd）
  bool _printCpd = true;

  /// 客单开关（对齐 smdcapp cb_print_kd，默认值取 ENABLE_KD 参数）
  late bool _printKd;

  /// 整单备注
  String _orderRemark = '';

  /// 是否正在下单（防重复点击）
  bool _isOrdering = false;

  /// 加载状态
  bool _isLoading = false;

  /// 已下单列表加载中
  bool _loadingOrdered = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pendingItems = List<CartItem>.from(widget.cartItems);
    _orderRemark = widget.remark;
    // 对齐 smdcapp: cbPrintKd.isChecked = decodeBoolean(ENABLE_KD, true)
    _printKd = SpUtil.getBool('ENABLE_KD', defValue: true) ?? true;
    // 对齐 smdcapp PlacedOrderFragment2.initData：加载已下单菜品
    _loadOrderedItems();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ═══════════════ 已下单数据加载（对齐 smdcapp PlacedOrderFragment2 + CartGoodsModel.orderedDishes） ═══════════════

  /// 获取已下单菜品列表（对齐 smdcapp OrderModel.getTableInfo → detailList 中 id!=0 的明细）
  ///
  /// 主设备模式：POST /api/table/GetTableDetailList，参数 tablemaster = PCMasterBean JSON（含 tmp）
  /// 云服务模式：POST /YttSvr/app/sale/getSaleTmpDetail，参数 saleid
  Future<void> _loadOrderedItems() async {
    // 对齐 smdcapp: 已下单列表按 id!=0 过滤（CartGoodsModel.orderedDishes: allDishesList.filter { it.id != 0 }）
    setState(() => _loadingOrdered = true);
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
          showError: false,
        );
      } else {
        final Map<String, dynamic>? tmp =
            widget.tableJson?['tmp'] as Map<String, dynamic>?;
        final String saleid = tmp?['saleid']?.toString() ?? widget.saleid;
        if (saleid.isEmpty) {
          // 无 saleid（新开台未下过单），无需加载
          if (mounted) setState(() => _loadingOrdered = false);
          return;
        }
        resp = await requestForm(
          HttpApi.getSaleTmpDetail,
          <String, dynamic>{'saleid': saleid},
          showError: false,
        );
      }

      if (!mounted) return;

      // 解析 data（主设备: Data, 云: data）
      final dynamic data = resp['Data'] ?? resp['data'];
      if (data is Map<String, dynamic>) {
        final dynamic rawList = data['detailList'];
        if (rawList is List) {
          final List<CartItem> ordered = <CartItem>[];
          for (final dynamic raw in rawList) {
            if (raw is! Map<String, dynamic>) continue;
            // 对齐 smdcapp CartGoodsModel: id != 0 为已下单
            final int id = _toInt(raw['id']);
            if (id == 0) continue;
            ordered.add(_detailToCartItem(raw));
          }
          setState(() {
            _orderedItems.clear();
            _orderedItems.addAll(ordered);
          });
        }
      }
    } catch (_) {
      // 加载失败静默处理，不影响待下单流程
    } finally {
      if (mounted) setState(() => _loadingOrdered = false);
    }
  }

  /// 将接口明细 JSON 转为 CartItem（对齐 smdcapp PlacedOrderFragment2 展示字段）
  CartItem _detailToCartItem(Map<String, dynamic> d) {
    final double qty = _toDouble(d['qty']);
    final double sellprice = _toDouble(d['sellprice']);
    final double rrprice = _toDouble(d['rrprice']);
    final double rramt = _toDouble(d['rramt']);
    final int weighflag = _toInt(d['weighflag']);
    final int presentflag = _toInt(d['presentflag']);
    final double weighnum = _toDouble(d['weighnum']);

    final Product product = Product(
      id: d['productid']?.toString() ?? '',
      name: d['productname']?.toString() ?? '',
      price: sellprice,
      desc: '已下单',
      emoji: '🍜',
      gradient: const <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
    );

    final CartItem item = CartItem(
      product: product,
      quantity: weighflag == 1 ? 1 : qty.toInt(),
      specText: _firstNonEmpty(d['spec'], d['cooktext']),
      weighNum: weighflag == 1 ? (weighnum > 0 ? weighnum : qty) : 0,
    );
    item.remark = d['remark']?.toString() ?? '';
    item.orderedAmt = rramt;
    item.subqty = _toDouble(d['subqty']);
    item.isRefunded = presentflag == 2;
    item.isGift = presentflag == 1;
    // 使用服务端现单价 rrprice 展示（对齐 smdcapp tvOPrice = bean.rramt）
    item.customPrice = rrprice;
    return item;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// 取第一个非空非空串的值
  String _firstNonEmpty(dynamic a, dynamic b) {
    final String sa = a?.toString() ?? '';
    if (sa.isNotEmpty) return sa;
    return b?.toString() ?? '';
  }

  // ═══════════════════ 数据计算 ═══════════════════

  double _totalPrice(List<CartItem> items) =>
      items.fold(0, (double sum, CartItem item) => sum + item.totalPrice);

  int _totalCount(List<CartItem> items) =>
      items.fold(0, (int sum, CartItem item) => sum + item.quantity);

  double get _grandTotal =>
      _totalPrice(_pendingItems) + _totalPrice(_orderedItems);

  int get _grandCount =>
      _totalCount(_pendingItems) + _totalCount(_orderedItems);

  void _changeQuantity(CartItem item, int delta) {
    setState(() {
      item.quantity += delta;
      if (item.quantity <= 0) {
        _pendingItems.remove(item);
      }
    });
  }

  // ═══════════════════ 下单逻辑 ═══════════════════

  Future<void> _placeOrder() async {
    if (_isOrdering) {
      Toast.show('正在下单中，请稍后...');
      return;
    }
    if (_pendingItems.isEmpty && _orderedItems.isEmpty) {
      Toast.show('请添加商品');
      return;
    }

    setState(() {
      _isOrdering = true;
      _isLoading = true;
    });

    try {
      String printType = '-1';
      int printAllType = -1;
      if (_printCpd && _pendingItems.isNotEmpty) {
        printType = '3';
        printAllType = 1;
      }

      final bool masterDevice = ConnectionManager.pcAlive;

      final Map<String, dynamic> resp;
      if (masterDevice) {
        // 对齐 smdcapp PC模式: map["tablemaster"] = Gson().toJson(pcMasterBean)
        final String pcJson = _buildPlaceOrderPCJson(printType);
        resp = await OrderRepository.placeOrder(
          master: '',
          detail: '',
          masterDevice: true,
          pcMasterJson: pcJson,
        );
      } else {
        // 云服务模式: master/detail/printtype/printalltype
        final String masterJson = _buildMasterJson();
        final String detailJson = _buildDetailJson();
        resp = await OrderRepository.placeOrder(
          master: masterJson,
          detail: detailJson,
          printType: printType,
          printAllType: printAllType,
          masterDevice: false,
        );
      }

      final bool success = resp.containsKey('Success')
          ? resp['Success'] == true
          : (resp['retcode'] == 0);

      if (success) {
        Toast.show('下单成功');
        // 对齐 smdcapp：下单成功后返回桌台首页并刷新桌台数据（桌台变为待结算状态）
        TableEventBus.fireTableChanged();
        if (mounted) {
          Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
        }
      } else {
        final String msg = resp['retmsg']?.toString() ??
            resp['Message']?.toString() ??
            '下单失败';
        Toast.show(msg);
      }
    } catch (e) {
      Toast.show('下单失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _isOrdering = false;
          _isLoading = false;
        });
      }
    }
  }

  String _buildMasterJson() {
    String sid = '';
    String spid = '';
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '';
        spid = storeMap['spid']?.toString() ?? '';
      }
    } catch (_) {}

    String userId = '';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        userId = userMap['userid']?.toString() ?? '';
      }
    } catch (_) {}

    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;

    final double totalRR = _grandTotal;
    final double totalOriginal = _pendingItems.fold<double>(
            0.0, (double s, CartItem i) => s + i.product.price * i.quantity) +
        _orderedItems.fold<double>(
            0.0, (double s, CartItem i) => s + i.product.price * i.quantity);
    final double disAmt = totalOriginal - totalRR;
    // 对齐 smdcapp: addamt = 做法加价金额总和
    final double addamt = _pendingItems.fold<double>(
        0.0, (double s, CartItem i) => s + i.extraPrice);

    final Map<String, dynamic> master = <String, dynamic>{
      'tableid': widget.tableId.isNotEmpty
          ? widget.tableId
          : (tmp?['tableid']?.toString() ?? '-1'),
      'tablename': widget.tableName,
      'remark': _orderRemark,
      'amt': totalRR,
      'retailamt': totalOriginal,
      'dscamt': disAmt > 0 ? disAmt : 0,
      'serviceamt': 0,
      'lowamt': 0,
      'addamt': addamt,
      'sid': sid,
      'spid': spid,
      'cashid': userId,
      'status': 1,
      'androidoperflag': 1,
      'billtype': 7,
      'lastbilltype': 7,
      'version': 180,
      'updatetime': _formatDateTime(DateTime.now()),
    };

    if (tmp != null) {
      if (tmp['saleid'] != null) {
        master['saleid'] = tmp['saleid'].toString();
      }
      if (tmp['id'] != null) {
        master['id'] = tmp['id'];
      }
      if (tmp['tablestatus'] != null) {
        master['tablestatus'] = tmp['tablestatus'].toString();
      }
      if (tmp['billdate'] != null) {
        master['billdate'] = tmp['billdate'].toString();
      }
      if (tmp['localbillno'] != null) {
        master['localbillno'] = tmp['localbillno'].toString();
        master['billno'] = tmp['localbillno'].toString();
      }
      if (tmp['serverid'] != null) {
        master['serverid'] = tmp['serverid'].toString();
      }
      if (tmp['servername'] != null) {
        master['servername'] = tmp['servername'].toString();
      }
      // 对齐 smdcapp: billtype 从 tmp 取（tmp.billtype），无则默认7
      if (tmp['billtype'] != null) {
        master['billtype'] = tmp['billtype'];
      }
    } else {
      if (widget.serverId.isNotEmpty) {
        master['serverid'] = widget.serverId;
      }
      if (widget.serverName.isNotEmpty) {
        master['servername'] = widget.serverName;
      }
    }

    return jsonEncode(master);
  }

  String _buildDetailJson() {
    String sid = '';
    String spid = '';
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '';
        spid = storeMap['spid']?.toString() ?? '';
      }
    } catch (_) {}

    String userId = '';
    String userName = '';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        userId = userMap['userid']?.toString() ?? '';
        userName = userMap['username']?.toString() ?? '';
      }
    } catch (_) {}

    // 对齐 smdcapp: 明细项需要 saleid/tableid/billno 关联主单
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String saleid = tmp?['saleid']?.toString() ?? widget.saleid;
    final String billno = tmp?['localbillno']?.toString() ?? '';
    final String serverId = tmp?['serverid']?.toString() ?? widget.serverId;

    final List<Map<String, dynamic>> details = <Map<String, dynamic>>[];

    for (final CartItem item in _pendingItems) {
      details.add(<String, dynamic>{
        'id': 0,
        'spid': spid,
        'sid': sid,
        'productid': item.product.id,
        'productname': item.displayName,
        'qty': item.isWeigh ? item.weighNum : item.quantity.toDouble(),
        'sellprice': item.product.price,
        'rrprice': item.discountedUnitPrice,
        'rramt': item.totalPrice,
        'discount': item.discount,
        'remark': item.remark,
        'spec': item.specText,
        'presentflag': item.isGift ? 1 : 0,
        'hangflag': item.isSuspended ? 1 : 0,
        'weighflag': item.isWeigh ? 1 : 0,
        'weighnum': item.weighNum,
        'cookaddamt': item.extraPrice,
        'bagamt': item.bagPrice,
        'salesname':
            item.waiterName.isNotEmpty ? item.waiterName : widget.serverName,
        'salesid': serverId,
        'operid': userId,
        'opername': userName,
        'createtime': _formatDateTime(DateTime.now()),
        'updateflag': 1,
        'saleid': saleid,
        'billno': billno,
        'tableid': widget.tableId,
        'serverid': serverId,
        'servername': widget.serverName,
      });
    }

    return jsonEncode(details);
  }

  // ═══════════════════ PC模式下单数据构建 ═══════════════════

  /// smdcapp TableDetailBean 定义的 tmp 字段白名单（对齐 order_page.dart _kTmpFields）。
  /// 避免桌台列表接口返回的多余字段导致 .NET 服务端空引用。
  static const Set<String> _kTmpFields = <String>{
    'vipname', 'saleid', 'vipid', 'preprintflag', 'detailList', 'mustfreeflag',
    'cashid', 'uniflowno', 'cdflag', 'servicetimerange', 'servicediscount',
    'tabletypeid', 'additionid', 'servicebegintime', 'serviceendtime', 'operid',
    'opername', 'opermachno', 'tablestatus', 'containweight', 'amt', 'retailamt',
    'roundamt', 'serviceamt', 'lowamt', 'remark', 'personnum', 'spid', 'serverid',
    'vipno', 'localbillno', 'sid', 'vipmobile', 'billtype', 'lastbilltype',
    'dataiflag', 'billdate', 'servername', 'tableid', 'id', 'tablecode', 'billno',
    'unitableid', 'unitableno', 'unitablename', 'machno', 'tablename', 'hangflag',
    'lockflag', 'withdrawmemo', 'dscamt', 'addamt', 'payment', 'printkdflag',
    'printcpdflag', 'sendprintflag', 'confirmqty', 'createtime', 'updatetime',
    'appVersionName',
  };

  /// 构建主设备模式下单的 PCMasterBean JSON
  /// （对齐 smdcapp OrderConfirmationActivity2:
  ///   pcMasterBean.tableMaster = masterBean,
  ///   pcMasterBean.detailList = detailList,
  ///   orderModel.postTableInfo(Gson().toJson(pcMasterBean), "") ）
  String _buildPlaceOrderPCJson(String printType) =>
      jsonEncode(_buildPCMasterMap(printType: printType, forSave: false));

  /// 构建 PCMasterBean Map（对齐 smdcapp OrderModel.getMasterBeanPC + getDownOrderBean）
  ///
  /// [forSave] 保存菜品场景（对齐 smdcapp OrderConfirmationActivity2.saveProduct）：
  /// downPrice = ShoppingCartUtil.getDownPrice(null, null) 全零 → 主单金额均按 0 计算
  /// （amt/retailamt/dscamt/serviceamt/lowamt），且 getMasterBeanPC 不设置打印字段
  Map<String, dynamic> _buildPCMasterMap({
    String printType = '-1',
    bool forSave = false,
  }) {
    String sid = '';
    String spid = '';
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '';
        spid = storeMap['spid']?.toString() ?? '';
      }
    } catch (_) {}

    String userId = '';
    String userName = '';
    String machNo = '';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        userId = userMap['userid']?.toString() ?? '';
        userName = userMap['username']?.toString() ?? '';
      }
    } catch (_) {}
    machNo = SpUtil.getString(Constant.machNo) ?? '';

    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;

    // 对齐 smdcapp saveProduct: downPrice = getDownPrice(null, null) 全零 → 主单金额均按 0 计算
    final double totalRR = forSave ? 0.0 : _grandTotal;
    final double totalOriginal = forSave
        ? 0.0
        : _pendingItems.fold<double>(
                0.0, (double s, CartItem i) => s + i.product.price * i.quantity) +
            _orderedItems.fold<double>(
                0.0, (double s, CartItem i) => s + i.product.price * i.quantity);
    final double disAmt = forSave ? 0.0 : totalOriginal - totalRR;
    // 对齐 smdcapp: addamt = 做法加价金额总和（非套餐商品）
    final double addamt = _pendingItems.fold<double>(
        0.0, (double s, CartItem i) => s + i.extraPrice);

    // 对齐 smdcapp: hangflag = 任一明细 hangflag==1 则主单 hangflag=1
    int hangflag = 0;
    for (final CartItem item in _pendingItems) {
      if (item.isSuspended) {
        hangflag = 1;
        break;
      }
    }

    final String now = _formatDateTime(DateTime.now());

    // ── 构建 tableMaster（对齐 smdcapp OrderModel.getMasterBeanPC） ──
    final Map<String, dynamic> tableMaster = <String, dynamic>{
      'tableid': widget.tableId.isNotEmpty
          ? widget.tableId
          : (tmp?['tableid']?.toString() ?? '-1'),
      'tablename': widget.tableName,
      'remark': _orderRemark,
      'amt': totalRR,
      'retailamt': totalOriginal,
      'dscamt': disAmt > 0 ? disAmt : 0,
      'serviceamt': 0,
      'lowamt': 0,
      'addamt': addamt,
      'sid': sid,
      'spid': spid,
      'cashid': userId,
      'status': 1,
      'androidoperflag': 1,
      'version': 180,
      'updatetime': now,
      'hangflag': hangflag,
    };

    // 对齐 smdcapp: masterBean.tmp = tmp（完整 TableDetailBean）+ 设置打印控制字段
    final Map<String, dynamic> filteredTmp = <String, dynamic>{};
    if (tmp != null) {
      // 按白名单过滤（对齐 order_page.dart _filterMasterTmpDto 逻辑）
      tmp.forEach((String key, dynamic value) {
        if (_kTmpFields.contains(key)) {
          filteredTmp[key] = value;
        }
      });

      // 对齐 smdcapp getMasterBeanPC: 从 tmp 提取字段到 master 层
      if (tmp['saleid'] != null) {
        tableMaster['saleid'] = tmp['saleid'].toString();
      }
      if (tmp['id'] != null) {
        tableMaster['id'] = tmp['id'];
      }
      if (tmp['tablestatus'] != null) {
        tableMaster['tablestatus'] = tmp['tablestatus'].toString();
      }
      if (tmp['billdate'] != null) {
        tableMaster['billdate'] = tmp['billdate'].toString();
      }
      // 对齐 smdcapp getMasterBeanPC: localbillno 缺省时默认 "temp"
      final String localBillno = tmp['localbillno']?.toString() ?? '';
      final String billnoUse = localBillno.isNotEmpty ? localBillno : 'temp';
      tableMaster['localbillno'] = billnoUse;
      tableMaster['billno'] = billnoUse;
      if (tmp['serverid'] != null) {
        tableMaster['serverid'] = tmp['serverid'].toString();
      }
      if (tmp['servername'] != null) {
        tableMaster['servername'] = tmp['servername'].toString();
      }
      if (tmp['tabletypeid'] != null) {
        tableMaster['tabletypeid'] = tmp['tabletypeid'].toString();
      }
      if (tmp['servicediscount'] != null) {
        tableMaster['servicediscount'] = tmp['servicediscount'];
      }

      // 对齐 smdcapp: 在 tmp 上设置金额/打印控制字段
      // （保存菜品时 getMasterBeanPC 不设置打印字段，保留 tmp 原值）
      filteredTmp['opermachno'] = machNo;
      if (!forSave) {
        filteredTmp['printkdflag'] = _printKd ? 1 : 0;
        filteredTmp['printcpdflag'] = _printCpd ? 1 : 0;
        filteredTmp['sendprintflag'] = printType != '-1' ? '1' : '-1';
      }
      filteredTmp['roundamt'] = 0;
      filteredTmp['amt'] = totalRR;
      filteredTmp['serviceamt'] = 0;
      filteredTmp['retailamt'] = totalOriginal;
      filteredTmp['addamt'] = addamt;
      filteredTmp['lowamt'] = 0;
      filteredTmp['dscamt'] = disAmt > 0 ? disAmt : 0;
      filteredTmp['lastbilltype'] = 7;
      filteredTmp['updatetime'] = now;
      filteredTmp['remark'] = _orderRemark;
      filteredTmp['localbillno'] = billnoUse;
      filteredTmp['billno'] = billnoUse;

      tableMaster['tmp'] = filteredTmp;
    } else {
      if (widget.serverId.isNotEmpty) {
        tableMaster['serverid'] = widget.serverId;
      }
      if (widget.serverName.isNotEmpty) {
        tableMaster['servername'] = widget.serverName;
      }
      tableMaster['billdate'] = now;
    }

    // ── 组装 PCMasterBean（对齐 smdcapp PCMasterBean: tableMaster + detailList + isUnionFlag） ──
    return <String, dynamic>{
      'tableMaster': tableMaster,
      'detailList': _buildPCDetailList(
        sid: sid,
        spid: spid,
        userId: userId,
        userName: userName,
      ),
      'isUnionFlag': false,
    };
  }

  /// 构建主设备模式明细列表（对齐 smdcapp OrderModel.getDownOrderBean 核心字段）
  ///
  /// 下单与保存菜品共用（对齐 smdcapp：postTableInfo 与 saveProduct 的
  /// detailList 均来自同一套 getDownOrderBean/待下单列表结构）
  List<Map<String, dynamic>> _buildPCDetailList({
    required String sid,
    required String spid,
    required String userId,
    required String userName,
  }) {
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String saleid = tmp?['saleid']?.toString() ?? widget.saleid;
    final String billno = tmp?['localbillno']?.toString() ?? '';
    final String serverId = tmp?['serverid']?.toString() ?? widget.serverId;

    final List<Map<String, dynamic>> detailList = <Map<String, dynamic>>[];
    for (final CartItem item in _pendingItems) {
      detailList.add(<String, dynamic>{
        'id': 0,
        'spid': spid,
        'sid': sid,
        'productid': item.product.id,
        'productname': item.displayName,
        'qty': item.isWeigh ? item.weighNum : item.quantity.toDouble(),
        'sellprice': item.product.price,
        'rrprice': item.discountedUnitPrice,
        'rramt': item.totalPrice,
        'discount': item.discount,
        'remark': item.remark,
        'spec': item.specText,
        'presentflag': item.isGift ? 1 : 0,
        'hangflag': item.isSuspended ? 1 : 0,
        'weighflag': item.isWeigh ? 1 : 0,
        'weighnum': item.weighNum,
        'cookaddamt': item.extraPrice,
        'bagamt': item.bagPrice,
        'salesname':
            item.waiterName.isNotEmpty ? item.waiterName : widget.serverName,
        'salesid': serverId,
        'operid': userId,
        'opername': userName,
        'createtime': _formatDateTime(DateTime.now()),
        'updateflag': 1,
        'saleid': saleid,
        'billno': billno,
        'tableid': widget.tableId,
        'serverid': serverId,
        'servername': widget.serverName,
      });
    }
    return detailList;
  }

  /// 格式化时间为 yyyy-MM-dd HH:mm:ss（对齐 smdcapp DateUtils.getTimeStamp）
  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  /// 保存菜品（对齐 smdcapp tv_save_dishes → OrderModel.saveProduct）
  /// 仅主设备模式可用，将待下单商品保存到主设备临时数据
  Future<void> _saveProduct() async {
    if (_pendingItems.isEmpty) {
      Toast.show('待下单无商品可保存');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final String masterJson = _buildSaveProductJson();
      final Map<String, dynamic> resp = await OrderRepository.saveProduct(
        masterJson: masterJson,
      );
      final bool success =
          resp.containsKey('Success') ? resp['Success'] == true : (resp['retcode'] == 0);
      if (success) {
        Toast.show('保存成功');
      } else {
        final String msg = resp['Message']?.toString() ?? resp['retmsg']?.toString() ?? '保存失败';
        Toast.show(msg);
      }
    } catch (e) {
      Toast.show('保存菜品数据失败：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 构建保存菜品的JSON（对齐 smdcapp OrderConfirmationActivity2.saveProduct）
  ///
  /// fastFoodBean = 购物车待下单列表（getDownOrderBean 完整结构，filter mustflag != 1，
  /// 本项目无必点菜建模，等效全量待下单）
  /// downPrice = ShoppingCartUtil.getDownPrice(null, null) → 主单金额均按 0 计算
  /// masterBean = getMasterBeanPC(tableInfo, downPrice, minSalemoney=0, servermoney=0, addamt, remark)
  /// pcMasterBean = { tableMaster, detailList, isUnionFlag: false }
  /// → POST /api/Table/SaveProduct，参数 tablemaster = gson.toJson(pcMasterBean)
  String _buildSaveProductJson() {
    return jsonEncode(_buildPCMasterMap(forSave: true));
  }

  /// 整单备注弹窗（对齐 smdcapp showMark，采用项目统一 InputDialog 风格）
  Future<void> _showRemarkDialog() async {
    final String? result = await InputDialog.show(
      context,
      title: '整单备注',
      hintText: '输入整单备注…',
      initialValue: _orderRemark,
    );
    if (result != null) {
      setState(() => _orderRemark = result);
    }
  }

  /// 操作菜单（对齐 smdcapp showOperation）
  void _showOperationMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: SafeArea(
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
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('操作',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                _OperationItem(icon: Icons.lock_open, label: '解锁台', onTap: () {
                  Navigator.pop(ctx);
                  _lockOrUnlockTable(lock: false);
                }),
                _OperationItem(icon: Icons.lock, label: '锁台', onTap: () {
                  Navigator.pop(ctx);
                  _lockOrUnlockTable(lock: true);
                }),
                _OperationItem(icon: Icons.percent, label: '整单折扣', onTap: () {
                  Navigator.pop(ctx);
                  _applyAllDiscount();
                }),
                const SizedBox(height: 8),
                Container(height: 8, color: const Color(0xFFF5F6F8)),
                _OperationItem(
                    icon: Icons.close,
                    label: '取消',
                    onTap: () => Navigator.pop(ctx)),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 锁台/解锁台（对齐 smdcapp lockFlagTable，lockflag=1锁/0解）
  Future<void> _lockOrUnlockTable({required bool lock}) async {
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      if (useMaster) {
        final Map<String, dynamic> tableBean =
            Map<String, dynamic>.from(widget.tableJson ?? <String, dynamic>{});
        tableBean['newtableid'] = widget.tableId;
        if (tableBean['tmp'] is Map) {
          (tableBean['tmp'] as Map<String, dynamic>)['lockflag'] = lock ? 1 : 0;
        }
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMasterTmpDto': tableBean,
          'flag': lock ? 1 : 0,
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
          'lockflag': lock ? '1' : '0',
          'autoflag': '0',
        });
      }
      if (!mounted) return;
      Toast.show(lock ? '锁台成功' : '解锁台成功');
      TableEventBus.fireTableChanged();
    } catch (_) {
      if (mounted) Toast.show(lock ? '锁台失败' : '解锁台失败');
    }
  }

  /// 整单折扣（对齐 smdcapp FastPrometionDiscountPopup）
  ///
  /// 对购物车中所有可打折商品应用折扣，更新购物车价格。
  Future<void> _applyAllDiscount() async {
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
    setState(() {
      for (final CartItem item in _pendingItems) {
        // 对齐 smdcapp: 赠送/不可打折商品跳过
        if (item.isGift) continue;
        if (item.product.dscflag == 0) continue;
        item.discount = discount;
      }
    });
    Toast.show('整单折扣已应用');
  }

  // ═══════════════════ UI构建（对齐 smdcapp activity_order_confirmation.xml） ═══════════════════

  /// 标题栏：返回箭头 + "桌台名--订单确认"
  Widget _buildTitleBar() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 46,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 46, minHeight: 46),
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 17, color: Color(0xFF1D2129)),
                onPressed: () => NavigatorUtils.goBack(context),
              ),
              Expanded(
                child: Text(
                  '${widget.tableName}--订单确认',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D2129),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// 头部信息卡片（合计 + 整单备注 + 会员，统一圆角卡片布局）
  Widget _buildHeaderCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1D2129).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          // ── 合计金额区（浅红渐变突出） ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFFFFF7F5), Colors.white],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(bottom: 3),
                  child: Text('合计',
                      style: TextStyle(fontSize: 13, color: Color(0xFF86909C))),
                ),
                const SizedBox(width: 10),
                Text(
                  '¥${_formatPrice(_grandTotal)}',
                  style: const TextStyle(
                    fontSize: 26,
                    color: _kBrandRed,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共$_grandCount份',
                    style: const TextStyle(
                        fontSize: 12,
                        color: _kBrandRed,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF2F3F5)),
          // ── 整单备注行 ──
          GestureDetector(
            onTap: _showRemarkDialog,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.edit_note, size: 18, color: Color(0xFFC9CDD4)),
                  const SizedBox(width: 6),
                  const Text('整单备注',
                      style: TextStyle(fontSize: 13, color: Color(0xFF4E5969))),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _orderRemark.isNotEmpty ? _orderRemark : '点击添加备注',
                      style: TextStyle(
                        fontSize: 13,
                        color: _orderRemark.isNotEmpty
                            ? const Color(0xFF1D2129)
                            : const Color(0xFFC9CDD4),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 16, color: Color(0xFFC9CDD4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab栏：待下单(¥xx 共N份) / 已下单(¥xx 共N份)（对齐 smdcapp tab 显示格式）
  Widget _buildTabs() {
    final double pendingPrice = _totalPrice(_pendingItems);
    final int pendingCount = _totalCount(_pendingItems);
    final double orderedPrice = _totalPrice(_orderedItems);
    final int orderedCount = _orderedItems.length;

    final String leftLabel = pendingCount > 0
        ? '待下单(¥${_formatPrice(pendingPrice)} 共${pendingCount}份)'
        : '待下单(¥0)';
    final String rightLabel = orderedCount > 0
        ? '已下单(¥${_formatPrice(orderedPrice)} 共${orderedCount}份)'
        : '已下单(¥0)';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1D2129).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: _kBrandRed,
        unselectedLabelColor: const Color(0xFF86909C),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
        indicatorColor: _kBrandRed,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 0,
        tabs: <Widget>[
          Tab(height: 44, text: leftLabel),
          Tab(height: 44, text: rightLabel),
        ],
      ),
    );
  }

  /// 商品列表
  Widget _buildItemList(List<CartItem> items, {required bool editable}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.receipt_long_outlined, size: 44, color: const Color(0xFF1D2129).withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            const Text('暂无商品', style: TextStyle(fontSize: 13, color: Color(0xFFC9CDD4))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF2F3F5)),
      itemBuilder: (BuildContext context, int index) {
        final CartItem item = items[index];
        return _buildItemRow(item, editable: editable);
      },
    );
  }

  /// 单个商品行（对齐 smdcapp dishes_item_await_one2：名称+价格+数量控制+三点菜单）
  Widget _buildItemRow(CartItem item, {required bool editable}) {
    // 对齐 smdcapp: 退菜记录灰色背景 (presentflag==2 → bg_gray_EAEEF6)
    final bool refunded = item.isRefunded;
    return Container(
      color: refunded ? const Color(0xFFEAEEF6) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          // 商品名称 + 规格/备注 + 退菜标记
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        item.displayName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF1D2129)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 对齐 smdcapp tvReturnHint: "(退N)"
                    if (item.subqty > 0 && !refunded)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '(退${_formatPrice(item.subqty)})',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFFF7D00)),
                        ),
                      ),
                  ],
                ),
                if (item.specText.isNotEmpty || item.remark.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    [if (item.specText.isNotEmpty) item.specText, if (item.remark.isNotEmpty) '备注:${item.remark}'].join(' | '),
                    style: const TextStyle(fontSize: 11, color: Color(0xFFC9CDD4)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // 价格（对齐 smdcapp: 退菜显示负数金额）
          Text(
            refunded
                ? '¥${item.totalPrice < 0 ? '-' : ''}${_formatPrice(item.totalPrice.abs())}'
                : '¥${_formatPrice(item.totalPrice)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: refunded ? const Color(0xFF86909C) : const Color(0xFF1D2129),
            ),
          ),
          const SizedBox(width: 12),
          // 数量控制
          if (item.isWeigh)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '×${item.weighNum == item.weighNum.roundToDouble() ? item.weighNum.toInt().toString() : item.weighNum.toString()}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF86909C)),
              ),
            )
          else if (editable)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 减号
                GestureDetector(
                  onTap: () => _changeQuantity(item, -1),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE5E6EB), width: 1.2),
                    ),
                    child: const Icon(Icons.remove, size: 13, color: Color(0xFF86909C)),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Center(
                    child: Text(
                      '${item.quantity}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1D2129)),
                    ),
                  ),
                ),
                // 加号
                GestureDetector(
                  onTap: () => _changeQuantity(item, 1),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: _kBrandRed,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(color: Color(0x30E13426), blurRadius: 4, offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Icon(Icons.add, size: 13, color: Colors.white),
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('x${item.quantity}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF86909C))),
            ),
          const SizedBox(width: 6),
          // 三点菜单
          if (editable)
            GestureDetector(
              onTap: () => _showItemMenu(item),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.more_horiz, size: 16, color: Color(0xFF86909C)),
              ),
            ),
        ],
      ),
    );
  }

  /// 显示菜品操作弹窗（与点菜页购物车保持一致，对齐 smdcapp OperationPopup）
  Future<void> _showItemMenu(CartItem item) async {
    final String? operation = await DishOperationPopup.show(
      context,
      dishName: item.displayName,
      isCookProduct: true,
      isComboProduct: false,
      isSuspended: item.isSuspended,
    );
    if (operation == null || !mounted) return;
    _handleItemOperation(operation, item);
  }

  /// 处理菜品操作（对齐 smdcapp OperationPopup.OperationListener.onCallBack）
  Future<void> _handleItemOperation(String type, CartItem item) async {
    switch (type) {
      case DishOperationType.discount:
        if (item.isGift) {
          Toast.show('赠送商品不能打折');
          return;
        }
        final DiscountResult? result = await DishDiscountSheet.show(
          context,
          dishName: item.displayName,
          currentDiscount: item.discount,
        );
        if (result != null) {
          setState(() {
            item.discount = result.discount;
            item.discountRemark = result.discount >= 100 ? '' : result.remark;
          });
        }

      case DishOperationType.gift:
        final GiveResult? giftResult = await DishGiveSheet.show(
          context,
          dishName: item.displayName,
          maxNum: item.quantity.toDouble(),
          isGive: item.isGift,
        );
        if (giftResult != null) {
          setState(() {
            if (item.isGift) {
              item.isGift = false;
              item.giftRemark = '';
            } else {
              item.isGift = true;
              item.giftRemark = giftResult.remark;
            }
          });
        }

      case DishOperationType.changePrice:
        if (item.isGift) {
          Toast.show('赠送商品不能改价');
          return;
        }
        final double? price = await DishChangePriceSheet.show(
          context,
          dishName: item.displayName,
          currentPrice: item.unitPrice,
        );
        if (price != null) {
          setState(() {
            if (price == item.product.price + item.extraPrice) {
              item.customPrice = null;
            } else {
              item.customPrice = price;
            }
          });
        }

      case DishOperationType.suspend:
        if (!item.isSuspended) {
          setState(() => item.isSuspended = true);
          Toast.show('已挂起');
        }

      case DishOperationType.bag:
        final double? bagPrice = await DishBagSheet.show(
          context,
          dishName: item.displayName,
          currentBagPrice: item.bagPrice,
        );
        if (bagPrice != null) {
          setState(() {
            item.bagPrice = bagPrice <= -1 ? 0 : bagPrice;
          });
        }

      case DishOperationType.remark:
        final String? remark = await DishRemarkSheet.show(
          context,
          dishName: item.displayName,
          currentRemark: item.remark,
        );
        if (remark != null) {
          setState(() => item.remark = remark);
        }

      case DishOperationType.delete:
        setState(() => _pendingItems.remove(item));

      case DishOperationType.waiter:
        final Waiter? waiter = await DishWaiterSheet.show(
          context,
          dishName: item.displayName,
          currentWaiter: item.waiterName,
        );
        if (waiter != null) {
          setState(() => item.waiterName = waiter.name);
        }

      case DishOperationType.cook:
        await _handleCookModify(item);

      case DishOperationType.rename:
        final RenameResult? renameResult = await DishRenameSheet.show(
          context,
          dishName: item.displayName,
          currentPrice: item.unitPrice,
        );
        if (renameResult != null) {
          setState(() {
            item.customName = renameResult.name;
            item.customPrice = renameResult.price;
          });
        }
    }
  }

  /// 做法修改（对齐 smdcapp checkSpec + SpecCookPopup2）
  Future<void> _handleCookModify(CartItem item) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
    DishSpecData specData;
    try {
      specData = await OrderRepository.fetchProductCookSpec(item.product.id);
      // 对齐 smdcapp: 仅当"显示公共做法"开关开启时才拉取公共做法
      final bool showPublicCook = SpUtil.getBool('setting_show_public_cook', defValue: true) ?? true;
      if (showPublicCook && specData.publiccook.isEmpty) {
        final List<DishCookGroup> publicCooks = await OrderRepository.fetchPublicCooks();
        if (publicCooks.isNotEmpty) {
          specData = DishSpecData(
            specdata: specData.specdata,
            cookdata: specData.cookdata,
            publiccook: publicCooks,
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      Toast.show('获取做法信息失败');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();

    if (specData.cookdata.isEmpty && specData.publiccook.isEmpty) {
      Toast.show('该菜品没有做法可选');
      return;
    }

    final CookModifyResult? result = await SpecCookSheet.showModify(
      context,
      dishName: item.displayName,
      unitPrice: item.unitPrice,
      specData: specData,
      currentSpecText: item.specText,
    );
    if (result == null || !mounted) return;

    final String specPrefix = _deriveSpecPrefix(item, specData);
    setState(() {
      item.specText = specPrefix.isEmpty
          ? result.cookText
          : (result.cookText.isEmpty ? specPrefix : '$specPrefix、${result.cookText}');
      item.extraPrice = result.cookExtra;
    });
  }

  /// 从当前 specText 中推导规格名前缀（多规格商品保留规格名）
  String _deriveSpecPrefix(CartItem item, DishSpecData specData) {
    if (specData.specdata.isEmpty || item.specText.isEmpty) return '';
    for (final DishSpec spec in specData.specdata) {
      if (item.specText == spec.specname) return spec.specname;
      if (item.specText.startsWith('${spec.specname}、')) return spec.specname;
    }
    return '';
  }

  /// 底部操作区（对齐 smdcapp：出品单/客单开关 + 操作/保存菜品/加菜/立即下单）
  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1D2129).withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 出品单/客单开关行
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text('出品单',
                            style: TextStyle(fontSize: 12, color: Color(0xFF4E5969))),
                        const SizedBox(width: 2),
                        SizedBox(
                          height: 22,
                          child: FittedBox(
                            child: Switch(
                              value: _printCpd,
                              activeThumbColor: Colors.white,
                              activeTrackColor: const Color(0xFF00BFA5),
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: const Color(0xFFE5E6EB),
                              onChanged: (bool v) => setState(() => _printCpd = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 0.5, height: 16, color: const Color(0xFFE5E6EB)),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text('客单',
                            style: TextStyle(fontSize: 12, color: Color(0xFF4E5969))),
                        const SizedBox(width: 2),
                        SizedBox(
                          height: 22,
                          child: FittedBox(
                            child: Switch(
                              value: _printKd,
                              activeThumbColor: Colors.white,
                              activeTrackColor: const Color(0xFF00BFA5),
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: const Color(0xFFE5E6EB),
                              onChanged: (bool v) => setState(() => _printKd = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF2F3F5)),
            // 按钮行
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: <Widget>[
                  // 操作
                  Expanded(
                    child: _BottomBtn(
                      label: '操作',
                      trailing: const Icon(Icons.more_horiz, size: 15, color: Color(0xFF86909C)),
                      onTap: _showOperationMenu,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 保存菜品（仅主设备连接时显示）
                  if (ConnectionManager.pcAlive) ...[
                    Expanded(
                      child: _BottomBtn(
                        label: '保存菜品',
                        onTap: _isLoading ? null : _saveProduct,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 加菜
                  Expanded(
                    child: _BottomBtn(
                      label: '加菜',
                      onTap: () => NavigatorUtils.goBack(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 立即下单（红色主按钮）
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _isLoading ? null : _placeOrder,
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(color: Color(0x35E13426), blurRadius: 8, offset: Offset(0, 3)),
                          ],
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                )
                              : const Text('立即下单',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ThemeUtils.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6F8),
        body: Column(
          children: <Widget>[
            _buildTitleBar(),
            _buildHeaderCard(),
            _buildTabs(),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF1D2129).withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: TabBarView(
                    controller: _tabController,
                    children: <Widget>[
                      _buildItemList(_pendingItems, editable: true),
                      _loadingOrdered
                          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                          : _buildItemList(_orderedItems, editable: false),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  /// 价格格式化
  String _formatPrice(double price) {
    if (price == price.roundToDouble()) {
      return price.toInt().toString();
    }
    return price.toStringAsFixed(1);
  }
}

// ═══════════════════ 子组件 ═══════════════════

/// 底部灰色按钮（对齐 smdcapp com_shape_line_gray_4_bg_gray）
class _BottomBtn extends StatelessWidget {
  const _BottomBtn({required this.label, this.onTap, this.trailing});

  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E6EB), width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4E5969))),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// 操作菜单项
class _OperationItem extends StatelessWidget {
  const _OperationItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: const Color(0xFF4E5969)),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(fontSize: 15, color: Color(0xFF1D2129))),
          ],
        ),
      ),
    );
  }
}
