import '../../util/file_log_writer.dart';
import 'order_models.dart';
import 'promotion_manager.dart';

/// 第N份促销计算（对齐 smdcapp NthDiscountCalculator 拆行模式）
///
/// 规则字段：
/// - discountForm：1=折扣(80=8折) 2=特价 3=减价
/// - sellNum：购买第几份享受优惠
/// - condition：1=购买相同商品 2=购买不同商品
/// - rule（condition=2）：1=价格降序分组优惠较低商品 2=价格降序从最低开始优惠
/// - billmaxnum：单笔订单最大享受次数（0=不限）
///
/// 流程：先合并还原该活动历史拆分行 → 按规则选出享受优惠的份 → 物理拆行
/// （普通价行 + 促销行 specpriceflag=7/cxmbillid），促销行单价写入 [CartItem.nthPrice]。
class NthDiscountManager {
  NthDiscountManager._();

  static final NthDiscountManager instance = NthDiscountManager._();

  /// 对购物车整体重算所有第N份促销，返回是否发生拆行变化
  ///
  /// [lockedByBill]：已下单的第N份促销份数（billid → 份数），用于整单上限扣减
  /// （对齐 smdcapp billmaxnum 计算时扣除已下单不可撤销行）。
  bool apply(
    List<CartItem> items, {
    Map<String, int> lockedByBill = const <String, int>{},
  }) =>
      applyToItems(
        items,
        PromotionManager.instance.nthPromotions,
        lockedByBill: lockedByBill,
      );

  /// 按指定活动列表重算（活动来源见 [PromotionManager.init]）
  bool applyToItems(
    List<CartItem> items,
    List<NthPromotion> masters, {
    Map<String, int> lockedByBill = const <String, int>{},
  }) {
    // 历史保存数据可能只带回 specpriceflag=7（无活动ID），先还原为普通行等待重算
    for (final CartItem item in items) {
      if (item.specpriceflag == 7 && item.cxmbillid.isEmpty) {
        item.resetNthPromo();
        PromotionManager.instance.applyToCartItem(item);
      }
    }
    if (masters.isEmpty) return false;
    bool changed = false;
    for (final NthPromotion master in masters) {
      if (_applyToMaster(master, items, lockedByBill[master.billid] ?? 0)) {
        changed = true;
      }
    }
    return changed;
  }

  bool _applyToMaster(NthPromotion master, List<CartItem> items, int lockedCount) {
    bool changed = false;
    final Set<CartItem> revoked = <CartItem>{};

    // 1. 合并还原该活动此前拆出的促销行（对齐 smdcapp mergeBack）
    final List<CartItem> promoRows = items
        .where((CartItem i) => i.isNthPromo && i.cxmbillid == master.billid)
        .toList();
    for (final CartItem promo in promoRows) {
      final CartItem? parent = _findParent(items, promo);
      if (parent != null) {
        parent.quantity += promo.quantity;
        parent.extraQty += promo.extraQty;
        items.remove(promo);
      } else {
        // 找不到正常行（例如整行都享受了优惠）：就地还原，由本轮重新分配
        promo.resetNthPromo();
        PromotionManager.instance.applyToCartItem(promo);
        revoked.add(promo);
      }
      changed = true;
    }

    // 2. 参与池（对齐 smdcapp poolItems 过滤）
    final List<CartItem> pool = items
        .where((CartItem i) =>
            master.productIds.contains(i.product.id) &&
            i.quantity > 0 &&
            !i.isGift &&
            i.douyinflag != 1 &&
            i.cxmbillid.isEmpty &&
            i.specpriceflag != 7 &&
            !i.isRefunded &&
            // 称重菜按重量计价、时价/改价行已有手工价，不参与份数促销
            !i.isWeigh &&
            i.customPrice == null)
        .toList();
    if (pool.isEmpty) return changed;

    // 3. 按整数份展开
    final List<_NthUnit> units = <_NthUnit>[];
    for (final CartItem item in pool) {
      for (int i = 0; i < item.quantity; i++) {
        units.add(_NthUnit(price: item.product.price, item: item));
      }
    }
    if (units.isEmpty) return changed;

    // 4. 选出享受优惠的份
    List<_NthUnit> candidates;
    switch (master.condition) {
      case 1:
        candidates = _sameProduct(units, master.sellNum);
        break;
      case 2:
        candidates = _differentProduct(units, master.sellNum, master.rule);
        break;
      default:
        candidates = const <_NthUnit>[];
    }

    // 5. 仅保留优惠后确实更便宜的份（避免出现“促”标但不降价的拆分行）
    final List<_NthUnit> beneficial = <_NthUnit>[];
    for (final _NthUnit unit in candidates) {
      final double promoUnitPrice =
          master.priceFor(unit.item.baseUnitPrice) + unit.item.unitCookExtra;
      if (promoUnitPrice < unit.item.discountedUnitPrice - 0.005) {
        beneficial.add(unit);
      }
    }
    if (beneficial.isEmpty) return changed;

    // 6. 单笔订单最大享受次数：扣除已下单已占用份数，相同商品规则下优先保住上一轮已优惠的份
    final List<_NthUnit> prioritized = master.condition == 1
        ? _stableSort(beneficial, (_NthUnit u) => revoked.contains(u.item) ? 1 : 0)
        : beneficial;
    final List<_NthUnit> applied;
    if (master.billmaxnum > 0) {
      final int remaining = master.billmaxnum - lockedCount;
      applied = remaining <= 0
          ? const <_NthUnit>[]
          : prioritized.take(remaining).toList();
    } else {
      applied = prioritized;
    }
    if (applied.isEmpty) return changed;

    // 7. 统计每个原始行需要拆出的优惠份数并执行拆行
    final Map<CartItem, int> counts = <CartItem, int>{};
    for (final _NthUnit unit in applied) {
      counts[unit.item] = (counts[unit.item] ?? 0) + 1;
    }
    counts.forEach((CartItem source, int count) {
      final int qty = count > source.quantity ? source.quantity : count;
      if (qty <= 0) return;
      final double promoUnitPrice = master.priceFor(source.baseUnitPrice);
      if (qty >= source.quantity && source.extraQty <= 0) {
        // 整行转为促销行，保留原行位置
        source.markNthPromo(
          billid: master.billid,
          promoUnitPrice: promoUnitPrice,
        );
      } else {
        final CartItem promo = source.copyAsNthPromo(
          billid: master.billid,
          promoUnitPrice: promoUnitPrice,
          qty: qty,
        );
        source.quantity -= qty;
        items.add(promo);
      }
      changed = true;
    });
    FileLogWriter.instance.writeToFile(
        '第N份促销: ${master.name} 活动${master.billid} 第${master.sellNum}份 '
        '形式${master.discountForm} 值${master.dis} 条件${master.condition} '
        '上限${master.billmaxnum} 候选${candidates.length} 实际${applied.length}',
        tag: '促销');
    return changed;
  }

