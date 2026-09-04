import '../entity/db_table_name.dart';
import '../entity/must_tablearea_entity.dart';
import 'base_dao.dart';

/// 必点菜区域 DAO（对齐 MustTableareaDao.kt）
class MustTableareaDao extends BaseDao<MustTableareaEntity> {
  MustTableareaDao._();
  static final MustTableareaDao instance = MustTableareaDao._();

  @override
  String get table => DbTableName.tMustTablearea;

  @override
  MustTableareaEntity fromMap(Map<String, dynamic> m) =>
      MustTableareaEntity.fromMap(m);

  /// 按 spid + sid 查询所有
  Future<List<MustTableareaEntity>> queryAllBySpidSid({
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND sid = ?',
      [spid, sid],
    );
    return rows.map(fromMap).toList();
  }
}
