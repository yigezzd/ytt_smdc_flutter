import '../entity/db_table_name.dart';
import '../entity/sys_user_entity.dart';
import 'base_dao.dart';

/// 系统用户 DAO（对齐 smdcapp SysUserDao.kt）
class SysUserDao extends BaseDao<SysUserEntity> {
  SysUserDao._();
  static final SysUserDao instance = SysUserDao._();

  @override
  String get table => DbTableName.sysUser;

  @override
  SysUserEntity fromMap(Map<String, dynamic> m) => SysUserEntity.fromMap(m);

  /// 按 userid 查询用户
  Future<SysUserEntity?> getByUserid(String userid) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE userid = ?',
      [userid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 重置所有记录的 stopflag 为 0
  Future<void> updateAll() async {
    await db.queryList('UPDATE $table SET stopflag = 0');
  }
}
