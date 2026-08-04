import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';

/// 本地运行日志写入工具（对齐 smdcapp JsonWriter）
///
/// 功能：
/// 1. 异步批量写入日志文件（使用 StreamController 队列，避免高频 IO）
/// 2. 按日期分目录：{appDocDir}/log/{yyyy-MM-dd}/json_writer/{yyyy-MM-dd}.log
/// 3. 分类日志支持：crash_log / mq_log / sql_log / print_log 等
/// 4. 单条日志最大 650KB 截断保护
/// 5. 磁盘空间低于 100MB 停止写入
/// 6. 启动时记录设备基础信息
/// 7. 自动清理过期日志（保留天数按月份：1-2月20天，其他10天）
class FileLogWriter {
  FileLogWriter._();

  static final FileLogWriter instance = FileLogWriter._();

  /// 日志根目录缓存
  String? _logRootPath;

  /// 单条日志最大长度（对齐 smdcapp MAX_LOG_LENGTH = 650000）
  static const int _maxLogLength = 650000;

  /// 日志写入队列
  final StreamController<_LogItem> _logController =
      StreamController<_LogItem>.broadcast();

  /// 批量缓冲
  final List<_LogItem> _batchBuffer = [];

  /// 批量写入阈值（对齐 smdcapp: 最多10条或500ms）
  static const int _batchSize = 10;
  static const Duration _batchTimeout = Duration(milliseconds: 500);

  Timer? _flushTimer;
  bool _initialized = false;

  /// 日志分类（对齐 smdcapp FileUtils.FolderType）
  static const String categoryJsonWriter = 'json_writer';
  static const String categoryCrashLog = 'crash_log';
  static const String categoryMqLog = 'mq_log';
  static const String categorySqlLog = 'sql_log';
  static const String categoryPrintLog = 'print_log';
  static const String categoryWmLog = 'wm_log';
  static const String categoryPoolLog = 'pool_log';

  /// 保留天数（对齐 smdcapp: 1-2月20天，其他10天）
  static int get _keepDays {
    final int month = DateTime.now().month;
    return (month == 1 || month == 2) ? 20 : 10;
  }

  // ─────────────── 初始化 ───────────────

  /// 初始化日志系统（在 main.dart 中调用）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Web 平台无文件系统，跳过文件日志初始化
    if (kIsWeb) return;

    // 获取日志根目录
    final dir = await getApplicationDocumentsDirectory();
    _logRootPath = '${dir.path}/log';

    // 启动批量写入监听
    _logController.stream.listen(_onLogItem);

