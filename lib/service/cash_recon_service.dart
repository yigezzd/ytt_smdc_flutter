import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/db/base_data_dao.dart';
import 'package:flutter_deer/db/cash_recon_dao.dart';
import 'package:flutter_deer/db/handover_record_dao.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/res/constant_print_key.dart';
import 'package:sp_util/sp_util.dart';

/// 交班服务门面（对齐 YttPhone CashReconService）
///
/// 平台分流：
/// - Web（[isLocal] == false）→ 云接口，现有逻辑不变
/// - iOS/Android（[isLocal] == true）→ 本地 sqflite DAO + 云端双写
class CashReconService {
  CashReconService._();

  static final CashReconService instance = CashReconService._();

  /// 是否走本地 SQLite（iOS/Android 为 true；Web 为 false）
  static bool get isLocal => !kIsWeb;

  // ──────────── 交班数据加载 ────────────

  /// 加载交班数据（按平台分流）
  ///
  /// 返回 {list: 支付方式明细, sumdata: 汇总, logintime, logouttime}，
  /// list/sumdata 字段名与云接口响应一致，页面 _parseData 无需改动。
  ///
  /// 移动端结算数据在服务端（本地 t_sale_* 仅离线/主设备场景写入），
  /// 因此优先取云端交班报表；云端为空或失败时回退本地 DAO 汇总。
  Future<
      ({
        Map<String, dynamic> sumdata,
        List<dynamic> list,
        String logintime,
        String logouttime,
      })> loadHandoverData() async {
    if (isLocal) {
      try {
        final cloud = await _loadHandoverCloud();
        if (cloud.list.isNotEmpty || cloud.sumdata.isNotEmpty) {
          return cloud;
        }
      } catch (_) {
        // 云端不可用时回退本地
      }
      return _loadHandoverLocal();
    }
    return _loadHandoverCloud();
  }

  /// Web：云端 getMaxLogoutTime + reportOnShiftByMachno（现有逻辑不变）
  Future<
      ({
        Map<String, dynamic> sumdata,
        List<dynamic> list,
        String logintime,
        String logouttime,
      })> _loadHandoverCloud() async {
    // 注意：cashrecon 系接口必须走 requestForm（form-urlencoded + 公共参数 + HMAC 签名）
    final Map<String, dynamic> timeResult = await requestForm(
        HttpApi.getMaxLogoutTime, <String, dynamic>{},
        showError: false);
    final String maxTime = timeResult['data']?.toString() ?? '';
    final String loginTime =
        maxTime.isNotEmpty ? maxTime : '${_today()} 00:00:00';
    final String logoutTime = _nowStr();
    final Map<String, dynamic> result = await requestForm(
      HttpApi.reportOnShift,
      <String, dynamic>{
        'cashid': _getUserId(),
        'logintime': loginTime,
        'logouttime': logoutTime,
        'proflag': 1,
        'typeflag': 0,
        'retireflag': 1,
      },
    );
    final Map<String, dynamic>? data = result['data'] is Map
        ? Map<String, dynamic>.from(result['data'] as Map)
        : null;
    return (
      sumdata: data?['sumdata'] is Map
          ? Map<String, dynamic>.from(data!['sumdata'] as Map)
          : <String, dynamic>{},
      list: data?['list'] is List ? data!['list'] as List : <dynamic>[],
      logintime: loginTime,
      logouttime: logoutTime,
    );
  }

