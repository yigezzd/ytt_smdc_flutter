import 'package:flutter/foundation.dart';

import '../../net/table_download_manager.dart';
import '../entity/db_table_name.dart';
import '../entity/mp_master_entity.dart';
import 'base_dao.dart';

/// 促销主表 DAO（对齐 MPMasterDao.kt）
class MPMasterDao extends BaseDao<MPMasterEntity> {
  MPMasterDao._();
  static final MPMasterDao instance = MPMasterDao._();

  @override
  String get table => DbTableName.tMpPtMaster;

  @override
  MPMasterEntity fromMap(Map<String, dynamic> m) => MPMasterEntity.fromMap(m);

  /// 按 billid 查询
  Future<MPMasterEntity?> getInfo(String billid, {int? spid}) async {
    String sql = 'SELECT * FROM $table WHERE billid = ?';
    final args = <Object?>[billid];
    if (spid != null) {
      sql += ' AND spid = ?';
      args.add(spid);
    }
    final row = await db.queryOne(sql, args);
    return row == null ? null : fromMap(row);
  }

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET status = 1");
  }

  /// 查询当天有效的基础促销主表（对齐 queryMPSanKe / queryMPMember）
  ///
  /// [billtypeList] 促销类型列表，如 [1, 2, 3]
  /// [vipTypeid] 会员类型ID，为空则散客模式，非空则会员模式
  /// JOIN 了 t_mp_store（门店过滤）、t_mp_pt_time（时间段过滤）
  /// 含 effectday 星期过滤、nodate 排除日期过滤
  Future<List<MPMasterEntity>> queryActivePromotions({
    required int spid,
    required int sid,
    required List<int> billtypeList,
    String? vipTypeid,
  }) async {
    if (kIsWeb) {
      return _queryActivePromotionsFromCache(
        spid: spid,
        sid: sid,
        billtypeList: billtypeList,
        vipTypeid: vipTypeid,
      );
    }
    // 计算当前星期几（1=周一...7=周日），对齐 getWeekByTimeStampV3
    final weekflag = DateTime.now().weekday;

    final placeholders = billtypeList.map((_) => '?').join(',');

    // VIP 过滤条件
    String vipCondition;
    final vipArgs = <Object?>[];
    if (vipTypeid != null && vipTypeid.isNotEmpty) {
      // 会员模式：vipflag=1 或 (vipflag=3 且在 vip_type 表中匹配)
      vipCondition = 'AND (a.vipflag = 1 OR (a.vipflag = 3 '
          'AND ? IN (SELECT typeid FROM ${DbTableName.tMpPtVipType} '
          'WHERE spid = ? AND billid = a.billid)))';
      vipArgs.addAll([vipTypeid, spid]);
    } else {
      // 散客模式
      vipCondition = 'AND a.vipflag IN (1, 2)';
    }

    final sql = 'SELECT a.*, SUBSTR(a.effectday, ?, 1) AS effectday '
        'FROM $table a '
        'INNER JOIN ${DbTableName.tMpStore} sto ON a.spid = sto.spid '
        'AND a.billid = sto.sbillid AND sto.billflag = \'MPPT\' AND a.stopflag = 0 '
        'INNER JOIN ${DbTableName.tMpPtTime} t ON a.spid = t.spid AND a.billid = t.billid '
        'WHERE a.spid = ? '
        'AND sto.sid IN (?, 0) '
        '$vipCondition '
        'AND a.status = 1 '
        'AND a.stopflag = 0 '
        'AND a.billtype IN ($placeholders) '
        'AND a.appflag = 1 '
        'AND (SUBSTR(a.effectday, ?, 1) = \'1\' OR a.effectday IS NULL) '
        'AND ((date(\'now\') >= COALESCE(date(a.startdate), date(\'now\')) '
        'AND date(\'now\') <= COALESCE(date(a.enddate), date(\'now\')) '
        'AND a.dateflag = 1) OR a.dateflag = 0) '
        'AND NOT EXISTS (SELECT a.billid FROM ${DbTableName.tMpPtNodate} n '
        'WHERE a.spid = n.spid AND a.sid = n.sid AND a.billid = n.billid '
        'AND n.spid = ? AND a.stopflag = 0 '
        'AND date(\'now\') >= COALESCE(date(n.startdate), date(\'now\')) '
        'AND date(\'now\') <= COALESCE(date(n.enddate), date(\'now\'))) '
        'AND time(\'now\', \'localtime\') BETWEEN time(t.starttime) AND time(t.endtime)';

    final args = <Object?>[
      weekflag, // SUBSTR 参数
      spid,
      sid,
      ...vipArgs,
      ...billtypeList,
      weekflag, // effectday 过滤
      spid, // NOT EXISTS 参数
    ];

    final rows = await db.queryList(sql, args);
    return rows.map(fromMap).toList();
  }

  /// Web 无 sqflite：按 [queryActivePromotions] 的 SQL 语义在内存中过滤
  /// tabledown 缓存（否则 Web 端基础促销初始化抛异常，分类/菜品折扣整体不生效）
  Future<List<MPMasterEntity>> _queryActivePromotionsFromCache({
    required int spid,
    required int sid,
    required List<int> billtypeList,
    String? vipTypeid,
  }) async {
    final List<Map<String, dynamic>> masters =
        await TableDownloadManager.readTableData(table);
    if (masters.isEmpty) return <MPMasterEntity>[];
    final List<Map<String, dynamic>> stores =
        await TableDownloadManager.readTableData(DbTableName.tMpStore);
    final List<Map<String, dynamic>> times =
        await TableDownloadManager.readTableData(DbTableName.tMpPtTime);
    final List<Map<String, dynamic>> nodates =
        await TableDownloadManager.readTableData(DbTableName.tMpPtNodate);
    final bool isVip = vipTypeid != null && vipTypeid.isNotEmpty;
    final List<Map<String, dynamic>> vipTypes = isVip
        ? await TableDownloadManager.readTableData(DbTableName.tMpPtVipType)
        : const <Map<String, dynamic>>[];

    final DateTime now = DateTime.now();
    final String today = _datePart(now.toIso8601String());
    final int nowSec = now.hour * 3600 + now.minute * 60 + now.second;
    final int weekIndex = now.weekday - 1;

    bool isActive(Map<String, dynamic> m) {
      if (_asInt(m['spid']) != spid) return false;
      if (_asInt(m['status']) != 1 || _asInt(m['stopflag']) != 0) return false;
      if (!billtypeList.contains(_asInt(m['billtype']))) return false;
      if (_asInt(m['appflag']) != 1) return false;
      final String billid = m['billid']?.toString() ?? '';

      final int vipflag = _asInt(m['vipflag']);
      if (isVip) {
        final bool vipOk = vipflag == 1 ||
            (vipflag == 3 &&
                vipTypes.any((Map<String, dynamic> v) =>
                    _asInt(v['spid']) == spid &&
                    v['billid']?.toString() == billid &&
                    v['typeid']?.toString() == vipTypeid));
        if (!vipOk) return false;
      } else if (vipflag != 1 && vipflag != 2) {
        return false;
      }

      final dynamic effectday = m['effectday'];
      if (effectday != null) {
        final String days = effectday.toString();
        if (days.length <= weekIndex || days[weekIndex] != '1') return false;
      }

      final int dateflag = _asInt(m['dateflag']);
      if (dateflag == 1) {
        if (!_inDateRange(today, m['startdate'], m['enddate'])) return false;
      } else if (dateflag != 0) {
        return false;
      }

      final bool storeOk = stores.any((Map<String, dynamic> s) =>
          _asInt(s['spid']) == spid &&
          s['sbillid']?.toString() == billid &&
          s['billflag']?.toString() == 'MPPT' &&
          (_asInt(s['sid']) == sid || _asInt(s['sid']) == 0));
      if (!storeOk) return false;

      final bool timeOk = times.any((Map<String, dynamic> t) {
        if (_asInt(t['spid']) != spid || t['billid']?.toString() != billid) {
          return false;
        }
        final int? start = _timeSec(t['starttime']);
        final int? end = _timeSec(t['endtime']);
        if (start == null || end == null) return false;
        return nowSec >= start && nowSec <= end;
      });
      if (!timeOk) return false;

      final int masterSid = _asInt(m['sid']);
      final bool blocked = nodates.any((Map<String, dynamic> n) =>
          _asInt(n['spid']) == spid &&
          _asInt(n['sid']) == masterSid &&
          n['billid']?.toString() == billid &&
          _inDateRange(today, n['startdate'], n['enddate']));
      return !blocked;
    }

    return masters.where(isActive).map(fromMap).toList();
  }

  static int _asInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  /// 取 yyyy-MM-dd 日期部分（对齐 SQLite date()，无法解析返回空串）
  static String _datePart(dynamic v) {
    final String s = v?.toString() ?? '';
    if (s.length < 10) return '';
    final String d = s.substring(0, 10);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) ? d : '';
  }

  /// 对齐 SQL：date('now') BETWEEN COALESCE(date(start), today) AND COALESCE(date(end), today)
  static bool _inDateRange(String today, dynamic start, dynamic end) {
    final String s = _datePart(start);
    final String e = _datePart(end);
    if (s.isNotEmpty && today.compareTo(s) < 0) return false;
    if (e.isNotEmpty && today.compareTo(e) > 0) return false;
    return true;
  }

  /// "HH:mm" / "HH:mm:ss" 转当日秒数（对齐 SQLite time()，无法解析返回 null）
  static int? _timeSec(dynamic v) {
    final List<String> parts = (v?.toString() ?? '').split(':');
    if (parts.length < 2) return null;
    final int? h = int.tryParse(parts[0]);
    final int? m = int.tryParse(parts[1]);
    final int s = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    if (h == null || m == null) return null;
    return h * 3600 + m * 60 + s;
  }
}