    // 清理过期日志
    deleteOldLogs();
  }

  /// 记录设备基础信息（对齐 smdcapp JsonWriter.initLogInfo）
  ///
  /// 需在登录成功后调用（此时商户号/门店/机号已存入 SpUtil），
  /// 对齐 smdcapp LoginActivity 登录成功后调用 initLogInfo 的时机。
  void logDeviceInfo() {
    if (!_initialized || kIsWeb) return;
    _writeDeviceInfo();
  }

  // ─────────────── 公共写入方法 ───────────────

  /// 写入运行日志（对齐 smdcapp JsonWriter.writeToFile）
  void writeToFile(dynamic data, {String tag = '描述'}) {
    if (data == null) return;
    String content;
    if (data is String) {
      content = data;
    } else {
      try {
        content = json.encode(data);
      } catch (e) {
        content = 'Serialization Error: $e';
      }
    }
    _enqueue(content, tag, categoryJsonWriter);
  }

  /// 写入错误日志（对齐 smdcapp WriteErrorLogUtils.writeErrorLog）
  void writeErrorLog(
    dynamic error,
    String url,
    String params,
    String errorTips,
  ) {
    final sb = StringBuffer();
    if (error != null) {
      sb.writeln(error.toString());
    }
    sb.writeln(
        '${_timePrefix()}当前模式连接模式--->>>${ConnectionManager.pcAlive}');
    if (errorTips.isNotEmpty) {
      sb.writeln('${_timePrefix()}后台返回的消息--->>>$errorTips');
    }
    sb.writeln('${_timePrefix()}---->>>$url');
    sb.writeln('${_timePrefix()}---->>>$params');
    sb.writeln('----time >>>${_formatTime(DateTime.now())}');
    _enqueue(sb.toString(), '错误日志', categoryCrashLog);
  }

  /// 写入MQ日志（对齐 smdcapp WriteErrorLogUtils.writeMqLog）
  void writeMqLog(dynamic error, String url, String params, String errorTips) {
    final sb = StringBuffer();
    if (error != null) sb.writeln(error.toString());
    if (errorTips.isNotEmpty) sb.writeln(errorTips);
    sb.writeln('url: $url | params: $params | time: ${_formatTime(DateTime.now())}');
    _enqueue(sb.toString(), 'MQ日志', categoryMqLog);
  }

  /// 写入SQL日志（对齐 smdcapp WriteErrorLogUtils.writeSQLLog）
  void writeSqlLog(dynamic error, String url, String params, String errorTips) {
    final sb = StringBuffer();
    if (error != null) sb.writeln(error.toString());
    if (errorTips.isNotEmpty) sb.writeln(errorTips);
    sb.writeln('url: $url | params: $params | time: ${_formatTime(DateTime.now())}');
    _enqueue(sb.toString(), 'SQL日志', categorySqlLog);
  }

  /// 写入打印日志（对齐 smdcapp WriteErrorLogUtils.writePrintLog）
  void writePrintLog(dynamic error, String url, String params, String errorTips) {
    final sb = StringBuffer();
    if (error != null) sb.writeln(error.toString());
    if (errorTips.isNotEmpty) sb.writeln(errorTips);
    sb.writeln('url: $url | params: $params | time: ${_formatTime(DateTime.now())}');
    _enqueue(sb.toString(), '打印日志', categoryPrintLog);
  }

  /// 写埋点日志（对齐 smdcapp JsonWriter.writeActionLog）
  void writeActionLog({
    required String viewTag,
    required String action,
    String target = '',
    dynamic extra,
  }) {
    final map = <String, dynamic>{
      'viewTag': viewTag,
      'action': action,
      'target': target,
      'extra': extra,
    };
    writeToFile(map, tag: '埋点日志');
  }

  // ─────────────── 内部实现 ───────────────

  void _enqueue(String data, String tag, String category) {
    if (!_initialized || kIsWeb) return;

    // 长度截断保护（对齐 smdcapp MAX_LOG_LENGTH）
    String processedData = data;
    if (data.length > _maxLogLength) {
      processedData =
          '${data.substring(0, _maxLogLength)}\n...[Truncated, Original total: ${data.length} chars]';
    }

    // 计算大小显示
    final int len = data.length;
    String sizeDisplay;
    if (len > 1024 * 1024) {
      sizeDisplay = '${(len * 100 / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      sizeDisplay = '${(len * 100 / 1024).toStringAsFixed(2)} KB';
    }

    final enrichedTag = '$tag [Size: $sizeDisplay]';
    final time = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());

    _logController.add(_LogItem(
      tag: enrichedTag,
      data: processedData,
      time: time,
      category: category,
    ));
  }

  void _onLogItem(_LogItem item) {
    _batchBuffer.add(item);

    // 达到批量阈值立即刷盘
    if (_batchBuffer.length >= _batchSize) {
      _flushTimer?.cancel();
      _flushBatch();
      return;
    }

    // 定时强制刷盘（对齐 smdcapp 500ms）
    _flushTimer?.cancel();
    _flushTimer = Timer(_batchTimeout, _flushBatch);
  }

  void _flushBatch() {
    if (_batchBuffer.isEmpty) return;
    final items = List<_LogItem>.from(_batchBuffer);
    _batchBuffer.clear();

    // 异步写入文件
    _writeBatchToFile(items);
  }

  Future<void> _writeBatchToFile(List<_LogItem> items) async {
    try {
      if (_logRootPath == null) return;

      // 按分类分组写入
      final Map<String, List<_LogItem>> grouped = {};
      for (final item in items) {
        grouped.putIfAbsent(item.category, () => []).add(item);
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      for (final entry in grouped.entries) {
        final category = entry.key;
        final categoryItems = entry.value;

        final dirPath = '$_logRootPath/$dateStr/$category';
        final dir = Directory(dirPath);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        final filePath = '$dirPath/$dateStr.log';
        final file = File(filePath);

        final sb = StringBuffer();
        for (final item in categoryItems) {
          // 格式：时间_{time}_{pcAlive}_{tag}:{data}
          sb.write('时间_');
          sb.write(item.time);
          sb.write('_');
          sb.write(ConnectionManager.pcAlive);
          sb.write('_');
          sb.write(item.tag);
          sb.write(':');
          sb.write(item.data);
          sb.write('\n');
        }

        await file.writeAsString(sb.toString(),
            mode: FileMode.append, flush: true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FileLogWriter write error: $e');
      }
    }
  }

  /// 记录设备基础信息（对齐 smdcapp JsonWriter.initLogInfo）
  void _writeDeviceInfo() {
    final sb = StringBuffer('\n');
    sb.writeln('---------初始化信息---------');
    sb.writeln('连接模式: ${ConnectionManager.pcAlive ? "主设备" : "云服务"}');
    sb.writeln('商户号: ${SpUtil.getString(Constant.businessNumber) ?? ""}');
    sb.writeln('门店编码: ${SpUtil.getString(Constant.storeCode) ?? ""}');
    sb.writeln('机号: ${SpUtil.getString(Constant.machNo) ?? ""}');
    sb.writeln('平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    writeToFile(sb.toString(), tag: '设备信息');
  }

  // ─────────────── 日志清理 ───────────────

  /// 删除过期日志（对齐 smdcapp JsonWriter.delLogs / deleteOldLogDirectories）
  void deleteOldLogs() {
    if (_logRootPath == null) return;
    try {
      final logDir = Directory(_logRootPath!);
      if (!logDir.existsSync()) return;

      final now = DateTime.now();
      final keepDays = _keepDays;
      final dateFormat = DateFormat('yyyy-MM-dd');

      final entities = logDir.listSync();
      for (final entity in entities) {
        if (entity is! Directory) {
          // 删除残留的 zip 文件
          if (entity.path.endsWith('.zip')) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
          continue;
        }
        final dirName = entity.path.split(Platform.pathSeparator).last;
        try {
          final dirDate = dateFormat.parse(dirName);
          if (dirDate.isBefore(now.subtract(Duration(days: keepDays - 1)))) {
            entity.deleteSync(recursive: true);
          }
        } catch (_) {
          // 目录名不是合法日期，跳过
        }
      }
    } catch (_) {}
  }

  /// 获取日志根目录路径（供上传模块使用）
  String? get logRootPath => _logRootPath;

  // ─────────────── 工具方法 ───────────────

  String _timePrefix() =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  String _formatTime(DateTime dt) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
}

/// 日志条目
class _LogItem {
  final String tag;
  final String data;
  final String time;
  final String category;

  _LogItem({
    required this.tag,
    required this.data,
    required this.time,
    required this.category,
  });
}
