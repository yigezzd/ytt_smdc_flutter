import '../entity/db_table_name.dart';
import '../entity/mp_time_entity.dart';
import 'base_dao.dart';

/// 促销活动时间 DAO（对齐 MPTimeDao.kt）
class MpTimeDao extends BaseDao<MpTimeEntity> {
  MpTimeDao._();
  static final MpTimeDao instance = MpTimeDao._();

  @override
  String get table => DbTableName.tMpPtTime;

  @override
  MpTimeEntity fromMap(Map<String, dynamic> m) => MpTimeEntity.fromMap(m);

  /// 按 billid + spid + sid 查询（对齐原项目 byBillid）
  Future<List<MpTimeEntity>> byBillid(String billid, {
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE billid = ? AND spid = ? AND sid = ?',
      [billid, spid, sid],
    );
    return rows.map(fromMap).toList();
  }
}
