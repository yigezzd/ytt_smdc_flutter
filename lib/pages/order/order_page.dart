import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/cut_model_sheet.dart';
import 'package:flutter_deer/components/dish_operation_dialogs.dart';
import 'package:flutter_deer/components/spec_cook_sheet.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/pages/order/widgets/cart_panel_sheet.dart';
import 'package:flutter_deer/pages/order/widgets/set_meal_sheet.dart';
import 'package:flutter_deer/pages/order/widgets/time_price_sheet.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';
import 'package:flutter_deer/util/theme_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/barcode_scanner_page.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 商品图片 OSS 前缀（对齐 smdcapp NetHelpUtils.imgAddress）
const String _kImgAddress = 'http://byyoupic.oss-cn-shenzhen.aliyuncs.com/';

/// 商品卡片高度（估算，用于滚动联动计算）
const double _kProductHeight = 100.0;

/// 分类 header 高度
const double _kHeaderHeight = 40.0;

/// 点菜页（对齐 smdcapp 正餐点餐界面）
///
/// 功能：
/// 1. 顶部展示桌台信息（桌台号 + 人数）
/// 2. 左侧分类侧边栏 + 右侧商品列表
/// 3. 一次性加载全部商品，滚动商品列表联动左侧分类高亮
/// 4. 点击左侧分类，右侧滚动到对应分类区域
class OrderPage extends StatefulWidget {
  const OrderPage({
    super.key,
    this.tableId = '',
    this.tableName = 'A01',
    this.tableCode = '',
    this.persons = 5,
    this.serverId = '',
    this.serverName = '',
    this.remark = '',
    this.saleid = '',
    this.tableJson,
    this.fastMode = false,
  });

  final String tableId;
  final String tableName;
  final String tableCode;
  final int persons;
  final String serverId;
  final String serverName;
  final String remark;
  final String saleid;

  /// 完整桌台对象 JSON（用于 PC 模式修改开台信息接口，对齐 smdcapp objectClone 逻辑）
  final Map<String, dynamic>? tableJson;

