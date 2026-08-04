/// RabbitMQ 服务实现（移动端：Android/iOS/Desktop）
///
/// 对齐 smdcapp RabbitMqUtil.java 的连接与消息处理逻辑。
/// 使用 dart_amqp 包实现 AMQP 0-9-1 协议通信。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_amqp/dart_amqp.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_deer/util/log_upload_utils.dart';

/// 桌台变更事件流控制器
final StreamController<int> _tableChangedController =
    StreamController<int>.broadcast();

/// 暴露给 MqService 的桌台变更流
Stream<int> get tableChangedStream => _tableChangedController.stream;

/// 锁台事件流控制器（对齐 smdcapp LockTableEvent）
final StreamController<Map<String, dynamic>> _lockTableController =
    StreamController<Map<String, dynamic>>.broadcast();

/// 锁台事件流（retcode 8/10/11 中的锁台/解锁消息）
Stream<Map<String, dynamic>> get lockTableStream => _lockTableController.stream;

/// 扫码点餐接单事件流（对齐 smdcapp retcode=9）
final StreamController<Map<String, dynamic>> _scanOrderController =
    StreamController<Map<String, dynamic>>.broadcast();

/// 扫码点餐接单事件流
Stream<Map<String, dynamic>> get scanOrderStream => _scanOrderController.stream;

/// 强制下线事件流（对齐 smdcapp retcode=6 数据清空/登录失效）
final StreamController<String> _forceLogoutController =
    StreamController<String>.broadcast();

/// 强制下线事件流
Stream<String> get forceLogoutStream => _forceLogoutController.stream;

/// 打印通知事件流（对齐 smdcapp retcode=66）
final StreamController<String> _printNoticeController =
    StreamController<String>.broadcast();

/// 打印通知事件流
Stream<String> get printNoticeStream => _printNoticeController.stream;

/// 叫号刷新事件流（对齐 smdcapp retcode=13）
final StreamController<void> _callNumberController =
    StreamController<void>.broadcast();

/// 叫号刷新事件流
Stream<void> get callNumberStream => _callNumberController.stream;

/// 连接状态
bool _connected = false;
bool get isConnected => _connected;

/// 当前连接与通道（用于断开）
Client? _client;
Channel? _channel;

/// 是否正在连接中（防止并发）
bool _connecting = false;

/// 重连定时器
Timer? _reconnectTimer;

/// 连接参数缓存（用于重连）
String _host = '';
int _port = 5672;
String _account = '';
String _storeCode = '';
String _machNo = '';

/// 连接 RabbitMQ（对齐 smdcapp RabbitMqUtil.Connect）
Future<void> connectMq({
  required String host,
  required int port,
  required String account,
  required String storeCode,
  required String machNo,
}) async {
  // 缓存参数用于重连
  _host = host;
  _port = port;
  _account = account;
  _storeCode = storeCode;
  _machNo = machNo;

  if (_connecting) {
    return;
  }
  _connecting = true;

  try {
    // 先断开旧连接
    await _closeConnection();

    debugPrint('[MqService] 正在连接 RabbitMQ: $host:$port, '
        'account=$_account, storeCode=$_storeCode, machNo=$_machNo');

    final ConnectionSettings settings = ConnectionSettings(
      host: host,
      port: port,
      authProvider: const PlainAuthenticator('byyzm', 'byyzm'),
      maxConnectionAttempts: 3,
      reconnectWaitTime: const Duration(seconds: 10),
    );

    _client = Client(settings: settings);
    await _client!.connect();
    _channel = await _client!.channel();
    debugPrint('[MqService] TCP连接成功，channel已建立');

    // 队列名：{account}-{storeCode}-{machNo}（对齐 smdcapp QUEUE_NAME）
    final String queueName = '$_account-$_storeCode-$_machNo';

    // 声明队列（non-durable, autoDelete，对齐 smdcapp queueDeclare）
    final Queue queue = await _channel!.queue(
      queueName,
      durable: false,
      autoDelete: true,
    );
    debugPrint('[MqService] 队列声明成功: $queueName');

    // 引用已存在的 topic exchange（对齐 smdcapp：不声明 exchange，仅绑定）
    // 服务端 "ytt" exchange 已存在，重新声明可能因 durable 不匹配导致 channel 关闭
    final Exchange exchange = await _channel!.exchange(
      'ytt',
      ExchangeType.TOPIC,
      declare: false,
    );

    // 绑定 routing keys（对齐 smdcapp 三级绑定）
    await queue.bind(exchange, 'ytt.$_account');
    await queue.bind(exchange, 'ytt.$_account.$_storeCode');
    await queue.bind(exchange, 'ytt.$_account.$_storeCode.$_machNo');

    debugPrint('[MqService] 已连接 RabbitMQ: $host:$port, queue=$queueName, '
        'routingKeys=[ytt.$_account, ytt.$_account.$_storeCode, ytt.$_account.$_storeCode.$_machNo]');
    _connected = true;

    // 消费消息（对齐 smdcapp basicConsume + msgHandler）
    final Consumer consumer = await queue.consume(noAck: false);
    consumer.listen((AmqpMessage message) {
      _handleMessage(message);
      // 手动确认（对齐 smdcapp basicAck）
      message.ack();
    });
  } catch (e) {
    debugPrint('[MqService] 连接失败: $e');
    _connected = false;
    // 10秒后重试（对齐 smdcapp setNetworkRecoveryInterval(10000)）
    _scheduleReconnect();
  } finally {
    _connecting = false;
  }
}

