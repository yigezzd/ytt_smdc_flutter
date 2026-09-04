import 'app_database.dart';

/// 交班查询 DAO（对齐 YttPhone CashReconMapper + CashReconService + SaleJkdDao）
///
/// SQL 原样移植自 Java/Kotlin，仅将字符串拼接改为参数化查询；
/// 返回的 Map 键名与 YttPhone 一致（小写），供交班页/服务层直接使用。
class CashReconDao {
  CashReconDao._();

  static final CashReconDao instance = CashReconDao._();

  final AppDatabase _db = AppDatabase.instance;

  /// 最后一次交班时间（对齐 SaleJkdDao.getMaxLogoutTime）
  Future<String> getMaxLogoutTime({
    required String spid,
    required String sid,
    required String operid,
    required String machno,
  }) async {
    final Map<String, dynamic>? row = await _db.queryOne(
      "select ifnull(logouttime,'') logouttime from t_sale_jkd "
      'where spid=? and sid=? and operid=? and machno=? '
      'order by logouttime desc limit 1',
      <Object?>[spid, sid, operid, machno],
    );
    return row?['logouttime']?.toString() ?? '';
  }

  /// 最早结账时间（对齐 CashReconService.getSaleMaterMaxTime）
  ///
  /// [maxTime] 非空时以它为下限（>= maxTime），空则取全表最早。
  Future<String> getSaleMaterMaxTime({
    required String maxTime,
    required String spid,
    required String sid,
    required String machno,
  }) async {
    final String where = maxTime.isNotEmpty ? ' billdate >= ? AND' : '';
    final Map<String, dynamic>? row = await _db.queryOne(
      "select ifnull(billdate,'') logouttime from t_sale_master where"
      '$where spid=? and sid=? and machno=? order by billdate asc limit 1',
      maxTime.isNotEmpty
          ? <Object?>[maxTime, spid, sid, machno]
          : <Object?>[spid, sid, machno],
    );
    return row?['logouttime']?.toString() ?? '';
  }

  /// 最早会员储值时间（对齐 CashReconService.getVipMoneyMaterMaxTime）
  Future<String> getVipMoneyMaterMaxTime({
    required String maxTime,
    required String spid,
    required String sid,
    required String machno,
  }) async {
    final String where = maxTime.isNotEmpty ? ' createtime >= ? AND' : '';
    final Map<String, dynamic>? row = await _db.queryOne(
      "select ifnull(createtime,'') logouttime from t_vip_money_detail where"
      '$where spid=? and sid=? and machno=? order by createtime asc limit 1',
      maxTime.isNotEmpty
          ? <Object?>[maxTime, spid, sid, machno]
          : <Object?>[spid, sid, machno],
    );
    return row?['logouttime']?.toString() ?? '';
  }

  /// 最早押金时间（对齐 CashReconService.getDepositFlowMaxTime）
  Future<String> getDepositFlowMaxTime({
    required String maxTime,
    required String spid,
    required String sid,
    required String machno,
  }) async {
    final String where = maxTime.isNotEmpty ? ' createtime >= ? AND' : '';
    final Map<String, dynamic>? row = await _db.queryOne(
      "select ifnull(createtime,'') logouttime from t_deposit_flow where"
      '$where spid=? and sid=? and machno=? order by createtime asc limit 1',
      maxTime.isNotEmpty
          ? <Object?>[maxTime, spid, sid, machno]
          : <Object?>[spid, sid, machno],
    );
    return row?['logouttime']?.toString() ?? '';
  }

