/// RabbitMQ 服务桩实现（Web 平台）
///
/// Web 端不支持 dart_amqp（依赖 dart:io），提供空实现。
/// 桌台状态更新靠定时轮询兜底。
library;

import 'dart:async';

/// 空流（Web 端无 MQ 推送）
final StreamController<int> _tableChangedController =
    StreamController<int>.broadcast();

/// 暴露给 MqService 的桌台变更流（Web 端永远不会有事件）
Stream<int> get tableChangedStream => _tableChangedController.stream;

/// 锁台事件流（Web 端永远不会有事件）
final StreamController<Map<String, dynamic>> _lockTableController =
    StreamController<Map<String, dynamic>>.broadcast();

Stream<Map<String, dynamic>> get lockTableStream =>
    _lockTableController.stream;

/// 扫码点餐接单事件流（Web 端永远不会有事件）
final StreamController<Map<String, dynamic>> _scanOrderController =
    StreamController<Map<String, dynamic>>.broadcast();

Stream<Map<String, dynamic>> get scanOrderStream =>
    _scanOrderController.stream;

/// 强制下线事件流（Web 端永远不会有事件）
final StreamController<String> _forceLogoutController =
    StreamController<String>.broadcast();

Stream<String> get forceLogoutStream => _forceLogoutController.stream;

/// 打印通知事件流（Web 端永远不会有事件）
final StreamController<String> _printNoticeController =
    StreamController<String>.broadcast();

Stream<String> get printNoticeStream => _printNoticeController.stream;

/// 叫号刷新事件流（Web 端永远不会有事件）
final StreamController<void> _callNumberController =
    StreamController<void>.broadcast();

Stream<void> get callNumberStream => _callNumberController.stream;

/// Web 端始终未连接
bool get isConnected => false;

/// Web 端连接为空操作
Future<void> connectMq({
  required String host,
  required int port,
  required String account,
  required String storeCode,
  required String machNo,
}) async {
  // Web 平台不支持 RabbitMQ，静默跳过
}

/// Web 端断开为空操作
void disconnectMq() {
  // no-op
}
