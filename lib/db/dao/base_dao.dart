import '../app_database.dart';

/// 基础 DAO（对齐 BaseDao.kt + 各 DAO 的通用 CRUD / saveToDb）
///
/// 子类只需指定 [table] 和 [fromMap]，即可获得：
/// - queryAll / queryById / queryByColumn
/// - batchInsert（900 条一批，避开 SQLite 999 变量限制）
/// - deleteAll / saveToDb（全量先清后写）
abstract class BaseDao<T> {
  const BaseDao();

  AppDatabase get db => AppDatabase.instance;

  /// 对应表名
  String get table;

  /// 从数据库行 Map 构造实体
  T fromMap(Map<String, dynamic> m);

  /// 查询全部
  Future<List<T>> queryAll() async {
    final rows = await db.queryList('SELECT * FROM $table');
    return rows.map(fromMap).toList();
  }

  /// 按主键 id 查询
  Future<T?> queryById(int id) async {
    final row = await db.queryOne('SELECT * FROM $table WHERE id = ?', [id]);
    return row == null ? null : fromMap(row);
  }

  /// 按单列等值查询（返回第一条）
  Future<T?> queryByColumn(String column, dynamic value) async {
    final row =
        await db.queryOne('SELECT * FROM $table WHERE $column = ?', [value]);
    return row == null ? null : fromMap(row);
  }

  /// 按单列等值查询（返回列表）
  Future<List<T>> queryListByColumn(String column, dynamic value) async {
    final rows =
        await db.queryList('SELECT * FROM $table WHERE $column = ?', [value]);
    return rows.map(fromMap).toList();
  }

  /// 批量插入（900 条一批，对齐 chunked(900)）
  Future<void> batchInsert(List<Map<String, dynamic>> list) async {
    for (int i = 0; i < list.length; i += 900) {
      final end = (i + 900 > list.length) ? list.length : i + 900;
      await db.batchInsert(table, list.sublist(i, end));
    }
  }

  /// 清空表
  Future<void> deleteAll() async {
    await db.clearTable(table);
  }

  /// 全量保存（对齐 @Transaction saveToDb：isFull=true 先清空再写入）
  Future<void> saveToDb(
    List<Map<String, dynamic>> list,
    bool isFull,
  ) async {
    if (isFull) {
      await deleteAll();
    }
    if (list.isNotEmpty) {
      await batchInsert(list);
    }
  }
}
