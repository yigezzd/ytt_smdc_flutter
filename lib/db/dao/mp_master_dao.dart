import '../entity/db_table_name.dart';
import '../entity/mp_master_entity.dart';
import 'base_dao.dart';

/// 促销主表 DAO（对齐 MPMasterDao.kt）
class MPMasterDao extends BaseDao<MPMasterEntity> {
  MPMasterDao._();
  static final MPMasterDao instance = MPMasterDao._();

  @override
  String get table => DbTableName.tMpPtMaster;

  @override
  MPMasterEntity fromMap(Map<String, dynamic> m) => MPMasterEntity.fromMap(m);

  /// 按 billid 查询
  Future<MPMasterEntity?> getInfo(String billid, {int? spid}) async {
    String sql = 'SELECT * FROM $table WHERE billid = ?';
    final args = <Object?>[billid];
    if (spid != null) {
      sql += ' AND spid = ?';
      args.add(spid);
    }
    final row = await db.queryOne(sql, args);
    return row == null ? null : fromMap(row);
  }

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET status = 1");
  }

  /// 查询当天有效的基础促销主表（对齐 queryMPSanKe / queryMPMember）
  ///
  /// [billtypeList] 促销类型列表，如 [1, 2, 3]
  /// [vipTypeid] 会员类型ID，为空则散客模式，非空则会员模式
  /// JOIN 了 t_mp_store（门店过滤）、t_mp_pt_time（时间段过滤）
  /// 含 effectday 星期过滤、nodate 排除日期过滤
  Future<List<MPMasterEntity>> queryActivePromotions({
    required int spid,
    required int sid,
    required List<int> billtypeList,
    String? vipTypeid,
  }) async {
    // 计算当前星期几（1=周一...7=周日），对齐 getWeekByTimeStampV3
    final weekflag = DateTime.now().weekday;

    final placeholders = billtypeList.map((_) => '?').join(',');

    // VIP 过滤条件
    String vipCondition;
    final vipArgs = <Object?>[];
    if (vipTypeid != null && vipTypeid.isNotEmpty) {
      // 会员模式：vipflag=1 或 (vipflag=3 且在 vip_type 表中匹配)
      vipCondition = 'AND (a.vipflag = 1 OR (a.vipflag = 3 '
          'AND ? IN (SELECT typeid FROM ${DbTableName.tMpPtVipType} '
          'WHERE spid = ? AND billid = a.billid)))';
      vipArgs.addAll([vipTypeid, spid]);
    } else {
      // 散客模式
      vipCondition = 'AND a.vipflag IN (1, 2)';
    }

    final sql = 'SELECT a.*, SUBSTR(a.effectday, ?, 1) AS effectday '
        'FROM $table a '
        'INNER JOIN ${DbTableName.tMpStore} sto ON a.spid = sto.spid '
        'AND a.billid = sto.sbillid AND sto.billflag = \'MPPT\' AND a.stopflag = 0 '
        'INNER JOIN ${DbTableName.tMpPtTime} t ON a.spid = t.spid AND a.billid = t.billid '
        'WHERE a.spid = ? '
        'AND sto.sid IN (?, 0) '
        '$vipCondition '
        'AND a.status = 1 '
        'AND a.stopflag = 0 '
        'AND a.billtype IN ($placeholders) '
        'AND a.appflag = 1 '
        'AND (SUBSTR(a.effectday, ?, 1) = \'1\' OR a.effectday IS NULL) '
        'AND ((date(\'now\') >= COALESCE(date(a.startdate), date(\'now\')) '
        'AND date(\'now\') <= COALESCE(date(a.enddate), date(\'now\')) '
        'AND a.dateflag = 1) OR a.dateflag = 0) '
        'AND NOT EXISTS (SELECT a.billid FROM ${DbTableName.tMpPtNodate} n '
        'WHERE a.spid = n.spid AND a.sid = n.sid AND a.billid = n.billid '
        'AND n.spid = ? AND a.stopflag = 0 '
        'AND date(\'now\') >= COALESCE(date(n.startdate), date(\'now\')) '
        'AND date(\'now\') <= COALESCE(date(n.enddate), date(\'now\'))) '
        'AND time(\'now\', \'localtime\') BETWEEN time(t.starttime) AND time(t.endtime)';

    final args = <Object?>[
      weekflag, // SUBSTR 参数
      spid,
      sid,
      ...vipArgs,
      ...billtypeList,
      weekflag, // effectday 过滤
      spid, // NOT EXISTS 参数
    ];

    final rows = await db.queryList(sql, args);
    return rows.map(fromMap).toList();
  }
}