  /// 合并还原时寻找拆分行对应的正常行（对齐 smdcapp：商品+规格+做法+价格一致）
  CartItem? _findParent(List<CartItem> items, CartItem promo) {
    for (final CartItem candidate in items) {
      if (identical(candidate, promo)) continue;
      if (candidate.isNthPromo) continue;
      if (candidate.product.id == promo.product.id &&
          candidate.specText == promo.specText &&
          candidate.customPrice == promo.customPrice &&
          candidate.isGift == promo.isGift) {
        return candidate;
      }
    }
    return null;
  }

  /// condition=1：同商品按 productid+规格分组，组内每 N 份取价格最低的一份优惠
  List<_NthUnit> _sameProduct(List<_NthUnit> units, int n) {
    final List<_NthUnit> result = <_NthUnit>[];
    final Map<String, List<_NthUnit>> groups = <String, List<_NthUnit>>{};
    for (final _NthUnit unit in units) {
      final String key = '${unit.item.product.id}_${unit.item.specName}';
      groups.putIfAbsent(key, () => <_NthUnit>[]).add(unit);
    }
    for (final List<_NthUnit> group in groups.values) {
      final List<_NthUnit> sorted = List<_NthUnit>.from(group)
        ..sort((_NthUnit a, _NthUnit b) {
          final int byPrice = b.price.compareTo(a.price);
          if (byPrice != 0) return byPrice;
          return b.item.specpriceflag.compareTo(a.item.specpriceflag);
        });
      for (int i = 0; i + n <= sorted.length; i += n) {
        result.add(sorted[i + n - 1]);
      }
    }
    return result;
  }

  /// condition=2：不同商品混合计算
  List<_NthUnit> _differentProduct(List<_NthUnit> units, int n, int rule) {
    final List<_NthUnit> result = <_NthUnit>[];
    if (rule == 1) {
      // 价格降序分组，每组最低价享受优惠
      final List<_NthUnit> sorted = List<_NthUnit>.from(units)
        ..sort((_NthUnit a, _NthUnit b) {
          final int byPrice = b.price.compareTo(a.price);
          if (byPrice != 0) return byPrice;
          return b.item.specpriceflag.compareTo(a.item.specpriceflag);
        });
      for (int i = 0; i + n <= sorted.length; i += n) {
        result.add(sorted[i + n - 1]);
      }
    } else if (rule == 2) {
      // 价格降序排序后从最低价开始优惠（数量 = 总份数 / N）
      final List<_NthUnit> sorted = List<_NthUnit>.from(units)
        ..sort((_NthUnit a, _NthUnit b) {
          final int byPrice = b.price.compareTo(a.price);
          if (byPrice != 0) return byPrice;
          return a.item.specpriceflag.compareTo(b.item.specpriceflag);
        });
      final int count = units.length ~/ n;
      if (count > 0) {
        result.addAll(sorted.sublist(sorted.length - count).reversed);
      }
    } else {
      FileLogWriter.instance.writeToFile(
          '第N份促销: 未知规则 rule=$rule', tag: '促销');
    }
    return result;
  }

  /// 稳定排序：按 [keyOf] 降序，保留原有相对顺序
  List<_NthUnit> _stableSort(List<_NthUnit> list, int Function(_NthUnit) keyOf) {
    final List<MapEntry<int, _NthUnit>> indexed =
        list.asMap().entries.toList(growable: false);
    indexed.sort((MapEntry<int, _NthUnit> a, MapEntry<int, _NthUnit> b) {
      final int byKey = keyOf(b.value).compareTo(keyOf(a.value));
      return byKey != 0 ? byKey : a.key.compareTo(b.key);
    });
    return indexed.map((MapEntry<int, _NthUnit> e) => e.value).toList();
  }
}

/// 展开后的单品份（对齐 smdcapp UnitItem）
class _NthUnit {
  const _NthUnit({required this.price, required this.item});

  final double price;
  final CartItem item;
}
