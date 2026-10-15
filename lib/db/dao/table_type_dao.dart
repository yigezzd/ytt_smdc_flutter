import 'package:flutter/foundation.dart';

import '../../net/table_download_manager.dart';
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

  /// 行数据源：移动端读 SQLite；Web 无 sqflite，改读 TableDownloadManager 内存缓存
  /// （否则 Web 端附加费读取全部抛异常 → 开台弹窗选项为空点不动、名称恒显示"无"）
  Future<List<Map<String, dynamic>>> _rows() async {
    if (kIsWeb) {
      return TableDownloadManager.readTableData(table);
    }
    return db.queryList('SELECT * FROM $table');
  }

  /// 有效行（对齐 smdcapp 查询条件 stopflag = 0 and status = 1）
  static bool _isActive(Map<String, dynamic> m) =>
      _asInt(m['stopflag']) == 0 && _asInt(m['status']) == 1;

  /// Web 缓存行是后台原始 JSON，数字字段可能为 int/double/字符串，统一转换
  static int _asInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  /// 查询所有有效的桌台类型
  Future<List<TableTypeEntity>> queryAll() async {
    final List<Map<String, dynamic>> rows = await _rows();
    return rows.where(_isActive).map(fromMap).toList();
  }

  /// 按 tabletypeid + spid + sid 查询
  Future<TableTypeEntity?> querySpidAndSid(String tabletypeid,
      {required int spid, required int sid}) async {
    final List<Map<String, dynamic>> rows = await _rows();
    for (final Map<String, dynamic> m in rows) {
      if (_isActive(m) &&
          _asInt(m['spid']) == spid &&
          _asInt(m['sid']) == sid &&
          m['tabletypeid']?.toString() == tabletypeid) {
        return fromMap(m);
      }
    }
    return null;
  }

  /// 获取桌台附加费对象信息
  Future<TableTypeEntity?> getByCreateid(String id) async {
    final List<Map<String, dynamic>> rows = await _rows();
    for (final Map<String, dynamic> m in rows) {
      if (_isActive(m) && m['tabletypeid']?.toString() == id) {
        return fromMap(m);
      }
    }
    return null;
  }

  /// 重置所有记录的 stopflag 为 0
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET stopflag = 0");
  }
}
