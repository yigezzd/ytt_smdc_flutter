import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/net/table_download_manager.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';

/// 数据交换页（对齐 smdcapp ChangeDataPopup + dialog_change_data.xml）
///
/// 登录成功后 / 个人中心"数据交换"入口进入本页面，
/// 一次性并发请求全部注册表（tabledown 接口）并缓存到本地。
///
/// [type] 0=登录页入口（按 isAllUpdata 判定全量/增量）
///        1=设置页入口（默认交换全部数据，即全量更新）
class DataExchangePage extends StatefulWidget {
  const DataExchangePage({super.key, this.type = 0});

  final int type;

  @override
  State<DataExchangePage> createState() => _DataExchangePageState();
}

class _DataExchangePageState extends State<DataExchangePage> {
  /// 品牌红（对齐 smdcapp colorPrimary / red_e13426）
  static const Color _brandRed = Color(0xFFE13426);

  /// 进度文本（对齐 smdcapp tv_change_data，初始"交换数据中"）
  String _statusText = '交换数据中';

  /// 进度条总数（需下载的表数量，对齐 smdcapp numberbar1.max）
  int _max = 0;

  /// 当前进度（已启动下载的表数量，对齐 smdcapp numberbar1.progress = event.NUM）
  int _progress = 0;

  StreamSubscription<ChangeDataEvent>? _subscription;

  /// 重试弹窗是否正在展示（防止重复弹出）
  bool _retryDialogShowing = false;

  @override
  void initState() {
    super.initState();
    // 订阅下载进度（对齐 smdcapp EventBus.register + onChangeDataEvent）
    _subscription = TableDownloadManager.onProgress.listen(_onProgressEvent);
    // 重置数据后开始下载（对齐 smdcapp ChangeDataPopup.onCreate: initInfo() + downTable()）
    TableDownloadManager.initInfo();
    _startDownload();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// 开始下载（对齐 smdcapp ChangeDataPopup.downTable）
  void _startDownload({bool isRetry = false}) {
    // 设置页进来的默认交换全部数据（对齐 smdcapp: type==1 → isAll=true，否则取 isAllUpdata）
    final bool isAll = widget.type == 1 || TableDownloadManager.isAllUpdata();

    List<String>? targets;
    if (isRetry) {
      // 重试时只下载失败的表（对齐 smdcapp: getFailedTableList + initInfo 重置）
      final List<String> failedList = TableDownloadManager.getFailedTableList();
      TableDownloadManager.initInfo();
      targets = failedList;
    }

    if (mounted) {
      setState(() {
        _max = targets == null
            ? TableDownloadManager.getAllTableNames().length
            : targets.length;
        _progress = 0;
        _statusText = '交换数据中';
      });
    }
    TableDownloadManager.downTableFlow(
      isFullUpdate: isAll,
      targetTables: targets,
    );
  }

  /// 进度事件处理（对齐 smdcapp onChangeDataEvent）
  void _onProgressEvent(ChangeDataEvent event) {
    if (!mounted) {
      return;
    }
    switch (event.code) {
      case ChangeDataEvent.code404:
        // 部分数据交换失败 → 弹窗提示重试（对齐 smdcapp TipPop）
        setState(() => _statusText = event.tag);
        _showRetryDialog();
        break;
      case ChangeDataEvent.code200:
        // 全部下载完成 → 重新初始化数据并进入桌台页
        // （对齐 smdcapp: initInfo + TableInfoActivity.startActivity + 登录页 finish）
        TableDownloadManager.initInfo();
        if (mounted) {
          NavigatorUtils.push(context, Routes.home, clearStack: true);
        }
        break;
      default:
        // 下载中：更新文本与进度条
        setState(() {
          _statusText = event.tag;
          _progress = event.num;
        });
    }
  }

  /// 失败重试弹窗（对齐 smdcapp TipPop "部分数据交换失败,点击重试重新交换数据"）
  Future<void> _showRetryDialog() async {
    if (_retryDialogShowing || !mounted) {
      return;
    }
    _retryDialogShowing = true;
    final bool retry = await ConfirmDialog.show(
      context,
      content: '部分数据交换失败,点击重试重新交换数据',
      confirmText: '重试',
      barrierDismissible: false,
    );
    _retryDialogShowing = false;
    if (!mounted) {
      return;
    }
    if (retry) {
      _startDownload(isRetry: true);
    } else {
      // 取消也进入桌台页（对齐 smdcapp: 取消后仍跳转 TableInfoActivity）
      TableDownloadManager.initInfo();
      NavigatorUtils.push(context, Routes.home, clearStack: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _brandRed,
        // 下载期间禁止返回（对齐 smdcapp dismissOnBackPressed(false)）
        body: PopScope(
          canPop: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 进度文本（对齐 smdcapp tv_change_data: 16sp 白色居中）
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  // 数字进度条（对齐 smdcapp NumberProgressBar Grace_Yellow）
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _NumberProgressBar(
                      max: _max,
                      progress: _progress,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 数字进度条（对齐 smdcapp NumberProgressBar Grace_Yellow 样式）
///
/// 黄色(#FFC73B)已达到进度 + 灰色(#CCCCCC)未达到进度，
/// 百分比文本跟随在进度末端。
class _NumberProgressBar extends StatelessWidget {
  const _NumberProgressBar({
    required this.max,
    required this.progress,
  });

  final int max;
  final int progress;

  /// 已达到进度颜色（对齐 progress_reached_color #FFC73B）
  static const Color _reachedColor = Color(0xFFFFC73B);

  /// 未达到进度颜色（对齐 progress_unreached_color #CCCCCC）
  static const Color _unreachedColor = Color(0xFFCCCCCC);

  @override
  Widget build(BuildContext context) {
    final double ratio =
        max <= 0 ? 0.0 : (progress / max).clamp(0.0, 1.0);
    final int percent = (ratio * 100).round();

    return LayoutBuilder(
      builder: (_, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double reachedWidth = width * ratio;
        return SizedBox(
          height: 22,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              // 未达到进度（灰色底条）
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: _unreachedColor,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              // 已达到进度（黄色填充条）
              if (reachedWidth > 0)
                Container(
                  width: reachedWidth,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _reachedColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              // 百分比文本跟随进度末端（对齐 NumberProgressBar 文本位置）
              Positioned(
                left: (reachedWidth + 6).clamp(0.0, width - 44),
                child: Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _reachedColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
