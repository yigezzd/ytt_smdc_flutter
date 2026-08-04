import 'dart:async';

/// 桌台本地事件总线（对齐 smdcapp EventBus.getDefault().post(...)）
///
/// 当 App 内部执行桌台操作（开台、锁台、消台、清台、结算等）成功后，
/// 通过 [fireTableChanged] 广播事件，桌台页订阅后立即刷新数据，
/// 无需等待下一次定时轮询。
class TableEventBus {
  TableEventBus._();

  static final StreamController<void> _controller =
      StreamController<void>.broadcast();

  /// 桌台变更事件流（桌台页订阅此流）
  static Stream<void> get onTableChanged => _controller.stream;

  /// 触发桌台变更事件（操作成功后调用）
  static void fireTableChanged() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }
}