  /// 销售汇总（对齐 CashReconMapper.getSummaryData，SQL 原样移植）
  Future<Map<String, dynamic>?> getSummaryData({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
    required String machno,
    required String cashid,
  }) {
    return _db.queryOne(
      'select *,(case when personnum =0 then 0 else  Round(amt/personnum ,2) end) perpersonprice '
      '       from ( '
      '        SELECT '
      '        count(saleid) billnum, '
      '        sum(amt) amt, '
      '        sum(ifnull(lowamt,0)) lowamt,'
      '       sum(ifnull(serviceamt,0)) serviceamt, '
      '        sum(case when tableid is null then 1 else a.personnum end) personnum '
      '        FROM '
      '        t_sale_master a '
      '        WHERE '
      '         a.spid=? '
      '        AND a.sid=? '
      '        AND a.cashid =? '
      '        AND a.billdate >= ? '
      '        AND a.billdate <= ? '
      ' and a.machno=? '
      '        and a.opertype not in(2) '
      '        ) c',
      <Object?>[spid, sid, cashid, logintime, logouttime, machno],
    );
  }

  /// 交班销售流水列表（对齐 CashReconMapper.salejdklistByMachno）
  Future<List<Map<String, dynamic>>> salejdklistByMachno({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
    required String machno,
    required String cashid,
  }) {
    return _db.queryList(
      'select * FROM ( '
      '        select dscamt,amt,opertype,billtype,retailamt,roundamt from t_sale_master '
      '        where spid=?  and sid=? and status = 1 and cashid=? '
      '        and billdate >= ? '
      '        and billdate <= ? '
      '        and machno=? '
      '         and opertype not in(2) '
      '        )c',
      <Object?>[spid, sid, cashid, logintime, logouttime, machno],
    );
  }

