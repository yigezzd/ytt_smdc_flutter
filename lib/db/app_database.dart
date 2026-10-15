import 'package:flutter/foundation.dart';
import 'package:flutter_deer/db/entity/db_table_name.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// 本地数据库（对齐 YttPhone DbManager + SqlActuatorUtils）
///
/// 仅 iOS/Android 使用：Web 平台通过 CashReconService 的 kIsWeb 分支隔离，
/// 本类在 Web 上不执行任何操作（sqflite 仅 import 不会崩溃）。
///
/// - 库名 catering.db（对齐 YttPhone DB_NAME），version 2，onCreate 建全部 15 张表
/// - 通用执行器对齐 SqlActuatorUtils：queryList/queryOne/insert/batchInsert
///   （insert 按表 PRAGMA 列名动态取值，多余键忽略；null/空串 → ''、数字原样）
/// - 退出登录时 clearAll() 清空全部业务表
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  /// 数据库文件名（对齐 YttPhone DB_NAME）
  static const String dbName = 'catering.db';

  static const int dbVersion = 3;

  Database? _db;

  /// 本地业务表（非后台下载，App 本地产生的数据）
  static const List<String> localTables = <String>[
    't_sale_master',
    't_sale_payway',
    't_sale_detail',
    't_sale_cook',
    't_bi_payway_store',
    't_type_handover_prn',
    't_vip_money_detail',
    't_deposit_flow',
    't_sale_jkd',
    't_sale_jkd_detail',
  ];

  /// 全部表名清单 = 后台数据表 + 本地业务表
  static const List<String> tables = <String>[
    ...DbTableName.backendTables,
    ...localTables,
  ];

  Future<Database> get database async {
    if (_db != null) {
      return _db!;
    }
    if (kIsWeb) {
      // Web 平台无 sqflite 插件，正常流程不会走到这里（调用方已按 kIsWeb 分流）
      throw UnsupportedError('sqflite 不支持 Web 平台');
    }
    final String path = join(await getDatabasesPath(), dbName);
    _db = await openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    for (final String sql in _createTableSqls) {
      await db.execute(sql);
    }
  }

  /// 版本升级：v1 → v2 补齐 t_must_product 的 smdcapp MustProduct 字段
  /// （specid/specname/mustqty，旧数据在下次全量下载后填充）
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      const List<String> columns = <String>[
        'specid TEXT',
        'specname TEXT',
        'mustqty REAL',
      ];
      for (final String column in columns) {
        try {
          await db.execute('ALTER TABLE t_must_product ADD COLUMN $column');
        } catch (_) {
          // 列已存在时忽略
        }
      }
    }
    if (oldVersion < 3) {
      // v2 → v3 补建 t_table_type
      // （此前 _createTableSqls 漏建该表，数据交换写入与附加费查询均报 no such table
      //  → 开台弹窗附加费选项为空、点击无响应；升级后由数据交换补充数据）
      await db.execute(_tTableTypeSql);
    }
  }

  /// 查询列表（对齐 SqlActuatorUtils.queryListBysql）
  Future<List<Map<String, dynamic>>> queryList(
    String sql, [
    List<Object?>? args,
  ]) async {
    final Database db = await database;
    return db.rawQuery(sql, args);
  }

  /// 查询单条（对齐 SqlActuatorUtils.queryBysql：取第一条，无数据返回 null）
  Future<Map<String, dynamic>?> queryOne(
    String sql, [
    List<Object?>? args,
  ]) async {
    final List<Map<String, dynamic>> list = await queryList(sql, args);
    return list.isEmpty ? null : list.first;
  }

  /// 单条插入（对齐 SqlActuatorUtils.insert）
  ///
  /// 按表 PRAGMA 列名动态拼 INSERT：map 中缺失的列补默认值（''/0），
  /// 多余的键自动忽略；id 为 null/0/'' 时由 SQLite 自动生成。
  Future<int> insert(String table, Map<String, dynamic> values) async {
    final Database db = await database;
    final List<String> columns = await _tableColumns(db, table);
    final Set<String> numericColumns = await _numericColumns(db, table);
    final Map<String, dynamic> row = <String, dynamic>{};
    for (final String col in columns) {
      row[col] = _normalize(values[col], numeric: numericColumns.contains(col));
    }
    return db.insert(table, row);
  }

  /// 批量插入（对齐 SqlActuatorUtils.patchInsert，80 条一批由调用方控制）
  Future<void> batchInsert(
    String table,
    List<Map<String, dynamic>> values,
  ) async {
    final Database db = await database;
    final List<String> columns = await _tableColumns(db, table);
    final Set<String> numericColumns = await _numericColumns(db, table);
    final Batch batch = db.batch();
    for (final Map<String, dynamic> map in values) {
      final Map<String, dynamic> row = <String, dynamic>{};
      for (final String col in columns) {
        row[col] = _normalize(map[col], numeric: numericColumns.contains(col));
      }
      batch.insert(table, row);
    }
    await batch.commit(noResult: true);
  }

  /// 清空全部业务表（退出登录时调用）
  ///
  /// 逐表 try/catch：个别未建表的表（如 sys_machine/sys_auth）跳过，
  /// 避免单表 "no such table" 异常中断其后所有表的清空。
  Future<void> clearAll() async {
    final Database db = await database;
    for (final String table in tables) {
      try {
        await db.delete(table);
      } catch (e) {
        debugPrint('清空表失败($table): $e');
      }
    }
    _columnCache.clear();
    _numericColumnCache.clear();
  }

  /// 清空单表（基础表全量重写前调用）
  Future<void> clearTable(String table) async {
    final Database db = await database;
    await db.delete(table);
  }

  /// WAL 检查点（日志上传前把 WAL 数据刷回主数据库文件，保证拷贝完整）
  Future<void> checkpoint() async {
    try {
      final Database db = await database;
      await db.execute('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
  }

  /// 表列缓存（对齐 SqlActuatorUtils.getTableColumn）
  final Map<String, List<String>> _columnCache = <String, List<String>>{};

  /// 表数值列缓存（INTEGER/REAL 等），用于空值规整
  final Map<String, Set<String>> _numericColumnCache = <String, Set<String>>{};

  Future<List<String>> _tableColumns(Database db, String table) async {
    final List<String>? cached = _columnCache[table];
    if (cached != null) {
      return cached;
    }
    final List<Map<String, dynamic>> rows = await db.rawQuery('PRAGMA table_info($table)');
    final List<String> columns = rows.map((Map<String, dynamic> r) => r['name'] as String).toList();
    _columnCache[table] = columns;
    _numericColumnCache[table] = rows
        .where((Map<String, dynamic> r) => _isNumericType(r['type']?.toString() ?? ''))
        .map((Map<String, dynamic> r) => r['name'] as String)
        .toSet();
    return columns;
  }

  /// 数值列判断（PRAGMA 声明的列类型）
  static bool _isNumericType(String type) {
    final String t = type.toUpperCase();
    return t.contains('INT') ||
        t.contains('REAL') ||
        t.contains('FLOA') ||
        t.contains('DOUB') ||
        t.contains('NUM') ||
        t.contains('DEC');
  }

  Future<Set<String>> _numericColumns(Database db, String table) async {
    if (!_numericColumnCache.containsKey(table)) {
      await _tableColumns(db, table);
    }
    return _numericColumnCache[table] ?? const <String>{};
  }

  /// 值规整（对齐 SqlActuatorUtils.getObjectStr：null/空串 → ''、数字原样、其余转字符串）
  ///
  /// [numeric] 为 true 时（列类型为 INTEGER/REAL 等），空值写 NULL：
  /// 云端 tabledown 对空字段下发 null，若统一写成空串，SQLite 对数值列
  /// 不做转换会按 TEXT 存储，实体 fromMap 的 `as int?` / `as num?` 强转
  /// 会抛类型异常（曾导致促销表整表读取失败、促销不生效）。
  dynamic _normalize(dynamic v, {bool numeric = false}) {
    if (v == null || (v is String && v.isEmpty)) {
      return numeric ? null : '';
    }
    if (v is String) {
      return v;
    }
    if (v is num || v is bool) {
      return v;
    }
    return v.toString();
  }

  /// 桌台类型表・附加费建表 SQL（对齐 smdcapp TableType.kt，字段与 [TableTypeEntity] 一致）
  ///
  /// 该表注册在 [DbTableName.backendTables] 中由数据交换下载，但曾漏建于此，
  /// 导致 "no such table: t_table_type"：附加费选项查询失败 → 开台弹窗附加费点不动、
  /// 修改开台信息附加费恒显示"无"。onCreate 与 v3 升级共用此 SQL（IF NOT EXISTS 幂等）。
  static const String _tTableTypeSql = '''
    CREATE TABLE IF NOT EXISTS t_table_type (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT, createid TEXT, createname TEXT, createtime TEXT,
      excesstime REAL, isort INTEGER, lowamt REAL, lowtype INTEGER, minsalesamtflag INTEGER,
      name TEXT, operid TEXT, opername TEXT, reservationflag INTEGER,
      serviceamt REAL, servicetype INTEGER, sid INTEGER, spid INTEGER,
      status INTEGER, stopflag INTEGER, tabletypeid TEXT, trueflag INTEGER, updatetime TEXT,
      starthour REAL, startamt REAL, overhour REAL, overamt REAL,
      begintime TEXT, endtime TEXT, addhour REAL, addamt REAL, maxhour REAL, maxamt REAL,
      remark TEXT, starthourtype INTEGER, overhourtype INTEGER, addhourtype INTEGER,
      maxhourtype INTEGER, exceedtype INTEGER, freemin REAL, exceedmin1 REAL, exceedmin2 REAL,
      calculatemin1 REAL, calculatemin2 REAL, automaticflag INTEGER, serviceamtflag INTEGER
    )
    ''';

  /// 建表 SQL（字段对齐 YttPhone room/entity，全部小写）
  static const List<String> _createTableSqls = <String>[
    // ──────────── 销售（对齐 SaleMaster.java）────────────
    '''
    CREATE TABLE t_sale_master (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, saleid TEXT, billno TEXT, billdate TEXT,
      tableid TEXT, tableno TEXT, vipid TEXT, vipno TEXT, vipname TEXT, vipmobile TEXT,
      personnum INTEGER, amt REAL, dscamt REAL, addamt REAL, payment REAL,
      billtype INTEGER, mallbillid TEXT, makedataflag INTEGER, upflag INTEGER,
      cashid TEXT, serverid TEXT, machno TEXT, createtime TEXT, updatetime TEXT,
      status INTEGER, takeouttype INTEGER, localbillno TEXT, returnbillno TEXT,
      remark TEXT, ordernumber TEXT, opertype INTEGER, operid TEXT, operamt REAL,
      opertime TEXT, retailamt REAL, changeamt REAL, paywayname TEXT, roundamt REAL,
      dockerid INTEGER, billflag INTEGER, lowamt REAL, qty REAL, serviceamt REAL,
      takecode TEXT, cashname TEXT, servername TEXT, tablename TEXT, operremark TEXT,
      printnumber INTEGER, wmorderid TEXT
    )
    ''',
    // ──────────── 销售支付（对齐 SalePayway.java）────────────
    '''
    CREATE TABLE t_sale_payway (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, saleid TEXT, payid TEXT, payname TEXT,
      payamt REAL, rate REAL, rramt REAL, changeamt REAL,
      vipid TEXT, vipno TEXT, vipname TEXT, voucher TEXT, faceamt REAL,
      wxtrade TEXT, wxrefund TEXT, wxclientid TEXT, vipnowmoney REAL,
      operid TEXT, createtime TEXT, paystatus INTEGER, remark TEXT,
      terminalsn TEXT, machno TEXT, clienttype TEXT, depositonlyid TEXT,
      virtualamt REAL, actulamt REAL, paytype INTEGER,
      salecapitalmoney REAL, salegivemoney REAL, count INTEGER, terminalkey TEXT
    )
    ''',
    // ──────────── 销售明细（对齐 SaleDetail.java）────────────
    '''
    CREATE TABLE t_sale_detail (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, saleid TEXT, billno TEXT, onlyid TEXT,
      productid TEXT, productcode TEXT, productno TEXT, productname TEXT,
      typeid TEXT, typename TEXT, unit TEXT, specid TEXT, spec TEXT,
      qty REAL, subqty REAL, sellprice REAL, discount REAL, rrprice REAL, rramt REAL,
      presentflag INTEGER, remark TEXT, combflag TEXT, combid TEXT,
      combgroupid TEXT, combproductid TEXT, saleductamt REAL,
      hangflag INTEGER, callflag INTEGER, urgeflag INTEGER, presentprice REAL,
      cooktext TEXT, cookaddamt REAL, roundamt REAL, discountamt REAL, addpoint REAL,
      specpriceflag INTEGER, bxxpxxflag INTEGER, cxmbillid TEXT,
      salesid TEXT, salesname TEXT, operid TEXT, opername TEXT, opertime TEXT,
      createtime TEXT, seq INTEGER, opertype INTEGER, operremark TEXT, operamt REAL,
      costprice REAL, jcmbillid TEXT
    )
    ''',
    // ──────────── 销售做法（对齐 SaleCook.java）────────────
    '''
    CREATE TABLE t_sale_cook (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, saleid TEXT, onlyid TEXT,
      code TEXT, name TEXT, price REAL, qty REAL, ptype INTEGER
    )
    ''',
    // ──────────── 支付方式（对齐 PayWayInfo.kt）────────────
    '''
    CREATE TABLE t_bi_payway (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, fuseflag INTEGER, handoverflag INTEGER,
      opencashflag INTEGER, padflag INTEGER, stopflag INTEGER, rate REAL,
      pointflag INTEGER, operflag INTEGER, isort INTEGER, paytype INTEGER,
      scanflag INTEGER, status INTEGER,
      value TEXT, createtime TEXT, code TEXT, operid TEXT, remark TEXT,
      opername TEXT, name TEXT, updatetime TEXT, payid TEXT,
      faceflag TEXT, actulamt TEXT, virtualamt TEXT, faceamt TEXT
    )
    ''',
    // ──────────── 门店支付方式（对齐 PaywayStore.java）────────────
    '''
    CREATE TABLE t_bi_payway_store (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, payid TEXT, code TEXT, name TEXT, rate REAL,
      handoverflag INTEGER, pointflag INTEGER, stopflag INTEGER, paytype INTEGER,
      opencashflag INTEGER, isort INTEGER, status INTEGER,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT, remark TEXT,
      fuseflag INTEGER, scanflag INTEGER, operflag INTEGER, padflag INTEGER
    )
    ''',
    // ──────────── 商品分类（对齐 ProductType.kt）────────────
    '''
    CREATE TABLE t_bi_type (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, status INTEGER, isort INTEGER, stopflag INTEGER,
      typeid TEXT, code TEXT, name TEXT, parenttypeid TEXT, level INTEGER,
      typeid1 TEXT, createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT,
      discount INTEGER, pcshowflag INTEGER, padshowflag INTEGER,
      mobileshowflag INTEGER, scanshowflag INTEGER
    )
    ''',
    // ──────────── 交班排除分类（对齐 YpeHandoverPrn.java，云端无接口保持空表）────────────
    '''
    CREATE TABLE t_type_handover_prn (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, typeid TEXT, machno TEXT, typeflag INTEGER,
      status INTEGER, createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 参数表（对齐 Parameter.java）────────────
    '''
    CREATE TABLE t_bi_parameter (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, type INTEGER, code TEXT, value TEXT, remark TEXT,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 会员余额明细（对齐 VipMoneyDetail.java）────────────
    '''
    CREATE TABLE t_vip_money_detail (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, vipid TEXT, vipno TEXT, vipname TEXT,
      addmoney REAL, givemoney REAL, decmoney REAL, endmoney REAL,
      payid TEXT, payname TEXT, saleid TEXT, salename TEXT,
      operid TEXT, opername TEXT, billno TEXT, memo TEXT, machno TEXT,
      opertype INTEGER, createtime TEXT, introducer TEXT,
      arrearages REAL, arrearagestotal REAL, clienttype TEXT,
      returnmoney REAL, ruleid INTEGER, capitalmoney REAL
    )
    ''',
    // ──────────── 会员流水（对齐 VipFlow.java）────────────
    '''
    CREATE TABLE t_vip_flow (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, vipid TEXT, vipno TEXT, vipname TEXT, typeid TEXT,
      cardmoney REAL, salemoney REAL, payid TEXT, payname TEXT,
      operid TEXT, opername TEXT, saleid TEXT, salename TEXT, introducer TEXT,
      billno TEXT, opertype INTEGER, machno TEXT, memo TEXT, createtime TEXT,
      saleductamt REAL, favourableamt REAL, clienttype TEXT
    )
    ''',
    // ──────────── 押金流水（对齐 DepositFlow.java）────────────
    '''
    CREATE TABLE t_deposit_flow (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, onlyid TEXT, billno TEXT,
      tableid TEXT, tablename TEXT, saleid TEXT,
      createtime TEXT, updatetime TEXT, status INTEGER,
      payamt REAL, rate REAL, rramt REAL, payname TEXT, payid TEXT,
      refundamt REAL, third_order_no TEXT, trade_no TEXT,
      refund_third_no TEXT, refund_trade_no TEXT,
      operid TEXT, opername TEXT, machno TEXT, usetime TEXT,
      vipid TEXT, terminalsn TEXT, terminalkey TEXT, paytype TEXT
    )
    ''',
    // ──────────── 预订（对齐 ReserveMaster.java，Flutter 无预订功能保持空表）────────────
    '''
    CREATE TABLE t_reserve_master (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, billid TEXT, billno TEXT,
      rtype INTEGER, rtypeval INTEGER, arrivaltime TEXT, arrivalmin INTEGER,
      person INTEGER, arrivaltype INTEGER, remindtime TEXT,
      name TEXT, sex INTEGER, mobile TEXT,
      downpayment REAL, mealamt REAL, tableqty INTEGER, tablenames TEXT,
      saleid TEXT, salename TEXT, remark TEXT, status INTEGER,
      createtime TEXT, createid TEXT, createname TEXT,
      updatetime TEXT, updateid TEXT, updatename TEXT,
      payid TEXT, payway TEXT, wxtrade TEXT, wxrefund TEXT, wxclientid TEXT,
      wxretstatus INTEGER, machno TEXT, paydate TEXT, retpaydate TEXT
    )
    ''',
    // ──────────── 交班主表（对齐 SaleJkd.java）────────────
    '''
    CREATE TABLE t_sale_jkd (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, flowid TEXT, flowno TEXT,
      operid TEXT, opername TEXT, logintime TEXT, logouttime TEXT, machno TEXT,
      salecnt INTEGER, returncnt INTEGER, returnamt REAL, halfdraw REAL,
      saleamt REAL, payableamt REAL, payamt REAL, createtime TEXT, upflag INTEGER,
      remark TEXT, dutyamt REAL, discountamt REAL, presentqty REAL, presentamt REAL,
      payflag INTEGER, rechargeamt REAL, rechargesubmitamt REAL,
      amt REAL, personnum INTEGER, perpersonprice REAL,
      reservecnt INTEGER, reservepayamt REAL, reserveamt REAL,
      lowamt REAL, serviceamt REAL, vipcardamt REAL, depositpayableamt REAL,
      depositdedamt REAL, lastdepositremamt REAL, totalreceipts REAL,
      rebateamt REAL, roundamt REAL, vipdiscountamt REAL, promotionamt REAL,
      rechargecnt REAL, salegivemoney REAL, salecapitalmoney REAL,
      vipcardpayableamt REAL, blindamt REAL
    )
    ''',
    // ──────────── 交班明细（对齐 SaleJkdDetail.java）────────────
    '''
    CREATE TABLE t_sale_jkd_detail (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, flowid TEXT, flowno TEXT,
      paywayid TEXT, payway TEXT,
      saleamt REAL, payableamt REAL, payamt REAL,
      itype INTEGER, remark TEXT, givemoney REAL, handoverflag INTEGER,
      billnum INTEGER, resaleamt REAL, rebillnum INTEGER,
      depositdedamt REAL, lastdepositremamt REAL,
      capitalmoney REAL, actulamt REAL, faceflag INTEGER, unusedepositamt REAL
    )
    ''',
    // ──────────── 商品表（对齐 ProductBean.kt）────────────
    '''
    CREATE TABLE t_bi_product (
      id INTEGER PRIMARY KEY, spid INTEGER, sid INTEGER,
      productid TEXT, barcode TEXT, name TEXT,
      typeid TEXT, typeid1 TEXT, typeid2 TEXT, helpcode TEXT, unit TEXT,
      sellprice REAL, mprice1 REAL, mprice2 REAL, mprice3 REAL, inprice REAL,
      isort INTEGER, dscflag INTEGER, printflag INTEGER, labelflag INTEGER,
      pointflag INTEGER, minsaleflag INTEGER, presentflag INTEGER, curflag INTEGER,
      stockflag INTEGER, eatinstoreflag INTEGER, bagflag INTEGER, recommendflag INTEGER,
      pcshowflag INTEGER, scanshowflag INTEGER, padshowflag INTEGER, mobileshowflag INTEGER,
      sellclearflag INTEGER, saledateflag INTEGER, stopflag INTEGER, cookflag INTEGER,
      specflag INTEGER, combflag INTEGER, weighflag INTEGER, hangflag INTEGER,
      callflag INTEGER, urgeflag INTEGER, status INTEGER, typeproisort INTEGER,
      imageurl TEXT, createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT,
      code TEXT, rrprice REAL, stockqty REAL, discount REAL, typename TEXT,
      cookaddamt REAL, startsellqty REAL DEFAULT 1, servicefeeflag INTEGER DEFAULT 1,
      addsellqty REAL DEFAULT 1, maxsellqty REAL DEFAULT 0.0, jcmbillid TEXT,
      chooseqtyflag INTEGER DEFAULT 0, moreeatflag INTEGER DEFAULT 0,
      combsource INTEGER, datetype INTEGER, cycletype INTEGER, saletime TEXT,
      rawflag INTEGER, saleqty REAL, deductvalue REAL, deducttype INTEGER,
      saleweek TEXT, begindate TEXT, timetype INTEGER, combtype INTEGER,
      enddate TEXT, salemonth TEXT
    )
    ''',
    // ──────────── 商品规格表（对齐 SpecInfo.kt）────────────
    '''
    CREATE TABLE t_bi_spec (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, isort INTEGER, stopflag INTEGER, status INTEGER,
      specid TEXT, name TEXT, createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 商品规格关联表（对齐 ProductSpec.kt）────────────
    '''
    CREATE TABLE t_bi_product_spec (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, isort INTEGER, rawflag INTEGER,
      specname TEXT, productid TEXT, specid TEXT,
      inprice REAL, sellprice REAL, mprice1 REAL, mprice2 REAL, mprice3 REAL,
      status INTEGER, rrprice REAL, specpriceflag INTEGER, stockqty REAL,
      defsizeflag INTEGER
    )
    ''',
    // ──────────── 商品售卖日期表（对齐 ProductDate.kt）────────────
    '''
    CREATE TABLE t_bi_product_date (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, status INTEGER, stopflag INTEGER, isort INTEGER,
      rawflag INTEGER, mobileshowflag INTEGER, recommendflag INTEGER,
      productid TEXT, begindate TEXT, enddate TEXT, cycletype INTEGER,
      saleweek TEXT, salemonth TEXT, saletime TEXT,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 商品单位表（对齐 ProductUnit.kt）────────────
    '''
    CREATE TABLE t_bi_unit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, status INTEGER, stopflag INTEGER, isort INTEGER,
      rawflag INTEGER, unitid TEXT, name TEXT,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 套餐设置表（对齐 ProductCombSet.kt）────────────
    '''
    CREATE TABLE t_bi_comb_set (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, repeatflag INTEGER, defflag INTEGER,
      specid TEXT, combid TEXT, productid TEXT, groupid TEXT, groupname TEXT,
      productname TEXT, barcode TEXT, unit TEXT, size TEXT,
      selectqty REAL, price REAL, qty REAL,
      status INTEGER, isort INTEGER, stopflag INTEGER,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT,
      cutprice REAL, addprice REAL, selecttype INTEGER
    )
    ''',
    // ──────────── 桌台绑定指定分类表（对齐 TableAreaType.kt）────────────
    '''
    CREATE TABLE t_table_area_type (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, status INTEGER, isort INTEGER,
      areaid TEXT, typeid TEXT, level INTEGER,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 桌台区域表（对齐 AbleArea.java）────────────
    '''
    CREATE TABLE t_table_area (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, status INTEGER, stopflag INTEGER, isort INTEGER,
      areaid TEXT, name TEXT, createtime TEXT, createid TEXT, createname TEXT,
      updatetime TEXT, operid TEXT, opername TEXT, isalltype INTEGER
    )
    ''',
    // ──────────── 桌台类型表・附加费（对齐 TableType.kt）────────────
    _tTableTypeSql,
    // ──────────── 附加费区间表（对齐 TablePricingModeTime.kt）────────────
    '''
    CREATE TABLE t_table_pricingmode_time (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sid INTEGER, spid INTEGER, status INTEGER,
      tabletypeid TEXT, starttime TEXT, endtime TEXT,
      min INTEGER, price REAL, weekprice REAL,
      isort INTEGER, createtime TEXT, updatetime TEXT
    )
    ''',
    // ──────────── 促销活动VIP类型表（对齐 MPVipType.kt）────────────
    '''
    CREATE TABLE t_mp_pt_vip_type (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, billid TEXT, typeid TEXT,
      createtime TEXT, updatetime TEXT
    )
    ''',
    // ──────────── 促销活动时间表（对齐 MPTime.kt）────────────
    '''
    CREATE TABLE t_mp_pt_time (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, billid TEXT, starttime TEXT, endtime TEXT,
      createtime TEXT, updatetime TEXT
    )
    ''',
    // ──────────── 促销规则表（对齐 MPRule.kt）────────────
    '''
    CREATE TABLE t_mp_pt_rule (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, billid TEXT, ruleid TEXT,
      amt REAL, qty REAL, giveqty REAL, discount REAL, price REAL,
      createtime TEXT, updatetime TEXT
    )
    ''',
    // ──────────── 促销商品或分类表（对齐 MPProductOrType.kt）────────────
    '''
    CREATE TABLE t_mp_pt_product_or_type (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, discount REAL, price REAL,
      billid TEXT, ruleid TEXT, productid TEXT, typeid TEXT,
      specid TEXT, saletype TEXT
    )
    ''',
    // ──────────── 促销不可用日期表（对齐 MPNoDate.kt）────────────
    '''
    CREATE TABLE t_mp_pt_nodate (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, billid TEXT, startdate TEXT, enddate TEXT
    )
    ''',
    // ──────────── 促销主表（对齐 MPMaster.kt）────────────
    '''
    CREATE TABLE t_mp_pt_master (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, status INTEGER, dateflag INTEGER,
      billid TEXT, billno TEXT, name TEXT,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT,
      startdate TEXT, enddate TEXT, billtype INTEGER, effectday TEXT,
      posflag INTEGER, scanflag INTEGER, takeoutflag INTEGER,
      applytype INTEGER, stopflag INTEGER, appflag INTEGER,
      number INTEGER, billnum INTEGER, vipflag INTEGER,
      payment REAL, discountamt REAL,
      createid TEXT, createname TEXT, updateid TEXT,
      startdateLong INTEGER, enddateLong INTEGER, updatename TEXT,
      n_discountform INTEGER, n_sellnum REAL, n_dis REAL,
      n_condition INTEGER, n_rule INTEGER, billmaxnum INTEGER
    )
    ''',
    // ──────────── 促销活动可用分类表（对齐 MPStoreType.kt）────────────
    '''
    CREATE TABLE t_mp_store_type (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, sbillid TEXT, typeid TEXT,
      createtime TEXT, updatetime TEXT
    )
    ''',
    // ──────────── 促销活动门店表（对齐 MPStore.kt）────────────
    '''
    CREATE TABLE t_mp_store (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, sbillid TEXT, billflag TEXT,
      createtime TEXT, updatetime TEXT
    )
    ''',
    // ──────────── 商品做法表（对齐 ProductCook.kt）────────────
    '''
    CREATE TABLE t_product_cook (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, productid TEXT, groupid TEXT,
      cookcode TEXT, price REAL, status INTEGER,
      mandatoryflag INTEGER, mandatoryqty REAL, maximumflag INTEGER, maximum REAL,
      ptype INTEGER, defrecommend INTEGER,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 做法信息表（对齐 CookInfo.kt）────────────
    '''
    CREATE TABLE t_cook_info (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, code TEXT, name TEXT, groupid TEXT,
      price REAL, ptype INTEGER, status INTEGER, stopflag INTEGER,
      cupstickercode TEXT, createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 做法分组表（对齐 CookGroup.kt）────────────
    '''
    CREATE TABLE t_cook_group (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, groupid TEXT, name TEXT,
      editqtyflag INTEGER, status INTEGER, isort INTEGER,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 必点菜主表（对齐 MustMaster.kt）────────────
    '''
    CREATE TABLE t_must_master (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, stopflag INTEGER,
      posflag1 INTEGER, posflag INTEGER, scanflag2 INTEGER, scanflag1 INTEGER,
      scanflag INTEGER, takeoutflag INTEGER, outcheckflag INTEGER,
      mustrule INTEGER, musttype INTEGER, appflag INTEGER, appflag1 INTEGER,
      dateflag INTEGER, checkflag INTEGER, status INTEGER,
      startdate TEXT, billid TEXT, createid TEXT, createname TEXT,
      tableareas TEXT, createtime TEXT, enddate TEXT,
      updateid TEXT, name TEXT, productnames TEXT,
      updatetime TEXT, updatename TEXT, billno TEXT, areaid TEXT,
      timeperiod1 TEXT, timeperiod2 TEXT, timeperiod3 TEXT
    )
    ''',
    // ──────────── 必点菜商品表（对齐 MustProduct.kt）────────────
    '''
    CREATE TABLE t_must_product (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, billid TEXT, productid TEXT,
      specid TEXT, specname TEXT, mustqty REAL,
      createtime TEXT, updatetime TEXT
    )
    ''',
    // ──────────── 必点菜区域表（对齐 MustTablearea.kt）────────────
    '''
    CREATE TABLE t_must_tablearea (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, billid TEXT, areaid TEXT,
      createtime TEXT, updatetime TEXT
    )
    ''',
    // ──────────── 吃法分组表（对齐 EatGroup.kt）────────────
    '''
    CREATE TABLE t_eat_group (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, groupid TEXT, name TEXT,
      status INTEGER, gisort INTEGER,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 吃法信息表（对齐 EatInfo.kt）────────────
    '''
    CREATE TABLE t_eat_info (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, code TEXT, name TEXT, groupid TEXT,
      price REAL, status INTEGER, stopflag INTEGER, groupisort INTEGER,
      createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 会员分类表（对齐 VipType.java）────────────
    '''
    CREATE TABLE t_vip_type (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, typeid TEXT, code TEXT, name TEXT,
      prefetype INTEGER, discount INTEGER,
      birthdiscount INTEGER, birthpointratio REAL,
      vipdaydiscount INTEGER, vipdaypointratio REAL,
      pointflag INTEGER, pointtype INTEGER, pointbase INTEGER,
      point REAL, salemoney REAL,
      beginpoint REAL, endpoint REAL,
      isvipmoney INTEGER, background_img TEXT, privilege_remark TEXT,
      validdays INTEGER, nowmoney REAL,
      usepointflag INTEGER, usepoints REAL, usepointtomoney REAL,
      salelimittype INTEGER, salelimitamt REAL, salelimitset REAL,
      isort INTEGER, status INTEGER,
      operid TEXT, opername TEXT,
      createtime TEXT, updatetime TEXT,
      lowaddmoney REAL, saledaycount INTEGER,
      stopflag INTEGER, validflag INTEGER,
      capitalrate REAL, giverate REAL,
      rechargeflag INTEGER, rechargetype INTEGER,
      rechargepoint REAL, rechargeamt REAL,
      fjflag INTEGER DEFAULT 0, fjfdiscount REAL DEFAULT 0
    )
    ''',
    // ──────────── 商品吃法关联表（对齐 ProductEat.kt）────────────
    '''
    CREATE TABLE t_product_eat (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      spid INTEGER, sid INTEGER, productid TEXT, groupid TEXT,
      eatcode TEXT, price REAL, defrecommend INTEGER,
      status INTEGER, createtime TEXT, updatetime TEXT, operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 系统门店表（对齐 SysStore.kt）────────────
    '''
    CREATE TABLE sys_store (
      id INTEGER PRIMARY KEY, dbid INTEGER, spid INTEGER, sid INTEGER,
      status INTEGER, isort INTEGER, stopflag INTEGER,
      dbname TEXT, account TEXT,
      daprovince TEXT, dacity TEXT, dacounty TEXT,
      linkman TEXT, linkaddr TEXT, linkmobile TEXT,
      mobilepay INTEGER, paytype INTEGER, vertype INTEGER,
      vipflag INTEGER, termmaxnum INTEGER, invitecode INTEGER,
      storemodel INTEGER, viprechargeflag INTEGER,
      scanbarcodeflag INTEGER, takeoutflag INTEGER,
      vipmallflag INTEGER, linenumberflag INTEGER,
      itemtypeconfig INTEGER, itemtypeflag INTEGER,
      miniverflag INTEGER DEFAULT 2,
      vendorcode TEXT, vendorname TEXT,
      terminalsn TEXT, terminalkey TEXT,
      registtime TEXT, validtime TEXT,
      starttime TEXT, endtime TEXT,
      trade TEXT, code TEXT, name TEXT,
      roleid TEXT, mobile TEXT,
      lng TEXT, lat TEXT,
      pwd TEXT, rfid TEXT,
      lastlogin TEXT, lastip TEXT, logincount INTEGER,
      createtime TEXT, updatetime TEXT,
      operid TEXT, opername TEXT, imgurl TEXT,
      jobid TEXT, sex INTEGER, icard TEXT,
      entrytime TEXT, birthtime TEXT,
      viewrepamtrate REAL, attendancegroupid REAL,
      areaid TEXT, proflag INTEGER,
      distpricerate REAL, distprice REAL,
      shopid TEXT, settlementflag INTEGER,
      clearalltime TEXT, termmaxnum_agent INTEGER DEFAULT 0
    )
    ''',
    // ──────────── 商品门店价格表（对齐 ProductStore.kt）────────────
    '''
    CREATE TABLE t_bi_product_store (
      id INTEGER PRIMARY KEY,
      spid INTEGER, sid INTEGER,
      stopflag INTEGER, status INTEGER,
      productid TEXT,
      inprice REAL, sellprice REAL,
      mprice1 REAL, mprice2 REAL, mprice3 REAL,
      createtime TEXT, updatetime TEXT,
      operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 系统备注表（对齐 ReasonInfo.kt）────────────
    '''
    CREATE TABLE t_bi_reason_info (
      id INTEGER PRIMARY KEY,
      spid INTEGER, sid INTEGER,
      status INTEGER,
      value TEXT, code TEXT, typeid TEXT,
      createtime TEXT, updatetime TEXT,
      operid TEXT, opername TEXT
    )
    ''',
    // ──────────── 系统用户表（对齐 SysUserBean.java）────────────
    '''
    CREATE TABLE sys_user (
      id INTEGER PRIMARY KEY,
      sid INTEGER, spid INTEGER,
      userid TEXT, code TEXT, name TEXT,
      roleid TEXT, mobile TEXT, pwd TEXT,
      stopflag INTEGER, wxopenid TEXT,
      lastlogin TEXT, lastip TEXT, logincount INTEGER,
      createtime TEXT, status INTEGER,
      updatetime TEXT, operid TEXT, opername TEXT,
      emall TEXT, rfid TEXT,
      rechargeflag INTEGER, imgurl TEXT, openid TEXT
    )
    ''',
    // ──────────── 会员信息表（对齐 VipInfo.java）────────────
    '''
    CREATE TABLE t_vip_info (
      id INTEGER PRIMARY KEY,
      spid INTEGER, sid INTEGER,
      typeid TEXT, vipid TEXT, vipno TEXT,
      vipname TEXT, mobile TEXT, address TEXT,
      password TEXT, birthday TEXT, birthdaylan TEXT,
      sex TEXT, idcardno TEXT, rfcardid TEXT,
      jscardid TEXT, wxopenid TEXT,
      validflag INTEGER, validdate TEXT,
      overflag INTEGER, overmoney REAL,
      nowpoint REAL, nowmoney REAL,
      capitalmoney REAL, givemoney REAL,
      alladdmoney REAL, allsalemoney REAL,
      pocketmoney REAL,
      usedate TEXT, refunddate TEXT, lastsaledate TEXT,
      cardstatus INTEGER, issuesid INTEGER,
      memo TEXT, status INTEGER,
      createid TEXT, createtime TEXT, updatetime TEXT,
      operid TEXT, opername TEXT, imageurl TEXT,
      usecardflag INTEGER, birthdayednum INTEGER,
      thiirdvipid TEXT, helpcode TEXT,
      regtype INTEGER, nickname TEXT, faceid TEXT,
      arrearages REAL, cardtype INTEGER
    )
    ''',
  ];
}
