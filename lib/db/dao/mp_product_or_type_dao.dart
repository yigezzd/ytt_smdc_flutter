import '../entity/db_table_name.dart';
import '../entity/mp_product_or_type_entity.dart';
import 'base_dao.dart';

/// 促销商品或分类 DAO（对齐 MPProAndTypeDao.kt）
class MpProductOrTypeDao extends BaseDao<MpProductOrTypeEntity> {
  MpProductOrTypeDao._();
  static final MpProductOrTypeDao instance = MpProductOrTypeDao._();

  @override
  String get table => DbTableName.tMpPtProductOrType;

  @override
  MpProductOrTypeEntity fromMap(Map<String, dynamic> m) =>
      MpProductOrTypeEntity.fromMap(m);

  /// 查询所有（spid + sid）
  Future<List<MpProductOrTypeEntity>> queryAllBySpidSid({
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND sid = ?',
      [spid, sid],
    );
    return rows.map(fromMap).toList();
  }

  /// 按 billid + saletype 查询
  Future<List<MpProductOrTypeEntity>> selectList({
    required int spid,
    required String billid,
    int? saletype,
  }) async {
    String sql = 'SELECT * FROM $table WHERE spid = ? AND billid = ?';
    final args = <Object?>[spid, billid];
    if (saletype != null) {
      sql += ' AND saletype = ?';
      args.add(saletype);
    }
    final rows = await db.queryList(sql, args);
    return rows.map(fromMap).toList();
  }

  /// 按多个 billid 批量查询
  Future<List<MpProductOrTypeEntity>> byBillids({
    required List<String> billids,
    required int spid,
    required int sid,
  }) async {
    if (billids.isEmpty) {
      return [];
    }
    final placeholders = billids.map((_) => '?').join(',');
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND sid = ? AND billid IN ($placeholders)',
      [spid, sid, ...billids],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询促销商品/分类并关联规则表（对齐 queryAll2 / queryAll3）
  ///
  /// SQL: SELECT a.*, b.discount FROM t_mp_pt_product_or_type a
  ///      LEFT JOIN t_mp_pt_rule b ON a.billid=b.billid AND a.spid=b.spid
  ///      LEFT JOIN t_mp_store c ON a.productid=c.productid
  ///      WHERE a.spid=? AND c.spid=? AND c.storeflag=1
  Future<List<MpProductOrTypeEntity>> queryAllWithRule(int spid) async {
    final sql = 'SELECT a.*, b.discount FROM $table a '
        'LEFT JOIN ${DbTableName.tMpPtRule} b ON a.billid=b.billid AND a.spid=b.spid '
        'LEFT JOIN ${DbTableName.tMpStore} c ON a.productid=c.productid '
        'WHERE a.spid=? AND c.spid=? AND c.storeflag=1';
    final rows = await db.queryList(sql, [spid, spid]);
    return rows.map(fromMap).toList();
  }

  /// 查询基础活动所有关联规则表（对齐 queryAll2）
  ///
  /// JOIN rule + store，条件 (c.sid = :sid OR c.sid = 0)
  Future<List<MpProductOrTypeEntity>> queryAll2({
    required int spid,
    required int sid,
  }) async {
    final sql = 'SELECT a.* FROM $table a '
        'LEFT JOIN ${DbTableName.tMpPtRule} b ON a.spid = b.spid '
        'AND a.sid = b.sid AND a.billid = b.billid AND a.ruleid = b.ruleid '
        'INNER JOIN ${DbTableName.tMpStore} c ON a.spid = c.spid '
        'AND a.billid = c.sbillid '
        'WHERE a.spid = ? AND (c.sid = ? OR c.sid = 0)';
    final rows = await db.queryList(sql, [spid, sid]);
    return rows.map(fromMap).toList();
  }

  /// 查询基础活动所有关联规则表（对齐 queryAll3，SQL 与 queryAll2 相同）
  Future<List<MpProductOrTypeEntity>> queryAll3({
    required int spid,
    required int sid,
  }) async {
    return queryAll2(spid: spid, sid: sid);
  }

  /// 获得活动（对齐 getMpProAndTypeDtoList）
  ///
  /// 复杂联表：JOIN master/rule/time/store，按 productids + 时间 + 门店过滤
  /// 返回 `List<Map<String, dynamic>>`，字段对齐原项目 MpProAndTypeDto
  Future<List<Map<String, dynamic>>> getMpProAndTypeDtoList({
    required int sid,
    required String productids,
  }) async {
    // 将逗号分隔的 productids 转为 SQL IN 参数
    final idList = productids.split(',').where((s) => s.trim().isNotEmpty).toList();
    if (idList.isEmpty) {
      return [];
    }
    final placeholders = idList.map((_) => '?').join(',');

    final sql = 'SELECT '
        'mpm.spid, ms.sid, pot.billid, pot.productid, mpm.name, '
        'mpm.dateflag, mpm.billtype, mpm.startdate, mpm.enddate, '
        'mpt.starttime, mpt.endtime, mpm.effectday, '
        'pot.discount, pot.price, pot.ruleid, pot.typeid, pot.specid, '
        'pot.saletype, mpr.qty, mpr.giveqty '
        'FROM $table AS pot '
        'LEFT JOIN ${DbTableName.tMpPtMaster} AS mpm ON pot.billid = mpm.billid '
        'LEFT JOIN ${DbTableName.tMpPtRule} AS mpr ON pot.ruleid = mpr.ruleid '
        'LEFT JOIN ${DbTableName.tMpPtTime} AS mpt ON pot.billid = mpt.billid '
        'LEFT JOIN ${DbTableName.tMpStore} AS ms ON pot.billid = ms.sbillid '
        'WHERE pot.saletype != 2 '
        'AND (ms.sid = 0 OR ms.sid = ?) '
        "AND ((mpm.dateflag = 1 AND mpm.startdate <= date('now','localtime') "
        "AND mpm.enddate >= date('now','localtime')) OR mpm.dateflag = 0) "
        "AND mpt.starttime <= time('now','localtime') "
        "AND mpt.endtime >= time('now','localtime') "
        'AND (pot.productid IN ($placeholders) OR pot.productid IS NULL '
        "OR trim(pot.productid) = '') "
        'AND (SELECT COUNT(1) = 0 FROM ${DbTableName.tMpPtNodate} AS tmpn '
        'WHERE pot.billid = tmpn.billid AND tmpn.startdate <= date() '
        'AND tmpn.enddate >= date())';

    return db.queryList(sql, [sid, ...idList]);
  }
}
