import 'package:flutter/foundation.dart';

import '../../db/dao/mp_master_dao.dart';
import '../../db/dao/mp_product_or_type_dao.dart';
import '../../db/dao/mp_rule_dao.dart';
import '../../db/entity/db_table_name.dart';
import '../../db/entity/mp_master_entity.dart';
import '../../db/entity/mp_product_or_type_entity.dart';
import '../../db/entity/mp_rule_entity.dart';
import '../../net/table_download_manager.dart';
import '../../util/file_log_writer.dart';
import '../../util/user_helper.dart';
import 'order_models.dart';

/// 基础促销（对齐 smdcapp PromotionManager.checkPromotion123）
///
/// 单据类型：1=分类折扣、2=菜品折扣、3=特价菜；
/// 4/5/6/7/8 属于场景促销（买赠/满量/满减/满赠/满折），此处不处理。
class BasicPromotion {
  const BasicPromotion({
    required this.billid,
    required this.billtype,
    required this.discount,
    required this.price,
    required this.typeid,
    required this.productid,
    required this.specid,
  });

  final String billid;
  final int billtype;

  /// 折扣（100=不打折）
  final double discount;

  /// 特价（billtype==3 时生效）
  final double price;

  final String typeid;
  final String productid;
  final String specid;

  /// 应用后的单价（对齐 smdcapp: 1/2 按折扣算，3 直接取特价）
  double priceFor(double sellPrice) =>
      billtype == 3 ? price : sellPrice * discount / 100;
}

/// 第N份促销（billtype=10，对齐 smdcapp NthDiscountCalculator 使用的 MPMaster 字段）
class NthPromotion {
  const NthPromotion({
    required this.billid,
    required this.name,
    required this.discountForm,
    required this.sellNum,
    required this.dis,
    required this.condition,
    required this.rule,
    required this.billmaxnum,
    required this.productIds,
  });

  final String billid;
  final String name;

  /// 优惠形式：1=折扣（80=8折）2=特价 3=减价
  final int discountForm;

  /// 每 N 份
  final int sellNum;

  /// 优惠值（对应 [discountForm]）
  final double dis;

  /// 门槛条件：1=购买相同商品 2=购买不同商品
  final int condition;

  /// condition=2 生效：1=价格降序分组优惠较低商品 2=价格降序从最低开始优惠
  final int rule;

  /// 单笔订单最大享受次数（0=不限）
  final int billmaxnum;

  /// 参与商品ID集合
  final Set<String> productIds;

  /// 对齐 smdcapp calculateDiscountedPrice：减价兜底不低于 0
  double priceFor(double sellPrice) {
    switch (discountForm) {
      case 1:
        return sellPrice * dis / 100;
      case 2:
        return dis;
      case 3:
        final double price = sellPrice - dis;
        return price < 0 ? 0 : price;
      default:
        return sellPrice;
    }
  }
}

/// 商品基础促销管理器（对齐 smdcapp PromotionManager）
///
/// 数据源：tabledown 同步的 t_mp_pt_master / t_mp_pt_product_or_type / t_mp_pt_rule。
/// 点菜加购、订单加载、订单确认页进入时调用 [applyToCartItem] 把分类折扣/菜品折扣/特价菜落到 CartItem。
class PromotionManager {
  PromotionManager._();

  static final PromotionManager instance = PromotionManager._();

  /// 基础促销依赖的本地表（Web 缓存缺失时按需同步）
  static const List<String> _promotionTables = <String>[
    DbTableName.tMpPtMaster,
    DbTableName.tMpPtNodate,
    DbTableName.tMpPtProductOrType,
    DbTableName.tMpPtRule,
    DbTableName.tMpPtTime,
    DbTableName.tMpStore,
    DbTableName.tMpStoreType,
    DbTableName.tMpPtVipType,
  ];

  final List<BasicPromotion> _promotions = <BasicPromotion>[];
  final List<NthPromotion> _nthPromotions = <NthPromotion>[];
  bool _inited = false;

  /// Web 促销表已尝试过按需同步（避免无活动时每次初始化都重复下载）
  bool _webPromoSynced = false;

  bool get isEmpty => _promotions.isEmpty;

  /// 第N份促销（billtype=10），随 [init] 一起加载
  List<NthPromotion> get nthPromotions => _nthPromotions;