  /// 交班 4 段 UNION 汇总（对齐 CashReconMapper.reportOnShiftByMachno，SQL 原样移植）
  ///
  /// 销售 t_sale_master+t_sale_payway+t_bi_payway(+t_bi_payway_store)；
  /// 会员储值 t_vip_money_detail；会员消费 t_vip_flow；预订 t_reserve_master。
  Future<List<Map<String, dynamic>>> reportOnShiftByMachno({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
    required String machno,
    required String cashid,
  }) {
    return _db.queryList(
      'select sum(billnum) billnum,sum(rebillnum) rebillnum,itype,paywayid,payway,handoverflag '
      '                ,sum(saleamt) saleamt '
      '                ,sum(resaleamt)*-1 resaleamt '
      '                ,sum(givemoney) givemoney '
      '                ,(case when handoverflag=1 then SUM( c.saleamt + c.resaleamt*-1 ) else 0 end ) as payableamt '
      '        FROM ( '
      'SELECT'
      " '1' AS itype,"
      ' b.payid AS paywayid,'
      ' c.name AS payway,'
      ' ifnull(ps.handoverflag,c.handoverflag) handoverflag,'
      ' (case when a.opertype = 3 then 0  else (Round(b.rramt/ ifnull(ps.rate,c.rate),2)) end )  saleamt,'
      ' (case when a.opertype = 3 then (-1*Round(b.rramt/ ifnull(ps.rate,c.rate),2))  else 0 end  )  resaleamt,'
      ' (case when a.opertype !=3 then 1  else 0 end  )  billnum,'
      '(case when a.opertype !=3 then 0  else 1 end )  rebillnum,'
      ' 0 AS givemoney '
      ' FROM '
      ' t_sale_master a, '
      ' t_sale_payway b,'
      ' t_bi_payway c'
      ' left join t_bi_payway_store ps on ps.spid=c.spid and ps.payid=c.payid and ps.status=1 and ps.spid=? and ps.sid=?'
      ' WHERE '
      ' a.spid =b.spid and a.sid=b.sid and a.saleid = b.saleid AND a.status = 1 '
      ' and b.spid=c.spid AND b.payid = c.payid AND c.spid= ? AND c.status = 1 '
      ' AND a.spid = ?'
      '  AND a.sid = ?'
      '  AND a.cashid = ?'
      '  AND a.billdate >= ?'
      '  AND a.billdate <= ?'
      ' and a.machno=?'
      ' and opertype not in(2) '
      ' UNION ALL '
      " select (case when a.opertype=1 then '2' when  a.opertype=3 then '6' when  a.opertype=4 then '6' when  a.opertype=8 then '8' else a.opertype end ) AS itype,"
      ' a.payid AS paywayid,b.name AS payway,'
      ' ifnull(ps.handoverflag,b.handoverflag) handoverflag,'
      ' (case when opertype =1 then  Round( a.addmoney/ ifnull( ps.rate, b.rate ), 2 )'
      ' when  opertype =3 then  Round( a.addmoney/ ifnull( ps.rate, b.rate ), 2 ) '
      ' when  opertype =4 then  Round( a.arrearages/ ifnull( ps.rate, b.rate ), 2 ) '
      ' when  opertype =8 then  Round( a.addmoney/ ifnull( ps.rate, b.rate ), 2 ) '
      ' else  Round( a.decmoney/ ifnull( ps.rate, b.rate ), 2 ) end) AS saleamt,'
      ' 0 AS resaleamt,0  billnum, 0  rebillnum,ROUND(a.givemoney/ifnull(ps.rate,b.rate),2) AS givemoney'
      ' FROM'
      ' t_vip_money_detail a,t_bi_payway b'
      ' left join t_bi_payway_store ps on ps.spid=b.spid and ps.payid=b.payid and ps.status=1 and ps.spid=? and ps.sid=?'
      ' WHERE '
      ' a.spid=b.spid and a.payid = b.payid '
      ' and a.spid= ?'
      ' AND a.sid = ?'
      '  AND a.operid = ?'
      ' AND a.createtime >= ?'
      ' AND a.createtime <= ?'
      ' and a.opertype in(1,3,4,8)'
      ' and a.machno=?'
      " and a.memo!='开卡余额'"
      ' UNION ALL'
      " select  (case when a.opertype=1 then '3' when  a.opertype=2 then '5' "
      "        when  a.opertype=3 then '4' when  a.opertype=9 then '7' else a.opertype "
      '        end )AS itype,'
      ' a.payid AS paywayid, b.name AS payway,'
      ' ifnull(ps.handoverflag,b.handoverflag) handoverflag,'
      ' (case when a.opertype=3 then (-1*Round( a.salemoney/ ifnull( ps.rate, b.rate ), 2 ))'
      'else Round( a.salemoney/ ifnull( ps.rate, b.rate ), 2 ) end) AS saleamt,'
      ' 0 AS resaleamt,0 AS billnum,0 AS rebillnum,0 AS givemoney '
      ' FROM '
      ' t_vip_flow a,t_bi_payway b '
      ' left join t_bi_payway_store ps on ps.spid=b.spid and ps.payid=b.payid and ps.status=1 and ps.spid=? and ps.sid= ?'
      ' WHERE '
      ' a.spid=b.spid and a.payid = b.payid '
      ' AND a.spid = ?'
      ' AND a.sid = ?'
      ' AND a.operid = ?'
      ' AND a.createtime  >= ?'
      ' AND a.createtime <= ?'
      ' and a.opertype in(1,2,3) '
      ' and a.machno=?'
      ' union all '
      " SELECT '10' AS itype, a.payid AS paywayid,c.name AS payway,"
      ' ifnull(ps.handoverflag,c.handoverflag) handoverflag,'
      ' (case when ifnull(a.wxretstatus,0) = 1 then (Round(a.downpayment/ ifnull(ps.rate,c.rate),2))  else (Round(a.downpayment/ ifnull(ps.rate,c.rate),2)) end )  saleamt,'
      ' (case when ifnull(a.wxretstatus,0) = 1 then (Round(a.downpayment/ifnull(ps.rate,c.rate),2))  else 0 end  )  resaleamt,'
      ' (case when ifnull(a.wxretstatus,0) = 1 then 1  else 1 end  )  billnum,'
      ' (case when ifnull(a.wxretstatus,0) = 0 then 0  else 1 end )  rebillnum,'
      ' 0 AS givemoney '
      ' FROM '
      ' t_reserve_master a, t_bi_payway c '
      ' left join t_bi_payway_store ps on ps.spid=c.spid and ps.payid=c.payid and ps.status=1 and ps.spid=? and ps.sid=?'
      ' WHERE '
      ' a.spid =c.spid and a.sid=c.sid and a.payid=c.payid  AND c.status = 1 '
      ' and a.spid= ? AND a.sid = ? '
      ' and a.updateid =?'
      ' AND a.updatetime >= ?'
      ' AND a.updatetime <= ?'
      ' and a.machno=?'
      ' )c GROUP BY itype,paywayid,payway,handoverflag ',
      <Object?>[
        // 第1段：t_bi_payway_store 门店条件 + t_bi_payway 条件 + t_sale_master 条件
        spid, sid, spid, spid, sid, cashid, logintime, logouttime, machno,
        // 第2段：t_vip_money_detail
        spid, sid, spid, sid, cashid, logintime, logouttime, machno,
        // 第3段：t_vip_flow
        spid, sid, spid, sid, cashid, logintime, logouttime, machno,
        // 第4段：t_reserve_master
        spid, sid, spid, sid, cashid, logintime, logouttime, machno,
      ],
    );
  }

