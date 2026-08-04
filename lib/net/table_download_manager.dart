import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';

/// 数据交换事件（对齐 smdcapp ChangeDataEvent）
class ChangeDataEvent {
  /// 下载中
  static const int code100 = 100;

  /// 全部下载完成
  static const int code200 = 200;

  /// 部分下载失败
  static const int code404 = 404;

  /// 当前已启动下载的表数量
  int num = 0;

  /// 事件码
  int code = code100;

  /// 文本提示（如 "(20/40) 商品促销信息 开始下载..."）
  String tag = '';
}

/// 表下载管理器（对齐 smdcapp TableDownloadManager + TableRegistry）
///
/// 登录成功后 / 个人中心"数据交换"入口统一调用 [downTableFlow]，
/// 通过云服务统一表下载接口 `/YttSvr/app/update/tabledown` 并发拉取全部注册表，
/// 数据以 JSON 文件形式缓存到本地（documents/table_data/{表名}.json）。
class TableDownloadManager {
  TableDownloadManager._();

  /// 注册表：表名 → 备注（对齐 smdcapp TableRegistry.tableRemarkMap，顺序一致）
  static const Map<String, String> tableRemarkMap = <String, String>{
    't_bi_product': '商品信息',
    't_bi_unit': '单位信息',
    't_bi_type': '商品分类信息',
    't_must_master': '必点菜信息',
    't_must_product': '必点菜信息',
    't_must_tablearea': '必点菜信息',
    'sys_store': '门店信息',
    't_bi_product_date': '商品售卖日期',
    't_bi_product_store': '商品门店',
    't_bi_spec': '规格信息',
    't_bi_product_spec': '规格信息',
    't_product_cook': '做法信息',
    't_cook_info': '做法信息',
    't_cook_group': '做法信息',
    't_bi_comb_set': '套餐信息',
    'sys_machine': '系统信息',
    't_mp_pt_master': '商品促销信息',
    't_mp_pt_nodate': '商品促销信息',
    't_mp_pt_product_or_type': '商品促销信息',
    't_mp_pt_rule': '商品促销信息',
    't_mp_pt_time': '商品促销信息',
    'sys_auth': '权限信息',
    't_mp_store_type': '商品促销信息',
    't_mp_store': '商品促销信息',
    't_mp_pt_vip_type': '商品促销信息',
    't_bi_reason_info': '备注信息',
    't_bi_payway': '支付信息',
    't_bi_parameter': '预定信息',
    't_reserve_master': '预定信息',
    't_vip_flow': '会员信息',
    'sys_user': '系统信息',
    't_table_type': '桌台信息',
    't_vip_info': '会员信息',
    't_vip_type': '会员信息',
    't_table_pricingmode_time': '桌台信息',
    't_table_area_type': '桌台信息',
    't_table_area': '桌台信息',
    't_product_eat': '一菜多吃',
    't_eat_group': '一菜多吃',
    't_eat_info': '一菜多吃',
  };

  /// 系统相关表：后台不校验更新时间和 pagesize，一次性全量返回，只有 1 页
  /// （对齐 smdcapp TableRegistry.sysNameList）
  static const List<String> sysNameList = <String>['sys_auth', 'sys_machine'];

  /// 并发下载数（对齐 smdcapp getChunkSize，移动端取标准值 3）
  static const int _concurrency = 3;

  /// 全量模式每页数量（对齐 smdcapp maxPageSize 标准设备 1800）
  static const int _fullPageSize = 1800;

  /// 增量模式每页数量（对齐 smdcapp 增量 maxPageSize 900）
  static const int _incrementalPageSize = 900;

  // ==================== 进度事件广播（对齐 smdcapp EventBus） ====================

  static final StreamController<ChangeDataEvent> _eventController =
      StreamController<ChangeDataEvent>.broadcast();

  /// 数据交换进度流（对齐 smdcapp @Subscribe onChangeDataEvent）
  static Stream<ChangeDataEvent> get onProgress => _eventController.stream;

  // ==================== 计数器（对齐 smdcapp startedCount/completedCount） ====================

