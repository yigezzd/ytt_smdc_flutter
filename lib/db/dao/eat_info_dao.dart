import '../entity/db_table_name.dart';
import '../entity/eat_info_entity.dart';
import 'base_dao.dart';

/// 吃法信息 DAO（对齐 EatInfoDao.kt）
class EatInfoDao extends BaseDao<EatInfoEntity> {
  EatInfoDao._();
  static final EatInfoDao instance = EatInfoDao._();

  @override
  String get table => DbTableName.tEatInfo;

  @override
  EatInfoEntity fromMap(Map<String, dynamic> m) => EatInfoEntity.fromMap(m);

  /// 根据分组ID查询该分组下所有启用的吃法
  Future<List<EatInfoEntity>> getEatInfoByGroupId(String groupId) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE groupid = ? AND status = 1 AND stopflag = 0 '
      'ORDER BY groupisort ASC',
      [groupId],
    );
    return rows.map(fromMap).toList();
  }

  /// 根据吃法编码查询
  Future<EatInfoEntity?> getByCode(String code) async {
    return queryByColumn('code', code);
  }
}