  /// 初始化基础促销（每次登录 / 跨天 / 切换会员后重新调用）
  ///
  /// [force] true 时强制重查本地促销表（订单确认页进入时调用，
  /// 保证促销数据变更后价格与标签能刷新，对齐 smdcapp 价格引擎重算口径）。
  Future<void> init({bool force = false}) async {
    if (_inited && !force) return;
    _promotions.clear();
    _nthPromotions.clear();
    _inited = false;
    try {
      // spid/sid 优先取独立键（登录写入 int），缺失时回退门店 JSON
      // （避免 SP 键类型/写入不一致导致促销整体不生效）
      int spid = UserHelper.getSpid();
      if (spid == 0) spid = int.tryParse(UserHelper.getSpidStr()) ?? 0;
      int sid = UserHelper.getSid();
      if (sid == 0) sid = int.tryParse(UserHelper.getSidStr()) ?? 0;
      if (spid == 0) {
        FileLogWriter.instance
            .writeToFile('促销初始化跳过: spid=0（登录信息未就绪）', tag: '促销');
        return;
      }
      // Web 端 tabledown 只缓存在内存（刷新/热重启即清空），缓存缺失时
      // 按需全量拉取促销表，否则基础促销会静默为空（Android/iOS 有 SQLite 不受影响）
      if (kIsWeb && !_webPromoSynced) {
        final List<Map<String, dynamic>> cached =
            await TableDownloadManager.readTableData(DbTableName.tMpPtMaster);
        if (cached.isEmpty) {
          FileLogWriter.instance
              .writeToFile('促销初始化: Web 缓存为空，开始同步促销表', tag: '促销');
          await TableDownloadManager.downTableFlow(
            isFullUpdate: true,
            targetTables: _promotionTables,
          );
        }
        _webPromoSynced = true;
      }
      final List<MPMasterEntity> masters =
          await MPMasterDao.instance.queryActivePromotions(
        spid: spid,
        sid: sid,
        billtypeList: const <int>[1, 2, 3, 10],
      );
      if (masters.isEmpty) {
        FileLogWriter.instance.writeToFile(
            '促销初始化: spid=$spid sid=$sid 无有效基础促销（主表为空）',
            tag: '促销');
        // Web 同步失败/为空时保留未初始化状态，后续调用可重试查询
        if (!kIsWeb) _inited = true;
        return;
      }

      final List<String> billids =
          masters.map((MPMasterEntity m) => m.billid).toList();
      // 明细/规则的 sid 是活动创建门店，跨店适用时与当前门店不同；
      // 适用门店已由主表查询的 t_mp_store 关联把关，这里不能再按 sid 过滤
      final List<MpProductOrTypeEntity> details =
          await MpProductOrTypeDao.instance.byBillids(
        billids: billids,
        spid: spid,
      );
      final List<MpRuleEntity> rules = await MpRuleDao.instance.byBillids(
        billids: billids,
        spid: spid,
      );

      final Map<String, int> typeByBill = <String, int>{};
      for (final MPMasterEntity m in masters) {
        typeByBill[m.billid] = m.billtype;
      }
      // 菜品折扣（billtype=2）的折扣取自规则表最小值（对齐 initMpMaster）
      final Map<String, double> ruleDiscountByBill = <String, double>{};
      for (final MpRuleEntity r in rules) {
        if (r.discount <= 0) continue;
        final double? cur = ruleDiscountByBill[r.billid];
        if (cur == null || r.discount < cur) {
          ruleDiscountByBill[r.billid] = r.discount;
        }
      }

      for (final MpProductOrTypeEntity d in details) {
        // saletype=2 为赠送商品，不参与折扣计算
        if (d.saletype == '2') continue;
        final int billtype = typeByBill[d.billid] ?? 0;
        // 第N份促销单独走 NthDiscountManager，不混入基础促销
        if (billtype == 10) continue;
        double discount = d.discount;
        if (billtype == 2) {
          discount = ruleDiscountByBill[d.billid] ?? 0;
        }
        _promotions.add(BasicPromotion(
          billid: d.billid,
          billtype: billtype,
          discount: discount == 0 ? 100 : discount,
          price: d.price,
          typeid: d.typeid,
          productid: d.productid,
          specid: d.specid,
        ));
      }
      // 第N份促销（billtype=10）：参与商品取自促销明细的 productid
      // （对齐 smdcapp applyNthDiscount：ids = master.mpProOrType.mapNotNull { productid }）
      for (final MPMasterEntity m in masters) {
        if (m.billtype != 10) continue;
        final int sellNum = m.nSellnum.toInt();
        if (sellNum <= 1 || m.nDiscountform <= 0) continue;
        final Set<String> ids = <String>{
          for (final MpProductOrTypeEntity d in details)
            if (d.billid == m.billid && d.productid.isNotEmpty) d.productid,
        };
        if (ids.isEmpty) continue;
        _nthPromotions.add(NthPromotion(
          billid: m.billid,
          name: m.name,
          discountForm: m.nDiscountform,
          sellNum: sellNum,
          dis: m.nDis,
          condition: m.nCondition,
          rule: m.nRule,
          billmaxnum: m.billmaxnum,
          productIds: ids,
        ));
      }
      _inited = true;
      FileLogWriter.instance.writeToFile(
          '促销初始化: 主表${masters.length}条 明细${details.length}条 规则${rules.length}条 '
          '→ 有效促销${_promotions.length}条 第N份${_nthPromotions.length}条 '
          '${_promotions.map((BasicPromotion p) => '${p.billid}/类型${p.billtype}/折${p.discount}/特价${p.price}/分类${p.typeid}/商品${p.productid}').join(' ')} '
          '${_nthPromotions.map((NthPromotion p) => '${p.billid}/第${p.sellNum}份/形式${p.discountForm}/值${p.dis}/条件${p.condition}/规则${p.rule}/上限${p.billmaxnum}/商品${p.productIds.length}个').join(' ')}',
          tag: '促销');
    } catch (e) {
      // 促销表缺失或查询异常时静默降级为无促销（记录日志便于现场排查）
      FileLogWriter.instance.writeToFile('促销初始化失败: $e', tag: '促销');
    }
  }