  /// 菜品统计（对齐 CashReconMapper.getSaleProSummary）
  ///
  /// [typelist] 非空时 join t_type_handover_prn 排除（对齐 ParameterMapper.getHandoverType 结果）。
  Future<List<Map<String, dynamic>>> getSaleProSummary({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
    required String machno,
    required String cashid,
    required String sorttype,
    List<String> typelist = const <String>[],
  }) {
    final bool hasType = typelist.isNotEmpty;
    final String joinSql = hasType
        ? ' left join t_type_handover_prn c on b.spid =c.spid and '
            'b.typeid=c.typeid and c.sid=? and c.status=1 and c.machno=? and c.typeflag=1'
        : '';
    final String excludeSql = hasType ? '            and c.id is null  ' : '';
    final String orderSql = sorttype == '1'
        ? '              order by c.productname asc  '
        : '              order by c.rramt desc  ';
    final List<Object?> args = <Object?>[
      ...(hasType ? <Object?>[sid, machno] : <Object?>[]),
      spid, sid, cashid, logintime, logouttime, machno,
    ];
    return _db.queryList(
      'select * from (  '
      '        select b.productname,sum(b.qty) qty,sum(b.rramt) rramt,type.typeid,type.name typename  '
      '        from t_sale_master a,t_sale_detail b  '
      '        inner join t_bi_type type on b.spid=type.spid and b.typeid=type.typeid and type.status=1 '
      '$joinSql'
      '        where a.spid=b.spid and a.sid=b.sid  and a.saleid=b.saleid  '
      '        and a.spid=? and a.sid=? and a.cashid = ?'
      '        AND a.billdate >= ?'
      '        AND a.billdate <= ?'
      '        and a.machno=?'
      '$excludeSql'
      '        group by b.productname,type.typeid,type.name ) c  '
      '$orderSql',
      args,
    );
  }

  /// 分类统计（对齐 CashReconMapper.getSaleProTypeSummary）
  Future<List<Map<String, dynamic>>> getSaleProTypeSummary({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
    required String machno,
    required String cashid,
    List<String> typelist = const <String>[],
  }) {
    final bool hasType = typelist.isNotEmpty;
    final String joinSql = hasType
        ? ' left join t_type_handover_prn c on b.spid=c.spid and b.typeid=c.typeid and c.sid=? and c.status=1 and '
            '    c.machno=? and c.typeflag=2 '
        : '';
    final String excludeSql = hasType ? '        and c.id is null ' : '';
    final List<Object?> args = <Object?>[
      ...(hasType ? <Object?>[sid, machno] : <Object?>[]),
      spid, sid, cashid, logintime, logouttime, machno,
    ];
    return _db.queryList(
      'select * from ( '
      '        select type.name typename,sum(b.qty) qty,sum(b.rramt) rramt '
      '        from t_sale_master a,t_sale_detail b '
      '        inner join t_bi_type type on b.spid=type.spid and b.typeid=type.typeid and type.status=1 '
      '$joinSql'
      '        where a.spid=b.spid and a.sid=b.sid  and a.saleid=b.saleid '
      '        and a.spid=? and a.sid=? and a.cashid = ?'
      '        AND a.billdate  >=  ?'
      '        AND a.billdate <=  ?'
      '        and a.machno= ?'
      '$excludeSql'
      '       group by type.name )c '
      '        order by c.rramt desc',
      args,
    );
  }

