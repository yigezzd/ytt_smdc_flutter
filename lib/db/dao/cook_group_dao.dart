import '../entity/cook_group_entity.dart';
import '../entity/db_table_name.dart';
import 'base_dao.dart';

/// 做法分组 DAO（对齐 CookGroupDao.kt）
class CookGroupDao extends BaseDao<CookGroupEntity> {
  CookGroupDao._();
  static final CookGroupDao instance = CookGroupDao._();

  @override
  String get table => DbTableName.tCookGroup;

  @override
  CookGroupEntity fromMap(Map<String, dynamic> m) =>
      CookGroupEntity.fromMap(m);

  /// 按 groupid + spid + sid 查询
  Future<CookGroupEntity?> queryCookGroup(String groupid,
      {required int spid, required int sid}) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE groupid = ? AND spid = ? AND sid = ? AND status = 1',
      [groupid, spid, sid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET status = 1");
  }
}
