import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sp_util/sp_util.dart';

import 'package:flutter_deer/res/constant.dart';

import 'mq_service_impl.dart' if (dart.library.js_interop) 'mq_service_stub.dart'
    as impl;

/// RabbitMQ 推送服务（对齐 smdcapp RabbitMqUtil + App.initMqTasks）
///
/// 登录成功后连接 RabbitMQ 服务器，监听桌台变更消息（retcode 8/10/11），
/// 通过 [onTableChanged] 流通知订阅者（桌台页）刷新数据。
///
/// 连接参数（对齐 smdcapp）：
/// - host: 登录响应 `rabbitaddress`（默认 ysp01.yun8609.net）
/// - port: 5672
/// - user/pass: byyzm/byyzm
/// - exchange: "ytt" (topic)
/// - queue: "{account}-{storeCode}-{machNo}" (autoDelete, non-durable)
/// - routing keys: "ytt.{account}", "ytt.{account}.{storeCode}", "ytt.{account}.{storeCode}.{machNo}"
class MqService {
  MqService._();

  static final MqService _instance = MqService._();
  static MqService get instance => _instance;

  /// 桌台变更事件流（retcode 8/10/11 时发射）
  Stream<int> get onTableChanged => impl.tableChangedStream;

  /// 锁台事件流（对齐 smdcapp LockTableEvent，retcode 8/10/11 中的锁台消息）
  Stream<Map<String, dynamic>> get onLockTable => impl.lockTableStream;

  /// 扫码点餐接单事件流（对齐 smdcapp retcode=9）
  Stream<Map<String, dynamic>> get onScanOrder => impl.scanOrderStream;

  /// 强制下线事件流（对齐 smdcapp retcode=6 数据清空/登录失效）
  Stream<String> get onForceLogout => impl.forceLogoutStream;

  /// 打印通知事件流（对齐 smdcapp retcode=66）
  Stream<String> get onPrintNotice => impl.printNoticeStream;

  /// 叫号刷新事件流（对齐 smdcapp retcode=13）
  Stream<void> get onCallNumberRefresh => impl.callNumberStream;

  /// 是否已连接
  bool get isConnected => impl.isConnected;

  /// 连接 RabbitMQ（登录成功后调用，对齐 smdcapp App.initMqTasks）
  ///
  /// Web 平台自动跳过（dart_amqp 依赖 dart:io），靠定时轮询兜底。
  Future<void> connect() async {
    if (kIsWeb) {
      debugPrint('[MqService] Web 平台不支持 RabbitMQ，跳过连接');
      return;
    }

    String host =
        SpUtil.getString(Constant.rabbitAddress) ?? 'ysp01.yun8609.net';
    int port = SpUtil.getInt(Constant.rabbitPort) ?? 5672;
    String account =
        SpUtil.getString(Constant.businessNumber) ?? '';
    String storeCode =
        SpUtil.getString(Constant.storeCode) ?? '0';
    String machNo = SpUtil.getString(Constant.machNo) ?? '';

    // 兆底：若单独字段未保存（旧登录会话），从完整登录数据中提取
    if (account.isEmpty || machNo.isEmpty) {
      try {
        final String raw = SpUtil.getString(Constant.allLoginData) ?? '';
        if (raw.isNotEmpty) {
          final Map<String, dynamic> data =
              json.decode(raw) as Map<String, dynamic>;
          host = data['rabbitaddress']?.toString() ?? host;
          port = int.tryParse(data['rabbitport']?.toString() ?? '') ?? port;
          if (account.isEmpty && data['store'] is Map) {
            account = (data['store'] as Map)['account']?.toString() ?? '';
            storeCode = (data['store'] as Map)['code']?.toString() ?? storeCode;
          }
          if (machNo.isEmpty && data['mach'] is Map) {
            machNo = (data['mach'] as Map)['code']?.toString() ?? '';
          }
        }
      } catch (e) {
        debugPrint('[MqService] 解析登录数据失败: $e');
      }
    }

    debugPrint('[MqService] connect() 配置: host=$host, port=$port, '
        'account=$account, storeCode=$storeCode, machNo=$machNo');

    if (account.isEmpty) {
      debugPrint('[MqService] 商户号为空，跳过 MQ 连接');
      return;
    }

    await impl.connectMq(
      host: host,
      port: port,
      account: account,
      storeCode: storeCode,
      machNo: machNo,
    );
  }

  /// 断开连接（退出登录时调用）
  void disconnect() {
    impl.disconnectMq();
  }
}
