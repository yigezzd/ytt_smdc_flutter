import '../entity/able_area_entity.dart';
import '../entity/db_table_name.dart';
import 'base_dao.dart';

/// 桌台区域 DAO（对齐 AbleAreaDao.kt）
class AbleAreaDao extends BaseDao<AbleAreaEntity> {
  AbleAreaDao._();
  static final AbleAreaDao instance = AbleAreaDao._();

  @override
  String get table => DbTableName.tTableArea;

  @override
  AbleAreaEntity fromMap(Map<String, dynamic> m) => AbleAreaEntity.fromMap(m);

  /// 按 areaid 查询
  Future<AbleAreaEntity?> queryByAreaid(String areaid) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE areaid = ?',
      [areaid],
    );
    return row == null ? null : fromMap(row);
  }
}
