import '../entity/db_table_name.dart';
import '../entity/spec_info_entity.dart';
import 'base_dao.dart';

/// 商品规格 DAO（对齐 SpecInfoDao.kt）
class SpecInfoDao extends BaseDao<SpecInfoEntity> {
  SpecInfoDao._();
  static final SpecInfoDao instance = SpecInfoDao._();

  @override
  String get table => DbTableName.tBiSpec;

  @override
  SpecInfoEntity fromMap(Map<String, dynamic> m) => SpecInfoEntity.fromMap(m);

  /// 按 specid 查询
  Future<SpecInfoEntity?> queryBySpecid(String specid, {int? spid}) async {
    String sql = 'SELECT * FROM $table WHERE specid = ?';
    final args = <Object?>[specid];
    if (spid != null) {
      sql += ' AND spid = ?';
      args.add(spid);
    }
    final row = await db.queryOne(sql, args);
    return row == null ? null : fromMap(row);
  }
}
