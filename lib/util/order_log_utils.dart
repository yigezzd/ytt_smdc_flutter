import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';

/// 敏感操作日志工具（对齐 smdcapp RecordsOrderLogModel + OrderLog）
///
/// 功能：
/// 1. 记录桌台敏感操作（开台、消台、退菜、打折等）到本地 JSON 文件
/// 2. 批量上传到云服务接口 POST /YttSvr/app/salelog/setLog
/// 3. 上传成功后清除本地已上传记录
///
/// 本地存储路径：{appDocDir}/order_logs/pending_logs.json
class OrderLogUtils {
  OrderLogUtils._();

  static final OrderLogUtils instance = OrderLogUtils._();

  /// 本地待上传日志缓存
  List<Map<String, dynamic>> _pendingLogs = [];

  /// 文件路径缓存
  String? _filePath;

  bool _initialized = false;

  // ─────────────── 初始化 ───────────────

  /// 初始化（在 main.dart 或登录成功后调用）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Web 平台无文件系统，跳过本地日志初始化
    if (kIsWeb) return;

    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/order_logs');
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    _filePath = '${logDir.path}/pending_logs.json';

    // 加载本地未上传的日志
    _loadFromDisk();
  }

  // ─────────────── 记录日志 ───────────────

  /// 记录敏感操作日志（对齐 smdcapp RecordsOrderLogModel.saveOrderLog）
  ///
  /// [saleid] 单据ID
  /// [memo] 操作描述（如 "开台"、"退菜:宫保鸡丁x1"）
  /// [billno] 订单号（可选）
  /// [isUpload] 是否立即上传（默认 false，批量上传）
  Future<void> saveOrderLog({
    required String saleid,
    required String memo,
    String billno = '',
    bool isUpload = false,
  }) async {
    if (!_initialized) await init();

    // 从 SP 读取公共字段（对齐 smdcapp SpUtils）
    String spid = '';
    String sid = '';
    try {
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = json.decode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '';
        spid = storeMap['spid']?.toString() ?? '';
      }
    } catch (_) {}

    String operid = '';
    String opername = '';
    try {
      final userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final userMap = json.decode(userStr) as Map<String, dynamic>;
        operid = userMap['userid']?.toString() ?? '';
        opername = userMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    final log = <String, dynamic>{
      'spid': int.tryParse(spid) ?? 0,
      'sid': int.tryParse(sid) ?? 0,
      'saleid': saleid,
      'billno': billno,
      'memo': memo,
      'operid': operid,
      'opername': opername,
      'client': 'APP',
      'machno': SpUtil.getString(Constant.machNo) ?? '',
      'opertime': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      'createtime': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
    };

    // 写入运行日志（对齐 smdcapp JsonWriter.writeToFile 敏感操作日志）
    FileLogWriter.instance.writeToFile(log, tag: '敏感操作日志');

    // 添加到待上传列表
    _pendingLogs.add(log);
    _saveToDisk();

    // 立即上传
    if (isUpload) {
      await uploadLog(saleid: saleid);
    }
  }

  // ─────────────── 上传日志 ───────────────

  /// 上传敏感操作日志到云服务（对齐 smdcapp RecordsOrderLogModel.uplodLog）
  ///
  /// [saleid] 指定上传某个 saleid 的日志，为空则上传全部
  Future<void> uploadLog({String saleid = ''}) async {
    if (!_initialized) await init();

    // 筛选待上传的日志
    final List<Map<String, dynamic>> toUpload;
    if (saleid.isEmpty) {
      toUpload = List.from(_pendingLogs);
    } else {
      toUpload = _pendingLogs.where((l) => l['saleid'] == saleid).toList();
    }

    if (toUpload.isEmpty) return;

    try {
      // POST /YttSvr/app/salelog/setLog，参数 data = JSON数组字符串
      final dataJson = json.encode(toUpload);
      final result = await request(
        HttpApi.saleLogSetLog,
        null,
        false,
        false,
        dataJson,
      );

      final retcode = result['retcode'];
      if (retcode == 0) {
        // 上传成功，删除本地已上传记录（对齐 smdcapp deleteAll / deleteBySaleid）
        if (saleid.isEmpty) {
          _pendingLogs.clear();
        } else {
          _pendingLogs.removeWhere((l) => l['saleid'] == saleid);
        }
        _saveToDisk();
        FileLogWriter.instance
            .writeToFile('敏感操作日志上传成功，数量: ${toUpload.length}', tag: '日志上传');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('OrderLogUtils uploadLog error: $e');
      }
      FileLogWriter.instance.writeToFile('敏感操作日志上传失败: $e', tag: '日志上传');
    }
  }

  /// 获取待上传日志数量
  int get pendingCount => _pendingLogs.length;

  // ─────────────── 本地持久化 ───────────────

  void _loadFromDisk() {
    try {
      if (kIsWeb || _filePath == null) return;
      final file = File(_filePath!);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.isNotEmpty) {
          final list = json.decode(content) as List<dynamic>;
          _pendingLogs =
              list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {
      _pendingLogs = [];
    }
  }

  void _saveToDisk() {
    try {
      if (kIsWeb || _filePath == null) return;
      final file = File(_filePath!);
      file.writeAsStringSync(json.encode(_pendingLogs));
    } catch (_) {}
  }
}
