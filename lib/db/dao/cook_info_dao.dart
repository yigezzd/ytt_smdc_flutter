import '../entity/cook_info_entity.dart';
import '../entity/db_table_name.dart';
import 'base_dao.dart';

/// 做法信息 DAO（对齐 CookInfoDao.kt）
class CookInfoDao extends BaseDao<CookInfoEntity> {
  CookInfoDao._();
  static final CookInfoDao instance = CookInfoDao._();

  @override
  String get table => DbTableName.tCookInfo;

  @override
  CookInfoEntity fromMap(Map<String, dynamic> m) => CookInfoEntity.fromMap(m);

  /// 按 code 查询（未停用且有效）
  Future<CookInfoEntity?> byProid(String code) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE code = ? AND stopflag = 0 AND status = 1',
      [code],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按多个编码批量查询做法信息
  Future<List<CookInfoEntity>> queryByCookCodes(List<String> codes) async {
    if (codes.isEmpty) return [];
    final placeholders = codes.map((_) => '?').join(',');
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE code IN ($placeholders) '
      'AND stopflag = 0 AND status = 1',
      codes,
    );
    return rows.map(fromMap).toList();
  }

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET status = 1");
  }
}
