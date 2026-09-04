import '../entity/db_table_name.dart';
import '../entity/eat_group_entity.dart';
import 'base_dao.dart';

/// 吃法分组 DAO（对齐 EatGroupDao.kt）
class EatGroupDao extends BaseDao<EatGroupEntity> {
  EatGroupDao._();
  static final EatGroupDao instance = EatGroupDao._();

  @override
  String get table => DbTableName.tEatGroup;

  @override
  EatGroupEntity fromMap(Map<String, dynamic> m) => EatGroupEntity.fromMap(m);

  /// 获取所有有效的吃法分组，按排序号升序
  Future<List<EatGroupEntity>> getAllEatGroups() async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE status = 1 ORDER BY gisort ASC',
    );
    return rows.map(fromMap).toList();
  }

  /// 根据分组ID查询
  Future<EatGroupEntity?> getGroupById(String groupId) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE groupid = ? LIMIT 1',
      [groupId],
    );
    return row == null ? null : fromMap(row);
  }
}
