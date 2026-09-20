import 'dart:async';

/// 购物车本地事件总线（对齐 smdcapp EventBus.getDefault().post(...)）
///
/// 订单确认页等页面改动待下单购物车（删除菜品/整单打包/改服务员等）后
/// 通过 [fireCartChanged] 广播事件，点菜页订阅后立即刷新角标与合计金额。
class CartEventBus {
  CartEventBus._();

  static final StreamController<void> _controller =
      StreamController<void>.broadcast();

  /// 购物车变更事件流（点菜页订阅此流）
  static Stream<void> get onCartChanged => _controller.stream;

  /// 触发购物车变更事件（操作成功后调用）
  static void fireCartChanged() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }
}