  /// iOS/Android：本地流程（对齐 YttPhone reportOnShiftByMachno）
  Future<
      ({
        Map<String, dynamic> sumdata,
        List<dynamic> list,
        String logintime,
        String logouttime,
      })> _loadHandoverLocal() async {
    final CashReconDao dao = CashReconDao.instance;
    final String spid = _getSpid();
    final String sid = _getSid();
    final String machno = SpUtil.getString(Constant.machNo) ?? '';
    final String store = SpUtil.getString(Constant.storeCode) ?? '';
    final String operid = _getUserId();

    // 基础表为空时自动重试一次同步（对齐计划：交班查询时 t_bi_payway 为空重试）
    if (await BaseDataDao.instance.isPaywayEmpty()) {
      await syncBaseData();
    }

    // 1. logintime（对齐 HandWordActivity.getloginTime）
    final String maxTime = await dao.getMaxLogoutTime(
        spid: spid, sid: sid, operid: operid, machno: machno);
    String selltime = await dao.getSaleMaterMaxTime(
        maxTime: maxTime, spid: spid, sid: sid, machno: machno);
    if (selltime.isEmpty) {
      // 没有交班时间就取第一次结账时间；仍空则取今天 00:00:00
      selltime = '${_today()} 00:00:00';
    }
    final String vipMoneytime = await dao.getVipMoneyMaterMaxTime(
        maxTime: maxTime, spid: spid, sid: sid, machno: machno);
    final String depositflowtime = await dao.getDepositFlowMaxTime(
        maxTime: maxTime, spid: spid, sid: sid, machno: machno);
    // eqTimeBaset 逐对取最早
    final String tempTime =
        _eqTimeBaset(depositflowtime, vipMoneytime);
    final String tempTime2 = _eqTimeBaset(selltime, tempTime);
    final String logintime = _formatTime(tempTime2);
    final String logouttime = _nowStr();

    // 2. 生成交班单号（对齐 reportOnShiftByMachno 172-195 行）
    final String flowno = await HandoverRecordDao.instance.getMaxFlowno(
        spid: spid, sid: sid, store: store, machno: machno);
    final Map<String, dynamic> master = <String, dynamic>{
      'flowno': flowno,
      'logintime': logintime,
      'logouttime': logouttime,
    };

    // 3. 销售汇总（对齐 214-220 行，数字兜底）
    final Map<String, dynamic>? summarydata = await dao.getSummaryData(
      logintime: logintime,
      logouttime: logouttime,
      spid: spid,
      sid: sid,
      machno: machno,
      cashid: operid,
    );
    if (summarydata != null) {
      for (final String key in <String>[
        'billnum',
        'amt',
        'personnum',
        'perpersonprice',
        'lowamt',
        'serviceamt',
      ]) {
        summarydata[key] = _toDouble(summarydata[key]);
      }
    }

    // 4. 交班 4 段 UNION 汇总（对齐 223-231 行，数字兜底）
    final List<Map<String, dynamic>> list = await dao.reportOnShiftByMachno(
      logintime: logintime,
      logouttime: logouttime,
      spid: spid,
      sid: sid,
      machno: machno,
      cashid: operid,
    );
    for (final Map<String, dynamic> map in list) {
      map['resaleamt'] = _toDouble(map['resaleamt']);
      map['saleamt'] = _toDouble(map['saleamt']);
      map['billnum'] = _toInt(map['billnum']);
      map['rebillnum'] = _toInt(map['rebillnum']);
      map['givemoney'] = _toDouble(map['givemoney']);
      map['payableamt'] = _toDouble(map['payableamt']);
    }

    // 5. 销售流水列表（对齐 236-242 行）
    final List<Map<String, dynamic>> salejdklist =
        await dao.salejdklistByMachno(
      logintime: logintime,
      logouttime: logouttime,
      spid: spid,
      sid: sid,
      machno: machno,
      cashid: operid,
    );
    for (final Map<String, dynamic> map in salejdklist) {
      map['dscamt'] = _toDouble(map['dscamt']);
      map['amt'] = _toDouble(map['amt']);
      map['retailamt'] = _toDouble(map['retailamt']);
      map['roundamt'] = _toDouble(map['roundamt']);
    }
    master['salecnt'] = salejdklist.length;

    // 6. 金额汇总（对齐 244-368 行；币种抹零参数 AmountHandleType，
    //    list 中 payid 字段实际不存在，两分支对 itype==1 的统计行为等价）
    final String amountHandleType = _getParamValue(
      await dao.getParam(
          spid: spid, sid: sid, machno: machno, namelist: const <String>['AmountHandleType']),
      'AmountHandleType',
    );
    double saleamt = 0; // 收款合计
    double payableamt = 0; // 应交合计
    double rechargeamt = 0; // 充值
    double rechargesubmitamt = 0; // 充值应交
    double reservepayamt = 0; // 预订应交
    double reserveamt = 0; // 预订总
    double allpayableamt = 0; // 应交总金额
    for (final Map<String, dynamic> item in list) {
      final String itype = item['itype']?.toString() ?? '';
      final String handoverflag = item['handoverflag']?.toString() ?? '';
      final double sale = _toDouble(item['saleamt']);
      final double resale = _toDouble(item['resaleamt']);
      if (amountHandleType != '0' || itype == '1') {
        // 分支A（AmountHandleType==0）排除 payid=06，因 list 无 payid 字段恒为真
        if (itype == '1') {
          saleamt = _rd2(saleamt + sale + resale);
        }
      }
      // 充值
      if (itype == '2') {
        rechargeamt = _rd2(rechargeamt + sale + resale);
      }
      // 预订
      if (itype == '10') {
        reserveamt = _rd2(reserveamt + sale + resale);
      }
      // 应交（handoverflag=1）
      if (handoverflag == '1') {
        allpayableamt = _rd2(allpayableamt + sale + resale);
        if (itype == '1') {
          payableamt = _rd2(payableamt + sale + resale);
        }
        if (itype == '2') {
          rechargesubmitamt = _rd2(rechargesubmitamt + sale + resale);
        }
        if (itype == '10') {
          reservepayamt = _rd2(reservepayamt + sale + resale);
        }
      }
    }
    master['rechargeamt'] = rechargeamt;
    master['rechargesubmitamt'] = rechargesubmitamt;
    master['payableamt'] = payableamt;
    master['saleamt'] = saleamt;
    master['reservepayamt'] = reservepayamt;
    master['reserveamt'] = reserveamt;
    master['allpayableamt'] = allpayableamt;

    // 退菜/折扣/支付笔数（对齐 333-368 行）
    final List<Map<String, dynamic>> returnlist = salejdklist
        .where((Map<String, dynamic> m) => m['opertype']?.toString() == '3')
        .toList();
    master['returncnt'] = returnlist.length;
    double returnamt = 0;
    for (final Map<String, dynamic> r in returnlist) {
      returnamt = _rd2(returnamt + _toDouble(r['amt']));
    }
    master['returnamt'] = returnamt;
    double dscamt = 0;
    for (final Map<String, dynamic> r in salejdklist) {
      dscamt = _rd2(dscamt + _toDouble(r['dscamt']));
    }
    master['dscamt'] = dscamt;
    final List<Map<String, dynamic>> zflist = salejdklist
        .where((Map<String, dynamic> m) => m['opertype']?.toString() == '1')
        .toList();
    master['zfcnt'] = zflist.length;
    double zfamt = 0;
    for (final Map<String, dynamic> r in zflist) {
      zfamt = _rd2(zfamt + _toDouble(r['amt']));
    }
    master['zfamt'] = zfamt;

    // 7. 汇总合并（对齐 371-373 行）
    if (summarydata != null) {
      master.addAll(summarydata);
    }

    // 8. 菜品统计（proflag=1，对齐 375-383 行）
    final List<String> proTypeList = await dao.getHandoverType(
        spid: spid, sid: sid, machno: machno, typeflag: 1);
    master['prolist'] = await dao.getSaleProSummary(
      logintime: logintime,
      logouttime: logouttime,
      spid: spid,
      sid: sid,
      machno: machno,
      cashid: operid,
      sorttype: '',
      typelist: proTypeList,
    );

    // 9. 退菜统计（retireflag=1，对齐 392-396 行）
    master['returnprolist'] = await dao.getReturnProSummary(
      logintime: logintime,
      logouttime: logouttime,
      spid: spid,
      sid: sid,
      machno: machno,
      cashid: operid,
    );

    // 10. 预订金（对齐 398-406 行；t_reserve_master 为空表）
    final Map<String, dynamic>? reserveSumdata = await dao.reserveSumdata(
      logintime: logintime,
      logouttime: logouttime,
      spid: spid,
      sid: sid,
      machno: machno,
      cashid: operid,
    );
    if (reserveSumdata != null) {
      reserveSumdata['reservepayamt'] = _toDouble(reserveSumdata['reservepayamt']);
      master.addAll(reserveSumdata);
    }
    master['reservelist'] = await dao.getReserveList(
      logintime: logintime,
      logouttime: logouttime,
      spid: spid,
      sid: sid,
      machno: machno,
      cashid: operid,
    );

    // 11. 押金（对齐 408-421 行）
    master['tableYjList'] = await dao.getTableYjSum(
        logintime: logintime, logouttime: logouttime, spid: spid, sid: sid);
    master['syYjSum'] = await dao.getSyYjSum();
    master['bcSyYjSum'] = await dao.getBcSyYjSum(
        logintime: logintime, logouttime: logouttime);
    master['dkYjSum'] = await dao.getDkYjSum(
        logintime: logintime, logouttime: logouttime);

    return (sumdata: master, list: list, logintime: logintime, logouttime: logouttime);
  }