/// 处理收到的 MQ 消息（对齐 smdcapp RabbitMqUtil.msgHandler）
///
/// retcode 消息类型（对齐 smdcapp）：
/// 1=心跳, 5=上传日志, 6=数据清空/强制下线, 8/10/11=桌台变更,
/// 9=扫码点餐接单, 13=刷新叫号列表, 66=打印通知
void _handleMessage(AmqpMessage message) {
  try {
    final String body = message.payloadAsString;
    final Map<String, dynamic> json =
        jsonDecode(body) as Map<String, dynamic>;
    final int retcode = json['retcode'] as int? ?? 0;

    switch (retcode) {
      case 1:
        // 心跳数据，忽略
        break;
      case 5:
        // 上传日志（对齐 smdcapp RabbitMqUtil case 5 → JsonWriter.uploadLog）
        debugPrint('[MqService] 收到上传日志指令 retcode=5');
        // 异步执行日志压缩上传，不阻塞 MQ 消息处理（内部已捕获异常）
        LogUploadUtils.uploadLog().then((result) {
          debugPrint('[MqService] 日志上传结果: $result');
        });
        break;
      case 6:
        // 数据清空/强制下线（对齐 smdcapp AppStateManager.setLoginStatus）
        debugPrint('[MqService] 收到强制下线推送 retcode=6');
        if (!_forceLogoutController.isClosed) {
          _forceLogoutController.add('登录失效，请重新登录');
        }
        break;
      case 8:
      case 10:
      case 11:
        // 桌台变更（开台/锁台/清台/下单等）
        debugPrint('[MqService] 收到桌台变更推送 retcode=$retcode');
        _handleTableChange(json);
        break;
      case 9:
        // 扫码点餐接单（对齐 smdcapp sendMsg(handler, 9, msg)）
        debugPrint('[MqService] 收到扫码点餐接单推送 retcode=9');
        if (!_scanOrderController.isClosed) {
          _scanOrderController.add(json);
        }
        break;
      case 13:
        // 刷新叫号列表（对齐 smdcapp sendMsg(handler, 13, ...)）
        debugPrint('[MqService] 收到叫号刷新推送 retcode=13');
        if (!_callNumberController.isClosed) {
          _callNumberController.add(null);
        }
        break;
      case 66:
        // 打印通知（对齐 smdcapp printMsgNotice）
        final String data = json['data']?.toString() ?? '';
        debugPrint('[MqService] 收到打印通知推送 retcode=66');
        if (data.isNotEmpty && !_printNoticeController.isClosed) {
          _printNoticeController.add(data);
        }
        break;
      default:
        // 其它消息暂不处理
        debugPrint('[MqService] 未处理的消息码 retcode=$retcode');
        break;
    }
  } catch (e) {
    debugPrint('[MqService] 消息解析失败: $e');
  }
}

/// 处理桌台变更消息（对齐 smdcapp retcode 8/10/11 的锁台事件处理）
void _handleTableChange(Map<String, dynamic> json) {
  // 先通知桌台页刷新
  final int retcode = json['retcode'] as int? ?? 8;
  if (!_tableChangedController.isClosed) {
    _tableChangedController.add(retcode);
  }

  // 处理锁台/解锁事件（对齐 smdcapp LockTableEvent）
  try {
    final dynamic data = json['data'];
    if (data is Map<String, dynamic>) {
      final String lockflag = data['lockflag']?.toString() ?? '';
      final String autoflag = data['autoflag']?.toString() ?? '';
      final String machno = data['machno']?.toString() ?? '';
      final String saleid = data['saleid']?.toString() ?? '';
      final String opername = data['opername']?.toString() ?? '';

      // 只有包含锁台标志的消息才触发锁台事件
      if (lockflag.isNotEmpty && machno != _machNo) {
        if (!_lockTableController.isClosed) {
          _lockTableController.add(<String, dynamic>{
            'saleid': saleid,
            'opername': opername,
            'machno': machno,
            'lockflag': lockflag,
            'autoflag': autoflag,
          });
        }
      }
    }
  } catch (e) {
    debugPrint('[MqService] 锁台事件解析失败: $e');
  }
}

/// 调度重连
void _scheduleReconnect() {
  _reconnectTimer?.cancel();
  _reconnectTimer = Timer(const Duration(seconds: 10), () {
    if (!_connected && _account.isNotEmpty) {
      debugPrint('[MqService] 尝试重连 RabbitMQ...');
      connectMq(
        host: _host,
        port: _port,
        account: _account,
        storeCode: _storeCode,
        machNo: _machNo,
      );
    }
  });
}

/// 断开连接（对齐 smdcapp CloseRabbitMq）
void disconnectMq() {
  _reconnectTimer?.cancel();
  _reconnectTimer = null;
  _connected = false;
  _closeConnection();
  debugPrint('[MqService] 已断开 RabbitMQ 连接');
}

/// 关闭底层连接
Future<void> _closeConnection() async {
  try {
    await _channel?.close();
    await _client?.close();
  } catch (_) {
    // 忽略关闭异常
  }
  _channel = null;
  _client = null;
}
