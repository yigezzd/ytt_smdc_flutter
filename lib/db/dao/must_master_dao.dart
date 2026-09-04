import '../entity/db_table_name.dart';
import '../entity/must_master_entity.dart';
import 'base_dao.dart';

/// 必点菜主表 DAO（对齐 MustMasterDao.kt）
class MustMasterDao extends BaseDao<MustMasterEntity> {
  MustMasterDao._();
  static final MustMasterDao instance = MustMasterDao._();

  @override
  String get table => DbTableName.tMustMaster;

  @override
  MustMasterEntity fromMap(Map<String, dynamic> m) =>
      MustMasterEntity.fromMap(m);

  /// 获取指定区域下的必点菜列表（正餐）
  Future<List<MustMasterEntity>> queryAreaZC({
    required int spid,
    required int sid,
    String? areaid,
  }) async {
    final rows = await db.queryList(
      'SELECT a.*, b.areaid FROM ${DbTableName.tMustMaster} a '
      'LEFT JOIN ${DbTableName.tMustTablearea} b ON '
      'a.billid = b.billid AND a.spid = ? AND a.sid = ? '
      'AND ((strftime(\'%Y-%m-%d\', a.startdate) <= strftime(\'%Y-%m-%d\', \'now\') '
      'AND strftime(\'%Y-%m-%d\', a.enddate) >= strftime(\'%Y-%m-%d\', \'now\')) '
      'AND a.dateflag = 1 OR a.dateflag = 0) '
      'AND a.appflag = 1 AND a.stopflag = 0 '
      'WHERE (b.areaid = ? OR b.areaid IS NULL) '
      'AND a.appflag = 1 AND a.stopflag = 0 AND a.spid = ? AND a.sid = ?',
      [spid, sid, areaid ?? '', spid, sid],
    );
    return rows.map(fromMap).toList();
  }

  /// 获取指定区域下的必点菜列表（快餐）
  Future<List<MustMasterEntity>> queryAreaKC({
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT a.*, b.areaid FROM ${DbTableName.tMustMaster} a '
      'LEFT JOIN ${DbTableName.tMustTablearea} b ON '
      'a.billid = b.billid AND a.spid = COALESCE(b.spid, ?) '
      'AND a.sid = COALESCE(b.sid, ?) '
      'AND ((strftime(\'%Y-%m-%d\', a.startdate) <= strftime(\'%Y-%m-%d\', \'now\') '
      'AND strftime(\'%Y-%m-%d\', a.enddate) >= strftime(\'%Y-%m-%d\', \'now\')) '
      'AND a.dateflag = 1 OR a.dateflag = 0) '
      'AND a.appflag1 = 1 AND a.stopflag = 0',
      [spid, sid],
    );
    return rows.map(fromMap).toList();
  }

  /// 正常查询所有必点菜
  Future<List<MustMasterEntity>> queryAreaZCALL({
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT a.* FROM ${DbTableName.tMustMaster} a '
      'WHERE a.spid = ? AND a.sid = ? '
      'AND ((strftime(\'%Y-%m-%d\', a.startdate) <= strftime(\'%Y-%m-%d\', \'now\') '
      'AND strftime(\'%Y-%m-%d\', a.enddate) >= strftime(\'%Y-%m-%d\', \'now\')) '
      'AND a.dateflag = 1 OR a.dateflag = 0) '
      'AND (a.appflag = 1 OR appflag1 = 1) AND a.stopflag = 0 AND a.status = 1',
      [spid, sid],
    );
    return rows.map(fromMap).toList();
  }

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET status = 1");
  }
}