  /// 是否快餐模式（对齐 smdcapp DishesHomeAct2 快餐点餐：无桌台、标题“快餐点餐”、显示模式切换图标）
  final bool fastMode;

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> with TickerProviderStateMixin {
  /// 分类列表
  List<DishCategory> _categories = <DishCategory>[];

  /// 按分类分组后的商品 Map（key=typeid）
  Map<String, List<DishProduct>> _groupedProducts = <String, List<DishProduct>>{};

  /// 当前高亮的分类下标（ValueNotifier 分离重建，滚动联动时仅重建侧边栏）
  final ValueNotifier<int> _activeCategoryIndex = ValueNotifier<int>(0);

  /// 可变的开台信息（修改开台信息后更新，对齐 smdcapp DishesHomeAct2.showChangeTablePop 回调更新逻辑）
  late int _persons;
  late String _serverId;
  late String _serverName;
  late String _remark;

  /// 是否正在加载
  bool _loading = true;

  /// 加载错误信息
  String? _errorMsg;

  /// 购物车
  final List<CartItem> _cartItems = <CartItem>[];

  /// 商品数量缓存 Map（productid → 数量），O(1) 查询代替 O(n) 遍历
  final Map<String, int> _productCountMap = <String, int>{};

  /// 商品所属分类反查 Map（productid → typeid），用于分类角标统计
  final Map<String, String> _productTypeIdMap = <String, String>{};

  /// 分类购物车数量 Map（typeid → 数量），用于左侧分类角标
  final Map<String, int> _categoryCountMap = <String, int>{};

  late AnimationController _cartBadgeController;

  /// 右侧列表 ScrollController
  final ScrollController _listScrollController = ScrollController();

  /// 左侧分类 ScrollController
  final ScrollController _categoryScrollController = ScrollController();

  /// 是否正在程序化滚动（防止联动死循环）
  bool _isProgrammaticScroll = false;

  /// 每个分类区块的起始偏移量（用于滚动联动计算）
  final List<double> _sectionOffsets = <double>[];

  /// 滚动节流：上次处理时间戳
  int _lastScrollProcessTime = 0;

  /// 商品回调缓存（避免每次 build 重建闭包）
  final Map<String, VoidCallback> _addCallbacks = <String, VoidCallback>{};
  final Map<String, VoidCallback> _removeCallbacks = <String, VoidCallback>{};

  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  /// 搜索关键词
  String _searchKeyword = '';

  /// 沽清商品ID集合（对齐 smdcapp GuQingBean/WarnProductBean，productid → warnqty）
  final Map<String, double> _warnProductMap = <String, double>{};

  @override
  void initState() {
    super.initState();
    _persons = widget.persons;
    _serverId = widget.serverId;
    _serverName = widget.serverName;
    _remark = widget.remark;
    _cartBadgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _listScrollController.addListener(_onListScroll);
    _loadData();
  }

  @override
  void dispose() {
    _listScrollController.removeListener(_onListScroll);
    _listScrollController.dispose();
    _categoryScrollController.dispose();
    _cartBadgeController.dispose();
    _activeCategoryIndex.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ==================== 数据加载 ====================

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      // 并行加载分类、商品和沽清数据（对齐 smdcapp：菜品接口固定走云服务，不走主设备）
      final results = await Future.wait(<Future<dynamic>>[
        OrderRepository.fetchCategories(),
        OrderRepository.fetchAllProducts(),
        OrderRepository.fetchWarnList(),
      ]);

      final List<DishCategory> categories = results[0] as List<DishCategory>;
      final List<DishProduct> products = results[1] as List<DishProduct>;
      final List<Map<String, dynamic>> warnList = results[2] as List<Map<String, dynamic>>;

      // 解析沽清数据（对齐 smdcapp GuQingBean: productid + warnqty）
      _warnProductMap.clear();
      for (final Map<String, dynamic> w in warnList) {
        final String pid = w['productid']?.toString() ?? '';
        if (pid.isNotEmpty) {
          final double warnqty = double.tryParse(w['warnqty']?.toString() ?? '0') ?? 0;
          _warnProductMap[pid] = warnqty;
        }
      }

      // 按 typeid 分组
      final Map<String, List<DishProduct>> grouped = <String, List<DishProduct>>{};
      for (final DishProduct p in products) {
        grouped.putIfAbsent(p.typeid, () => <DishProduct>[]).add(p);
        _productTypeIdMap[p.productid] = p.typeid;
      }

      // 过滤掉没有商品的分类
      final List<DishCategory> validCategories = categories
          .where((DishCategory c) => grouped.containsKey(c.typeid) && grouped[c.typeid]!.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _categories = validCategories;
        _groupedProducts = grouped;
        _loading = false;
      });
      _activeCategoryIndex.value = 0;

      // 计算各分类区块偏移量
      _calculateSectionOffsets();

      // 必点菜自动加购 → 恢复已保存菜品（对齐 smdcapp DishesHomeAct2：initData(initMust) → delay(100) → initGetSaveData）
      _initCartFromServer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = '加载菜品失败，请下拉刷新重试';
      });
    }
  }

  /// 计算每个分类区块在列表中的起始偏移
  void _calculateSectionOffsets() {
    _sectionOffsets.clear();
    double offset = 0;
    for (final DishCategory cat in _categories) {
      _sectionOffsets.add(offset);
      final int productCount = _groupedProducts[cat.typeid]?.length ?? 0;
      // 分类 header + 商品卡片
      offset += _kHeaderHeight + productCount * _kProductHeight;
    }
  }

  // ==================== 购物车初始化（必点菜自动加购 + 已保存菜品回显） ====================

  /// 初始化购物车服务端数据（对齐 smdcapp DishesHomeAct2 顺序：
  /// cartModel.initData 内 initMust 先加必点菜，随后 initGetSaveData 恢复已保存菜品）
  Future<void> _initCartFromServer() async {
    await _initMustDishes();
    await _restoreSavedCart();
  }

  /// 必点菜自动加入购物车（对齐 smdcapp CartGoodsModel.initMust → addMust →
  /// ProductMustValidator + MustHelper.getFixedMandatoryItems）
  ///
  /// 仅固定必点菜（mustrule==0）静默自动加购，可选必点菜（mustrule==1）
  /// 在下单时校验提示（对齐 smdcapp isCheckOptional 时机）。
  /// 数量规则：正餐模式（storemodel==2）且每人必点（musttype==0）→ 数量=人数，
  /// 否则 1；扣除购物车已有数量后补足差额（对齐 smdcapp gapQty 逻辑）。
  Future<void> _initMustDishes() async {
    try {
      final Map<String, dynamic>? tmp =
          widget.tableJson?['tmp'] as Map<String, dynamic>?;
      // 对齐 smdcapp initMust：isMust = mustfreeflag != "1" || dcMode == 0
      final String mustfreeflag = tmp?['mustfreeflag']?.toString() ?? '0';
      final int dcMode =
          StoreModeUtils.getCurrentStoreModel() == StoreModeUtils.storeModelNormal ? 1 : 0;
      if (!(mustfreeflag != '1' || dcMode == 0)) return;

      final String areaid = widget.tableJson?['areaid']?.toString() ?? '';
      if (areaid.isEmpty) return;
      final List<Map<String, dynamic>> mustGroups =
          await OrderRepository.fetchMustDishes(areaid: areaid);
      if (mustGroups.isEmpty || !mounted) return;

      // 人数：优先取 tmp.personnum（对齐 smdcapp order.personnum）
      final int tmpPerson = _mustToInt(tmp?['personnum']);
      final int personNum = tmpPerson > 0 ? tmpPerson : _persons;
      final int storemodel = StoreModeUtils.getCurrentStoreModel();

      final List<CartItem> addItems = <CartItem>[];
      for (final Map<String, dynamic> group in mustGroups) {
        // 仅固定必点菜自动加购（对齐 smdcapp mustrule == 0）
        if (_mustToInt(group['mustrule']) != 0) continue;
        final dynamic rawList = group['mustproductlist'];
        if (rawList is! List || rawList.isEmpty) continue;
        // 对齐 smdcapp MustHelper.getFixedMandatoryItems：正餐且每人必点 → 人数，否则 1
        final double requiredQty =
            (storemodel == StoreModeUtils.storeModelNormal && _mustToInt(group['musttype']) == 0)
                ? (personNum < 1 ? 1 : personNum).toDouble()
                : 1.0;
        for (final dynamic raw in rawList) {
          if (raw is! Map<String, dynamic>) continue;
          final String pid = raw['productid']?.toString() ?? '';
          if (pid.isEmpty) continue;
          // 扣除购物车已有数量（对齐 smdcapp ProductMustValidator：退菜不计入）
          final double inCartQty = _cartItems
              .where((CartItem c) => c.product.id == pid && !c.isRefunded)
              .fold(0.0, (double s, CartItem c) => s + c.quantity);
          final double gapQty = requiredQty - inCartQty;
          if (gapQty <= 0) continue;
          addItems.add(_mustProductToCartItem(raw, gapQty));
        }
      }
      if (addItems.isEmpty || !mounted) return;
      setState(() {
        _cartItems.addAll(addItems);
        _rebuildCountMap();
      });
      _cartBadgeController.forward(from: 0);
    } catch (_) {
      // 必点菜初始化失败不影响主流程（对齐 smdcapp 静默处理）
    }
  }

  /// 必点菜条目转购物车条目（对齐 smdcapp ShoppingCartUtil.mustToProduct + toDetalListBean）
  CartItem _mustProductToCartItem(Map<String, dynamic> raw, double qty) {
    final String pid = raw['productid']?.toString() ?? '';
    final DishProduct? dish = _findDishProduct(pid);
    final bool isComb = _mustToInt(raw['combflag']) == 1 ||
        (dish != null && dish.combflag == 1);
    final Product product = dish != null
        ? Product(
            id: dish.productid,
            name: dish.name,
            price: dish.sellprice,
            desc: dish.typename.isNotEmpty ? dish.typename : (isComb ? '套餐' : '产品简介'),
            emoji: isComb ? '🍱' : '🍜',
            gradient: isComb
                ? const <Color>[Color(0xFFE8EAF6), Color(0xFFC5CAE9)]
                : const <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
            soldOut: dish.isSoldOut,
            mprice1: dish.mprice1,
            mprice2: dish.mprice2,
            mprice3: dish.mprice3,
            dscflag: dish.dscflag,
          )
        : Product(
            id: pid,
            name: raw['name']?.toString() ?? raw['productname']?.toString() ?? '',
            price: _mustToDouble(raw['sellprice']),
            desc: isComb ? '套餐' : '产品简介',
            emoji: isComb ? '🍱' : '🍜',
            gradient: isComb
                ? const <Color>[Color(0xFFE8EAF6), Color(0xFFC5CAE9)]
                : const <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
          );
    return CartItem(product: product, quantity: qty.toInt() < 1 ? 1 : qty.toInt());
  }

  /// 在已加载商品中查找商品（用于恢复/必点菜时复用商品目录的价格与展示信息）
  DishProduct? _findDishProduct(String productid) {
    if (productid.isEmpty) return null;
    for (final List<DishProduct> list in _groupedProducts.values) {
      for (final DishProduct p in list) {
        if (p.productid == productid) return p;
      }
    }
    return null;
  }

  /// 恢复桌台已保存的未落单菜品（对齐 smdcapp DishesHomeAct2.initGetSaveData）
  ///
  /// 仅主设备模式：POST /api/Table/GetSaveProductList
  /// （tablemaster = getMasterBeanPC 结构 MasterBean JSON，unionFlag = "0"），
  /// 将返回的 Data.detailList 逐条转换加入购物车。
  Future<void> _restoreSavedCart() async {
    try {
      if (!ConnectionManager.pcAlive || widget.tableJson == null) return;
      final String masterJson = _buildRestoreMasterJson();
      final List<Map<String, dynamic>> details =
          await OrderRepository.fetchSaveProductList(masterJson: masterJson);
      if (details.isEmpty || !mounted) return;
      setState(() {
        for (final Map<String, dynamic> d in details) {
          final CartItem item = _savedDetailToCartItem(d);
          final int index = _cartItems
              .indexWhere((CartItem c) => c.uniqueKey == item.uniqueKey);
          if (index >= 0) {
            _cartItems[index].quantity += item.quantity;
          } else {
            _cartItems.add(item);
          }
        }
        _rebuildCountMap();
      });
      _cartBadgeController.forward(from: 0);
    } catch (_) {
      // 恢复失败静默处理，不影响主流程（对齐 smdcapp onFailure 仅记日志）
    }
  }

  /// 构建查询已保存菜品的 MasterBean JSON（对齐 smdcapp getMasterBeanPC 核心字段）
  ///
  /// smdcapp：masterBean = getMasterBeanPC(tableInfo, downPrice(空), 0, 0, 0, tmp.remark)，
  /// 金额均为 0，localbillno 缺省 "temp"。
  String _buildRestoreMasterJson() {
    final Map<String, dynamic>? tmp =
        widget.tableJson?['tmp'] as Map<String, dynamic>?;
    final String now = _mustNowStr();
    final Map<String, dynamic> master = <String, dynamic>{
      'tableid': widget.tableId.isNotEmpty
          ? widget.tableId
          : (tmp?['tableid']?.toString() ?? '-1'),
      'tablename': widget.tableName,
      'remark': tmp?['remark']?.toString() ?? '',
      'amt': 0,
      'retailamt': 0,
      'dscamt': 0,
      'serviceamt': 0,
      'lowamt': 0,
      'addamt': 0,
      'status': 1,
      'androidoperflag': 1,
      'version': 180,
      'updatetime': now,
    };
    if (tmp != null) {
      // 按 smdcapp TableDetailBean 白名单过滤 tmp（对齐本项目修改开台信息做法，避免 .NET 空引用）
      final Map<String, dynamic> filteredTmp = <String, dynamic>{};
      tmp.forEach((String key, dynamic value) {
        if (_kTmpFields.contains(key)) {
          filteredTmp[key] = value;
        }
      });
      // 对齐 smdcapp getMasterBeanPC：localbillno 缺省 "temp"，金额/时间同步进 tmp
      final String localBillno = filteredTmp['localbillno']?.toString() ?? '';
      final String billnoUse = localBillno.isNotEmpty ? localBillno : 'temp';
      filteredTmp['localbillno'] = billnoUse;
      filteredTmp['billno'] = billnoUse;
      filteredTmp['amt'] = 0;
      filteredTmp['retailamt'] = 0;
      filteredTmp['dscamt'] = 0;
      filteredTmp['serviceamt'] = 0;
      filteredTmp['lowamt'] = 0;
      filteredTmp['addamt'] = 0;
      filteredTmp['lastbilltype'] = 7;
      filteredTmp['updatetime'] = now;
      master['tmp'] = filteredTmp;

      if (tmp['saleid'] != null) {
        master['saleid'] = tmp['saleid'].toString();
      }
      if (tmp['id'] != null) {
        master['id'] = tmp['id'];
      }
      if (tmp['billdate'] != null) {
        master['billdate'] = tmp['billdate'].toString();
      }
      master['localbillno'] = billnoUse;
      master['billno'] = billnoUse;
      if (tmp['serverid'] != null) {
        master['serverid'] = tmp['serverid'].toString();
      }
      if (tmp['servername'] != null) {
        master['servername'] = tmp['servername'].toString();
      }
      if (tmp['tabletypeid'] != null) {
        master['tabletypeid'] = tmp['tabletypeid'].toString();
      }
      if (tmp['tablestatus'] != null) {
        master['tablestatus'] = tmp['tablestatus'].toString();
      }
    } else {
      master['billdate'] = now;
    }
    return jsonEncode(master);
  }

  /// 已保存明细转购物车条目（对齐 smdcapp mustToProduct + sperRemark 拼接 + addCart）
  CartItem _savedDetailToCartItem(Map<String, dynamic> d) {
    final double qty = _mustToDouble(d['qty']);
    final double sellprice = _mustToDouble(d['sellprice']);
    final double rrprice = _mustToDouble(d['rrprice']);
    final int weighflag = _mustToInt(d['weighflag']);
    final double weighnum = _mustToDouble(d['weighnum']);

    // 优先用当前商品目录信息（对齐 smdcapp 按商品档案重建），回退保存快照
    final DishProduct? dish = _findDishProduct(d['productid']?.toString() ?? '');
    final Product product = dish != null
        ? _toProduct(dish)
        : Product(
            id: d['productid']?.toString() ?? '',
            name: d['productname']?.toString() ?? '',
            price: sellprice,
          );

    // 对齐 smdcapp：specname + cooktext 用“、”拼接作为规格做法描述
    final String specname =
        d['spec']?.toString() ?? d['specname']?.toString() ?? '';
    final String cooktext = d['cooktext']?.toString() ?? '';
    final String specText = specname.isEmpty
        ? cooktext
        : (cooktext.isEmpty ? specname : '$specname、$cooktext');

    final CartItem item = CartItem(
      product: product,
      quantity: weighflag == 1 ? 1 : (qty > 0 ? qty.toInt() : 1),
      specText: specText,
      extraPrice: _mustToDouble(d['cookaddamt']),
      weighNum: weighflag == 1 ? (weighnum > 0 ? weighnum : qty) : 0,
    );
    item.remark = d['remark']?.toString() ?? '';
    item.isGift = _mustToInt(d['presentflag']) == 1;
    item.isSuspended = _mustToInt(d['hangflag']) == 1;
    item.bagPrice = _mustToDouble(d['bagamt']);
    final double discount = _mustToDouble(d['discount']);
    if (discount > 0 && discount < 100) {
      item.discount = discount;
    }
    // 保存的现价与当前计算单价不一致且非折扣 → 按保存价改价还原
    if (!item.isDiscounted &&
        rrprice > 0 &&
        (rrprice - item.unitPrice).abs() > 0.005) {
      item.customPrice = rrprice;
    }
    return item;
  }

  int _mustToInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _mustToDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// 当前时间 yyyy-MM-dd HH:mm:ss（对齐 smdcapp DateUtils.getTimeStamp）
  String _mustNowStr() {
    final DateTime dt = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  // ==================== 滚动联动 ====================

  /// 右侧列表滚动监听 → 联动左侧分类高亮（带 16ms 节流）
  void _onListScroll() {
    if (_isProgrammaticScroll) return;
    if (_sectionOffsets.isEmpty) return;

    // 节流：约每帧最多处理一次，避免高频计算
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastScrollProcessTime < 16) return;
    _lastScrollProcessTime = now;

    final double scrollPos = _listScrollController.offset + 10; // 10px 容差
    int newIndex = 0;
    for (int i = _sectionOffsets.length - 1; i >= 0; i--) {
      if (scrollPos >= _sectionOffsets[i]) {
        newIndex = i;
        break;
      }
    }

    // 仅更新 ValueNotifier，不触发整页 setState
    if (newIndex != _activeCategoryIndex.value) {
      _activeCategoryIndex.value = newIndex;
      _scrollCategoryToVisible(newIndex);
    }
  }

  /// 确保左侧分类项可见
  void _scrollCategoryToVisible(int index) {
    if (!_categoryScrollController.hasClients) return;
    final double itemHeight = 56.0;
    final double viewportHeight = _categoryScrollController.position.viewportDimension;
    final double targetOffset = index * itemHeight;
    final double currentOffset = _categoryScrollController.offset;

    if (targetOffset < currentOffset) {
      _categoryScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (targetOffset + itemHeight > currentOffset + viewportHeight) {
      _categoryScrollController.animateTo(
        targetOffset + itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// 点击左侧分类 → 右侧滚动到对应区块
  void _onCategoryTap(int index) {
    if (index == _activeCategoryIndex.value) return;
    _activeCategoryIndex.value = index;

    if (index < _sectionOffsets.length && _listScrollController.hasClients) {
      _isProgrammaticScroll = true;
      _listScrollController
          .animateTo(
        _sectionOffsets[index],
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      )
          .then((_) {
        _isProgrammaticScroll = false;
      });
    }
  }

  // ==================== 购物车逻辑 ====================

  int get _totalCount =>
      _cartItems.fold(0, (int sum, CartItem item) => sum + item.quantity);

  double get _totalPrice =>
      _cartItems.fold(0, (double sum, CartItem item) => sum + item.totalPrice);

  /// 某商品在购物车中的数量（O(1) 查询）
  int _productCount(DishProduct product) {
    return _productCountMap[product.productid] ?? 0;
  }

  /// 重建商品数量缓存 Map + 分类数量 Map
  void _rebuildCountMap() {
    _productCountMap.clear();
    _categoryCountMap.clear();
    for (final CartItem item in _cartItems) {
      _productCountMap[item.product.id] =
          (_productCountMap[item.product.id] ?? 0) + item.quantity;
      final String? typeid = _productTypeIdMap[item.product.id];
      if (typeid != null) {
        _categoryCountMap[typeid] =
            (_categoryCountMap[typeid] ?? 0) + item.quantity;
      }
    }
  }

  /// 获取商品加购回调（缓存闭包，避免列表 rebuild 时重建）
  VoidCallback _getAddCallback(DishProduct product) {
    return _addCallbacks.putIfAbsent(product.productid, () => () => _addToCart(product));
  }

  /// 获取商品减购回调（缓存闭包）
  VoidCallback _getRemoveCallback(DishProduct product) {
    return _removeCallbacks.putIfAbsent(product.productid, () => () => _removeFromCart(product));
  }

  /// 加购（无规格商品）
  /// 对齐 smdcapp CartGoodsModel: setting_check_down_goods 开启时，重复点菜弹确认
  Future<void> _addToCart(DishProduct dish, {int quantity = 1, String specText = '', double extraPrice = 0}) async {
    // 限点校验（对齐 smdcapp DialogHelper: maxsellqty > 0 时检查本单已点数量）
    if (dish.maxsellqty > 0) {
      final double currentQty = _cartItems
          .where((CartItem item) => item.product.id == dish.productid)
          .fold(0.0, (double sum, CartItem item) => sum + item.quantity);
      if (currentQty + quantity > dish.maxsellqty) {
        Toast.show('本单限点${_fmtQty(dish.maxsellqty)}${dish.unit}');
        return;
      }
    }
    // 对齐 smdcapp CartGoodsModel.checkProductType:
    // 开启"下单确认"开关时，商品已在购物车中则弹确认
    final bool checkDown = SpUtil.getBool('setting_check_down_goods') ?? false;
    if (checkDown) {
      final bool alreadyInCart = _cartItems.any(
        (CartItem item) => item.product.id == dish.productid,
      );
      if (alreadyInCart) {
        final bool confirmed = await ConfirmDialog.show(
          context,
          content: '当前商品：【${dish.name}】 已点过，是否继续？',
        );
        if (!confirmed || !mounted) return;
      }
    }
    final Product product = _toProduct(dish);
    setState(() {
      final String key = '${product.id}_$specText';
      final int index = _cartItems.indexWhere((CartItem item) => item.uniqueKey == key);
      if (index >= 0) {
        _cartItems[index].quantity += quantity;
      } else {
        _cartItems.add(CartItem(
          product: product,
          quantity: quantity,
          specText: specText,
          extraPrice: extraPrice,
        ));
      }
      _rebuildCountMap();
    });
    _cartBadgeController.forward(from: 0);
  }

  /// 规格商品加购（对齐 smdcapp addCart 逻辑）
  void _addSpecToCart(DishProduct dish, int quantity, String specText, double unitPrice, double wholeExtra) {
    // 限点校验（对齐 smdcapp DialogHelper）
    if (dish.maxsellqty > 0) {
      final double currentQty = _cartItems
          .where((CartItem item) => item.product.id == dish.productid)
          .fold(0.0, (double sum, CartItem item) => sum + item.quantity);
      if (currentQty + quantity > dish.maxsellqty) {
        Toast.show('本单限点${_fmtQty(dish.maxsellqty)}${dish.unit}');
        return;
      }
    }
    final Product product = Product(
      id: dish.productid,
      name: dish.name,
      price: unitPrice,
      desc: dish.typename.isNotEmpty ? dish.typename : '产品简介',
      emoji: '🍜',
      gradient: const <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
      soldOut: dish.isSoldOut,
      mprice1: dish.mprice1,
      mprice2: dish.mprice2,
      mprice3: dish.mprice3,
      dscflag: dish.dscflag,
    );
    setState(() {
      final String key = '${product.id}_$specText';
      final int index = _cartItems.indexWhere((CartItem item) => item.uniqueKey == key);
      if (index >= 0) {
        _cartItems[index].quantity += quantity;
      } else {
        _cartItems.add(CartItem(
          product: product,
          quantity: quantity,
          specText: specText,
          extraPrice: wholeExtra,
        ));
      }
      _rebuildCountMap();
    });
    _cartBadgeController.forward(from: 0);
  }

  /// 打开规格做法弹窗（对齐 smdcapp: 先调 getProductCookSpec 接口获取规格数据）
  Future<void> _openSpecSheet(DishProduct dish) async {
    try {
      // 显示加载中
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
      final DishSpecData specData = await OrderRepository.fetchProductCookSpec(dish.productid);
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading

      if (specData.specdata.isEmpty && specData.cookdata.isEmpty) {
        // 无规格做法数据，直接加购
        _addToCart(dish);
        return;
      }

      await SpecCookSheet.show(
        context,
        product: dish,
        specData: specData,
        onAddToCart: (int qty, String specText, double unitPrice, double wholeExtra) {
          _addSpecToCart(dish, qty, specText, unitPrice, wholeExtra);
        },
        onBuyNow: (int qty, String specText, double unitPrice, double wholeExtra) {
          _addSpecToCart(dish, qty, specText, unitPrice, wholeExtra);
          _goConfirm();
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading
      Toast.show('获取规格信息失败');
    }
  }

  /// 打开套餐弹窗（对齐 smdcapp: 先调 getProductComb 接口获取套餐详情）
  Future<void> _openSetMealSheet(DishProduct dish) async {
    try {
      // 显示加载中
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
      final ComboMealData? comboData = await OrderRepository.fetchProductComb(dish.productid);
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading

      if (comboData == null || comboData.prolist.isEmpty) {
        Toast.show('暂无套餐数据');
        return;
      }

      await SetMealSheet.show(
        context,
        product: dish,
        comboData: comboData,
        onAddToCart: (SetMealResult result) {
          _addComboToCart(dish, result);
        },
        onBuyNow: (SetMealResult result) {
          _addComboToCart(dish, result);
          _goConfirm();
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading
      Toast.show('获取套餐信息失败');
    }
  }

  /// 打开时价菜/称重菜弹窗（对齐 smdcapp showTimePricePop 链式逻辑）
  ///
  /// 业务逻辑对齐 smdcapp SelectProductFragment.tv_size.onClick：
  /// - curflag==1（时价菜）优先：先输价格；若同时 weighflag==1 再链式输重量
  /// - 仅 weighflag==1（称重菜）：输重量
  Future<void> _openTimePriceOrWeighSheet(DishProduct dish) async {
    if (dish.isTimePrice) {
      // 时价菜：先输价格（对齐 smdcapp showTimePricePop(name+"-价格", 0, it)）
      final double? price = await TimePriceSheet.show(
        context,
        title: '${dish.name}-价格',
        type: 0,
        initValue: dish.sellprice,
      );
      if (price == null || !mounted) return;
      if (dish.isWeigh) {
        // 同时是称重菜：链式输重量（对齐 smdcapp type==0 回调中 weighflag==1 分支）
        final double? weight = await TimePriceSheet.show(
          context,
          title: '${dish.name}-重量',
          type: 1,
        );
        if (weight == null || !mounted) return;
        _addTimePriceWeighToCart(dish, price, weight);
      } else {
        _addTimePriceToCart(dish, price);
      }
    } else if (dish.isWeigh) {
      // 纯称重菜：输重量（对齐 smdcapp showTimePricePop(name+"-重量", 1, it)）
      final double? weight = await TimePriceSheet.show(
        context,
        title: '${dish.name}-重量',
        type: 1,
      );
      if (weight == null || !mounted) return;
      _addWeighToCart(dish, weight);
    }
  }

  /// 时价菜加购（对齐 smdcapp：cPrice=price、isChangePrice=true、selectNum=1）
  void _addTimePriceToCart(DishProduct dish, double price) {
    // 限点校验
    if (dish.maxsellqty > 0) {
      final double currentQty = _cartItems
          .where((CartItem item) => item.product.id == dish.productid)
          .fold(0.0, (double sum, CartItem item) => sum + item.quantity);
      if (currentQty + 1 > dish.maxsellqty) {
        Toast.show('本单限点${_fmtQty(dish.maxsellqty)}${dish.unit}');
        return;
      }
    }
    final Product product = _toProduct(dish);
    setState(() {
      _cartItems.add(CartItem(
        product: product,
        quantity: 1,
      )..customPrice = price);
      _rebuildCountMap();
    });
    _cartBadgeController.forward(from: 0);
  }

  /// 称重菜加购（对齐 smdcapp：每次称重复制商品独立加购，weighNum=selectNum=重量）
  void _addWeighToCart(DishProduct dish, double weight) {
    // 限点校验
    if (dish.maxsellqty > 0) {
      final double currentQty = _cartItems
          .where((CartItem item) => item.product.id == dish.productid)
          .fold(0.0, (double sum, CartItem item) => sum + item.quantity);
      if (currentQty + 1 > dish.maxsellqty) {
        Toast.show('本单限点${_fmtQty(dish.maxsellqty)}${dish.unit}');
        return;
      }
    }
    final Product product = _toProduct(dish);
    setState(() {
      _cartItems.add(CartItem(
        product: product,
        quantity: 1,
        weighNum: weight,
      ));
      _rebuildCountMap();
    });
    _cartBadgeController.forward(from: 0);
  }

  /// 时价+称重菜加购（对齐 smdcapp：cPrice=price 且 weighNum=重量，总价=价格×重量）
  void _addTimePriceWeighToCart(DishProduct dish, double price, double weight) {
    // 限点校验
    if (dish.maxsellqty > 0) {
      final double currentQty = _cartItems
          .where((CartItem item) => item.product.id == dish.productid)
          .fold(0.0, (double sum, CartItem item) => sum + item.quantity);
      if (currentQty + 1 > dish.maxsellqty) {
        Toast.show('本单限点${_fmtQty(dish.maxsellqty)}${dish.unit}');
        return;
      }
    }
    final Product product = _toProduct(dish);
    setState(() {
      _cartItems.add(CartItem(
        product: product,
        quantity: 1,
        weighNum: weight,
      )..customPrice = price);
      _rebuildCountMap();
    });
    _cartBadgeController.forward(from: 0);
  }

  /// 套餐商品加购（对齐 smdcapp 套餐加入购物车逻辑）
  void _addComboToCart(DishProduct dish, SetMealResult result) {
    // 限点校验（对齐 smdcapp DialogHelper）
    if (dish.maxsellqty > 0) {
      final double currentQty = _cartItems
          .where((CartItem item) => item.product.id == dish.productid)
          .fold(0.0, (double sum, CartItem item) => sum + item.quantity);
      if (currentQty + result.quantity > dish.maxsellqty) {
        Toast.show('本单限点${_fmtQty(dish.maxsellqty)}${dish.unit}');
        return;
      }
    }
    final Product product = Product(
      id: dish.productid,
      name: dish.name,
      price: result.unitPrice,
      desc: dish.typename.isNotEmpty ? dish.typename : '套餐',
      emoji: '🍱',
      gradient: const <Color>[Color(0xFFE8EAF6), Color(0xFFC5CAE9)],
      soldOut: dish.isSoldOut,
      mprice1: dish.mprice1,
      mprice2: dish.mprice2,
      mprice3: dish.mprice3,
      dscflag: dish.dscflag,
    );
    setState(() {
      final String key = '${product.id}_${result.specText}';
      final int index = _cartItems.indexWhere((CartItem item) => item.uniqueKey == key);
      if (index >= 0) {
        _cartItems[index].quantity += result.quantity;
      } else {
        _cartItems.add(CartItem(
          product: product,
          quantity: result.quantity,
          specText: result.specText,
          extraPrice: result.combAddAmt,
        ));
      }
      _rebuildCountMap();
    });
    _cartBadgeController.forward(from: 0);
  }

  /// 展开购物车面板
  void _openCartPanel() {
    if (_cartItems.isEmpty) {
      Toast.show('购物车还是空的，先选几个菜吧');
      return;
    }
    CartPanelSheet.show(
      context,
      cartItems: _cartItems,
      onAdd: (CartItem item) {
        setState(() {
          item.quantity++;
          _rebuildCountMap();
        });
      },
      onRemove: (CartItem item) {
        setState(() {
          item.quantity--;
          if (item.quantity <= 0) {
            _cartItems.remove(item);
          }
          _rebuildCountMap();
        });
      },
      onClear: () {
        setState(() {
          _cartItems.clear();
          _rebuildCountMap();
        });
        Navigator.of(context).pop();
      },
      onItemChanged: (CartItem item) {
        setState(() {
          _rebuildCountMap();
        });
      },
      onDelete: (CartItem item) {
        setState(() {
          _cartItems.remove(item);
          _rebuildCountMap();
        });
        if (_cartItems.isEmpty) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  /// 减少
  void _removeFromCart(DishProduct dish) {
    setState(() {
      final int index = _cartItems.indexWhere(
          (CartItem item) => item.product.id == dish.productid);
      if (index >= 0) {
        _cartItems[index].quantity--;
        if (_cartItems[index].quantity <= 0) {
          _cartItems.removeAt(index);
        }
      }
      _rebuildCountMap();
    });
  }

  /// 将 DishProduct 转为购物车使用的 Product 模型
  Product _toProduct(DishProduct dish) {
    return Product(
      id: dish.productid,
      name: dish.name,
      price: dish.sellprice,
      desc: dish.typename.isNotEmpty ? dish.typename : '产品简介',
      emoji: '🍜',
      gradient: const <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
      soldOut: dish.isSoldOut,
      mprice1: dish.mprice1,
      mprice2: dish.mprice2,
      mprice3: dish.mprice3,
      dscflag: dish.dscflag,
    );
  }

  /// 跳转订单确认页
  void _goConfirm() {
    if (_cartItems.isEmpty) {
      Toast.show('购物车还是空的，先选几个菜吧');
      return;
    }
    NavigatorUtils.push(
      context,
      Routes.orderConfirmPage,
      arguments: <String, dynamic>{
        'tableName': widget.tableName,
        'persons': widget.persons,
        'cartItems': _cartItems,
        'tableId': widget.tableId,
        'tableCode': widget.tableCode,
        'saleid': widget.saleid,
        'serverId': widget.serverId,
        'serverName': widget.serverName,
        'remark': widget.remark,
        'tableJson': widget.tableJson,
      },
    );
  }

  // ==================== 搜索与扫码 ====================

  /// 搜索过滤（按名称/条码/助记码匹配）
  void _onSearchChanged(String value) {
    setState(() {
      _searchKeyword = value.trim();
    });
    // 搜索时重置滚动位置
    if (_searchKeyword.isNotEmpty && _listScrollController.hasClients) {
      _isProgrammaticScroll = true;
      _listScrollController.jumpTo(0);
      _isProgrammaticScroll = false;
    }
  }

  /// 判断商品是否匹配搜索关键词
  bool _matchSearch(DishProduct product) {
    if (_searchKeyword.isEmpty) return true;
    final String kw = _searchKeyword.toLowerCase();
    return product.name.toLowerCase().contains(kw) ||
        product.barcode.toLowerCase().contains(kw) ||
        product.helpcode.toLowerCase().contains(kw);
  }

  /// 调用摄像头扫描条码（对齐 ylx-boos-flutter scan_price 流程）
  /// 对齐 smdcapp SearchActivity: setting_product_is_scans 开启时，扫码加购后自动继续扫码
  Future<void> _scanBarcode() async {
    if (Device.isMobile) {
      NavigatorUtils.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final Object? code = await Navigator.push(
        context,
        MaterialPageRoute<Object>(builder: (_) => const BarcodeScannerPage()),
      );
      if (code == null || !mounted) return;
      _searchController.text = code.toString();
      _onSearchChanged(code.toString());
      // 对齐 smdcapp: if (SpUtils.isProductScans()) { delay(700); goScan() }
      final bool continuousScan = SpUtil.getBool('setting_product_is_scans') ?? false;
      if (continuousScan) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) _scanBarcode();
      }
    } else {
      Toast.show('当前平台暂不支持扫码');
    }
  }

  // ==================== UI构建 ====================

  /// 顶部导航栏（对齐 smdcapp DishesHomeAct2：快餐模式标题“快餐点餐”+模式切换图标，正餐模式显示返回按钮）
  ///
  /// 快餐模式布局对齐 smdcapp 截图：标题(左) + 搜索框(中) + 切换图标(右) 同行
  Widget _buildAppBar(bool isDark) {
    if (widget.fastMode) {
      return _buildFastModeAppBar(isDark);
    }
    return ColoredBox(
      color: isDark ? const Color(0xFF242526) : Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 46,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                  onPressed: () => NavigatorUtils.goBack(context),
                ),
              ),
              Center(
                child: Text(
                  '点菜',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                  icon: Icon(
                    Icons.more_horiz,
                    size: 22,
                    color: isDark ? Colors.white70 : const Color(0xFF4E5969),
                  ),
                  onPressed: () => Toast.show('更多操作开发中'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 快餐模式顶栏（对齐 smdcapp DishesHomeAct2：标题“快餐点餐” + 右侧模式切换图标，搜索框在标题下方）
  Widget _buildFastModeAppBar(bool isDark) {
    return ColoredBox(
      color: isDark ? const Color(0xFF242526) : Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 46,
          child: Stack(
            children: <Widget>[
              // 中间: 标题（对齐 smdcapp titleTextView “快餐点餐”）
              Center(
                child: Text(
                  '快餐点餐',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                ),
              ),
              // 右侧: 模式切换图标（对齐 smdcapp imgSx + data_change 图标）
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                  icon: Image.asset(
                    'assets/images/data_change.png',
                    width: 20,
                    height: 20,
                  ),
                  onPressed: _showModeSwitchSheet,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 模式切换弹窗（对齐 smdcapp DishesHomeAct2.showModel → CutModelPopup）
  ///
  /// 正餐模式：返回桌台页（对齐 smdcapp TableInfoActivity.startActivity + finish）
  /// 快餐模式：提示已是快餐模式（对齐 smdcapp "当前已经是快餐模式"）
  void _showModeSwitchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CutModelSheet(
        onSelected: (int mode) {
          if (mode == StoreModeUtils.storeModelNormal) {
            // 切换正餐模式：清除购物车 + 返回桌台页（对齐 smdcapp cartModel.setNullData + finish）
            StoreModeUtils.putCurrentStoreModel(StoreModeUtils.storeModelNormal);
            Toast.show('切换正餐模式成功');
            Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
          } else if (mode == StoreModeUtils.storeModelFast) {
            Toast.show('当前已经是快餐模式');
          } else {
            Toast.show('配送模式开发中');
          }
        },
      ),
    );
  }

  /// 桌台信息栏（桌台号 + 人数 + 搜索框 + 扫码按钮）
  ///
  /// 快餐模式无桌台信息（对齐 smdcapp 快餐模式不显示桌台行，仅显示搜索框）
  Widget _buildTableInfoBar(bool isDark) {
    if (widget.fastMode) {
      return Container(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
        child: _buildSearchField(isDark),
      );
    }
    return Container(
      color: isDark ? const Color(0xFF242526) : Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 第一行：桌台信息
          Row(
            children: <Widget>[
              _InfoChip(
                iconAsset: 'assets/images/icon_table.png',
                label: widget.tableName,
                isDark: isDark,
              ),
              const SizedBox(width: 16),
              _InfoChip(
                iconAsset: 'assets/images/icon_people.png',
                label: '人数: $_persons',
                isDark: isDark,
              ),
              const SizedBox(width: 4),
              // 编辑图标（对齐 smdcapp DishesHomeAct2 ivEdit → showChangeTablePop）
              GestureDetector(
                onTap: _showEditTableInfoSheet,
                child: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: isDark ? Colors.white70 : const Color(0xFF86909C),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Toast.show('更多操作开发中'),
                child: Text(
                  '更多>',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF4E5969),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：搜索框
          _buildSearchField(isDark),
        ],
      ),
    );
  }

  /// 搜索框组件（Row 布局，扫码图标固定在最右侧不被挤动）
  Widget _buildSearchField(bool isDark) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 10),
          Icon(Icons.search, size: 18, color: isDark ? const Color(0xFF999999) : const Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Flexible(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '请输入菜品名称或检索码',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF666666) : const Color(0xFF9CA3AF),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          // 清除图标（仅有文本时显示，不会挤动扫描图标）
          if (_searchKeyword.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.cancel, size: 16, color: isDark ? const Color(0xFF666666) : const Color(0xFFBDBDBD)),
              ),
            ),
          // 扫描图标（始终固定在最右侧）
          GestureDetector(
            onTap: _scanBarcode,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SvgPicture.asset(
                'assets/svg/scan.svg',
                width: 20,
                height: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 修改开台信息弹窗（对齐 smdcapp DishesHomeAct2.showChangeTablePop → TableOpenBottomV2Dialog 修改模式）
  void _showEditTableInfoSheet() {
    final TextEditingController personCtrl =
        TextEditingController(text: '$_persons');
    final TextEditingController remarkCtrl =
        TextEditingController(text: _remark);
    final String serverId = _serverId;
    String serverName = _serverName.isNotEmpty ? _serverName : '系统管理员';
    String selectedServerId = serverId;
    bool submitting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetCtx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 标题栏
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          '修改开台信息',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D2129),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(sheetCtx).pop(),
                        child: const Icon(Icons.close, size: 22, color: Color(0xFF86909C)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // 人数
                  Row(
                    children: <Widget>[
                      const Text('人数：', style: TextStyle(fontSize: 15, color: Color(0xFF4E5969))),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        height: 40,
                        child: TextField(
                          controller: personCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          textAlign: TextAlign.center,
                          onTap: () {
                            // 聚焦时自动选中全部文本
                            personCtrl.selection = TextSelection(
                              baseOffset: 0,
                              extentOffset: personCtrl.text.length,
                            );
                          },
                          style: const TextStyle(fontSize: 15, color: Color(0xFF1D2129)),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: _kBrandRed),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 服务员
                  Row(
                    children: <Widget>[
                      const Text('服务员：', style: TextStyle(fontSize: 15, color: Color(0xFF4E5969))),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          final Waiter? waiter = await DishWaiterSheet.show(
                            ctx,
                            dishName: widget.tableName,
                            currentWaiter: serverName,
                          );
                          if (waiter != null) {
                            setSheetState(() {
                              serverName = waiter.name;
                              selectedServerId = waiter.userid;
                            });
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              serverName,
                              style: const TextStyle(fontSize: 15, color: Color(0xFF1D2129)),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF86909C)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 备注
                  Row(
                    children: <Widget>[
                      const Text('备注：', style: TextStyle(fontSize: 15, color: Color(0xFF4E5969))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: remarkCtrl,
                            style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
                            decoration: InputDecoration(
                              hintText: '请输入备注',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFC9CDD4)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: _kBrandRed),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 按钮行：取消 + 确定
                  Row(
                    children: <Widget>[
                      // 取消
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(sheetCtx).pop(),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFE5E6EB)),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Center(
                              child: Text(
                                '取消',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF4E5969)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 确定
                      Expanded(
                        child: GestureDetector(
                          onTap: submitting
                              ? null
                              : () async {
                                  final int personNum =
                                      int.tryParse(personCtrl.text.trim()) ?? 0;
                                  if (personNum <= 0) {
                                    Toast.show('请输入正确的人数！');
                                    return;
                                  }
                                  setSheetState(() => submitting = true);
                                  final bool success = await _submitUpdateTableInfo(
                                    personNum: personNum,
                                    remark: remarkCtrl.text.trim(),
                                    serverId: selectedServerId,
                                    serverName: serverName,
                                  );
                                  if (!ctx.mounted) return;
                                  setSheetState(() => submitting = false);
                                  if (success) {
                                    Navigator.of(sheetCtx).pop();
                                    // 更新页面状态（对齐 smdcapp 回调中更新 tvPeople）
                                    setState(() {
                                      _persons = personNum;
                                      _serverId = selectedServerId;
                                      _serverName = serverName;
                                      _remark = remarkCtrl.text.trim();
                                    });
                                  }
                                },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Center(
                              child: submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      '确定',
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
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 构建完整的 tmp 默认结构（对齐接口文档 UpdateSaleMasterTmp 的 masterTmpDto.tmp 全字段）
  ///
  /// 服务端 .NET 模型字段缺失时为 null，访问会抛 NullReferenceException，
  /// 因此必须提供完整默认值，再用实际数据覆盖。
  static Map<String, dynamic> _defaultTmp() => <String, dynamic>{
        'm_resevrestatus': 0,
        'spid': 0,
        'sid': 0,
        'saleid': '',
        'billno': '',
        'billdate': '',
        'tableid': '',
        'tablecode': '',
        'tablename': '',
        'tableno': '',
        'arrearages': '',
        'tablestatus': 0,
        'tablestatusText': '',
        'vipid': '',
        'vipno': '',
        'vipname': '',
        'vipmobile': '',
        'retailamt': '',
        'dscamt': '',
        'amt': '',
        'addamt': '',
        'payment': '',
        'changeamt': '',
        'billtype': 0,
        'lastbilltype': 0,
        'mallbillid': '',
        'makedataflag': 0,
        'upflag': 0,
        'cashid': '',
        'cashname': '',
        'serverid': '',
        'servername': '',
        'machno': '',
        'takeouttype': 0,
        'localbillno': '',
        'returnbillno': '',
        'personnum': 0,
        'person': 0,
        'dataiflag': 0,
        'unitableid': '',
        'unitableno': '',
        'allunitablenames': '',
        'dataitableid': '',
        'serviceamt': '',
        'remark': '',
        'lockflag': 0,
        'tabletypeid': '',
        'openMinutes': '',
        'rate': '',
        'showamt': '',
        'showPayment': '',
        'showDueinamt': '',
        'dueinamt': '',
        'removeZero': '',
        'roundamt': '',
        'handRemoveZeroAmt': '',
        'lowamt': '',
        'opertype': 0,
        'paytime': '',
        'cxreduceamt': '',
        'takeoutpayamt': '',
        'deliverfee': '',
        'operremark': '',
        'operamt': '',
        'qty': '',
        'rowcount': '',
        'unitablename': '',
        'billflag': 0,
        'tablenobyinput': 0,
        'prodchgflag': 0,
        'realbillno': '',
        'ordernumber': '',
        'printremark': '',
        'takeout': 0,
        'takeoutsort': 0,
        'togoinfo': '',
        'togoflag': 0,
        'resevrestatus': 0,
        'resevremsg': '',
        'resevreVisibility': 0,
        'totalretailamt': '',
        'detailList': <dynamic>[],
        'hangflag': 0,
        'takecode': '',
        'customername': '',
        'tel': '',
        'address': '',
        'psprice': '',
        'bagamt': '',
        'takeoutfavour': '',
        'shopfavour': '',
        'mealtype': 0,
        'printkdflag': 0,
        'printcpdflag': 0,
        'oldtablename': '',
        'oldtablecode': '',
        'newtablename': '',
        'newtablecode': '',
        'newtableid': '',
        'prnretflag': 0,
        'prnpreflag': 0,
        'onlinecode': '',
        'hasdecamt': '',
        'ispaying': '',
        'reRalcPriceFlag': '',
        'printjzflag': 0,
        'confirmqty': '',
        'weightinfo': '',
        'containweight': 0,
        'opermachno': '',
        'delivertime': '',
        'servicebegintime': '',
        'serviceendtime': '',
        'fornowamt': '',
        'fornowlowamt': '',
        'fornowdscamt': '',
        'fornowserviceamt': '',
        'printtype': 0,
        'sendprintflag': 0,
        'depositAmt': '',
        'additionid': '',
        'servicediscount': '',
        'servicetimerange': '',
        'cdflag': 0,
        'cxmbillid': '',
        'retailamtByServiceFeeFlag': '',
        'amtByServiceFeeFlag': '',
        'paymachno': '',
        'uniflowno': 0,
        'uniflownoText': '',
        'orderid': '',
        'wxclientbillno': '',
        'billretflag': 0,
        'ordercreatetime': '',
        'intOpenMinutes': 0,
        'warnedcount': 0,
        'lastwarntime': '',
        'taxrate': '',
        'serviceamtByHand': '',
        'preprintflag': 0,
        'wxpaytype': 0,
        'wxterminalsn': '',
        'wxterminalkey': '',
        'id': 0,
        'status': 0,
        'createtime': '',
        'updatetime': '',
        'opertime': '',
        'createid': '',
        'createname': '',
        'operid': '',
        'opername': '',
      };

  /// 构建完整的 masterTmpDto 默认结构（对齐接口文档 UpdateSaleMasterTmp 全字段）
  static Map<String, dynamic> _defaultMasterTmpDto() => <String, dynamic>{
        'isSelected': '',
        'tmp': _defaultTmp(),
        'unionPayFlag': 0,
        'unionTableIds': '',
        'unionTableCodes': '',
        'unionTablNames': '',
        'billtype': 0,
        'unitableid': '',
        'newtableid': '',
        'dataiflag': 0,
        'unionSaleIds': '',
        'serviceamt': '',
        'lowamt': '',
        'person': 0,
        'printkdflag': 0,
        'payways': <dynamic>[],
        'paydetail': <dynamic>[],
        'saleid': '',
        'prnpreflag': 0,
        'autogenedflag': '',
        'androidoperflag': 0,
        'noprintdishflag': 0,
        'transInTableReCalcServiceAmtFlag': 0,
        'isTimeOut': 0,
        'timeOutMinutes': '',
        'surplusMinutes': '',
        'version': 0,
        'spid': 0,
        'sid': 0,
        'tableid': '',
        'code': '',
        'name': '',
        'areaid': '',
        'areaname': '',
        'tabletypeid': '',
        'tabletypename': '',
        'stopflag': 0,
        'isort': 0,
        'reservationflag': 0,
        'opentimeout': 0,
        'warnbefore': 0,
        'warncount': 0,
        'warninterval': 0,
        'id': 0,
        'status': 0,
        'createtime': '',
        'updatetime': '',
        'opertime': '',
        'createid': '',
        'createname': '',
        'operid': '',
        'opername': '',
      };

  /// 深度合并：[overrides] 中的实际数据覆盖 [defaults] 默认值，
  /// 嵌套 Map 递归合并；null 值不覆盖默认值，保证服务端所需的全部字段都存在且非空。
  static Map<String, dynamic> _deepMerge(
    Map<String, dynamic> defaults,
    Map<String, dynamic> overrides,
  ) {
    final Map<String, dynamic> result = Map<String, dynamic>.from(defaults);
    overrides.forEach((String key, dynamic value) {
      if (value == null) {
        return; // null 不覆盖默认值，避免服务端空引用
      }
      if (value is Map && result[key] is Map) {
        result[key] = _deepMerge(
          (result[key] as Map).cast<String, dynamic>(),
          value.cast<String, dynamic>(),
        );
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  /// smdcapp TableDetailBean 定义的 tmp 字段白名单。
  ///
  /// 桌台列表接口返回的 tmp 含大量额外字段（isSelected/arrearages/tablestatusText/
  /// rate/taxrate/ispaying/Showamt 等），且部分类型为 boolean/number，
  /// 而服务端 C# 模型期望 string。smdcapp 重新序列化时只保留其 Java 模型定义的字段，
  /// 因此我们必须同样过滤，否则多余字段导致 .NET 空引用。
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

  /// smdcapp TableInfoBean 定义的 masterTmpDto 外层字段白名单。
  static const Set<String> _kTableFields = <String>{
    'tabletypename', 'createtime', 'code', 'areaname', 'tabletypeid', 'tablestatus',
    'operid', 'spid', 'sid', 'createname', 'stopflag', 'areaid', 'person', 'flag',
    'dieshesType', 'createid', 'opername', 'isalltype', 'tmp', 'name', 'billtype',
    'tableid', 'isort', 'id', 'updatetime', 'unicount', 'status', 'lowtype',
    'serviceamt', 'dataitableid', 'trueflag', 'reservationflag', 'lowamt',
    'minsalesamtflag', 'servicetype', 'virtulflag', 'excesstime', 'exceedtype',
    'virtualflag', 'newtableid',
  };

  /// 按 smdcapp 模型字段白名单过滤 masterTmpDto，丢弃桌台列表原始 JSON 中的多余字段。
  static Map<String, dynamic> _filterMasterTmpDto(Map<String, dynamic> tableBean) {
    final Map<String, dynamic> result = <String, dynamic>{};
    tableBean.forEach((String key, dynamic value) {
      if (!_kTableFields.contains(key)) {
        return; // 丢弃外层多余字段
      }
      if (key == 'tmp' && value is Map) {
        final Map<String, dynamic> filteredTmp = <String, dynamic>{};
        value.cast<String, dynamic>().forEach((String tk, dynamic tv) {
          if (_kTmpFields.contains(tk)) {
            filteredTmp[tk] = tv;
          }
        });
        result['tmp'] = filteredTmp;
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  /// 提交修改开台信息接口（对齐 smdcapp TableDao.updateMasterTmp 双模式逻辑）
  Future<bool> _submitUpdateTableInfo({
    required int personNum,
    required String remark,
    required String serverId,
    required String serverName,
  }) async {
    try {
      final bool useMaster = ConnectionManager.pcAlive;

      if (useMaster) {
        // 主设备模式：对齐 smdcapp PCTableHttpUtil.updateMasterTmp
        // POST /api/table/UpdateSaleMasterTmp，参数 data 为 PCTableChangeVTO JSON
        // smdcapp 逻辑：克隆完整 TableInfoBean，仅修改 tmp 的 4 个字段
        //
        // 关键：桌台列表原始 JSON 含大量 smdcapp 模型没有的额外字段（且部分类型不符），
        // 直接发送会导致 .NET 服务端空引用。因此深度合并后用 smdcapp 字段白名单过滤，
        // 保证发送的字段集与 smdcapp 重新序列化的结果一致。
        final Map<String, dynamic> actual = widget.tableJson ??
            <String, dynamic>{
              'tableid': widget.tableId,
              'name': widget.tableName,
              'code': widget.tableCode,
            };
        final Map<String, dynamic> tableBean =
            _deepMerge(_defaultMasterTmpDto(), actual);

        // 更新 tmp 中的字段（对齐 smdcapp objectClone.tmp.serverid = ...)
        final Map<String, dynamic> tmp = tableBean['tmp'] is Map
            ? Map<String, dynamic>.from(tableBean['tmp'] as Map)
            : _defaultTmp();
        tmp['serverid'] = serverId;
        tmp['servername'] = serverName;
        tmp['remark'] = remark;
        tmp['personnum'] = personNum;
        tableBean['tmp'] = tmp;

        // 按 smdcapp 模型字段白名单过滤，丢弃桌台列表原始 JSON 的多余字段
        // （对齐 smdcapp：FastJSON 重新序列化只保留 Java 模型定义的字段）
        final Map<String, dynamic> filteredBean = _filterMasterTmpDto(tableBean);

        final Map<String, dynamic> vto = <String, dynamic>{
          'masterTmpDto': filteredBean,
        };
        await requestForm(
          HttpApi.pcUpdateMasterTmp,
          <String, dynamic>{'data': jsonEncode(vto)},
          masterDevice: true,
          showError: true,
        );
      } else {
        // 云服务模式：对齐 smdcapp /YttSvr/app/sale/updateMasterTmp
        await requestForm(
          HttpApi.updateMasterTmp,
          <String, dynamic>{
            'saleid': widget.saleid,
            'remark': remark,
            'personnum': '$personNum',
            'tableid': widget.tableId,
            'tablecode': widget.tableCode,
            'unitableid': '',
            'serverid': serverId,
            'servername': serverName,
            'tablename': widget.tableName,
            'printtype': '-1',
          },
          masterDevice: false,
          showError: true,
        );
      }

      Toast.show('修改桌台成功！');
      return true;
    } catch (_) {
      // 错误已在 requestForm 中 Toast
      return false;
    }
  }

  /// 左侧分类侧边栏（ValueListenableBuilder 局部重建，滚动联动不触发整页 rebuild）
  Widget _buildCategorySidebar(bool isDark) {
    return Container(
      width: 88,
      color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF7F8FA),
      child: ValueListenableBuilder<int>(
        valueListenable: _activeCategoryIndex,
        builder: (BuildContext context, int activeIndex, Widget? child) {
          return ListView.builder(
            controller: _categoryScrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _categories.length,
            itemBuilder: (BuildContext context, int index) {
              final bool selected = activeIndex == index;
              final DishCategory category = _categories[index];

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onCategoryTap(index),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: selected
                        ? (isDark ? const Color(0xFF242526) : Colors.white)
                        : Colors.transparent,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // 左侧红色指示条
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 14),
                        width: 3.5,
                        decoration: BoxDecoration(
                          color: selected ? _kBrandRed : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Center(
                        child: Text(
                          category.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: selected ? 14 : 13,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            color: selected
                                ? (isDark ? Colors.white : _kBrandRed)
                                : (isDark ? const Color(0xFFB8B8B8) : const Color(0xFF4E5969)),
                          ),
                        ),
                      ),
                      // 分类购物车数量角标
                      if ((_categoryCountMap[category.typeid] ?? 0) > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            decoration: BoxDecoration(
                              color: _kBrandRed,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${_categoryCountMap[category.typeid]}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 右侧商品列表（一次性加载全部，按分类分组 + 分类 header）
  Widget _buildProductList(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (_errorMsg != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4)),
            const SizedBox(height: 12),
            Text(
              _errorMsg!,
              style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C)),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: _kBrandRed,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('重新加载', style: TextStyle(fontSize: 13, color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Text(
          '暂无菜品数据',
          style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C)),
        ),
      );
    }

    // 构建扁平化列表：[分类header, 商品, 商品, ..., 分类header, 商品, ...]
    final List<Widget> slivers = <Widget>[];
    bool hasAnyResult = false;
    for (int i = 0; i < _categories.length; i++) {
      final DishCategory cat = _categories[i];
      final List<DishProduct> allProducts = _groupedProducts[cat.typeid] ?? <DishProduct>[];
      // 搜索过滤
      final List<DishProduct> products = _searchKeyword.isEmpty
          ? allProducts
          : allProducts.where(_matchSearch).toList();

      if (products.isEmpty) continue;
      hasAnyResult = true;

      // 分类 header
      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            height: _kHeaderHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 12),
            color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF7F8FA),
            child: Text(
              cat.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF86909C),
              ),
            ),
          ),
        ),
      );

      // 该分类下的商品（SliverList 懒加载 + RepaintBoundary 隔离重绘）
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final DishProduct product = products[index];
              return RepaintBoundary(
                child: _DishProductCard(
                  key: ValueKey<String>(product.productid),
                  product: product,
                  count: _productCount(product),
                  isDark: isDark,
                  showNum: SpUtil.getBool('ENABLE_PRODUCT_NUM', defValue: true) ?? true,
                  onAdd: _getAddCallback(product),
                  onRemove: _getRemoveCallback(product),
                  onSpec: () => _openSpecSheet(product),
                  onComb: () => _openSetMealSheet(product),
                  onTimePriceOrWeigh: () => _openTimePriceOrWeighSheet(product),
                ),
              );
            },
            childCount: products.length,
            addAutomaticKeepAlives: false,
          ),
        ),
      );
    }

    // 底部留白（给购物车栏让位）
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));

    // 搜索无结果提示
    if (!hasAnyResult) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off, size: 48, color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4)),
            const SizedBox(height: 12),
            Text(
              '未找到“$_searchKeyword”相关菜品',
              style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C)),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      controller: _listScrollController,
      slivers: slivers,
      // 性能优化：关闭隐式动画，减少滚动时的额外开销
      physics: const AlwaysScrollableScrollPhysics(),
    );
  }

  /// 底部购物车栏
  Widget _buildCartBar(bool isDark) {
    final int count = _totalCount;
    final bool hasItems = count > 0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF242526) : Colors.white,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF1D2129).withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 12),
                // 购物车图标 + 角标（点击展开购物车）
                GestureDetector(
                  onTap: _openCartPanel,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: hasItems
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                                )
                              : null,
                          color: hasItems ? null : const Color(0xFFC9CDD4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      if (hasItems)
                        Positioned(
                          top: -6,
                          right: -8,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.4, end: 1.0).animate(
                              CurvedAnimation(
                                parent: _cartBadgeController,
                                curve: Curves.elasticOut,
                              ),
                            ),
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: _kBrandRed,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Center(
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // 价格区域
                Expanded(
                  child: hasItems
                      ? Text(
                          '¥${_totalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF1D2129),
                          ),
                        )
                      : Text(
                          '未选购商品',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
                          ),
                        ),
                ),
                // 去下单按钮
                GestureDetector(
                  onTap: _goConfirm,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      gradient: hasItems
                          ? const LinearGradient(
                              colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                            )
                          : null,
                      color: hasItems ? null : const Color(0xFFC9CDD4),
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: const Center(
                      child: Text(
                        '去下单',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? ThemeUtils.light : ThemeUtils.dark,
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                _buildAppBar(isDark),
                _buildTableInfoBar(isDark),
                SizedBox(
                  height: 0.6,
                  child: ColoredBox(
                    color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFEDEDEF),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      _buildCategorySidebar(isDark),
                      Expanded(
                        child: ColoredBox(
                          color: isDark ? const Color(0xFF18191A) : Colors.white,
                          child: _buildProductList(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 底部购物车浮层
            _buildCartBar(isDark),
          ],
        ),
      ),
    );
  }
}

/// 信息小胶囊(桌台/人数)，图标对齐 smdcapp dishes_home_act.xml
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.iconAsset,
    required this.label,
    required this.isDark,
  });

  final String iconAsset;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.asset(
            iconAsset,
            width: 18,
            height: 18,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : const Color(0xFF1D2129),
          ),
        ),
      ],
    );
  }
}

/// 商品卡片（对齐 smdcapp 点菜列表项）
class _DishProductCard extends StatelessWidget {
  const _DishProductCard({
    super.key,
    required this.product,
    required this.count,
    required this.isDark,
    required this.showNum,
    required this.onAdd,
    required this.onRemove,
    required this.onSpec,
    required this.onComb,
    required this.onTimePriceOrWeigh,
  });

  final DishProduct product;
  final int count;
  final bool isDark;
  /// 是否显示数字角标（对齐 smdcapp ENABLE_PRODUCT_NUM）
  final bool showNum;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onSpec;
  final VoidCallback onComb;

  /// 时价菜/称重菜按钮回调（对齐 smdcapp showTimePricePop 链式弹窗）
  final VoidCallback onTimePriceOrWeigh;

  @override
  Widget build(BuildContext context) {
    final bool soldOut = product.isSoldOut;

    return Container(
      height: _kProductHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2A2B2C) : const Color(0xFFF2F3F5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          // 商品图（优先显示网络图片，无图时用渐变色块 + emoji 代替）
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: product.imageurl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: product.imageurl.startsWith('http')
                        ? product.imageurl
                        : '$_kImgAddress${product.imageurl}',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    memCacheWidth: 128,
                    placeholder: (_, __) => _buildPlaceholder(soldOut),
                    errorWidget: (_, __, dynamic error) => _buildPlaceholder(soldOut),
                  )
                : _buildPlaceholder(soldOut),
          ),
          const SizedBox(width: 10),
          // 中间信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: soldOut
                        ? (isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4))
                        : (isDark ? Colors.white : const Color(0xFF1D2129)),
                  ),
                ),
                const SizedBox(height: 4),
                // 限点 + 会员价（对齐 smdcapp，放在价格上方）
                if (product.maxsellqty > 0 || product.mprice1 > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: <Widget>[
                        if (product.maxsellqty > 0)
                          Text(
                            '(限点${_fmtQty(product.maxsellqty)}${product.unit})',
                            style: const TextStyle(fontSize: 11, color: _kBrandRed),
                          ),
                        if (product.maxsellqty > 0 && product.mprice1 > 0)
                          const SizedBox(width: 6),
                        if (product.mprice1 > 0)
                          Text(
                            '(会员:¥${_fmtPrice(product.mprice1)})',
                            style: const TextStyle(fontSize: 11, color: _kBrandRed),
                          ),
                      ],
                    ),
                  ),
                // 价格 + 单位
                Row(
                  children: <Widget>[
                    Text(
                      '¥${_fmtPrice(product.sellprice)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: soldOut ? const Color(0xFFC9CDD4) : _kBrandRed,
                      ),
                    ),
                    Text(
                      '/${product.unit}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
                // 剩余库存（对齐 smdcapp: sellclearflag==1 且未售罄时显示）
                if (product.sellclearflag == 1 && !soldOut)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '剩余:${_fmtQty(product.stockqty)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFFF8800)),
                    ),
                  ),
              ],
            ),
          ),
          // 右侧操作区（对齐 smdcapp 按钮优先级：售罄 > 选规格 > 选套餐 > 加减）
          if (soldOut)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E6EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('已售罄', style: TextStyle(fontSize: 11, color: Color(0xFF999999))),
            )
          else if (product.hasSpec)
            GestureDetector(
              onTap: onSpec,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  '选规格',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            )
          else if (product.combflag == 1)
            GestureDetector(
              onTap: onComb,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  '选套餐',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            )
          else if (product.isTimePrice || product.isWeigh)
            GestureDetector(
              onTap: onTimePriceOrWeigh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  // 对齐 smdcapp：curflag==1 显示“选择”，weighflag==1 显示“选重量”
                  product.isTimePrice ? '选择' : '选重量',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            )
          else
            _buildQuantityControl(),
        ],
      ),
    );
  }

  /// 占位图（无图片时的渐变色块 + emoji）
  Widget _buildPlaceholder(bool soldOut) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: soldOut
              ? const <Color>[Color(0xFFECEFF1), Color(0xFFCFD8DC)]
              : const <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: soldOut ? 0.4 : 1,
          child: const Text('🍜', style: TextStyle(fontSize: 28)),
        ),
      ),
    );
  }

  /// 数量加减控件（精致小尺寸）
  /// 对齐 smdcapp: ENABLE_PRODUCT_NUM 控制是否显示数字角标
  Widget _buildQuantityControl() {
    if (count == 0) {
      return GestureDetector(
        onTap: onAdd,
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: _kBrandRed,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, size: 13, color: Colors.white),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GestureDetector(
          onTap: onRemove,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC9CDD4), width: 1.2),
            ),
            child: const Icon(Icons.remove, size: 11, color: Color(0xFF86909C)),
          ),
        ),
        // 对齐 smdcapp: showNum 控制是否显示数字角标
        if (showNum)
          SizedBox(
            width: 30,
            child: Center(
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1D2129),
                ),
              ),
            ),
          ),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: _kBrandRed,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, size: 13, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// 格式化价格显示（对齐 smdcapp PriceUtil.formatSmart）
/// 整数不带小数点，非整数保留有效小数位
String _fmtPrice(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

/// 格式化数量显示（对齐 smdcapp PriceUtil.formatQty）
String _fmtQty(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
