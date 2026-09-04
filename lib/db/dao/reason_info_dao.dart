import '../entity/db_table_name.dart';
import '../entity/reason_info_entity.dart';
import 'base_dao.dart';

/// 系统备注 DAO（对齐 smdcapp ReasonInfoDao.kt）
class ReasonInfoDao extends BaseDao<ReasonInfoEntity> {
  ReasonInfoDao._();
  static final ReasonInfoDao instance = ReasonInfoDao._();

  @override
  String get table => DbTableName.tBiReasonInfo;

  @override
  ReasonInfoEntity fromMap(Map<String, dynamic> m) =>
      ReasonInfoEntity.fromMap(m);

  /// 按 typeid 查询备注列表（对齐原项目 queryByTypeId，只返回 value + code）
  Future<List<Map<String, dynamic>>> queryByTypeid(String typeid, {
    required int spid,
    required int sid,
  }) async {
    return db.queryList(
      'SELECT value, code FROM $table WHERE typeid = ? AND status = 1 '
      'AND spid = ? AND sid = ?',
      [typeid, spid, sid],
    );
  }

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList('UPDATE $table SET status = 1');
  }
}