  // ──────────── 交班提交 ────────────

  /// 提交交班（按平台分流）
  ///
  /// - iOS/Android：先写本地 t_sale_jkd/t_sale_jkd_detail（对齐 addShifthandover，
  ///   80 条一批），再调云端 addShifthandover（双写，云端交班记录/云打印保留）
  /// - Web：仅云端 addShifthandover
  Future<void> submitHandover({
    required Map<String, dynamic> master,
    required List<dynamic> details,
    required String printtype,
    required String totalprotype,
    required String totalpro,
    required String totalproret,
    required String totalpropre,
  }) async {
    if (isLocal) {
      await HandoverRecordDao.instance.saveHandover(
        master: master,
        details: details,
        spid: _getSpid(),
        sid: _getSid(),
        operid: _getUserId(),
        opername: _getUserName(),
        machno: SpUtil.getString(Constant.machNo) ?? '',
        store: SpUtil.getString(Constant.storeCode) ?? '',
      );
    }
    // 云端双写（对齐原版参数：master/details + printtype + totalpro*）
    await requestForm(
      HttpApi.addShifthandover,
      <String, dynamic>{
        'master': jsonEncode(master),
        'details': jsonEncode(details),
        'printtype': printtype,
        'totalprotype': totalprotype,
        'totalpro': totalpro,
        'totalproret': totalproret,
        'totalpropre': totalpropre,
      },
    );
  }

