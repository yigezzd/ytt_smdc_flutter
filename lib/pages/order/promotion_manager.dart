import '../../db/dao/mp_master_dao.dart';
import '../../db/dao/mp_product_or_type_dao.dart';
import '../../db/dao/mp_rule_dao.dart';
import '../../db/entity/mp_master_entity.dart';
import '../../db/entity/mp_product_or_type_entity.dart';
import '../../db/entity/mp_rule_entity.dart';
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

/// 商品基础促销管理器（对齐 smdcapp PromotionManager）
///
/// 数据源：tabledown 同步的 t_mp_pt_master / t_mp_pt_product_or_type / t_mp_pt_rule。
/// 点菜加购、订单加载、订单确认页进入时调用 [applyToCartItem] 把分类折扣/菜品折扣/特价菜落到 CartItem。
class PromotionManager {
  PromotionManager._();

  static final PromotionManager instance = PromotionManager._();

  final List<BasicPromotion> _promotions = <BasicPromotion>[];
  bool _inited = false;

  bool get isEmpty => _promotions.isEmpty;

  /// 初始化基础促销（每次登录 / 跨天 / 切换会员后重新调用）
  ///
  /// [force] true 时强制重查本地促销表（订单确认页进入时调用，
  /// 保证促销数据变更后价格与标签能刷新，对齐 smdcapp 价格引擎重算口径）。
  Future<void> init({bool force = false}) async {
    if (_inited && !force) return;
    _promotions.clear();
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
      final List<MPMasterEntity> masters =
          await MPMasterDao.instance.queryActivePromotions(
        spid: spid,
        sid: sid,
        billtypeList: const <int>[1, 2, 3],
      );
      if (masters.isEmpty) {
        FileLogWriter.instance.writeToFile(
            '促销初始化: spid=$spid sid=$sid 无有效基础促销（主表为空）',
            tag: '促销');
        _inited = true;
        return;
      }

      final List<String> billids =
          masters.map((MPMasterEntity m) => m.billid).toList();
      final List<MpProductOrTypeEntity> details =
          await MpProductOrTypeDao.instance.byBillids(
        billids: billids,
        spid: spid,
        sid: sid,
      );
      final List<MpRuleEntity> rules = await MpRuleDao.instance.byBillids(
        billids: billids,
        spid: spid,
        sid: sid,
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
      _inited = true;
      FileLogWriter.instance.writeToFile(
          '促销初始化: 主表${masters.length}条 明细${details.length}条 规则${rules.length}条 '
          '→ 有效促销${_promotions.length}条 '
          '${_promotions.map((BasicPromotion p) => '${p.billid}/类型${p.billtype}/折${p.discount}/特价${p.price}/分类${p.typeid}/商品${p.productid}').join(' ')}',
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
    // 团购商品不参与基础促销
    if (item.douyinflag == 1) return false;

    final String typeid = item.typeid;
    final String productid = item.product.id;
    final double sellPrice = item.product.price;

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
}