  /// 为购物车条目套用最优基础促销（对齐 checkPromotion123）
  ///
  /// 命中则写入 discount / jcmbillid / specpriceflag；未命中不改变原值。
  /// 返回是否命中。
  bool applyToCartItem(CartItem item) {
    if (!_inited || _promotions.isEmpty) return false;
    // 第N份促销行价格由第N份引擎单独计算，叠加基础促销会重复优惠
    if (item.specpriceflag == 7) return false;
    // 团购商品不参与基础促销
    if (item.douyinflag == 1) return false;

    final String typeid = item.typeid;
    final String productid = item.product.id;
    final double sellPrice = item.product.price - item.unitCookExtra;

    BasicPromotion? best;
    double bestPrice = sellPrice;
    bool matched = false;
    bool specRestricted = false;
    for (final BasicPromotion p in _promotions) {
      // 分类匹配（对齐 smdcapp checkPromotion123）：
      //   促销分类 == 商品分类，或二者存在分类层级包含关系（typeid 前缀）
      final bool typeHit = p.typeid.isNotEmpty &&
          typeid.isNotEmpty &&
          (typeid == p.typeid ||
              typeid.startsWith(p.typeid) ||
              p.typeid.startsWith(typeid));
      // 商品匹配：productid 相同（对齐 smdcapp：促销未限定规格时直接命中）
      final bool productIdHit = p.productid.isNotEmpty && productid == p.productid;
      if (productIdHit && p.specid.isNotEmpty) {
        // 客户端购物车未记录规格ID，促销限定规格时无法比对，跳过并记录
        specRestricted = true;
        continue;
      }
      if (!typeHit && !productIdHit) continue;
      matched = true;
      final double price = p.priceFor(sellPrice);
      if (price < bestPrice) {
        bestPrice = price;
        best = p;
      }
    }
    if (best == null) {
      if (matched) {
        FileLogWriter.instance.writeToFile(
            '促销未采用: ${item.product.name} 促销价不低于原价（原价$sellPrice）', tag: '促销');
      } else if (specRestricted) {
        FileLogWriter.instance.writeToFile(
            '促销未采用: ${item.product.name} 促销限定了规格(specid)，客户端无法比对', tag: '促销');
      }
      return false;
    }

    if (best.billtype == 3) {
      // 特价菜：不受 dscflag 限制
      item.discount = 100;
      item.specpriceflag = 3;
      item.jcmbillid = best.billid;
      item.promoPrice = best.price;
      FileLogWriter.instance.writeToFile(
          '促销命中(特价菜): ${item.product.name} ${sellPrice}→${best.price} 活动${best.billid}',
          tag: '促销');
      return true;
    }
    // 分类/菜品折扣：不可打折商品跳过
    if (item.product.dscflag != 1) {
      FileLogWriter.instance.writeToFile(
          '促销跳过: ${item.product.name} 商品不可打折（dscflag=0）活动${best.billid}', tag: '促销');
      return false;
    }
    item.discount = best.discount;
    item.specpriceflag = best.billtype;
    item.jcmbillid = best.billid;
    item.promoPrice = 0;
    FileLogWriter.instance.writeToFile(
        '促销命中(${best.billtype == 1 ? '分类折扣' : '菜品折扣'}): ${item.product.name} '
        '${sellPrice}→${bestPrice} 折扣${best.discount} 活动${best.billid}',
        tag: '促销');
    return true;
  }

