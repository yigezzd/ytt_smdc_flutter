import 'dart:io';

import 'package:flutter_deer/db/app_database.dart';
import 'package:flutter_deer/db/cash_recon_dao.dart';
import 'package:flutter_deer/db/handover_record_dao.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/service/cash_recon_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sp_util/sp_util.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 交班统计回测（对齐 YttPhone 口径）
///
/// 场景：
/// - 开台落单结账 S001：菜品A×2、B×1、C×1，退菜A×1（presentflag=2），
///   折扣 5，现金 35 + 微信 30 结账，应收 65
/// - 被撤原单 S003（billflag=2）：菜品D×5，金额 50，不得计入任何统计
/// - 撤单流水 S004（opertype=3/status=3/billflag=2）：金额 -50，
///   计入撤单统计（withdrawcnt/withdrawamt），不计入销售/菜品统计
/// - 会员充值 2 笔：现金 500 送 50（givemoney=50）、微信 300 不送
String _fmt(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 本地 SQLite（sqflite_common_ffi）替代移动端插件
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    // 模拟登录态（对齐 Constant 键名）
    SharedPreferences.setMockInitialValues(<String, Object>{
      Constant.user: '{"userid":"U01","code":"UC01","name":"测试员"}',
      Constant.store: '{"spid":"1","id":"2","name":"测试门店"}',
      Constant.machNo: 'M01',
      Constant.storeCode: 'ST01',
    });
    await SpUtil.getInstance();
    // 强制走本地 SQLite 统计路径（对齐主设备模式，避免发起云端请求）
    ConnectionManager.pcAlive = true;
    // 清理历史测试库，保证 onCreate 全新建表
    final String dir = await sqflite.databaseFactory.getDatabasesPath();
    for (final String name in <String>[
      'catering.db',
      'catering.db-wal',
      'catering.db-shm',
    ]) {
      final File f = File('$dir${Platform.pathSeparator}$name');
      if (f.existsSync()) {
        f.deleteSync();
      }
    }
  });

  test('回测：开台落单结账+退菜+撤单+会员充值 → 交班统计与交班落库', () async {
    final AppDatabase db = AppDatabase.instance;
    final DateTime now = DateTime.now();
    final String tSale = _fmt(now.subtract(const Duration(hours: 2)));
    final String tVip = _fmt(now.subtract(const Duration(hours: 1)));

    // ──────────── 基础表 ────────────
    for (final Map<String, dynamic> p in <Map<String, dynamic>>[
      <String, dynamic>{
        'spid': 1, 'sid': 2, 'payid': '01', 'name': '现金', 'code': '01',
        'rate': 1.0, 'handoverflag': 1, 'status': 1,
      },
      <String, dynamic>{
        'spid': 1, 'sid': 2, 'payid': '02', 'name': '微信', 'code': '02',
        'rate': 1.0, 'handoverflag': 1, 'status': 1,
      },
      <String, dynamic>{
        'spid': 1, 'sid': 2, 'payid': '06', 'name': '减免', 'code': '06',
        'rate': 1.0, 'handoverflag': 0, 'status': 1,
      },
    ]) {
      await db.insert('t_bi_payway', p);
      await db.insert('t_bi_payway_store', p);
    }
    await db.insert('t_bi_type', <String, dynamic>{
      'spid': 1, 'sid': 2, 'typeid': 'T1', 'name': '热菜', 'status': 1,
    });
    await db.insert('t_bi_type', <String, dynamic>{
      'spid': 1, 'sid': 2, 'typeid': 'T2', 'name': '凉菜', 'status': 1,
    });
    await db.insert('t_bi_parameter', <String, dynamic>{
      'spid': 1, 'sid': 2, 'type': 0,
      'code': 'AmountHandleType', 'value': '1', 'remark': 'M01',
    });

    // ──────────── 销售主表 ────────────
    Map<String, dynamic> master(
      String saleid,
      String billno,
      String tableid,
      double amt,
      int status,
      int opertype,
      int billflag, {
      double dscamt = 0,
      double retailamt = 0,
      String? returnbillno,
    }) =>
        <String, dynamic>{
          'spid': 1, 'sid': 2, 'saleid': saleid, 'billno': billno,
          'billdate': tSale, 'tableid': tableid, 'personnum': 2,
          'amt': amt, 'dscamt': dscamt, 'payment': amt, 'billtype': 7,
          'cashid': 'U01', 'cashname': '测试员',
          'serverid': 'U01', 'servername': '测试员',
          'machno': 'M01', 'createtime': tSale, 'updatetime': tSale,
          'status': status, 'opertype': opertype, 'retailamt': retailamt,
          'changeamt': 0.0, 'roundamt': 0.0, 'billflag': billflag,
          'lowamt': 0.0, 'serviceamt': 0.0,
          if (returnbillno != null) 'returnbillno': returnbillno,
        };
    // 正常结账单：应收 65 = 零售 100 - 折扣 5 - 退菜 30
    await db.insert('t_sale_master',
        master('S001', 'B001', 'T01', 65, 1, 1, 0, dscamt: 5, retailamt: 100));
    // 被撤原单（billflag=2，status=3）
    await db.insert('t_sale_master',
        master('S003', 'B003', 'T03', 50, 3, 1, 2, retailamt: 50));
    // 撤单流水（opertype=3/status=3，金额取负，对齐 WithdrawDialog 落库约定）
    await db.insert('t_sale_master', master('S004', 'B004', 'T03', -50, 3, 3, 2,
        retailamt: -50, returnbillno: 'B003'));

    // ──────────── 销售明细 ────────────
    Map<String, dynamic> detail(
      String saleid,
      String billno,
      String productid,
      String productname,
      String typeid,
      String typename,
      double qty,
      double rramt,
      int presentflag,
      int seq,
    ) =>
        <String, dynamic>{
          'spid': 1, 'sid': 2, 'saleid': saleid, 'billno': billno,
          'productid': productid, 'productname': productname,
          'typeid': typeid, 'typename': typename,
          'qty': qty, 'sellprice': 30.0, 'rrprice': 30.0, 'rramt': rramt,
          'presentflag': presentflag, 'seq': seq, 'createtime': tSale,
        };
    await db.batchInsert('t_sale_detail', <Map<String, dynamic>>[
      detail('S001', 'B001', 'PA', '菜品A', 'T1', '热菜', 2, 60, 0, 1),
      detail('S001', 'B001', 'PB', '菜品B', 'T1', '热菜', 1, 20, 0, 2),
      detail('S001', 'B001', 'PC', '菜品C', 'T2', '凉菜', 1, 20, 0, 3),
      // 退菜行（presentflag=2，数量/金额取负）
      detail('S001', 'B001', 'PA', '菜品A', 'T1', '热菜', -1, -30, 2, 4),
      detail('S003', 'B003', 'PD', '菜品D', 'T2', '凉菜', 5, 50, 0, 1),
      // 撤单流水明细（原单菜品取负，presentflag=2）
      detail('S004', 'B004', 'PD', '菜品D', 'T2', '凉菜', -5, -50, 2, 1),
    ]);

    // ──────────── 支付方式 ────────────
    Map<String, dynamic> payway(
      String saleid,
      String payid,
      String payname,
      double rramt,
      int paystatus,
    ) =>
        <String, dynamic>{
          'spid': 1, 'sid': 2, 'saleid': saleid, 'payid': payid,
          'payname': payname, 'payamt': rramt, 'rate': 1.0, 'rramt': rramt,
          'paystatus': paystatus, 'createtime': tSale, 'machno': 'M01',
        };
    await db.batchInsert('t_sale_payway', <Map<String, dynamic>>[
      payway('S001', '01', '现金', 35, 1),
      payway('S001', '02', '微信', 30, 1),
      payway('S003', '01', '现金', 50, 1),
      // 撤单流水支付方式（金额取负，paystatus=2，对齐 WithdrawDialog）
      payway('S004', '01', '现金', -50, 2),
    ]);

    // ──────────── 会员充值 ────────────
    await db.batchInsert('t_vip_money_detail', <Map<String, dynamic>>[
      <String, dynamic>{
        'spid': 1, 'sid': 2, 'vipid': 'V1', 'vipno': 'V001', 'vipname': '张三',
        'addmoney': 500.0, 'givemoney': 50.0, 'decmoney': 0.0,
        'endmoney': 500.0, 'payid': '01', 'payname': '现金',
        'operid': 'U01', 'opername': '测试员', 'machno': 'M01',
        'opertype': 1, 'createtime': tVip, 'memo': '',
      },
      <String, dynamic>{
        'spid': 1, 'sid': 2, 'vipid': 'V2', 'vipno': 'V002', 'vipname': '李四',
        'addmoney': 300.0, 'givemoney': 0.0, 'decmoney': 0.0,
        'endmoney': 300.0, 'payid': '02', 'payname': '微信',
        'operid': 'U01', 'opername': '测试员', 'machno': 'M01',
        'opertype': 1, 'createtime': tVip, 'memo': '',
      },
    ]);

    // ──────────── 交班数据加载 ────────────
    final result = await CashReconService.instance.loadHandoverData();
    final Map<String, dynamic> s = result.sumdata;
    final List<dynamic> list = result.list;

    // 班次起点 = 最早结账时间（无历史交班记录）
    expect(result.logintime, tSale);

    // 销售汇总（billflag=2 的被撤原单/撤单流水不计入）
    expect(s['billnum'], 1.0, reason: '有效单数');
    expect(s['amt'], 65.0, reason: '消费总额');
    expect(s['personnum'], 2.0, reason: '消费人数');
    expect(s['perpersonprice'], 32.5, reason: '人均');

    // 单数/撤单/退菜（互相独立的口径）
    expect(s['salecnt'], 1, reason: '交班单数不含撤单记录');
    expect(s['withdrawcnt'], 1, reason: '撤单笔数');
    expect(s['withdrawamt'], 50.0, reason: '撤单金额取绝对值');
    expect(s['returncnt'], 1.0, reason: '退菜笔数');
    expect(s['returnamt'], 30.0, reason: '退菜金额取绝对值');

    // 收款/应交/充值
    expect(s['saleamt'], 65.0, reason: '收款合计');
    expect(s['payableamt'], 65.0, reason: '应交合计');
    expect(s['rechargeamt'], 800.0, reason: '充值合计 500+300');
    expect(s['rechargesubmitamt'], 800.0, reason: '充值应交');
    expect(s['allpayableamt'], 865.0, reason: '应交总金额 = 65 + 800');

    // 折扣/支付单数
    expect(s['dscamt'], 5.0, reason: '折扣合计');
    expect(s['zfcnt'], 1, reason: '支付单数');
    expect(s['zfamt'], 65.0, reason: '支付金额');

    // 交班单号走本地生成（CC+门店编码+机号+日期+流水）
    expect(s['flowno'], startsWith('CCST01M01'));

    // ──────────── 支付方式列表（销售 2 行 + 充值 2 行）────────────
    expect(list.length, 4, reason: '撤单/被撤原单支付方式不入列表');
    Map<String, dynamic> row(String itype, String paywayid) => list
        .cast<Map<String, dynamic>>()
        .firstWhere((Map<String, dynamic> m) =>
            m['itype']?.toString() == itype &&
            m['paywayid']?.toString() == paywayid);
    final Map<String, dynamic> r1 = row('1', '01');
    expect(r1['saleamt'], 35.0, reason: '现金收款');
    expect(r1['payableamt'], 35.0);
    expect(r1['billnum'], 1);
    expect(r1['givemoney'], 0.0);
    final Map<String, dynamic> r2 = row('1', '02');
    expect(r2['saleamt'], 30.0, reason: '微信收款');
    expect(r2['payableamt'], 30.0);
    final Map<String, dynamic> v1 = row('2', '01');
    expect(v1['saleamt'], 500.0, reason: '现金充值');
    expect(v1['givemoney'], 50.0, reason: '充值赠送金额');
    expect(v1['payableamt'], 500.0, reason: '现金充值应交');
    final Map<String, dynamic> v2 = row('2', '02');
    expect(v2['saleamt'], 300.0, reason: '微信充值');
    expect(v2['givemoney'], 0.0);
    expect(v2['payableamt'], 300.0);

    // ──────────── 菜品统计 ────────────
    final List<Map<String, dynamic>> prolist =
        (s['prolist'] as List).cast<Map<String, dynamic>>();
    Map<String, dynamic> pro(String name) => prolist
        .firstWhere((Map<String, dynamic> m) => m['productname'] == name);
    expect(prolist.length, 3,
        reason: '被撤原单/撤单流水的菜品D（billflag=2）不得计入');
    expect(pro('菜品A')['qty'], 1.0, reason: '菜品A 2份-退1份');
    expect(pro('菜品A')['rramt'], 30.0, reason: '菜品A 60-退30');
    expect(pro('菜品A')['typename'], '热菜');
    expect(pro('菜品B')['qty'], 1.0);
    expect(pro('菜品B')['rramt'], 20.0);
    expect(pro('菜品C')['qty'], 1.0);
    expect(pro('菜品C')['rramt'], 20.0);
    expect(pro('菜品C')['typename'], '凉菜');
    expect(
        prolist.any((Map<String, dynamic> m) => m['productname'] == '菜品D'),
        isFalse);

    // ──────────── 退菜统计 ────────────
    // 对齐 YttPhone getReturnProSummary：按 presentflag=2 汇总，不过滤 billflag
    // （撤单流水明细会出现在退菜统计中，与 YttPhone SQL 原样一致）
    final List<Map<String, dynamic>> retlist =
        (s['returnprolist'] as List).cast<Map<String, dynamic>>();
    expect(retlist.length, 2);
    final Map<String, dynamic> retA = retlist
        .firstWhere((Map<String, dynamic> m) => m['productname'] == '菜品A');
    expect(retA['qty'], -1.0);
    expect(retA['rramt'], -30.0);
    final Map<String, dynamic> retD = retlist
        .firstWhere((Map<String, dynamic> m) => m['productname'] == '菜品D');
    expect(retD['qty'], -5.0);
    expect(retD['rramt'], -50.0);

    // ──────────── 分类统计（对齐 getSaleProTypeSummary）────────────
    final List<Map<String, dynamic>> typeList =
        await CashReconDao.instance.getSaleProTypeSummary(
      logintime: result.logintime,
      logouttime: result.logouttime,
      spid: '1',
      sid: '2',
      machno: 'M01',
      cashid: 'U01',
    );
    expect(typeList.length, 2);
    final Map<String, dynamic> hot = typeList
        .firstWhere((Map<String, dynamic> m) => m['typename'] == '热菜');
    expect(hot['qty'], 2.0, reason: '热菜 1+1 份');
    expect(hot['rramt'], 50.0, reason: '热菜 30+20 元');
    final Map<String, dynamic> cold = typeList
        .firstWhere((Map<String, dynamic> m) => m['typename'] == '凉菜');
    expect(cold['qty'], 1.0);
    expect(cold['rramt'], 20.0);
    // 若 billflag 过滤失效，菜品D 5份/50元 会混入凉菜（qty=6/rramt=70）
    expect(
        typeList.any((Map<String, dynamic> m) => m['qty'] == 6.0), isFalse);

    // ──────────── 交班提交落库 ────────────
    await HandoverRecordDao.instance.saveHandover(
      master: s,
      details: list,
      spid: '1',
      sid: '2',
      operid: 'U01',
      opername: '测试员',
      opercode: 'UC01',
      machno: 'M01',
      store: 'ST01',
    );

    final Map<String, dynamic>? jkd = await db.queryOne(
      'select * from t_sale_jkd where flowno = ?',
      <Object?>[s['flowno']],
    );
    expect(jkd, isNotNull);
    expect(jkd!['salecnt'], 1);
    expect(jkd['returncnt'], 1);
    expect(jkd['returnamt'], 30.0);
    expect(jkd['rechargeamt'], 800.0);
    expect(jkd['rechargesubmitamt'], 800.0);
    expect(jkd['saleamt'], 65.0);
    expect(jkd['payableamt'], 65.0);
    expect(jkd['amt'], 65.0);
    expect(jkd['personnum'], 2);
    expect(jkd['perpersonprice'], 32.5);
    expect(jkd['operid'], 'U01');
    expect(jkd['opername'], '测试员');
    expect(jkd['machno'], 'M01');
    expect(jkd['logintime'], tSale);
    expect(jkd['flowno'], s['flowno']);
    // flowid = yyMMddHHmmssSSS + 操作员code后2位 + 3位随机
    expect(jkd['flowid'], matches(RegExp(r'^\d{15}01\w{3}$')));

    final List<Map<String, dynamic>> jkdDetails = await db.queryList(
      'select * from t_sale_jkd_detail where flowno = ?',
      <Object?>[s['flowno']],
    );
    expect(jkdDetails.length, 4);
    final Map<String, dynamic> jv1 = jkdDetails.firstWhere(
        (Map<String, dynamic> m) =>
            m['itype']?.toString() == '2' && m['paywayid'] == '01');
    expect(jv1['saleamt'], 500.0);
    expect(jv1['givemoney'], 50.0, reason: '交班明细赠送金额');
    expect(jv1['flowno'], s['flowno']);
    expect(jv1['flowid'], jkd['flowid']);
    final Map<String, dynamic> jr1 = jkdDetails.firstWhere(
        (Map<String, dynamic> m) =>
            m['itype']?.toString() == '1' && m['paywayid'] == '01');
    expect(jr1['saleamt'], 35.0);
    expect(jr1['payableamt'], 35.0);
    expect(jr1['billnum'], 1);
  });
}
