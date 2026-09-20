import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/dish_operation_dialogs.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/dish_operation_popup.dart';
import 'package:flutter_deer/components/dish_select_sheet.dart';
import 'package:flutter_deer/components/spec_cook_sheet.dart';
import 'package:flutter_deer/net/cart_event_bus.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/pages/order/promotion_manager.dart';
import 'package:flutter_deer/pages/order/widgets/promotion_gift_sheet.dart';
import 'package:flutter_deer/pages/order/widgets/set_meal_sheet.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/promotion_helper.dart';
import 'package:flutter_deer/util/print_service.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';
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
    this.fastMode = false,
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

  /// 快餐模式（对齐 smdcapp：无桌台，不走下单接口，直接去结账页上传流水）
  final bool fastMode;

  @override
  State<OrderConfirmPage> createState() => _OrderConfirmPageState();
}

class _OrderConfirmPageState extends State<OrderConfirmPage> with SingleTickerProviderStateMixin {
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

  /// 已下单明细的最大 seq（对齐 smdcapp：每次下单新加的菜 seq 在原基础上+1）
  int _orderedMaxSeq = 0;

  /// 已下单明细接口原始行（下单前促销校验接口的 details 入参，对齐 smdcapp
  /// post() 传完整 detailList：待下单 + 已下单）
  List<Map<String, dynamic>> _orderedRawRows = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // 对齐 smdcapp AwaitOrderFragment.data()：待下单列表 = 购物车全量（含必点菜）
    _pendingItems = List<CartItem>.from(widget.cartItems);
    _orderRemark = widget.remark;
    // 对齐 smdcapp: cbPrintKd.isChecked = decodeBoolean(ENABLE_KD, true)
    _printKd = SpUtil.getBool('ENABLE_KD', defValue: true) ?? true;
    // 对齐 smdcapp：订单确认页的价格信息由促销引擎重算（进入页面即重新校验基础促销）
    _revalidatePromotions();
    // 对齐 smdcapp PlacedOrderFragment2.initData：加载已下单菜品（快餐模式无已下单数据，跳过）
    if (!widget.fastMode) {
      _loadOrderedItems();
    }
  }

  /// 进入订单确认页时重新校验「待下单」商品的基础促销（对齐 smdcapp checkPromotion123）
  ///
  /// 加购时可能因促销数据未就绪、商品分类缺失等原因漏套促销，
  /// 这里按本地促销表重查并重新套用，保证行价与「促/折扣」标签和 smdcapp 一致。
  Future<void> _revalidatePromotions() async {
    try {
      await PromotionManager.instance.init(force: true);
      // 商品分类缺失时按本地商品库回填（对齐 smdcapp initOrderInfo：typeid 取本地商品）
      final Map<String, Map<String, dynamic>> local =
          await OrderRepository.fetchLocalProductPriceFields();
      if (!mounted) return;
      for (final CartItem item in _pendingItems) {
        if (item.typeid.isEmpty) {
          final String tid = local[item.product.id]?['typeid']?.toString() ?? '';
          if (tid.isNotEmpty) item.typeid = tid;
        }
      }
      PromotionManager.instance.revalidateAll(_pendingItems);
      if (mounted) setState(() {});
    } catch (e) {
      FileLogWriter.instance.writeToFile('订单确认页促销校验失败: $e', tag: '促销');
    }
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
            (widget.tableJson?['tmp'] as Map<String, dynamic>?) ?? <String, dynamic>{};
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
        final Map<String, dynamic>? tmp = widget.tableJson?['tmp'] as Map<String, dynamic>?;
        String saleid = tmp?['saleid']?.toString() ?? '';
        if (saleid.isEmpty) {
          saleid = widget.saleid;
        }
        if (saleid.isEmpty) {
          // 无 saleid（新开台未下过单），无需加载
          FileLogWriter.instance.writeToFile('已下单加载跳过: saleid为空（新开台未下过单）', tag: '已下单加载');
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
        if (rawList is List && rawList.isNotEmpty) {
          _orderedRawRows =
              rawList.whereType<Map<String, dynamic>>().toList();
          // 对齐 smdcapp CartGoodsModel.initOrderInfo：明细接口可能不返回
          // combflag 等商品参数，按 productid 从本地商品库回填（对齐 svn r132898）
          final Map<String, int> localCombFlags = await OrderRepository.fetchLocalCombFlags();
          if (!mounted) return;
          for (final dynamic raw in rawList) {
            if (raw is! Map<String, dynamic>) continue;
            final int? localFlag = localCombFlags[raw['productid']?.toString() ?? ''];
            if (localFlag != null) {
              raw['combflag'] = localFlag;
            }
          }

          // 数据驱动识别套餐主行：被其它行 combid 引用的 onlyid 必为主行，
          // 不依赖接口 combflag（对齐 smdcapp formatCombList 主子行关联关系）
          final Set<String> referencedOnlyIds = <String>{};
          for (final dynamic raw in rawList) {
            if (raw is! Map<String, dynamic>) continue;
            final String cId = raw['combid']?.toString() ?? '';
            final String oId = raw['onlyid']?.toString() ?? '';
            if (cId.isNotEmpty && cId != oId) {
              referencedOnlyIds.add(cId);
            }
          }

          final List<CartItem> ordered = <CartItem>[];
          final Map<String, CartItem> onlyIdMap = <String, CartItem>{};
          // 第一遍被当作子行、但找不到主行的行（降级平铺展示，避免整条丢失）
          final List<Map<String, dynamic>> orphanChildren = <Map<String, dynamic>>[];
          int maxSeq = 0;
          // 第一遍：主行转条目（套餐明细行第二遍归组，对齐 smdcapp
          // AwaitOrderFragment2: combflag==1 主行 + itemList 子行展示）
          //
          // 注意：与 smdcapp CartGoodsModel.orderedDishes 的 id!=0 过滤不同——
          // smdcapp 的 allDishesList 混有本地购物车未落单菜(id==0)需要过滤；
          // 此处数据纯来自 getSaleTmpDetail（云端临时明细表），返回的均为
          // 已下单明细，且云端可能不回传 id（为0），若过滤会导致整个列表
          // 为空（已下单 tab 暂无商品），故不按 id 过滤。
          for (final dynamic raw in rawList) {
            if (raw is! Map<String, dynamic>) continue;
            final int seq = _toInt(raw['seq']);
            if (seq > maxSeq) {
              maxSeq = seq;
            }
            final String combid = raw['combid']?.toString() ?? '';
            final String onlyid = raw['onlyid']?.toString() ?? '';
            // 套餐主行判定：combflag==1 / combid==自身onlyid（CombHelper
            // 主商品关联不变式）/ onlyid 被子行引用，三者任一即为主行
            final bool isMainRow = _toInt(raw['combflag']) == 1 ||
                (combid.isNotEmpty && combid == onlyid) ||
                (onlyid.isNotEmpty && referencedOnlyIds.contains(onlyid));
            if (!isMainRow && combid.isNotEmpty) {
              continue; // 套餐明细行，归组到主行
            }
            final CartItem item = _detailToCartItem(raw);
            ordered.add(item);
            if (onlyid.isNotEmpty) {
              onlyIdMap[onlyid] = item;
            }
          }
          // 第二遍：套餐明细行按 combid 归组到主行（对齐 smdcapp test3）
          for (final dynamic raw in rawList) {
            if (raw is! Map<String, dynamic>) continue;
            final String combid = raw['combid']?.toString() ?? '';
            final String onlyid = raw['onlyid']?.toString() ?? '';
            // 主行/独立行不归组（combid==自身onlyid 为套餐主行关联不变式）
            if (_toInt(raw['combflag']) == 1 || combid.isEmpty || combid == onlyid) {
              continue;
            }
            final CartItem? parent = onlyIdMap[combid];
            if (parent == null) {
              // 主行缺失（如服务端未返回主行/onlyid 丢失）：降级平铺展示
              orphanChildren.add(raw);
              continue;
            }
            // combproductid 非空时校验与主行商品一致（对齐 smdcapp formatCombList 子行过滤）
            final String combproductid = raw['combproductid']?.toString() ?? '';
            if (combproductid.isNotEmpty && combproductid != parent.product.id) {
              continue;
            }
            final double mainQty = parent.quantity > 0 ? parent.quantity.toDouble() : 1;
            parent.combItems.add(ComboSelectedItem(
              productid: raw['productid']?.toString() ?? '',
              productname: raw['productname']?.toString() ?? '',
              qty: _toDouble(raw['qty']) / mainQty,
              combaddamt: _toDouble(raw['combaddamt']) / mainQty,
              groupid: raw['combgroupid']?.toString() ?? '',
              combsetproductid: raw['combsetproductid']?.toString() ?? '',
              specname: _firstNonEmpty(raw['specname'], raw['spec']),
              sellprice: _toDouble(raw['sellprice']),
              unit: raw['unit']?.toString() ?? '',
              cookText: raw['cooktext']?.toString() ?? '',
              cookExtra: _toDouble(raw['cookaddamt']) / mainQty,
            ));
            // 套餐主行不展示旧版拼接 spec 串（明细已逐行展开）
            parent.specText = '';
          }
          // 归组失败的子行降级为普通行展示，避免数据静默丢失
          for (final Map<String, dynamic> orphan in orphanChildren) {
            ordered.add(_detailToCartItem(orphan));
          }

          FileLogWriter.instance.writeToFile(
              '已下单加载成功: ${useMaster ? '主设备' : '云服务'} '
              '明细${rawList.length}条 本地combflag库${localCombFlags.length}条 '
              '最终展示${ordered.length}条(套餐${ordered.where((CartItem i) => i.combItems.isNotEmpty).length}条) '
              '${ordered.map((CartItem i) => '${i.product.name}x${i.quantity}${i.combItems.isNotEmpty ? '(子${i.combItems.length})' : ''}').join(',')}',
              tag: '已下单加载');
          // 逐条记录接口原始行关键字段，便于核对服务端返回结构
          for (final dynamic raw in rawList) {
            if (raw is! Map<String, dynamic>) continue;
            FileLogWriter.instance.writeToFile(
                '已下单明细行: name=${raw['productname']} id=${raw['id']} '
                'combflag=${raw['combflag']} combid=${raw['combid']} '
                'onlyid=${raw['onlyid']} combproductid=${raw['combproductid']} '
                'qty=${raw['qty']} rramt=${raw['rramt']}',
                tag: '已下单加载');
          }

          setState(() {
            _orderedMaxSeq = maxSeq;
            _orderedItems.clear();
            _orderedItems.addAll(ordered);
          });
        } else {
          FileLogWriter.instance.writeToFile(
              '已下单加载: ${useMaster ? '主设备' : '云服务'} '
              'data.detailList为空 rawKeys=${data.keys.join(',')}',
              tag: '已下单加载');
        }
      } else {
        FileLogWriter.instance
            .writeToFile('已下单加载: data结构异常 resp=${jsonEncode(resp)}', tag: '已下单加载');
      }
    } catch (e) {
      // 加载失败记录日志（对齐 smdcapp JsonWriter），便于定位接口/解析问题
      FileLogWriter.instance.writeToFile('已下单加载失败: $e', tag: '已下单加载');
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
      // 必传可变列表：默认值是 const 不可变列表，套餐子行归组 add 会抛
      // "Cannot add to an unmodifiable list"导致已下单加载整体失败
      combItems: <ComboSelectedItem>[],
    );
    item.remark = d['remark']?.toString() ?? '';
    item.orderedAmt = rramt;
    item.subqty = _toDouble(d['subqty']);
    item.isRefunded = presentflag == 2;
    item.isGift = presentflag == 1;
    // 已划菜状态（对齐 smdcapp cutflag，用于已下单菜单"划菜/取消划菜"文案）
    item.isCut = _toInt(d['cutflag']) == 1;
    // 团购核销菜标识（对齐 smdcapp douyinflag：为 1 时不提供单品操作）
    item.douyinflag = _toInt(d['douyinflag']);
    // 规格与做法分列（对齐 smdcapp DetailListBean.spec / cooktext）
    item.specName = d['spec']?.toString() ?? '';
    item.cookText = d['cooktext']?.toString() ?? '';
    // 必点菜标识还原（对齐 smdcapp DetailListBean mustflag/mustType）
    item.mustflag = _toInt(d['mustflag']);
    item.mustType = _toInt(d['mustType'] ?? d['musttype']);
    // 挂起/打包状态还原（用于列表标签展示）
    item.isSuspended = _toInt(d['hangflag']) == 1;
    item.bagPrice = _toDouble(d['bagamt']);
    item.isBag = _toInt(d['bagstatus']) == 1 || item.bagPrice > 0;
    // 基础促销还原（用于"促"标签与折后价展示）
    item.discount = _toDouble(d['discount']) == 0 ? 100 : _toDouble(d['discount']);
    item.jcmbillid = d['jcmbillid']?.toString() ?? '';
    item.specpriceflag = _toInt(d['specpriceflag']);
    // 场景促销赠品还原（用于下单前"已赠数量"统计，对齐 smdcapp cxmbillid/bxxpxxflag）
    item.cxmbillid = d['cxmbillid']?.toString() ?? '';
    item.bxxpxxflag = _toInt(d['bxxpxxflag']);
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

  /// 生成明细唯一标识 onlyid（对齐 smdcapp OrderModel.getonlyId：
  /// 机号 + 'a' + yyMMddHHmmss + 随机字符串，总长20位）
  String _genOnlyId() {
    final String machNo = SpUtil.getString(Constant.machNo) ?? '';
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final String timePart = '${(now.year % 100).toString().padLeft(2, '0')}'
        '${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    const String base = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final int randomLen = 20 - machNo.length - 1 - timePart.length;
    final math.Random rnd = math.Random.secure();
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < (randomLen > 0 ? randomLen : 4); i++) {
      sb.write(base[rnd.nextInt(base.length)]);
    }
    return '${machNo}a$timePart${sb.toString()}';
  }

  // ═══════════════════ 数据计算 ═══════════════════

  double _totalPrice(List<CartItem> items) =>
      items.fold(0, (double sum, CartItem item) => sum + item.totalPrice);

  int _totalCount(List<CartItem> items) =>
      items.fold(0, (int sum, CartItem item) => sum + item.quantity);

  double get _grandTotal => _totalPrice(_pendingItems) + _totalPrice(_orderedItems);

  int get _grandCount => _totalCount(_pendingItems) + _totalCount(_orderedItems);

  void _changeQuantity(CartItem item, int delta) {
    // 对齐 smdcapp checkQtyValid：必点菜不能操作
    if (item.mustflag == 1) {
      Toast.show('必点菜不能操作');
      return;
    }
    setState(() {
      item.quantity += delta;
      if (item.quantity <= 0) {
        _pendingItems.remove(item);
        // 赠品同步移除点菜页购物车（赠品在下单前才加入购物车，见 _mergeGiftSelections）
        if (item.isGift && widget.cartItems.contains(item)) {
          widget.cartItems.remove(item);
          CartEventBus.fireCartChanged();
        }
      }
    });
  }

  // ═══════════════════ 下单逻辑 ═══════════════════

  Future<void> _placeOrder() async {
    // 对齐 smdcapp：快餐模式无桌台，不走 upSaleMasterTmp 下单，直接去结账页
    if (widget.fastMode) {
      _goSettle();
      return;
    }
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
      // 下单前促销校验（对齐 smdcapp post() → getSalesPromotionList(promoflag=2) → showGivePop）：
      // 有剩余可赠额度时弹赠品选择弹窗，取消则中止下单
      if (!await _checkGiftPromotion()) return;

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

      final bool success =
          resp.containsKey('Success') ? resp['Success'] == true : (resp['retcode'] == 0);

      if (success) {
        Toast.show('下单成功');
        // 对齐 smdcapp postTableInfo 成功后的打印回调：触发厨打/出品单打印
        final String billno = widget.tableJson?['tmp']?['localbillno']?.toString() ?? '';
        final String saleid = widget.saleid.isNotEmpty
            ? widget.saleid
            : (widget.tableJson?['tmp']?['saleid']?.toString() ?? '');
        PrintService.instance.triggerCookPrint(saleid: saleid, billno: billno);
        // 对齐 smdcapp：下单成功后返回桌台首页并刷新桌台数据（桌台变为待结算状态）
        TableEventBus.fireTableChanged();
        if (mounted) {
          Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
        }
      } else {
        final String msg = resp['retmsg']?.toString() ?? resp['Message']?.toString() ?? '下单失败';
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

  // ═══════════════════ 下单前促销校验（对齐 smdcapp OrderConfirmationActivity2.post()） ═══════════════════

  /// 桌台绑定的会员ID（对齐 smdcapp PlacedOrderBean.tableInfoBean.tmp.vipid）
  String get _promoVipid => widget.tableJson?['tmp']?['vipid']?.toString() ?? '';

  /// 订单ID（对齐 smdcapp post(): dwonBean.tableInfoBean.tmp.saleid）
  String get _promoSaleid {
    final String tmpSaleid = widget.tableJson?['tmp']?['saleid']?.toString() ?? '';
    return tmpSaleid.isNotEmpty ? tmpSaleid : widget.saleid;
  }

  /// 本单菜品总原价（对齐 smdcapp downPrice.tempOPrice = Σ(原价×数量 + 做法加价)）
  double get _promoCheckAmt {
    double amt = 0;
    for (final CartItem item in <CartItem>[..._pendingItems, ..._orderedItems]) {
      amt += item.product.price * item.priceQty + item.extraPrice;
    }
    return amt;
  }

  /// 本单总数量（对齐 smdcapp downPrice.tempQty）
  String get _promoCheckQty {
    double qty = 0;
    for (final CartItem item in <CartItem>[..._pendingItems, ..._orderedItems]) {
      qty += item.priceQty;
    }
    return qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
  }

  /// 下单前促销校验：买赠/满赠活动及赠品（对齐 smdcapp post()）
  ///
  /// 无活动/无剩余额度直接下单；有额度则弹赠品选择弹窗，
  /// 选中的赠品并入待下单明细后继续下单。返回 false 表示取消下单。
  Future<bool> _checkGiftPromotion() async {
    final List<PromotionGiftActivity> activities =
        await PromotionHelper.fetchGiftActivities(
      saleid: _promoSaleid,
      amt: _promoCheckAmt,
      qty: _promoCheckQty,
      // 对齐 smdcapp post()：details 传完整明细（待下单 + 已下单）
      details: jsonEncode(<Map<String, dynamic>>[
        ..._orderedRawRows,
        ..._buildDetailList(),
      ]),
      vipid: _promoVipid,
    );
    if (activities.isEmpty) return true;

    // 已赠数量：按活动统计当前明细中的赠品行（含已下单，对齐 giveNum 的 sendList 统计）
    final Map<String, double> givenMap = <String, double>{};
    for (final CartItem item in <CartItem>[..._pendingItems, ..._orderedItems]) {
      if (item.cxmbillid.isEmpty) continue;
      givenMap[item.cxmbillid] = (givenMap[item.cxmbillid] ?? 0) + item.priceQty;
    }
    final List<PromotionGiftActivity> available = <PromotionGiftActivity>[];
    for (final PromotionGiftActivity a in activities) {
      a.givenQty = givenMap[a.billid] ?? 0;
      if (a.remainQty > 0) available.add(a);
    }
    if (available.isEmpty) {
      FileLogWriter.instance.writeToFile('下单前促销校验: 活动已赠完，直接下单', tag: '促销');
      return true;
    }
    if (!mounted) return false;

    final List<PromotionGiftSelection>? selected =
        await PromotionGiftSheet.show(context, activities: available);
    if (selected == null) {
      // 关闭弹窗 = 取消下单（对齐 smdcapp 未选择赠品不提交）
      FileLogWriter.instance.writeToFile('下单前促销校验: 用户取消赠品选择，中止下单', tag: '促销');
      return false;
    }
    if (selected.isEmpty) return true;
    setState(() => _mergeGiftSelections(selected));
    FileLogWriter.instance.writeToFile(
        '下单前促销校验: 选中赠品${selected.length}种 '
        '${selected.map((PromotionGiftSelection s) => '${s.name}x${s.qty}').join(',')}',
        tag: '促销');
    return true;
  }

  /// 赠品并入待下单明细（对齐 smdcapp showGivePop.onCallBack：
  /// 同活动同商品已存在则累加数量，否则新增赠品行）
  void _mergeGiftSelections(List<PromotionGiftSelection> selections) {
    for (final PromotionGiftSelection sel in selections) {
      CartItem? exist;
      for (final CartItem item in _pendingItems) {
        if (item.isGift &&
            item.cxmbillid == sel.cxmbillid &&
            item.product.id == sel.productid) {
          exist = item;
          break;
        }
      }
      final int qty = sel.qty.toInt() > 0 ? sel.qty.toInt() : 1;
      if (exist != null) {
        exist.quantity += qty;
        continue;
      }
      final CartItem gift = CartItem(
        product: Product(
          id: sel.productid,
          name: sel.name,
          price: sel.sellprice,
          desc: '赠品',
          emoji: '🎁',
          gradient: const <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
        ),
        quantity: qty,
      );
      gift.isGift = true;
      gift.cxmbillid = sel.cxmbillid;
      gift.bxxpxxflag = sel.bxxpxxflag;
      gift.typeid = sel.typeid;
      gift.unit = sel.unit;
      _pendingItems.add(gift);
      // 赠品同步进点菜页购物车（两页共用购物车，对齐 smdcapp cartMode.addCart）
      if (!widget.cartItems.contains(gift)) {
        widget.cartItems.add(gift);
      }
    }
    CartEventBus.fireCartChanged();
  }

  /// 快餐模式去结账（对齐 smdcapp OrderFastDetailActivity3.goSettle → SettleActivity）
  ///
  /// 快餐无桌台，smdcapp 从不调用 upSaleMasterTmp，单据（master/detail）
  /// 在结账页随支付通过 saleflow 一并上传。
  void _goSettle() {
    if (_pendingItems.isEmpty) {
      Toast.show('当前没有商品，请添加商品');
      return;
    }

    // 金额口径对齐 smdcapp getDownPrice/showAllPriceInfo：
    // 菜品费=总原价+做法加价，优惠=菜品费-应付，应付=现价合计
    final double totalRR = _grandTotal;
    final double totalOriginal = _pendingItems.fold<double>(
            0.0, (double s, CartItem i) => s + i.product.price * i.quantity) +
        _orderedItems.fold<double>(0.0, (double s, CartItem i) => s + i.product.price * i.quantity);
    final double addamt =
        _pendingItems.fold<double>(0.0, (double s, CartItem i) => s + i.extraPrice + i.bagPrice);
    final double dishAmt = totalOriginal + addamt;
    final double diff = dishAmt - totalRR;
    final double disAmt = diff > 0 ? diff : 0;

    final String saleid =
        widget.saleid.isNotEmpty ? widget.saleid : StoreModeUtils.generateSaleId();

    NavigatorUtils.push(
      context,
      Routes.settlePage,
      arguments: <String, dynamic>{
        'tableName': widget.tableName,
        'persons': widget.persons,
        'tableId': widget.tableId,
        'tableCode': widget.tableCode,
        'saleid': saleid,
        'serverId': widget.serverId,
        'serverName': widget.serverName,
        'remark': _orderRemark,
        'tableJson': widget.tableJson,
        'detailList': _buildDetailList(),
        'dishAmt': dishAmt,
        'serviceAmt': 0,
        'lowAmt': 0,
        'disAmt': disAmt,
        'payAmt': totalRR,
      },
    );
  }

  String _buildMasterJson() {
    String sid = '';
    String spid = '';
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '';
        spid = storeMap['spid']?.toString() ?? '';
      }
    } catch (_) {}

    String userId = '';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        userId = userMap['userid']?.toString() ?? '';
      }
    } catch (_) {}

    final Map<String, dynamic>? tmp = widget.tableJson?['tmp'] as Map<String, dynamic>?;

    final double totalRR = _grandTotal;
    final double totalOriginal = _pendingItems.fold<double>(
            0.0, (double s, CartItem i) => s + i.product.price * i.quantity) +
        _orderedItems.fold<double>(0.0, (double s, CartItem i) => s + i.product.price * i.quantity);
    final double disAmt = totalOriginal - totalRR;
    // 对齐 smdcapp: addamt = 做法加价金额总和（含打包费）
    final double addamt =
        _pendingItems.fold<double>(0.0, (double s, CartItem i) => s + i.extraPrice + i.bagPrice);

    final Map<String, dynamic> master = <String, dynamic>{
      'tableid': widget.tableId.isNotEmpty ? widget.tableId : (tmp?['tableid']?.toString() ?? '-1'),
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

  /// 套餐主行上传单价（对齐 smdcapp: rrprice 不含明细加减价，
  /// 加减价通过 combaddamt 单独上传，避免服务端/PC 二次计算时重复计入）
  double _combMainRrPrice(CartItem item) {
    if (item.customPrice != null) {
      return item.customPrice! - item.extraPrice;
    }
    final double base = item.memberUnitPrice ?? item.product.price;
    return item.discount < 100 ? base * item.discount / 100 : base;
  }

  /// 套餐主行明细加减价合计（对齐 smdcapp 主行 combaddamt = 明细加价总和×套餐数量）
  double _comboAddTotal(CartItem item) {
    double sum = 0;
    for (final ComboSelectedItem c in item.combItems) {
      sum += c.combaddamt;
    }
    return sum * item.quantity;
  }

  /// 套餐主行明细做法加价合计（对齐 smdcapp 主行 cookaddamt = 明细做法加价总和×套餐数量）
  double _comboCookTotal(CartItem item) {
    double sum = 0;
    for (final ComboSelectedItem c in item.combItems) {
      sum += c.cookExtra;
    }
    return sum * item.quantity;
  }

  /// 明细做法加价（对齐 smdcapp CookHelper：打包费绑定为整份加价做法计入 cookaddamt，
  /// ptype=1 不随数量翻倍）
  double _detailCookAddAmt(CartItem item) =>
      (item.isCombo ? _comboCookTotal(item) : item.extraPrice) + item.bagPrice;

  /// 打包做法文本（对齐 smdcapp CookHelper.createBagCookBean：
  /// 有打包费为"打包(￥66.0)"，零元打包为"打包"）
  String _bagCookText(CartItem item) {
    if (!item.isBag) return '';
    if (item.bagPrice <= 0) return '打包';
    final double bagAmount = double.parse(item.bagPrice.toStringAsFixed(2));
    return '打包(￥$bagAmount)';
  }

  /// 明细做法文本（对齐 smdcapp cooklist BAG_CODE：打包费拼入 cooktext）
  String _detailCookText(CartItem item) {
    final String base = item.isCombo ? '' : stripBagCookText(item.cookText);
    final String bag = _bagCookText(item);
    if (bag.isEmpty) return base;
    return base.isEmpty ? bag : '$base、$bag';
  }

  List<Map<String, dynamic>> _buildDetailList() {
    String sid = '';
    String spid = '';
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '';
        spid = storeMap['spid']?.toString() ?? '';
      }
    } catch (_) {}

    String userId = '';
    String userName = '';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        userId = userMap['userid']?.toString() ?? '';
        userName = userMap['username']?.toString() ?? '';
      }
    } catch (_) {}

    // 对齐 smdcapp: 明细项需要 saleid/tableid/billno 关联主单
    final Map<String, dynamic>? tmp = widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String saleid = tmp?['saleid']?.toString() ?? widget.saleid;
    final String billno = tmp?['localbillno']?.toString() ?? '';
    final String serverId = tmp?['serverid']?.toString() ?? widget.serverId;
    // 对齐 smdcapp bindSaleInfo 快餐分支（dcMode==0）：销售员缺省取当前登录人
    String salesId = serverId;
    String salesName = widget.serverName;
    if (widget.fastMode && salesId.isEmpty) {
      salesId = userId;
      salesName = userName;
    }

    final List<Map<String, dynamic>> details = <Map<String, dynamic>>[];

    // 对齐 smdcapp CartGoodsModel：本批待下单明细共用同一 seq（= 已下单最大 seq + 1），
    // 打印服务按 info.seq == bean.seq 过滤，同批菜品 seq 相同才能整批出票
    final int newSeq = _orderedMaxSeq + 1;

    for (final CartItem item in _pendingItems) {
      final String onlyid = _genOnlyId();
      final bool isComb = item.isCombo;
      details.add(<String, dynamic>{
        'id': 0,
        'spid': spid,
        'sid': sid,
        'productid': item.product.id,
        'productname': item.displayName,
        'qty': item.isWeigh ? item.weighNum : item.quantity.toDouble(),
        'sellprice': item.product.price,
        'rrprice': isComb ? _combMainRrPrice(item) : item.discountedUnitPrice,
        'rramt': item.totalPrice,
        'discount': item.discount,
        // 基础促销（分类折扣/菜品折扣/特价菜）
        'jcmbillid': item.jcmbillid,
        'specpriceflag': item.specpriceflag,
        'promoprice': item.promoPrice,
        // 场景促销赠品（买赠/满赠赠品，对齐 smdcapp DetailListBean cxmbillid/bxxpxxflag）
        'cxmbillid': item.cxmbillid,
        'bxxpxxflag': item.bxxpxxflag,
        'isGive': item.isGift,
        'remark': item.remark,
        // 套餐主行 spec 置空（对齐 smdcapp OrderModel: spec=getSpecName 对套餐返回空）；
        // 套餐明细以独立子行上传，避免拼接串超出服务端 spec 60字符限制
        'spec': isComb ? '' : item.specName,
        'presentflag': item.isGift ? 1 : 0,
        'hangflag': item.isSuspended ? 1 : 0,
        // 对齐 smdcapp：新下单商品 isPrint=true；挂起商品需 hashangflag=99 才会出挂起单
        'isPrint': true,
        if (item.isSuspended) 'hashangflag': 99,
        'weighflag': item.isWeigh ? 1 : 0,
        'weighnum': item.weighNum,
        'cookaddamt': _detailCookAddAmt(item),
        'bagamt': item.bagPrice,
        'salesname': item.waiterName.isNotEmpty ? item.waiterName : salesName,
        // 单品/整单改过服务员时明细 salesid 取该服务员（对齐 smdcapp OperationActivity2.waiter）
        'salesid': item.waiterId.isNotEmpty ? item.waiterId : salesId,
        'operid': userId,
        'opername': userName,
        'createtime': _formatDateTime(DateTime.now()),
        'updateflag': 1,
        'saleid': saleid,
        'billno': billno,
        'tableid': widget.tableId,
        'serverid': serverId,
        'servername': widget.serverName,
        // ── 以下为对齐 smdcapp DetailListBean 补齐的字段 ──
        // onlyid/seq 缺失会导致云服务端明细无法正常落库/定位，
        // 进而 getSaleTmpDetail 返回空 detailList（订单明细为空）
        'onlyid': onlyid,
        'seq': newSeq,
        'combflag': isComb ? 1 : 0,
        // 套餐主行：combid=自身onlyid，combaddamt=明细加减价×数量
        // （对齐 smdcapp OrderModel productToDetailBean 套餐分支）
        if (isComb) 'combid': onlyid,
        if (isComb) 'combaddamt': _comboAddTotal(item),
        'dscflag': item.product.dscflag,
        // 临时菜字段（对齐 smdcapp DetailListBean tpdish*，非临时菜为 0/空不影响后端）
        'tpdishflag': item.tpdishflag,
        'tpdscflag': item.tpdscflag,
        'tpdishid': item.tpdishid,
        'tpdishidzd': item.tpdishidzd,
        // 团券核销字段（对齐 smdcapp DetailListBean douyinflag/querytoken）
        'douyinflag': item.douyinflag,
        'querytoken': item.querytoken,
        // 必点菜字段（对齐 smdcapp DetailListBean mustflag/mustType）
        'mustflag': item.mustflag,
        'mustType': item.mustType,
        'subqty': 0,
        'urgeflag': 0,
        'callflag': 0,
        'opertype': 0,
        'bagstatus': item.isBag ? 1 : 0,
        'propresentflag': item.isGift ? 1 : 0,
        'unit': item.unit,
        'typeid': item.typeid,
        'typename': item.typename,
        'specid': '',
        'cooktext': _detailCookText(item),
        'eattext': '',
        'createid': userId,
        'createname': userName,
        'presentid': '',
        'mprice1': item.product.mprice1,
        'mprice2': item.product.mprice2,
        'mprice3': item.product.mprice3,
      });
      // 套餐明细子行（对齐 smdcapp getSetMealInfo：每个选中项一条 combflag=0 明细）
      if (isComb) {
        details.addAll(_buildCombChildDetails(
          item: item,
          mainOnlyId: onlyid,
          seq: newSeq,
          sid: sid,
          spid: spid,
          userId: userId,
          userName: userName,
          saleid: saleid,
          billno: billno,
          serverId: item.waiterId.isNotEmpty ? item.waiterId : salesId,
          salesName: salesName,
        ));
      }
    }

    return details;
  }

  String _buildDetailJson() => jsonEncode(_buildDetailList());

  /// 构建套餐明细子行（对齐 smdcapp ShoppingCartUtil.getSetMealInfo +
  /// OrderModel productToDetailBean 套餐分支）
  ///
  /// 子行字段规则：combflag=0、combid=主行onlyid、combproductid=套餐商品id、
  /// combgroupid=分组id、qty=套餐数量×明细数量、combaddamt=套餐数量×单份加减价、
  /// spec=子项规格名、seq与主行一致
  List<Map<String, dynamic>> _buildCombChildDetails({
    required CartItem item,
    required String mainOnlyId,
    required int seq,
    required String sid,
    required String spid,
    required String userId,
    required String userName,
    required String saleid,
    required String billno,
    required String serverId,
    String? salesName,
  }) {
    final List<Map<String, dynamic>> children = <Map<String, dynamic>>[];
    final String now = _formatDateTime(DateTime.now());
    final String salesname =
        item.waiterName.isNotEmpty ? item.waiterName : (salesName ?? widget.serverName);
    for (final ComboSelectedItem c in item.combItems) {
      children.add(<String, dynamic>{
        'id': 0,
        'spid': spid,
        'sid': sid,
        'productid': c.productid,
        'productname': c.productname,
        'qty': c.qty * item.quantity,
        'combsetqty': c.qty,
        'sellprice': c.sellprice,
        'rrprice': c.sellprice,
        'rramt': 0,
        'discount': item.discount,
        'spec': c.specname,
        'specname': c.specname,
        'specflag': c.specname.isNotEmpty ? 1 : 0,
        'specid': '',
        'combflag': 0,
        'combid': mainOnlyId,
        'combproductid': item.product.id,
        'combgroupid': c.groupid,
        'combsetproductid': c.combsetproductid,
        'combaddamt': c.combaddamt * item.quantity,
        'unit': c.unit,
        'remark': '',
        'presentflag': item.isGift ? 1 : 0,
        'hangflag': item.isSuspended ? 1 : 0,
        // 对齐 smdcapp：新下单商品 isPrint=true；挂起商品需 hashangflag=99 才会出挂起单
        'isPrint': true,
        if (item.isSuspended) 'hashangflag': 99,
        'weighflag': 0,
        'weighnum': 0,
        'cookaddamt': c.cookExtra * item.quantity,
        'cooktext': c.cookText,
        'bagamt': 0,
        'salesname': salesname,
        'salesid': serverId,
        'operid': userId,
        'opername': userName,
        'createtime': now,
        'updateflag': 1,
        'saleid': saleid,
        'billno': billno,
        'tableid': widget.tableId,
        'serverid': serverId,
        'servername': widget.serverName,
        'onlyid': _genOnlyId(),
        'seq': seq,
        'subqty': 0,
        'urgeflag': 0,
        'callflag': 0,
        'opertype': 0,
        'bagstatus': 0,
        'propresentflag': item.isGift ? 1 : 0,
        'typeid': '',
        'typename': '',
        'eattext': '',
        'createid': userId,
        'createname': userName,
        'presentid': '',
      });
    }
    return children;
  }

  // ═══════════════════ PC模式下单数据构建 ═══════════════════

  /// smdcapp TableDetailBean 定义的 tmp 字段白名单（对齐 order_page.dart _kTmpFields）。
  /// 避免桌台列表接口返回的多余字段导致 .NET 服务端空引用。
  static const Set<String> _kTmpFields = <String>{
    'vipname',
    'saleid',
    'vipid',
    'preprintflag',
    'detailList',
    'mustfreeflag',
    'cashid',
    'uniflowno',
    'cdflag',
    'servicetimerange',
    'servicediscount',
    'tabletypeid',
    'additionid',
    'servicebegintime',
    'serviceendtime',
    'operid',
    'opername',
    'opermachno',
    'tablestatus',
    'containweight',
    'amt',
    'retailamt',
    'roundamt',
    'serviceamt',
    'lowamt',
    'remark',
    'personnum',
    'spid',
    'serverid',
    'vipno',
    'localbillno',
    'sid',
    'vipmobile',
    'billtype',
    'lastbilltype',
    'dataiflag',
    'billdate',
    'servername',
    'tableid',
    'id',
    'tablecode',
    'billno',
    'unitableid',
    'unitableno',
    'unitablename',
    'machno',
    'tablename',
    'hangflag',
    'lockflag',
    'withdrawmemo',
    'dscamt',
    'addamt',
    'payment',
    'printkdflag',
    'printcpdflag',
    'sendprintflag',
    'confirmqty',
    'createtime',
    'updatetime',
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
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
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
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        userId = userMap['userid']?.toString() ?? '';
        userName = userMap['username']?.toString() ?? '';
      }
    } catch (_) {}
    machNo = SpUtil.getString(Constant.machNo) ?? '';

    final Map<String, dynamic>? tmp = widget.tableJson?['tmp'] as Map<String, dynamic>?;

    // 对齐 smdcapp saveProduct: downPrice = getDownPrice(null, null) 全零 → 主单金额均按 0 计算
    final double totalRR = forSave ? 0.0 : _grandTotal;
    final double totalOriginal = forSave
        ? 0.0
        : _pendingItems.fold<double>(
                0.0, (double s, CartItem i) => s + i.product.price * i.quantity) +
            _orderedItems.fold<double>(
                0.0, (double s, CartItem i) => s + i.product.price * i.quantity);
    final double disAmt = forSave ? 0.0 : totalOriginal - totalRR;
    // 对齐 smdcapp: addamt = 做法加价金额总和（含打包费，非套餐商品）
    final double addamt =
        _pendingItems.fold<double>(0.0, (double s, CartItem i) => s + i.extraPrice + i.bagPrice);

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
      'tableid': widget.tableId.isNotEmpty ? widget.tableId : (tmp?['tableid']?.toString() ?? '-1'),
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
      // 快餐/无桌台模式：合成 tmp（必须含 tablestatus），
      // 否则服务端上传临时桌台数据报"tablestatus属性不存在"
      final String billno = _generateBillNo();
      final String saleidUse = widget.saleid.isNotEmpty ? widget.saleid : billno;
      final Map<String, dynamic> fastTmp = <String, dynamic>{
        'tablestatus': 1,
        'personnum': widget.persons,
        'serverid': widget.serverId,
        'servername': widget.serverName,
        'tablename': widget.tableName,
        'billtype': 7,
        'saleid': saleidUse,
        'localbillno': billno,
        'billno': billno,
        'billdate': now,
        'remark': _orderRemark,
        'amt': totalRR,
        'serviceamt': 0,
        'retailamt': totalOriginal,
        'addamt': addamt,
        'lowamt': 0,
        'dscamt': disAmt > 0 ? disAmt : 0,
        'roundamt': 0,
        'lastbilltype': 7,
        'updatetime': now,
        'opermachno': machNo,
      };
      if (!forSave) {
        fastTmp['printkdflag'] = _printKd ? 1 : 0;
        fastTmp['printcpdflag'] = _printCpd ? 1 : 0;
        fastTmp['sendprintflag'] = printType != '-1' ? '1' : '-1';
      }
      tableMaster['tmp'] = fastTmp;
      tableMaster['tablestatus'] = '1';
      tableMaster['saleid'] = saleidUse;
      tableMaster['localbillno'] = billno;
      tableMaster['billno'] = billno;
      tableMaster['billtype'] = 7;
      tableMaster['lastbilltype'] = 7;
    }

    // ── 组装 PCMasterBean（对齐 smdcapp PCMasterBean: tableMaster + detailList + isUnionFlag） ──
    return <String, dynamic>{
      'tableMaster': tableMaster,
      'detailList': _buildPCDetailList(
        sid: sid,
        spid: spid,
        userId: userId,
        userName: userName,
        // 对齐 smdcapp OrderConfirmationActivity2.saveProduct：
        // 保存菜品时过滤必点菜（必点菜由点菜页进入时重新计算，避免恢复后重复）
        excludeMust: forSave,
      ),
      'isUnionFlag': false,
    };
  }

  /// 构建主设备模式明细列表（对齐 smdcapp OrderModel.getDownOrderBean 核心字段）
  ///
  /// 下单与保存菜品共用（对齐 smdcapp：postTableInfo 与 saveProduct 的
  /// detailList 均来自同一套 getDownOrderBean/待下单列表结构）；
  /// saveProduct 场景排除必点菜（对齐 OrderConfirmationActivity2.saveProduct）
  List<Map<String, dynamic>> _buildPCDetailList({
    required String sid,
    required String spid,
    required String userId,
    required String userName,
    bool excludeMust = false,
  }) {
    final Map<String, dynamic>? tmp = widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String saleid = tmp?['saleid']?.toString() ?? widget.saleid;
    final String billno = tmp?['localbillno']?.toString() ?? '';
    final String serverId = tmp?['serverid']?.toString() ?? widget.serverId;

    final List<Map<String, dynamic>> detailList = <Map<String, dynamic>>[];
    // 对齐 smdcapp CartGoodsModel：本批待下单明细共用同一 seq（= 已下单最大 seq + 1）
    final int newSeq = _orderedMaxSeq + 1;
    for (final CartItem item in _pendingItems) {
      if (excludeMust && item.mustflag == 1) continue;
      final String onlyid = _genOnlyId();
      final bool isComb = item.isCombo;
      detailList.add(<String, dynamic>{
        'id': 0,
        'spid': spid,
        'sid': sid,
        'productid': item.product.id,
        'productname': item.displayName,
        'qty': item.isWeigh ? item.weighNum : item.quantity.toDouble(),
        'sellprice': item.product.price,
        'rrprice': isComb ? _combMainRrPrice(item) : item.discountedUnitPrice,
        'rramt': item.totalPrice,
        'discount': item.discount,
        // 基础促销（分类折扣/菜品折扣/特价菜）
        'jcmbillid': item.jcmbillid,
        'specpriceflag': item.specpriceflag,
        'promoprice': item.promoPrice,
        // 场景促销赠品（买赠/满赠赠品，对齐 smdcapp DetailListBean cxmbillid/bxxpxxflag）
        'cxmbillid': item.cxmbillid,
        'bxxpxxflag': item.bxxpxxflag,
        'isGive': item.isGift,
        'remark': item.remark,
        // 套餐主行 spec 置空，明细以独立子行上传（对齐 smdcapp，避免 spec 超长）
        'spec': isComb ? '' : item.specName,
        'cooktext': _detailCookText(item),
        'presentflag': item.isGift ? 1 : 0,
        'hangflag': item.isSuspended ? 1 : 0,
        // 对齐 smdcapp：新下单商品 isPrint=true；挂起商品需 hashangflag=99 才会出挂起单
        'isPrint': true,
        if (item.isSuspended) 'hashangflag': 99,
        'weighflag': item.isWeigh ? 1 : 0,
        'weighnum': item.weighNum,
        'cookaddamt': _detailCookAddAmt(item),
        'bagamt': item.bagPrice,
        'bagstatus': item.isBag ? 1 : 0,
        'salesname': item.waiterName.isNotEmpty ? item.waiterName : widget.serverName,
        // 单品/整单改过服务员时明细 salesid 取该服务员（对齐 smdcapp OperationActivity2.waiter）
        'salesid': item.waiterId.isNotEmpty ? item.waiterId : serverId,
        'operid': userId,
        'opername': userName,
        'createtime': _formatDateTime(DateTime.now()),
        'updateflag': 1,
        'saleid': saleid,
        'billno': billno,
        'tableid': widget.tableId,
        'serverid': serverId,
        'servername': widget.serverName,
        // 必点菜字段（对齐 smdcapp DetailListBean mustflag/mustType）
        'mustflag': item.mustflag,
        'mustType': item.mustType,
        // 对齐 smdcapp DetailListBean: onlyid/seq/combflag 必传
        'onlyid': onlyid,
        'seq': newSeq,
        'combflag': isComb ? 1 : 0,
        if (isComb) 'combid': onlyid,
        if (isComb) 'combaddamt': _comboAddTotal(item),
      });
      // 套餐明细子行（与云模式同结构，对齐 smdcapp getSetMealInfo）
      if (isComb) {
        detailList.addAll(_buildCombChildDetails(
          item: item,
          mainOnlyId: onlyid,
          seq: newSeq,
          sid: sid,
          spid: spid,
          userId: userId,
          userName: userName,
          saleid: saleid,
          billno: billno,
          serverId: serverId,
        ));
      }
    }
    return detailList;
  }

  /// 格式化时间为 yyyy-MM-dd HH:mm:ss（对齐 smdcapp DateUtils.getTimeStamp）
  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  /// 生成唯一本地单号（对齐 smdcapp OrderModel.getBillno：yyyyMMddHHmmssSSS）
  String _generateBillNo() {
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '${now.millisecond.toString().padLeft(3, '0')}';
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
  /// fastFoodBean = 购物车待下单列表（getDownOrderBean 完整结构，过滤必点菜 mustflag == 1）
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
                  child: Text('操作', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                _OperationItem(
                    icon: Icons.lock_open,
                    label: '解锁台',
                    onTap: () {
                      Navigator.pop(ctx);
                      _lockOrUnlockTable(lock: false);
                    }),
                _OperationItem(
                    icon: Icons.lock,
                    label: '锁台',
                    onTap: () {
                      Navigator.pop(ctx);
                      _lockOrUnlockTable(lock: true);
                    }),
                _OperationItem(
                    icon: Icons.percent,
                    label: '整单折扣',
                    onTap: () {
                      Navigator.pop(ctx);
                      _applyAllDiscount();
                    }),
                // 整单挂起（对齐 smdcapp CartActionHandler.hangUpProductBatch，正餐模式专属）
                if (!StoreModeUtils.isFastMode())
                  _OperationItem(
                    icon: Icons.pause_circle_outline,
                    label: _allPendingSuspended ? '取消挂起' : '挂起',
                    onTap: () {
                      Navigator.pop(ctx);
                      _toggleAllSuspend();
                    },
                  ),
                // 整单打包（对齐 smdcapp OperationPopup2.NAME_DB → OperationActivity2.db）
                _OperationItem(
                    icon: Icons.shopping_bag_outlined,
                    label: '打包',
                    onTap: () {
                      Navigator.pop(ctx);
                      _bagWholeOrder();
                    }),
                // 整单服务员（对齐 smdcapp OperationPopup2.NAME_WAITER → OperationActivity2.waiter）
                _OperationItem(
                    icon: Icons.person_outline,
                    label: '服务员',
                    onTap: () {
                      Navigator.pop(ctx);
                      _waiterWholeOrder();
                    }),
                // 整单删除（对齐 smdcapp OperationPopup2.NAME_SC → OperationActivity2.del）
                _OperationItem(
                    icon: Icons.delete_outline,
                    label: '删除',
                    onTap: () {
                      Navigator.pop(ctx);
                      _deleteWholeOrder();
                    }),
                const SizedBox(height: 8),
                Container(height: 8, color: const Color(0xFFF5F6F8)),
                _OperationItem(icon: Icons.close, label: '取消', onTap: () => Navigator.pop(ctx)),
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

  /// 待下单商品是否全部已挂起（决定整单挂起按钮文案）
  bool get _allPendingSuspended =>
      _pendingItems.isNotEmpty && _pendingItems.every((CartItem i) => i.isSuspended);

  /// 整单挂起/取消挂起（对齐 smdcapp CartActionHandler.hangUpProductBatch）
  void _toggleAllSuspend() {
    if (_pendingItems.isEmpty) {
      Toast.show('当前没有可操作的待下单商品');
      return;
    }
    final bool allHanging = _allPendingSuspended;
    setState(() {
      for (final CartItem i in _pendingItems) {
        i.isSuspended = !allHanging;
      }
    });
    Toast.show(allHanging ? '已取消整桌挂起' : '已整桌挂起');
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

  /// 整单操作前的菜品勾选（对齐 smdcapp OperationActivity2：整桌操作先勾选菜品）
  ///
  /// 返回勾选的待下单菜品；null 表示取消或无菜品可操作。
  Future<List<CartItem>?> _pickPendingDishes({
    required String title,
    bool Function(CartItem item)? enabled,
    String disabledHint = '',
  }) async {
    if (_pendingItems.isEmpty) {
      Toast.show('待下单无可操作商品');
      return null;
    }
    final List<DishSelectEntry> entries = <DishSelectEntry>[];
    for (int i = 0; i < _pendingItems.length; i++) {
      final CartItem item = _pendingItems[i];
      final bool selectable = enabled?.call(item) ?? true;
      entries.add(DishSelectEntry(
        key: '$i',
        name: item.displayName,
        subtitle: selectable ? _pendingSubtitle(item) : disabledHint,
        disabled: !selectable,
      ));
    }
    final List<String>? picked =
        await DishSelectSheet.show(context, title: title, entries: entries);
    if (picked == null || picked.isEmpty || !mounted) return null;
    final List<CartItem> result = <CartItem>[];
    for (final String key in picked) {
      final int index = int.tryParse(key) ?? -1;
      if (index >= 0 && index < _pendingItems.length) {
        result.add(_pendingItems[index]);
      }
    }
    return result.isEmpty ? null : result;
  }

  /// 待下单菜品副标题（份数 + 规格做法 + 备注）
  String _pendingSubtitle(CartItem item) {
    final double qty = item.isWeigh ? item.weighNum : item.quantity.toDouble();
    final List<String> parts = <String>['x${_formatPrice(qty)}'];
    if (item.specText.isNotEmpty) parts.add(item.specText);
    if (item.remark.isNotEmpty) parts.add('备注:${item.remark}');
    return parts.join(' | ');
  }

  /// 整单打包（对齐 smdcapp OperationActivity2.db：打包费按勾选菜品均摊，
  /// 返回 -1 表示取消打包）
  Future<void> _bagWholeOrder() async {
    final List<CartItem>? picked = await _pickPendingDishes(title: '整单打包');
    if (picked == null || !mounted) return;
    final double? price = await DishBagSheet.show(context, dishName: '整单打包');
    if (price == null || !mounted) return;
    setState(() {
      for (final CartItem item in picked) {
        item.isBag = price >= 0;
        item.bagPrice = item.isBag ? price / picked.length : 0;
      }
    });
    CartEventBus.fireCartChanged();
    Toast.show(price <= -1 ? '已取消打包' : '打包成功');
  }

  /// 整单服务员（对齐 smdcapp OperationActivity2.waiter：勾选菜品统一改服务员）
  Future<void> _waiterWholeOrder() async {
    final List<CartItem>? picked = await _pickPendingDishes(title: '整单服务员');
    if (picked == null || !mounted) return;
    final Waiter? waiter = await DishWaiterSheet.show(context, dishName: '整单');
    if (waiter == null || !mounted) return;
    setState(() {
      for (final CartItem item in picked) {
        item.waiterId = waiter.userid;
        item.waiterName = waiter.name;
      }
    });
    CartEventBus.fireCartChanged();
    Toast.show('服务员已修改');
  }

  /// 整单删除（对齐 smdcapp OperationActivity2.del：勾选菜品后从购物车移除）
  Future<void> _deleteWholeOrder() async {
    final List<CartItem>? picked = await _pickPendingDishes(
      title: '整单删除',
      // 对齐 smdcapp handleRemoveProduct：固定必点菜不能删除
      enabled: (CartItem item) => !(item.mustflag == 1 && item.mustType == 0),
      disabledHint: '必点菜不能删除',
    );
    if (picked == null || !mounted) return;
    setState(() => _removePendingItems(picked));
    Toast.show('已删除${picked.length}项');
  }

  /// 移除待下单菜品并同步点菜页购物车（两页共用同一 CartItem 引用）
  void _removePendingItems(List<CartItem> items) {
    for (final CartItem item in items) {
      _pendingItems.remove(item);
      widget.cartItems.remove(item);
    }
    CartEventBus.fireCartChanged();
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
                icon: const Icon(Icons.arrow_back_ios_new, size: 17, color: Color(0xFF1D2129)),
                onPressed: () => NavigatorUtils.goBack(context),
              ),
              Expanded(
                child: Text(
                  // 对齐 smdcapp OrderFastDetailActivity3：快餐模式标题为“订单详情”
                  widget.fastMode ? '订单详情' : '${widget.tableName}--订单确认',
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
                  child: Text('合计', style: TextStyle(fontSize: 13, color: Color(0xFF86909C))),
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
                        fontSize: 12, color: _kBrandRed, fontWeight: FontWeight.w500),
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
                  const Text('整单备注', style: TextStyle(fontSize: 13, color: Color(0xFF4E5969))),
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

    final String leftLabel =
        pendingCount > 0 ? '待下单(¥${_formatPrice(pendingPrice)} 共${pendingCount}份)' : '待下单(¥0)';
    final String rightLabel =
        orderedCount > 0 ? '已下单(¥${_formatPrice(orderedPrice)} 共${orderedCount}份)' : '已下单(¥0)';

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
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
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
  Widget _buildItemList(List<CartItem> items, {required bool editable, bool isOrdered = false}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.receipt_long_outlined,
                size: 44, color: const Color(0xFF1D2129).withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            const Text('暂无商品', style: TextStyle(fontSize: 13, color: Color(0xFFC9CDD4))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF2F3F5)),
      itemBuilder: (BuildContext context, int index) {
        final CartItem item = items[index];
        return _buildItemRow(item, editable: editable, isOrdered: isOrdered);
      },
    );
  }

  /// 单个商品行（对齐 smdcapp dishes_item_await_one2：名称+价格+数量控制+三点菜单）
  ///
  /// 套餐商品在主行下方逐行展开明细（对齐 smdcapp AwaitOrderFragment2
  /// rvInfo + dishes_item_set_meal：名称+(规格) + x数量）
  Widget _buildItemRow(CartItem item, {required bool editable, bool isOrdered = false}) {
    // 对齐 smdcapp: 退菜记录灰色背景 (presentflag==2 → bg_gray_EAEEF6)
    final bool refunded = item.isRefunded;
    // 套餐主行不展示拼接sku串（明细已逐行展开，对齐 smdcapp 主行仅做法/备注）
    final String skuDesc = item.isCombo
        ? ''
        : item.specName.isNotEmpty
            ? item.specName
            : item.cookText.isEmpty
                ? item.specText
                : '';
    // 已保存的做法可能含旧打包费，展示时按当前打包状态重建。
    final List<String> cookParts =
        stripBagCookText(item.cookText).split('、').where((String text) => text.isNotEmpty).toList();
    if (item.isBag) {
      cookParts.add(_bagCookText(item));
    }
    final String cookDesc = cookParts.join('、');

    // 状态标签（对齐 smdcapp DishesTagHelper：必/促/赠/折/挂/包），下单前即可见
    final List<Widget> tags = <Widget>[
      if (item.mustflag == 1) _tag('必', _kBrandRed),
      if (item.isPromotion) _tag('促', _kBrandRed),
      if (item.isGift) _tag('赠', const Color(0xFFFF8547)),
      // 折扣标签（对齐 smdcapp DishesTagHelper：绿色 + "N折"/"N.5折"）
      if (item.isDiscounted)
        _tag('${_formatPrice(item.discount / 10)}折', const Color(0xFF00C15A)),
      if (item.isSuspended) _tag('挂', const Color(0xFF999999)),
      if (item.isBag) _tag('包', const Color(0xFF0055FF)),
    ];
    // 赠送/打折时展示划线原价（原单价×计价数量）
    final bool showOrigin = !refunded && (item.isGift || item.isDiscounted);
    final double originTotal = item.unitPrice * item.priceQty;

    final Widget mainRow = Container(
      color: refunded ? const Color(0xFFEAEEF6) : null,
      padding: EdgeInsets.fromLTRB(14, 12, 14, item.isBag || cookDesc.isNotEmpty ? 4 : 12),
      child: Row(
        children: <Widget>[
          // 商品名称 + 规格/备注 + 退菜标记
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ...tags.map((Widget t) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: t,
                        )),
                    Flexible(
                      child: Text(
                        item.displayName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF1D2129)),
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
                if (skuDesc.isNotEmpty || item.remark.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (skuDesc.isNotEmpty) skuDesc,
                      if (item.remark.isNotEmpty) '备注:${item.remark}'
                    ].join(' | '),
                    style: const TextStyle(fontSize: 11, color: Color(0xFFC9CDD4)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // 价格（对齐 smdcapp: 退菜显示负数金额；赠/折显示划线原价）
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (showOrigin)
                Text(
                  '¥${_formatPrice(originTotal)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9C9C9C),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
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
            ],
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
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF86909C)),
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
                          fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1D2129)),
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
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF86909C))),
            ),
          const SizedBox(width: 6),
          // 三点菜单（待下单→待下单菜单；已下单→已下单菜单，对齐 smdcapp 两套菜单）
          if (editable || isOrdered)
            GestureDetector(
              onTap: () => isOrdered ? _showOrderedItemMenu(item) : _showItemMenu(item),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        mainRow,
        if (item.isBag || cookDesc.isNotEmpty)
          Container(
            width: double.infinity,
            color: refunded ? const Color(0xFFEAEEF6) : null,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (cookDesc.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(
                          text: '做法：',
                          style: TextStyle(
                            color: Color(0xFF333333),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: cookDesc),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  ),
              ],
            ),
          ),
        if (item.isCombo) ...<Widget>[
          for (final ComboSelectedItem c in item.combItems) _buildCombChildRow(c, item),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// 套餐明细行（对齐 smdcapp dishes_item_set_meal：名称+(规格名) + x数量）
  ///
  /// 明细行可点击单独修改做法（对齐 smdcapp AwaitOrderFragment2.showMealOperationPop）
  Widget _buildCombChildRow(ComboSelectedItem c, CartItem item) {
    final String spec = c.specname.isNotEmpty ? '(${c.specname})' : '';
    final String name = '${c.productname}$spec';
    final String cook = c.cookText.isNotEmpty ? c.cookText : '';
    final bool editable = !item.isRefunded;
    return GestureDetector(
      onTap: editable ? () => _showComboSubMenu(c, item) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 0, 14, 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: Color(0xFF86909C)),
                  children: <InlineSpan>[
                    TextSpan(text: name),
                    if (cook.isNotEmpty)
                      TextSpan(
                        text: ' $cook',
                        style: const TextStyle(color: Color(0xFF4E5969)),
                      ),
                    if (c.cookExtra > 0) TextSpan(text: ' +¥${_formatPrice(c.cookExtra)}'),
                  ],
                ),
              ),
            ),
            Text(
              'x${_formatPrice(c.qty * item.quantity)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF86909C)),
            ),
          ],
        ),
      ),
    );
  }

  /// 套餐明细操作弹窗（对齐 smdcapp SetMealOperationPopup：做法 / 修改）
  Future<void> _showComboSubMenu(ComboSelectedItem c, CartItem item) async {
    final String? operation = await ComboSubOperationPopup.show(
      context,
      title: c.productname,
    );
    if (operation == null || !mounted) return;
    if (operation == DishOperationType.comboSubModify) {
      await _handleComboModify(item);
      return;
    }
    await _handleComboSubCookModify(c, item);
  }

  /// 套餐明细做法修改（对齐 smdcapp ACTION_SPEC_COOK → handleChangeSpecCook）
  Future<void> _handleComboSubCookModify(
    ComboSelectedItem c,
    CartItem item,
  ) async {
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
      specData = await OrderRepository.fetchProductCookSpec(c.productid);
      final bool showPublicCook =
          SpUtil.getBool('setting_show_public_cook', defValue: true) ?? true;
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
      dishName: c.productname,
      unitPrice: c.sellprice,
      specData: specData,
      currentSpecText: c.cookText,
    );
    if (result == null || !mounted) return;
    setState(() {
      c.cookText = result.cookText;
      c.cookExtra = result.cookExtra;
      _recalcComboExtra(item);
    });
  }

  /// 套餐主行加价 = 明细加减价 + 明细做法加价（对齐 smdcapp 主行 combaddamt + cookaddamt）
  void _recalcComboExtra(CartItem item) {
    double add = 0;
    for (final ComboSelectedItem c in item.combItems) {
      add += c.combaddamt + c.cookExtra;
    }
    item.extraPrice = add;
  }

  /// 显示菜品操作弹窗（与点菜页购物车保持一致，对齐 smdcapp OperationPopup）
  Future<void> _showItemMenu(CartItem item) async {
    final String? operation = await DishOperationPopup.show(
      context,
      dishName: item.displayName,
      // 对齐 smdcapp: isShowCook(combflag!=1) / isShowComb(combflag==1)
      isCookProduct: !item.isCombo,
      isComboProduct: item.isCombo,
      // 对齐 smdcapp OperationAction：已生效的操作显示为"取消XX"
      isSuspended: item.isSuspended,
      isGift: item.isGift,
      isBag: item.isBag,
    );
    if (operation == null || !mounted) return;
    _handleItemOperation(operation, item);
  }

  /// 已下单菜品操作菜单（对齐 smdcapp PlacedOrderFragment2.openAction）
  ///
  /// 菜单与订单详情页共用 buildOrderedOperations，保证两页一致；
  /// 本页仅展示已下单数据、无明细上报链路，操作统一提示去订单详情页执行
  /// （退菜/划菜/二次称重在 smdcapp 同样提示去详情页操作）。
  Future<void> _showOrderedItemMenu(CartItem item) async {
    // 对齐 smdcapp PlacedOrderFragment2.openAction：已退完/退菜记录/团购商品不打开单品操作
    if (item.isRefunded || item.douyinflag == 1) return;
    final double qty = item.isWeigh ? item.weighNum : item.quantity.toDouble();
    if (qty - item.subqty <= 0) {
      Toast.show('商品已退完不可以操作');
      return;
    }
    final String? operation = await DishOperationPopup.show(
      context,
      dishName: item.displayName,
      isOrdered: true,
      isGift: item.isGift,
      isCut: item.isCut,
      showWeigh: item.isWeigh && ParamsSpUtils.isReweigh(),
    );
    if (operation == null || !mounted) return;
    Toast.show('订单确认不支持$operation，请去订单详情操作');
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
        // 已赠送：直接取消赠送（对齐 smdcapp handleGiveaway presentflag==1 分支）
        if (item.isGift) {
          setState(() {
            item.isGift = false;
            item.giftRemark = '';
          });
          Toast.show('已取消赠送');
          return;
        }
        final GiveResult? giftResult = await DishGiveSheet.show(
          context,
          dishName: item.displayName,
          maxNum: item.quantity.toDouble(),
          isGive: item.isGift,
        );
        if (giftResult != null) {
          setState(() {
            item.isGift = true;
            item.giftRemark = giftResult.remark;
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
        // 对齐 smdcapp CartActionHandler.hangUpProduct：已挂起则取消挂起
        final bool nextSuspend = !item.isSuspended;
        setState(() => item.isSuspended = nextSuspend);
        Toast.show(nextSuspend ? '已挂起' : '已取消挂起');

      case DishOperationType.bag:
        // 已打包时直接取消，避免再次进入打包费输入弹窗。
        if (item.isBag) {
          setState(item.cancelBag);
          CartEventBus.fireCartChanged();
          Toast.show('已取消打包');
          return;
        }
        final double? bagPrice = await DishBagSheet.show(
          context,
          dishName: item.displayName,
          currentBagPrice: item.bagPrice,
        );
        if (bagPrice != null && mounted) {
          setState(() {
            item.isBag = bagPrice >= 0;
            item.bagPrice = item.isBag ? bagPrice : 0;
          });
          CartEventBus.fireCartChanged();
          Toast.show(bagPrice < 0 ? '已取消打包' : '打包成功');
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
        // 对齐 smdcapp handleRemoveProduct：固定必点菜不能删除
        if (item.mustflag == 1 && item.mustType == 0) {
          Toast.show('必点菜不能删除');
          return;
        }
        setState(() => _removePendingItems(<CartItem>[item]));

      case DishOperationType.waiter:
        final Waiter? waiter = await DishWaiterSheet.show(
          context,
          dishName: item.displayName,
          currentWaiter: item.waiterName,
        );
        if (waiter != null) {
          setState(() {
            item.waiterId = waiter.userid;
            item.waiterName = waiter.name;
          });
        }

      case DishOperationType.cook:
        await _handleCookModify(item);

      case DishOperationType.combo:
        // 套餐修改（对齐 smdcapp NAME_COMB → handleChangeComb）
        await _handleComboModify(item);

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
      final bool showPublicCook =
          SpUtil.getBool('setting_show_public_cook', defValue: true) ?? true;
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
      item.specName = specPrefix;
      item.cookText = result.cookText;
      item.specText = specPrefix.isEmpty
          ? result.cookText
          : (result.cookText.isEmpty ? specPrefix : '$specPrefix、${result.cookText}');
      item.extraPrice = result.cookExtra;
    });
  }

  /// 套餐修改（对齐 smdcapp OperationPopup.NAME_COMB → handleChangeComb：
  /// 拉取套餐配置，编辑模式打开套餐弹窗，确认后替换明细与加减价）
  Future<void> _handleComboModify(CartItem item) async {
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
    ComboMealData? comboData;
    try {
      comboData = await OrderRepository.fetchProductComb(item.product.id);
    } catch (_) {
      comboData = null;
    }
    if (!mounted) return;
    Navigator.of(context).pop();

    if (comboData == null || comboData.prolist.isEmpty) {
      Toast.show('暂无套餐数据');
      return;
    }

    await SetMealSheet.show(
      context,
      product: DishProduct(
        productid: item.product.id,
        name: item.product.name,
        sellprice: item.product.price,
        combflag: 1,
      ),
      comboData: comboData,
      isEditMode: true,
      initialSelection: item.combItems,
      onConfirmEdit: (SetMealResult result) {
        setState(() {
          // 保留已单独设置过的明细做法（按 combsetproductid+productid 匹配）
          final Map<String, ComboSelectedItem> cookMap = <String, ComboSelectedItem>{};
          for (final ComboSelectedItem old in item.combItems) {
            if (old.cookText.isNotEmpty || old.cookExtra != 0) {
              cookMap['${old.combsetproductid}_${old.productid}'] = old;
            }
          }
          for (final ComboSelectedItem fresh in result.selectedItems) {
            final ComboSelectedItem? old = cookMap['${fresh.combsetproductid}_${fresh.productid}'];
            if (old != null) {
              fresh.cookText = old.cookText;
              fresh.cookExtra = old.cookExtra;
            }
          }
          item.combItems = result.selectedItems;
          item.specText = result.specText;
          _recalcComboExtra(item);
        });
      },
    );
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
                        const Text('出品单', style: TextStyle(fontSize: 14, color: Color(0xFF4E5969))),
                        const SizedBox(width: 2),
                        Switch(
                          value: _printCpd,
                          activeThumbColor: Colors.white,
                          activeTrackColor: const Color(0xFF00BFA5),
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor: const Color(0xFFE5E6EB),
                          onChanged: (bool v) => setState(() => _printCpd = v),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 0.5, height: 16, color: const Color(0xFFE5E6EB)),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text('客单', style: TextStyle(fontSize: 14, color: Color(0xFF4E5969))),
                        const SizedBox(width: 2),
                        Switch(
                          value: _printKd,
                          activeThumbColor: Colors.white,
                          activeTrackColor: const Color(0xFF00BFA5),
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor: const Color(0xFFE5E6EB),
                          onChanged: (bool v) => setState(() => _printKd = v),
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
                  // 保存菜品（仅主设备连接且正餐模式显示；快餐无桌台临时单）
                  if (ConnectionManager.pcAlive && !widget.fastMode) ...[
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
                  // 立即下单/去结账（红色主按钮；快餐模式对齐 smdcapp tvPay → 结账页）
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _isLoading ? null : (widget.fastMode ? _goSettle : _placeOrder),
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                                color: Color(0x35E13426), blurRadius: 8, offset: Offset(0, 3)),
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
                              : Text(widget.fastMode ? '去结账' : '立即下单',
                                  style: const TextStyle(
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
            if (!widget.fastMode) _buildTabs(),
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
                  child: widget.fastMode
                      ? _buildItemList(_pendingItems, editable: true)
                      : TabBarView(
                          controller: _tabController,
                          children: <Widget>[
                            _buildItemList(_pendingItems, editable: true),
                            _loadingOrdered
                                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                                : _buildItemList(_orderedItems, editable: false, isOrdered: true),
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

  /// 小标签（赠/折/挂，对齐 smdcapp DishesTagHelper 徽章样式）
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
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4E5969))),
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
            Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF1D2129))),
          ],
        ),
      ),
    );
  }
}
