import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';

/// 捕获全局异常，进行统一处理。
void handleError(void Function() body) {
  /// 重写Flutter异常回调 FlutterError.onError
  FlutterError.onError = (FlutterErrorDetails details) {
    if (!Constant.inProduction) {
      // debug时，直接将异常信息打印。
      FlutterError.dumpErrorToConsole(details);
    }
    // 统一交由zone处理（落盘 crash_log）：现场 Release 没有控制台，
    // 异常不落盘则事后无迹可寻。
    Zone.current.handleUncaughtError(
      details.exception,
      details.stack ?? StackTrace.empty,
    );
  };

  /// 使用runZonedGuarded捕获Flutter未捕获的异常
  runZonedGuarded(body, (Object error, StackTrace stackTrace) async {
    await _reportError(error, stackTrace);
  });

}

Future<void> _reportError(Object error, StackTrace stackTrace) async {
  // 写入本地崩溃日志（同步落盘，避免进程随后退出丢掉缓冲区内容）
  FileLogWriter.instance.writeCrashLog(error, stackTrace);

  if (!Constant.inProduction) {
    debugPrintStack(
      stackTrace: stackTrace,
      label: error.toString(),
      maxFrames: 100,
    );
  } else {
    /// 将异常信息收集并上传到服务器。可以直接使用类似`flutter_bugly`插件处理异常上报。
  }

}
