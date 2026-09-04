import '../entity/db_table_name.dart';
import '../entity/table_type_entity.dart';
import 'base_dao.dart';

/// 桌台类型 DAO（对齐 TableTypeDao.kt）
class TableTypeDao extends BaseDao<TableTypeEntity> {
  TableTypeDao._();
  static final TableTypeDao instance = TableTypeDao._();

  @override
  String get table => DbTableName.tTableType;

  @override
  TableTypeEntity fromMap(Map<String, dynamic> m) =>
      TableTypeEntity.fromMap(m);

  /// 查询所有有效的桌台类型
  Future<List<TableTypeEntity>> queryAll() async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE stopflag = 0 AND status = 1',
    );
    return rows.map(fromMap).toList();
  }

  /// 按 tabletypeid + spid + sid 查询
  Future<TableTypeEntity?> querySpidAndSid(String tabletypeid,
      {required int spid, required int sid}) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE stopflag = 0 AND status = 1 '
      'AND spid = ? AND sid = ? AND tabletypeid = ?',
      [spid, sid, tabletypeid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 获取桌台附加费对象信息
  Future<TableTypeEntity?> getByCreateid(String id) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE tabletypeid = ? AND stopflag = 0 AND status = 1',
      [id],
    );
    return row == null ? null : fromMap(row);
  }

  /// 重置所有记录的 stopflag 为 0
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET stopflag = 0");
  }
}