  /// 退菜统计（对齐 CashReconMapper.getReturnProSummary）
  Future<List<Map<String, dynamic>>> getReturnProSummary({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
    required String machno,
    required String cashid,
  }) {
    return _db.queryList(
      'select b.productname,sum(b.qty) qty,sum(b.rramt) rramt   '
      '        from t_sale_master a,t_sale_detail b   '
      '        where a.spid=b.spid and a.sid=b.sid and a.saleid=b.saleid   '
      '        and a.spid=? and a.sid=? and a.cashid =? '
      '        AND a.billdate >= ?'
      '        AND a.billdate <= ?'
      ' and a.machno=?'
      ' and b.presentflag=2 group by b.productname',
      <Object?>[spid, sid, cashid, logintime, logouttime, machno],
    );
  }

  /// 预订金汇总（对齐 CashReconMapper.reserveSumdata；t_reserve_master 为空表）
  Future<Map<String, dynamic>?> reserveSumdata({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
    required String machno,
    required String cashid,
  }) {
    return _db.queryOne(
      'select count(a.billno) reservecnt,sum(case when  a.wxretstatus = 0 then  ifnull(a.downpayment,0) else 0 end ) reservepayamt  '
      '        from t_reserve_master a  '
      '        ,t_bi_payway c  '
      '        left join t_bi_payway_store ps on ps.spid=c.spid and ps.payid=c.payid and ps.status=1 and ps.spid=? and ps.sid=?'
      '        where  '
      '        a.spid=c.spid and a.payid=c.payid and c.status=1  '
      '        and a.spid = ? and a.sid=? '
      '        and a.updateid =?'
      '        AND a.updatetime  >= ?'
      '        AND a.updatetime  <= ?'
      ' and a.machno=?'
      ' and ifnull(ps.handoverflag,c.handoverflag)=1',
      <Object?>[spid, sid, spid, sid, cashid, logintime, logouttime, machno],
    );
  }

  /// 预订金按支付方式列表（对齐 CashReconMapper.getReserveList；t_reserve_master 为空表）
  Future<List<Map<String, dynamic>>> getReserveList({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
    required String machno,
    required String cashid,
    String handoverflag = '',
  }) {
    final String handoverSql =
        handoverflag == '1' ? ' and ifnull(ps.handoverflag,c.handoverflag)=1 ' : '';
    return _db.queryList(
      'select count(a.billno) reservecnt,a.payid,sum(case when  a.wxretstatus = 0 then  ifnull(a.downpayment,0) else 0 end ) reservepayamt '
      '        from t_reserve_master a , '
      '        t_bi_payway c '
      '        left join t_bi_payway_store ps on ps.spid=c.spid and ps.payid=c.payid and ps.status=1 and ps.spid= ? and ps.sid=? '
      '        where '
      '        a.spid=c.spid and a.payid=c.payid and c.status=1 '
      '        and a.spid = ? and a.sid=? '
      '        and a.updateid =?'
      '        AND a.updatetime >= ?'
      '        AND a.updatetime <= ?'
      ' and a.machno=?'
      '$handoverSql'
      ' group by a.payid ',
      <Object?>[spid, sid, spid, sid, cashid, logintime, logouttime, machno],
    );
  }

