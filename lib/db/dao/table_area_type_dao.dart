import '../entity/db_table_name.dart';
import '../entity/table_area_type_entity.dart';
import 'base_dao.dart';

/// 桌台绑定指定分类 DAO（对齐 TableAreaTypeDao.kt）
class TableAreaTypeDao extends BaseDao<TableAreaTypeEntity> {
  TableAreaTypeDao._();
  static final TableAreaTypeDao instance = TableAreaTypeDao._();

  @override
  String get table => DbTableName.tTableAreaType;

  @override
  TableAreaTypeEntity fromMap(Map<String, dynamic> m) =>
      TableAreaTypeEntity.fromMap(m);

  /// 按区域查询所有绑定分类
  Future<List<TableAreaTypeEntity>> queryAllByArea(String areaid,
      {int? spid}) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND areaid = ?',
      [spid, areaid],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询指定区域绑定的一级分类
  Future<List<TableAreaTypeEntity>> queryByAreaidLevel1(String areaid) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE areaid = ? AND level = 1',
      [areaid],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询指定区域绑定的二级分类
  Future<List<TableAreaTypeEntity>> queryByAreaidLevel2(String areaid) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE areaid = ? AND level = 2',
      [areaid],
    );
    return rows.map(fromMap).toList();
  }
}
