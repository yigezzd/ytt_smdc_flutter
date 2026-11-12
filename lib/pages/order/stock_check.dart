import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/pages/order/widgets/stock_check_dialog.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 库存校验行引用（套餐子行删除时只移除对应子项，主行被子行删空时整行移除）
class _StockRowRef {
  const _StockRowRef(this.item, [this.child]);

  final CartItem item;
  final ComboSelectedItem? child;
}

/// 下单前实时库存校验（对齐 smdcapp DishesHomeAct2.toCheckActivity →
/// OrderProcessor.postDown(checkStock=true) → OrderStockValidator）
///
/// 库存设置参数 OverStockPerSale：
/// - 1 允许出库，不提示：直接放行；
/// - 2 允许出库，提示：弹「库存不足-允许销售」，勾选行可删除/不参与本次下单；
/// - 3 不允许出库，并提示：弹「库存不足-不允许销售」，必须删除全部无库存菜品。
///
/// 返回 false 表示取消下单（含删除后无可下单商品）。
/// 删除购物车条目后回调 [onChanged]，由调用方刷新页面状态。
Future<bool> checkStockBeforeOrder(
  BuildContext context,
  List<CartItem> cart, {
  required VoidCallback onChanged,
}) async {
  final String overStock = ParamsSpUtils.getOverStockPerSale();
  if (overStock == '1') return true;

  final List<CartItem> pending = cart
      .where((CartItem c) => c.qtyValue > 0 && !c.isRefunded)
      .toList(growable: false);
  if (pending.isEmpty) return true;

  final Map<String, _StockRowRef> rowRefs = <String, _StockRowRef>{};
  final List<Map<String, dynamic>> details = <Map<String, dynamic>>[];
  for (int i = 0; i < pending.length; i++) {
    final CartItem item = pending[i];
    final String rowKey = 'row$i';
    rowRefs[rowKey] = _StockRowRef(item);
    details.add(<String, dynamic>{
      'id': 0,
      'productid': item.product.id,
      'productname': item.displayName,
      'qty': item.isWeigh ? item.weighNum : item.qtyValue,
      'specid': item.specid,
      'spec': item.specName,
      // 用 onlyid 承载行标识：服务端按 DetailListBean 反序列化，只原样回传 onlyid 等
      // 已知字段（自造字段会被丢弃），据此精确删除对应购物车行（对齐 smdcapp checkStock）
      'onlyid': rowKey,
    });
    if (!item.isCombo) continue;
    for (int j = 0; j < item.combItems.length; j++) {
      final ComboSelectedItem child = item.combItems[j];
      final String childKey = '${rowKey}_c$j';
      rowRefs[childKey] = _StockRowRef(item, child);
      details.add(<String, dynamic>{
        'id': 0,
        'productid': child.productid,
        'productname': child.productname,
        'qty': child.qty * item.qtyValue,
        'specid': child.specid,
        'spec': child.specname,
        'onlyid': childKey,
      });
    }
  }

  final List<Map<String, dynamic>>? errs =
      await OrderRepository.checkOrderStock(details);
  FileLogWriter.instance.writeToFile(
    '库存校验: 参数=$overStock 明细=${details.length} errlist=${errs?.length ?? -1}',
    tag: '下单',
  );
  // 接口失败不阻断下单（对齐 smdcapp fail-open）
  if (errs == null || errs.isEmpty || !context.mounted) return true;

  final List<StockCheckEntry> entries = <StockCheckEntry>[];
  final Set<String> seen = <String>{};
  for (final Map<String, dynamic> e in errs) {
    String key = e['onlyid']?.toString() ?? '';
    if (!rowRefs.containsKey(key)) {
      key = _matchRowKey(rowRefs, e);
      if (key.isEmpty) continue;
    }
    // 同一购物车行可能命中多原料，弹窗只展示一行
    if (!seen.add(key)) continue;
    entries.add(StockCheckEntry(
      key: key,
      name: e['productname']?.toString() ?? '',
      qty: _toDouble(e['qty']),
    ));
  }
  if (entries.isEmpty || !context.mounted) return true;

  final StockCheckResult? result = await StockCheckDialog.show(
    context,
    items: entries,
    allowSale: overStock != '3',
    onRemove: (List<StockCheckEntry> removed) {
      _removeRows(cart, rowRefs, removed);
      onChanged();
    },
  );
  if (result == null) return false;

  // 参数 3 必须删除全部无库存菜品后才能继续；参数 2 的删除已在弹窗内即时生效
  if (result.deleteAll) {
    _removeRows(cart, rowRefs, entries);
    onChanged();
  }

  if (cart.every((CartItem c) => c.qtyValue <= 0 || c.isRefunded)) {
    Toast.show('没有可下单的商品');
    return false;
  }
  return true;
}

/// 服务端未回传 onlyid 时，按商品+规格兜底匹配购物车行
String _matchRowKey(Map<String, _StockRowRef> rowRefs, Map<String, dynamic> err) {
  final String pid = err['productid']?.toString() ?? '';
  final String specid = err['specid']?.toString() ?? '';
  for (final MapEntry<String, _StockRowRef> entry in rowRefs.entries) {
    final _StockRowRef ref = entry.value;
    final String rowPid = ref.child?.productid ?? ref.item.product.id;
    final String rowSpecid = ref.child?.specid ?? ref.item.specid;
    if (rowPid == pid && rowSpecid == specid) return entry.key;
  }
  return '';
}

/// 删除库存不足行（套餐子行删除对应子项，主行直接移除整行）
void _removeRows(
  List<CartItem> cart,
  Map<String, _StockRowRef> rowRefs,
  List<StockCheckEntry> entries,
) {
  final List<_StockRowRef> refs = <_StockRowRef>[];
  for (final StockCheckEntry e in entries) {
    final _StockRowRef? ref = rowRefs[e.key];
    if (ref != null) refs.add(ref);
  }
  for (final _StockRowRef ref in refs) {
    final ComboSelectedItem? child = ref.child;
    if (child == null) {
      cart.remove(ref.item);
      continue;
    }
    ref.item.combItems.remove(child);
    if (ref.item.combItems.isEmpty) cart.remove(ref.item);
  }
}

double _toDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;
