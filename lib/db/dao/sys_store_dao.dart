import '../entity/db_table_name.dart';
import '../entity/sys_store_entity.dart';
import 'base_dao.dart';

/// 系统门店 DAO（对齐 smdcapp SysStoreDao.kt）
class SysStoreDao extends BaseDao<SysStoreEntity> {
  SysStoreDao._();
  static final SysStoreDao instance = SysStoreDao._();

  @override
  String get table => DbTableName.sysStore;

  @override
  SysStoreEntity fromMap(Map<String, dynamic> m) => SysStoreEntity.fromMap(m);

  /// 按 name 查询门店
  Future<SysStoreEntity?> queryByName(String name) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE name = ?',
      [name],
    );
    return row == null ? null : fromMap(row);
  }

  /// 重置所有记录的 stopflag 为 0
  Future<void> updateAll() async {
    await db.queryList('UPDATE $table SET stopflag = 0');
  }
}
