import 'dart:math';

import 'package:intl/intl.dart';

import 'app_database.dart';

/// 交班记录写入 DAO（对齐 YttPhone CashReconService.addShifthandover +
/// reportOnShiftByMachno 交班单号生成）
///
/// - [getMaxFlowno]：今日最大流水号 +1，生成 "CC" + store + machno + yyMMdd + 4位流水
/// - [saveHandover]：写 t_sale_jkd（master 补 flowid/flowno/createtime/operid/
///   opername/machno/spid/sid，对齐 addShifthandover），details 补
///   spid/sid/flowid/flowno + 数字兜底，80 条一批写 t_sale_jkd_detail
class HandoverRecordDao {
  HandoverRecordDao._();

  static final HandoverRecordDao instance = HandoverRecordDao._();

  final AppDatabase _db = AppDatabase.instance;

  /// 生成交班单号（对齐 reportOnShiftByMachno 172-195 行）
  ///
  /// 查询当天（logintime>=今天00:00:00 且 logouttime<今天23:59:59.999）
  /// 最大 flowno，取末 4 位流水 +1，无记录时从 0001 开始。
  Future<String> getMaxFlowno({
    required String spid,
    required String sid,
    required String store,
    required String machno,
  }) async {
    final DateTime now = DateTime.now();
    final String dt = DateFormat('yyyy-MM-dd').format(now);
    final String sdt = DateFormat('yyMMdd').format(now);
    final String startdt = '$dt 00:00:00';
    final String enddt = '$dt 23:59:59.999';
    final Map<String, dynamic>? smap = await _db.queryOne(
      'select max(flowno) as billno from t_sale_jkd '
      'where spid = ? and sid = ? and logintime>=? AND logouttime<? '
      'and flowno like ? and machno=?',
      <Object?>[
        spid,
        sid,
        startdt,
        enddt,
        'CC$store$machno%',
        machno,
      ],
    );
    String billno = smap?['billno']?.toString() ?? '';
    if (billno.isEmpty) {
      billno = '0001';
    } else {
      billno = billno.substring(billno.length - 4);
      final int next = (int.tryParse(billno) ?? 0) + 1;
      billno = next.toString().padLeft(4, '0');
    }
    return 'CC$store$machno$sdt$billno';
  }

  /// 保存交班记录（对齐 addShifthandover：先写主表再写明细）
  ///
  /// [master] 需含 logintime/logouttime 及页面组装字段；flowno 为空时
  /// 自动调用 [getMaxFlowno] 生成（[store] 为门店 code）。
  Future<void> saveHandover({
    required Map<String, dynamic> master,
    required List<dynamic> details,
    required String spid,
    required String sid,
    required String operid,
    required String opername,
    required String machno,
    required String store,
  }) async {
    final Map<String, dynamic> row = Map<String, dynamic>.from(master);
    // 主表补齐（对齐 addShifthandover 77-84 行）
    String flowno = row['flowno']?.toString() ?? '';
    if (flowno.isEmpty) {
      flowno = await getMaxFlowno(
          spid: spid, sid: sid, store: store, machno: machno);
    }
    row['spid'] = spid;
    row['sid'] = sid;
    row['flowid'] = _genFlowId(operid);
    row['flowno'] = flowno;
    row['createtime'] =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    row['operid'] = operid;
    row['opername'] = opername;
    row['machno'] = machno;
    // 整型兜底（对齐 addShifthandover 93-96 行）
    for (final String key in <String>['personnum', 'reservecnt', 'salecnt', 'returncnt']) {
      row[key] = _toInt(row[key]);
    }
    await _db.insert('t_sale_jkd', row);

    // 明细补齐（对齐 addShifthandover 108-123 行）
    final List<Map<String, dynamic>> detailRows = <Map<String, dynamic>>[];
    for (final dynamic d in details) {
      if (d is! Map) {
        continue;
      }
      final Map<String, dynamic> item = Map<String, dynamic>.from(d);
      if ((item['paywayid']?.toString() ?? '').isEmpty) {
        continue;
      }
      item['spid'] = spid;
      item['sid'] = sid;
      item['flowid'] = row['flowid'];
      item['flowno'] = flowno;
      item['saleamt'] = _toDouble(item['saleamt']);
      item['payableamt'] = _toDouble(item['payableamt']);
      item['payamt'] = _toDouble(item['payamt']);
      item['givemoney'] = _toDouble(item['givemoney']);
      item['billnum'] = _toInt(item['billnum']);
      item['rebillnum'] = _toInt(item['rebillnum']);
      detailRows.add(item);
    }
    // 80 条一批（对齐 addShifthandover 125-137 行）
    for (int j = 0; j < detailRows.length; j += 80) {
      final int end = j + 80 > detailRows.length ? detailRows.length : j + 80;
      await _db.batchInsert('t_sale_jkd_detail', detailRows.sublist(j, end));
    }
  }

  /// 生成 flowid（对齐 StringUtils.getMainId：yyMMddHHmmssSSS + 操作码后2位 + 3位随机）
  String _genFlowId(String operid) {
    final String time = DateFormat('yyMMddHHmmssSSS').format(DateTime.now());
    String code = operid;
    if (code.length >= 2) {
      code = code.substring(code.length - 2);
    } else {
      code = code.padLeft(2, '0');
    }
    const String chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890';
    final Random random = Random();
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 3; i++) {
      sb.write(chars[random.nextInt(chars.length)]);
    }
    return '$time$code$sb';
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

  int _toInt(dynamic v) {
    if (v == null) {
      return 0;
    }
    if (v is num) {
      return v.toInt();
    }
    return int.tryParse(v.toString()) ?? 0;
  }
}