  /// 参数查询（对齐 CashReconMapper.getParam：t_bi_parameter，code in 列表）
  Future<List<Map<String, dynamic>>> getParam({
    required String spid,
    required String sid,
    required String machno,
    List<String> namelist = const <String>[],
  }) {
    String inSql = '';
    if (namelist.isNotEmpty) {
      final String codes =
          namelist.map((String n) => "'$n'").join(',');
      inSql = ' and code in ($codes) ';
    }
    return _db.queryList(
      'select spid,sid,type,code,value,remark from t_bi_parameter '
      'where spid=? and sid=? and type=0 '
      '$inSql'
      ' and remark = ?',
      <Object?>[spid, sid, machno],
    );
  }

  /// 交班排除分类（对齐 ParameterMapper.getHandoverType；t_type_handover_prn 为空表）
  Future<List<String>> getHandoverType({
    required String spid,
    required String sid,
    required String machno,
    required int typeflag,
  }) async {
    final List<Map<String, dynamic>> rows = await _db.queryList(
      'select typeid from t_type_handover_prn where  spid=?  and sid=? and machno=? and typeflag=? and status=1 order by typeid asc ',
      <Object?>[spid, sid, machno, typeflag],
    );
    return rows
        .map((Map<String, dynamic> r) => r['typeid']?.toString() ?? '')
        .toList();
  }

  /// 桌台押金汇总（对齐 SaleDepositMapper.getTableYjSum，SQL 原样移植）
  Future<List<Map<String, dynamic>>> getTableYjSum({
    required String logintime,
    required String logouttime,
    required String spid,
    required String sid,
  }) {
    return _db.queryList(
      ' SELECT '
      ' payid AS paywayid, '
      ' payname AS payway, '
      ' SUM(CASE WHEN rramt > 0 THEN 1 ELSE 0 END) AS billnum, '
      ' SUM(CASE WHEN rramt > 0 THEN rramt ELSE 0 END) AS saleamt, '
      ' SUM(CASE WHEN status IN (3,4) AND rramt > 0 THEN 1 ELSE 0 END) AS rebillnum, '
      ' SUM(CASE WHEN status IN (3,4) THEN rramt ELSE 0 END) AS resaleamt '
      ' FROM t_deposit_flow '
      ' WHERE spid = ? AND sid = ?'
      ' AND createtime >= ?'
      ' AND createtime <= ?'
      ' GROUP BY payid ',
      <Object?>[spid, sid, logintime, logouttime],
    );
  }

  /// 剩余押金（对齐 DepositFlowDao.getSyYjSum：status=1 全表）
  Future<double> getSyYjSum() async {
    final List<Map<String, dynamic>> rows =
        await _db.queryList('select SUM(rramt) as total from t_deposit_flow where status = 1');
    return _toDouble(rows.isEmpty ? 0 : rows.first['total']);
  }

  /// 本班次剩余押金（对齐 DepositFlowDao.getBcSyYjSum）
  Future<double> getBcSyYjSum({
    required String logintime,
    required String logouttime,
  }) async {
    final List<Map<String, dynamic>> rows = await _db.queryList(
      'select SUM(rramt) as total from t_deposit_flow where status = 1'
      ' AND createtime >= ? AND createtime <= ?',
      <Object?>[logintime, logouttime],
    );
    return _toDouble(rows.isEmpty ? 0 : rows.first['total']);
  }

  /// 桌台抵扣押金（对齐 DepositFlowDao.getDkYjSum）
  Future<double> getDkYjSum({
    required String logintime,
    required String logouttime,
  }) async {
    final List<Map<String, dynamic>> rows = await _db.queryList(
      'SELECT SUM(ABS(rramt)) as total FROM t_deposit_flow WHERE '
      ' ((status = 4 AND rramt < 0) OR (status = 2)) '
      ' AND createtime >= ? AND createtime <= ?',
      <Object?>[logintime, logouttime],
    );
    return _toDouble(rows.isEmpty ? 0 : rows.first['total']);
  }

  double _toDouble(dynamic v) {
    if (v == null) {
      return 0;
    }
    if (v is num) {
      return v.toDouble();
    }
    return double.tryParse(v.toString()) ?? 0;
  }
}