  // ──────────── 基础数据同步 ────────────

  /// 登录成功后同步基础表（仅 iOS/Android，失败静默）
  ///
  /// getPayInfoList → t_bi_payway/t_bi_payway_store；getTypeList → t_bi_type；
  /// t_bi_parameter 写入交班开关当前值（code=开关名/remark=machno）。
  Future<void> syncBaseData() async {
    if (!isLocal) {
      return;
    }
    // 支付方式
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getPayInfoList,
        <String, dynamic>{
          'cond': '',
          'stopflag': '0',
          'pagesize': '100',
          'field': 'isort',
          'type': 'asc',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map) {
        final dynamic list = data['list'];
        if (list is List) {
          await BaseDataDao.instance.savePayways(
              list
                  .whereType<Map<dynamic, dynamic>>()
                  .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
                  .toList());
        }
      }
    } catch (_) {}
    // 商品分类
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getTypeList,
        <String, dynamic>{},
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map) {
        final dynamic children = data['children'];
        if (children is List) {
          await BaseDataDao.instance.saveTypes(
              children
                  .whereType<Map<dynamic, dynamic>>()
                  .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
                  .toList());
        }
      }
    } catch (_) {}
    // 交班参数开关
    try {
      final String spid = _getSpid();
      final String sid = _getSid();
      final String machno = SpUtil.getString(Constant.machNo) ?? '';
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        _paramRow(spid, sid, machno, ConstantPrintKey.saleProSummaryFlag),
        _paramRow(spid, sid, machno, ConstantPrintKey.saleClassSummaryFlag),
        _paramRow(spid, sid, machno, ConstantPrintKey.handPrintFlag),
      ];
      await BaseDataDao.instance.saveParameters(rows);
    } catch (_) {}
  }

  /// 组装参数行（对齐 Parameter 实体：type=0，remark=machno）
  Map<String, dynamic> _paramRow(
      String spid, String sid, String machno, String code) {
    return <String, dynamic>{
      'spid': spid,
      'sid': sid,
      'type': 0,
      'code': code,
      'value': '${SpUtil.getInt(code) ?? 0}',
      'remark': machno,
    };
  }

  // ──────────── 工具方法（对齐 HandWordActivity / DateUtils）────────────

  /// 取两个时间中最早（对齐 DateUtils.eqTimeBaset：空则返回另一个，都空返回当前时间）
  String _eqTimeBaset(String strTime, String edTime) {
    if (strTime.isEmpty) {
      return edTime.isEmpty ? _nowStr() : edTime;
    }
    if (edTime.isEmpty) {
      return strTime;
    }
    final DateTime a = DateTime.tryParse(strTime) ?? DateTime.now();
    final DateTime b = DateTime.tryParse(edTime) ?? DateTime.now();
    return a.isBefore(b) ? strTime : edTime;
  }

  /// 截取到秒（对齐 DateUtils.formatTime(YYYYMMDDHHMMSS)）
  String _formatTime(String t) {
    if (t.length > 19) {
      return t.substring(0, 19);
    }
    return t;
  }

  /// 两位小数向下取整（对齐 BigDecimal.setScale(2, ROUND_DOWN)）
  double _rd2(double v) => (v * 100).floorToDouble() / 100;

  /// getParam 结果中取指定 code 的 value
  String _getParamValue(List<Map<String, dynamic>> rows, String code) {
    for (final Map<String, dynamic> r in rows) {
      if (r['code']?.toString() == code) {
        return r['value']?.toString() ?? '';
      }
    }
    return '';
  }

  String _today() {
    final DateTime now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _nowStr() {
    final DateTime now = DateTime.now();
    return '${_today()} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  String _getUserId() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        return userMap['userid']?.toString() ?? '0';
      }
    } catch (_) {}
    return '0';
  }

  String _getUserName() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        final String name =
            userMap['name']?.toString() ?? userMap['username']?.toString() ?? '';
        final String code = userMap['code']?.toString() ?? '';
        return code.isNotEmpty ? '$name($code)' : name;
      }
    } catch (_) {}
    return '';
  }

  String _getSpid() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap['spid']?.toString() ?? '0';
      }
    } catch (_) {}
    return '0';
  }

  String _getSid() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap['id']?.toString() ?? '0';
      }
    } catch (_) {}
    return '0';
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