  static int _startedCount = 0;
  static int _completedCount = 0;

  /// 记录失败的表名（对齐 smdcapp failedTables）
  static final Set<String> _failedTables = <String>{};

  /// 重置数据（对齐 smdcapp initInfo）
  static void initInfo() {
    _failedTables.clear();
    _resetCount();
  }

  static void _resetCount() {
    _startedCount = 0;
    _completedCount = 0;
  }

  /// 获取所有已注册的表名（对齐 smdcapp TableRegistry.getAllTableNames）
  static List<String> getAllTableNames() => tableRemarkMap.keys.toList();

  /// 获取失败的表名列表（对齐 smdcapp getFailedTableList）
  static List<String> getFailedTableList() => _failedTables.toList();

  // ==================== 全量/增量判定（对齐 smdcapp SpUtils.isAllUpdata） ====================

  /// 当前门店标识：spid-sid-云服务URL（对齐 smdcapp "${getSPID}-${getSID}-${NetHelpUtils.currentUrl}"）
  static String _currentSpidKey() {
    String sid = '0';
    String spid = '0';
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            json.decode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '0';
        spid = storeMap['spid']?.toString() ?? '0';
      }
    } catch (_) {}
    return '$spid-$sid-${HttpApi.baseUrlYtt}';
  }

  /// 是否需要全量更新（对齐 smdcapp SpUtils.isAllUpdata）：
  /// 当前 spid-sid-url 与上一次下载时保存的不一致 → 需要全量更新
  static bool isAllUpdata() {
    final String currSpid = _currentSpidKey();
    final String lastSpid = SpUtil.getString('loca_last_updatetime_spid') ?? '';
    debugPrint('表下载是否全部更新 currSpid = $currSpid,,, $lastSpid');
    return currSpid != lastSpid;
  }

  /// 全部下载成功后保存当前门店标识（对齐 smdcapp SpUtils.putLastDownTableSpid）
  static void putLastDownTableSpid() {
    SpUtil.putString(
        'loca_last_login_time', DateTime.now().millisecondsSinceEpoch.toString());
    SpUtil.putString('loca_last_updatetime_spid', _currentSpidKey());
  }

  /// 单表上次更新时间（对齐 smdcapp SpUtils.getDownTableTime）
  static String getDownTableTime(String tableName) {
    return SpUtil.getString('${tableName}_loca_last_updatetime') ?? '';
  }

  /// 保存单表更新时间（对齐 smdcapp SpUtils.putDownTableTime）
  static void putDownTableTime(String tableName, String time) {
    SpUtil.putString('${tableName}_loca_last_updatetime', time);
  }

  // ==================== 下载主流程（对齐 smdcapp downTableFlow） ====================

  /// 开始下载表数据
  ///
  /// [isFullUpdate] true=全量更新（清空本地数据重新下载）
  /// [targetTables] 指定下载的表集合，null 表示全部注册表（重试时传失败表）
  static Future<void> downTableFlow({
    required bool isFullUpdate,
    List<String>? targetTables,
  }) async {
    try {
      _resetCount();
      final List<String> tables =
          targetTables ?? getAllTableNames();
      final int totalCount = tables.length;
      final int pageSize =
          isFullUpdate ? _fullPageSize : _incrementalPageSize;

      // 并发下载（对齐 smdcapp flatMapMerge(concurrency = chunkSize)）
      final List<String> queue = List<String>.of(tables);
      final List<Future<void>> workers = <Future<void>>[];
      for (int i = 0; i < _concurrency; i++) {
        workers.add(Future<void>(() async {
          while (queue.isNotEmpty) {
            final String table = queue.removeAt(0);
            _startedCount++;
            final String remark = tableRemarkMap[table] ?? '未知信息';
            final String msg = '($_startedCount/$totalCount) $remark 开始下载...';
            debugPrint('下载进度 = $msg');
            _postEvent(ChangeDataEvent()
              ..tag = msg
              ..num = _startedCount
              ..code = ChangeDataEvent.code100);

            final bool success =
                await downloadTableData(isFullUpdate, table, pageSize);
            _completedCount++;
            if (!success) {
              _failedTables.add(table);
              debugPrint('表下载失败添加表到集合 = $table');
            }
          }
        }));
      }
      await Future.wait(workers);

      if (_failedTables.isEmpty) {
        // 没有记录到失败的表，默认就是全部下载成功
        putLastDownTableSpid();
        final String endMsg = '($totalCount/$totalCount) 全部下载完成 100%';
        debugPrint('下载进度 = $endMsg');
        _postEvent(ChangeDataEvent()
          ..tag = endMsg
          ..num = totalCount
          ..code = ChangeDataEvent.code100);
        // 延迟一下，让UI可以显示最后一条完成状态的信息（对齐 smdcapp delay(500)）
        await Future<void>.delayed(const Duration(milliseconds: 500));
        _postEvent(ChangeDataEvent()
          ..tag = endMsg
          ..num = totalCount
          ..code = ChangeDataEvent.code200);
      } else {
        debugPrint('表下载全部执行完成状态：部分失败');
        _postEvent(ChangeDataEvent()
          ..tag = '部分数据同步失败'
          ..num = _completedCount
          ..code = ChangeDataEvent.code404);
      }
    } catch (e) {
      debugPrint('表下载异常: $e');
      _postEvent(ChangeDataEvent()
        ..tag = '部分数据同步失败'
        ..num = _completedCount
        ..code = ChangeDataEvent.code404);
    }
  }

  static void _postEvent(ChangeDataEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  // ==================== 单表下载（对齐 smdcapp downloadTableData） ====================

  /// 通用单表分页下载方法
  ///
  /// [isFull] true=全量更新（不传 updatetime，首页清空本地数据）
  /// [tableName] 表名
  /// [pageSize] 每页数量
  static Future<bool> downloadTableData(
      bool isFull, String tableName, int pageSize) async {
    int currentPage = 1;
    bool isSuccess = true;
    final String updateTableTime = _formatNow();
    try {
      // 上一次的更新时间（增量模式传给后台做过滤）
      final String lastTableTime = getDownTableTime(tableName);
      while (true) {
        late final Map<String, dynamic> response;
        try {
          response = await requestForm(
            HttpApi.tabledown,
            <String, dynamic>{
              'tablename': tableName,
              // 如果是全量更新，不传时间（对齐 smdcapp）
              'updatetime': isFull ? '' : lastTableTime,
              // 对齐 smdcapp TableApi.downloadTableData 显式发送 machserialnew 空值
              'machserialnew': '',
              'page': currentPage.toString(),
              'pagesize': pageSize.toString(),
            },
            showError: false,
          );
        } catch (e) {
          isSuccess = false;
          debugPrint('表下载网络请求异常 = $e');
          break;
        }

        final dynamic jsonData = response['data'] ?? response['Data'];
        final List<dynamic> rows = jsonData is List ? jsonData : <dynamic>[];
        debugPrint('表下载$tableName 第$currentPage页，数据长度${rows.length}');
        if (rows.isEmpty) {
          break;
        }

        // 是否是第一页
        final bool isFirstPage = currentPage == 1;
        // 只有【全量下载】且是【第一页】才清空本地数据（对齐 smdcapp needClear）
        final bool needClear = isFull && isFirstPage;
        try {
          await _saveToDb(tableName, rows, needClear);
        } catch (e) {
          isSuccess = false;
          debugPrint('表下载数据保存异常: $e');
          break;
        }

        if (rows.length < pageSize) {
          // 如果返回的数量小于每页限制，说明是最后一页，结束循环
          break;
        }
        // 系统相关表后台一次性全量返回，只有 1 页（对齐 smdcapp sysNameList）
        if (sysNameList.contains(tableName)) {
          break;
        }
        currentPage++;
      }
    } catch (e) {
      isSuccess = false;
      debugPrint('表下载失败: $e');
    }
    if (isSuccess) {
      putDownTableTime(tableName, updateTableTime);
    }
    debugPrint('表下载$tableName，完成状态: $isSuccess');
    return isSuccess;
  }

  // ==================== 本地存储（对齐 smdcapp Room saveToDb） ====================

  /// Web 平台内存缓存（浏览器无文件系统，用内存替代；每次登录重新下载）
  static final Map<String, List<dynamic>> _webCache = <String, List<dynamic>>{};

  /// 本地缓存目录：documents/table_data/（仅非 Web 平台使用）
  static Future<Directory> _getDataDir() async {
    final Directory doc = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${doc.path}${Platform.pathSeparator}table_data');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static File _tableFile(Directory dir, String tableName) {
    return File('${dir.path}${Platform.pathSeparator}$tableName.json');
  }

  /// 保存表数据到本地（对齐 smdcapp TableRegistry.saveToDb）
  ///
  /// [needClear] true=全量下载首页，先清空旧数据再写入；
  /// false=增量更新，按 id 主键合并（新数据覆盖旧数据，对齐 Room upsert）。
  static Future<void> _saveToDb(
      String tableName, List<dynamic> rows, bool needClear) async {
    // Web 平台：使用内存缓存（浏览器无 getApplicationDocumentsDirectory）
    if (kIsWeb) {
      _saveToWebCache(tableName, rows, needClear);
      return;
    }
    final Directory dir = await _getDataDir();
    final File file = _tableFile(dir, tableName);

    List<dynamic> merged;
    if (needClear || !file.existsSync()) {
      merged = rows;
    } else {
      // 增量合并：读取旧数据，按 id 主键 upsert（无 id 的行直接追加）
      List<dynamic> oldRows = <dynamic>[];
      try {
        final String content = await file.readAsString();
        final dynamic decoded = json.decode(content);
        if (decoded is List) {
          oldRows = decoded;
        }
      } catch (_) {}
      merged = _mergeRows(oldRows, rows);
    }

    await file.writeAsString(json.encode(merged));
  }

  /// Web 内存缓存写入（逻辑与文件版一致：全量覆盖 / 增量 upsert）
  static void _saveToWebCache(
      String tableName, List<dynamic> rows, bool needClear) {
    if (needClear || !_webCache.containsKey(tableName)) {
      _webCache[tableName] = List<dynamic>.of(rows);
    } else {
      _webCache[tableName] = _mergeRows(_webCache[tableName]!, rows);
    }
  }

  /// 按 id 主键合并（upsert）：新数据覆盖旧数据，无 id 的行直接追加
  static List<dynamic> _mergeRows(
      List<dynamic> oldRows, List<dynamic> newRows) {
    final Map<String, int> idIndex = <String, int>{};
    for (int i = 0; i < oldRows.length; i++) {
      final dynamic row = oldRows[i];
      if (row is Map && row['id'] != null) {
        idIndex[row['id'].toString()] = i;
      }
    }
    for (final dynamic row in newRows) {
      if (row is Map && row['id'] != null) {
        final String id = row['id'].toString();
        final int? idx = idIndex[id];
        if (idx != null) {
          oldRows[idx] = row;
        } else {
          idIndex[id] = oldRows.length;
          oldRows.add(row);
        }
      } else {
        oldRows.add(row);
      }
    }
    return oldRows;
  }

  /// 读取本地缓存的表数据（供业务使用）
  ///
  /// 返回指定表的行列表；本地无缓存或解析失败时返回空列表。
  static Future<List<Map<String, dynamic>>> readTableData(
      String tableName) async {
    // Web 平台：从内存缓存读取
    if (kIsWeb) {
      final List<dynamic>? rows = _webCache[tableName];
      if (rows == null || rows.isEmpty) {
        return <Map<String, dynamic>>[];
      }
      return rows
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
          .toList();
    }
    try {
      final Directory dir = await _getDataDir();
      final File file = _tableFile(dir, tableName);
      if (!file.existsSync()) {
        return <Map<String, dynamic>>[];
      }
      final String content = await file.readAsString();
      final dynamic decoded = json.decode(content);
      if (decoded is List) {
        return decoded
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  /// 当前时间格式化为 yyyy-MM-dd HH:mm:ss（对齐 smdcapp TimeUtil.yyyy_MM_dd_HH_mm_ss）
  static String _formatNow() {
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}