  /// 批量重新校验（订单确认页进入时调用，对齐 smdcapp 价格引擎对全单重算促销）
  ///
  /// 返回命中条数。
  int revalidateAll(List<CartItem> items) {
    int hit = 0;
    for (final CartItem item in items) {
      if (applyToCartItem(item)) hit++;
    }
    return hit;
  }

  /// 为已下单明细补套基础促销（对齐 smdcapp 价格引擎对全单重跑 checkPromotion123）
  ///
  /// 仅处理「当前没有任何优惠」的普通行；暂结/赠送/退菜/团购/套餐子行、
  /// 已有基础促销(1/2/3/6/7)、手工折扣(4)、会员价(5) 一律跳过，
  /// 避免覆盖服务端已定价结果或重复叠加。
  ///
  /// 命中后写入 discount / specpriceflag / jcmbillid / promoprice，返回是否命中。
  bool applyToOrderedDetail(Map<String, dynamic> row) {
    if (!_inited || _promotions.isEmpty) return false;
    if ((row['fornowid']?.toString() ?? '').isNotEmpty) return false;
    final int presentflag = _asInt(row['presentflag']);
    if (presentflag == 1 || presentflag == 2) return false;
    if (_asInt(row['douyinflag']) == 1) return false;
    // 套餐子行挂主行定价，不单独套促销
    if ((row['combproductid']?.toString() ?? '').isNotEmpty &&
        (row['combid']?.toString() ?? '').isNotEmpty) {
      return false;
    }
    final int specpriceflag = _asInt(row['specpriceflag']);
    if (const <int>[1, 2, 3, 4, 5, 6, 7].contains(specpriceflag)) return false;
    if ((row['jcmbillid']?.toString() ?? '').isNotEmpty) return false;
    // 已存在折扣（手工折扣/会员价未带 specpriceflag 的情况）
    final double discount = _asDouble(row['discount']);
    if (discount > 0 && discount < 100) return false;

    final double sellPrice = _asDouble(row['sellprice']);
    if (sellPrice <= 0) return false;
    final double serverRr = _asDouble(row['rrprice']);
    final double currentPrice =
        serverRr > 0 && serverRr < sellPrice ? serverRr : sellPrice;
    final String productid = row['productid']?.toString() ?? '';
    final String typeid = row['typeid']?.toString() ?? '';
    final String specid = row['specid']?.toString() ?? '';
    final bool canDiscount = _asInt(row['dscflag']) == 1;

    BasicPromotion? best;
    double bestPrice = currentPrice;
    for (final BasicPromotion p in _promotions) {
      // 分类匹配：分类相同或存在层级前缀关系（对齐 applyToCartItem）
      final bool typeHit = p.typeid.isNotEmpty &&
          typeid.isNotEmpty &&
          (typeid == p.typeid ||
              typeid.startsWith(p.typeid) ||
              p.typeid.startsWith(typeid));
      // 商品匹配：已下单明细带 specid，可精确比对规格
      final bool productHit = p.productid.isNotEmpty &&
          productid == p.productid &&
          (p.specid.isEmpty || p.specid == specid);
      if (!typeHit && !productHit) continue;
      // 分类/菜品折扣受商品是否可打折限制；特价菜不受限
      if (p.billtype != 3 && !canDiscount) continue;
      final double price = p.priceFor(sellPrice);
      if (price < bestPrice) {
        bestPrice = price;
        best = p;
      }
    }
    if (best == null) return false;

    if (best.billtype == 3) {
      row['discount'] = 100;
      row['specpriceflag'] = 3;
      row['jcmbillid'] = best.billid;
      row['promoprice'] = best.price;
      row['rrprice'] = best.price;
    } else {
      row['discount'] = best.discount;
      row['specpriceflag'] = best.billtype;
      row['jcmbillid'] = best.billid;
      row['promoprice'] = 0;
      row['rrprice'] = bestPrice;
    }
    FileLogWriter.instance.writeToFile(
        '已下单明细补套促销(${best.billtype == 3 ? '特价菜' : best.billtype == 2 ? '菜品折扣' : '分类折扣'}): '
        '${row['productname']} ${sellPrice}→$bestPrice 活动${best.billid}',
        tag: '促销');
    return true;
  }

  /// 批量补套已下单明细，返回命中条数
  int applyToOrderedDetails(List<Map<String, dynamic>> rows) {
    int hit = 0;
    for (final Map<String, dynamic> row in rows) {
      if (applyToOrderedDetail(row)) hit++;
    }
    return hit;
  }

  static int _asInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
}
