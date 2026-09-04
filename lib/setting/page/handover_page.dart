import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/res/constant_print_key.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/service/cash_recon_service.dart';
import 'package:flutter_deer/util/amount_calc_utils.dart';
import 'package:flutter_deer/util/print_service.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 交接班页面（对齐 YttPhone HandWordActivity）
///
/// 流程：getMaxLogoutTime → reportOnShiftByMachno → 展示 → addShifthandover → 打印 → 退出
/// 页面结构对齐 activity_hand_word.xml：
/// 交班人卡片 → 统计菜品/统计分类开关 → 销售汇总（收入/应交）→ 交班单
/// （营业门店/开始结束时间/总单数/总人数/服务费/人均消费/消费总额/低消差额
///  → 支付方式明细 → 收支合计 → 押金统计 → 菜品统计 → 分类统计）
/// → 底部：交班打印开关 + 交班按钮
class HandoverPage extends StatefulWidget {
  const HandoverPage({super.key});

  @override
  State<HandoverPage> createState() => _HandoverPageState();
}

class _HandoverPageState extends State<HandoverPage> {
  // 颜色对齐 activity_hand_word.xml
  static const Color _bgColor = Color(0xFFF9F9F9);
  static const Color _brandRed = Color(0xFFE13426);
  static const Color _textBlack = Color(0xFF000000);
  static const Color _textGray33 = Color(0xFF333333);
  static const Color _dividerColor = Color(0xFF707070);
  static const Color _rowLineColor = Color(0xFFE5E5E5);

  bool _loading = true;
  bool _submitting = false;
  String _loginTime = '';   // 开始时间（最后交班时间）
  String _logoutTime = '';  // 结束时间（当前时间）
  String _storeName = '';   // 营业门店

  // ──────────── 统计/打印开关（对齐 HandWordActivity totalpro/totalprotype/hand_print_flag）────────────
  // 统计菜品 -1 不统计 0全部（typeid 多选逗号隔开）；统计分类同理
  int _totalPro = SpUtil.getInt(ConstantPrintKey.saleProSummaryFlag) ?? -1;
  int _totalProType = SpUtil.getInt(ConstantPrintKey.saleClassSummaryFlag) ?? -1;
  // 交班打印 0不打印 1打印
  int _handPrintFlag = SpUtil.getInt(ConstantPrintKey.handPrintFlag) ?? 0;

  // ──────────── 交班数据（对齐 HandPageSumListBean / HandOtherBean）────────────
  Map<String, dynamic>? _sumData;          // sumdata 原始数据（用于提交 master / PC打印）
  List<dynamic>? _rawList;                 // list 原始数据（用于提交 details）
  List<Map<String, dynamic>> _paywayList = [];   // 支付方式明细（过滤 itype==1 && handoverflag==1）
  List<Map<String, dynamic>> _tableYjList = [];  // 桌台押金列表
  List<Map<String, dynamic>> _proList = [];      // 菜品统计列表
  List<Map<String, dynamic>> _protypeList = [];  // 分类统计列表

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ──────────── 数据加载（对齐 getloginTime → getChangeWordList）────────────

  Future<void> _loadData() async {
    try {
      // 平台分流：Web 走云接口（getMaxLogoutTime + reportOnShiftByMachno），
      // iOS/Android 走本地 SQLite 统计（对齐 YttPhone getloginTime → getChangeWordList）
      final result = await CashReconService.instance.loadHandoverData();
      _loginTime = result.logintime;
      _logoutTime = result.logouttime;
      _rawList = result.list;
      _sumData = result.sumdata;
      _parseData(_sumData);
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        Toast.show('获取交班数据失败');
        setState(() => _loading = false);
      }
    }
  }

  void _parseData(Map<String, dynamic>? sumdata) {
    if (sumdata == null) return;
    _storeName = _getStoreName();
    // 支付方式明细：过滤 itype==1 && handoverflag==1（对齐 HandWordCalcUtils.filterPaywayList）
    _paywayList = _filterPaywayList(_rawList ?? []);
    // 桌台押金列表（对齐 sumdata.tableYjList）
    if (sumdata['tableYjList'] is List) {
      _tableYjList = (sumdata['tableYjList'] as List)
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    // 菜品/分类统计列表（对齐 sumdata.prolist / protypelist）
    if (sumdata['prolist'] is List) {
      _proList = (sumdata['prolist'] as List)
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (sumdata['protypelist'] is List) {
      _protypeList = (sumdata['protypelist'] as List)
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
  }

  /// 过滤参与交班的支付方式（对齐 HandWordCalcUtils.filterPaywayList）
  List<Map<String, dynamic>> _filterPaywayList(List<dynamic> list) {
    return list
        .where((e) =>
            e is Map && _toInt(e['itype']) == 1 && _toInt(e['handoverflag']) == 1)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ──────────── 交班（对齐 reprotChangeHand → loaclHandOver → isPrint）────────────

  Future<void> _submitHandover() async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: '提示',
      content: '请确认是否现在交班？',
    );
    if (!confirmed || !mounted) return;

    // 对齐 reprotChangeHand 的两次校验
    if (_sumData == null) {
      Toast.show('请重试，未获取到交班内容！');
      return;
    }
    if (_loginTime.isEmpty) {
      Toast.show('交班时间获取错误！');
      return;
    }

    setState(() => _submitting = true);
    try {
      final String logouttime = _nowStr();
      final Map<String, dynamic> master = _buildMaster(logouttime);
      final String printtype = _handPrintFlag == 1 ? '10' : '-1';
      // 平台分流：iOS/Android 先写本地 t_sale_jkd/t_sale_jkd_detail 再云端双写；
      // Web 仅云端 addShifthandover（printtype 10交班单/-1不打印 + totalpro* 参数对齐原版）
      await CashReconService.instance.submitHandover(
        master: master,
        details: _rawList ?? <dynamic>[],
        printtype: printtype,
        totalprotype: '$_totalProType',
        totalpro: '$_totalPro',
        totalproret: '-1',
        totalpropre: '-1',
      );
      if (!mounted) return;
      Toast.show('交班成功！');
      await _isPrint();
    } catch (_) {
      // 拦截器已统一 Toast 错误信息
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// 构造交班 master（对齐 HandMasterBeanBuilder，totalreceipts = rechargesubmitamt + payableamt）
  Map<String, dynamic> _buildMaster(String logouttime) {
    final Map<String, dynamic> s = _sumData ?? <String, dynamic>{};
    final double payableamt = _toDouble(s['payableamt']);
    final double rechargesubmitamt = _toDouble(s['rechargesubmitamt']);
    return <String, dynamic>{
      'salecnt': _toDouble(s['salecnt']).toInt(),
      'returncnt': _toDouble(s['returncnt']).toInt(),
      'returnamt': _toDouble(s['returnamt']),
      'rechargeamt': _toDouble(s['rechargeamt']),
      'allpayableamt': _toDouble(s['allpayableamt']),
      'rechargesubmitamt': rechargesubmitamt,
      'reservepayamt': _toDouble(s['reservepayamt']),
      'totalreceipts': AmountCalcUtils.add(rechargesubmitamt, payableamt),
      'vipcardpayableamt': 0.0,
      'halfdraw': '',
      'saleamt': _toDouble(s['saleamt']),
      'payableamt': payableamt,
      'payamt': payableamt,
      'remark': '',
      'dutyamt': 0.0,
      'discountamt': 0.0,
      'presentqty': _toDouble(s['presentqty']),
      'presentamt': _toDouble(s['presentamt']),
      'logintime': _loginTime,
      'logouttime': logouttime,
      'flowno': s['flowno']?.toString() ?? '',
      'personnum': _toDouble(s['personnum']).toInt(),
      'serviceamt': _toDouble(s['serviceamt']),
      'lowamt': _toDouble(s['lowamt']),
      'amt': _toDouble(s['amt']),
      'perpersonprice': _toDouble(s['perpersonprice']),
    };
  }

  /// 交班后的打印处理（对齐 isPrint）
  ///
  /// 差异说明：原版本地 SQLite 交班成功后，PC 不在线/云打印时再次调用云端
  /// addShifthandover（printtype=10）触发云打印；Flutter 云模式交班数据已在
  /// 提交步骤一次写入云端（printtype 已按开关传 10/-1），无需重复提交，
  /// 避免产生重复交班记录，云端自会按 printtype 打印交班单。
  Future<void> _isPrint() async {
    // 记录交班开始时间 + 统计标志（对齐 isPrint 前两行）
    final Map<String, dynamic> sumdata = _sumData ?? <String, dynamic>{};
    sumdata['logintime'] = _loginTime;

    if (_handPrintFlag == 0) {
      // 不打印
      _endOperation();
      return;
    }
    final String type = PrintService.instance.printerType;
    if (type == 'PC打印') {
      if (ConnectionManager.pcAlive) {
        // 主设备在线：构造 PCHandTitle 并通过 /api/print/PrintHandOver 触发PC打印
        final String data = json.encode(<String, dynamic>{
          'list': _rawList ?? [],
          'sumdata': sumdata,
          'isprintpro': _totalPro == 0 ? 1 : 0,
          'isprinttype': _totalProType == 0 ? 1 : 0,
          'title': _buildPcHandTitle(),
        });
        final bool ok = await PrintService.instance.printHandOver(data);
        if (mounted) {
          Toast.show(ok ? 'PC打印发送成功!' : 'PC打印发送失败，请重试!');
        }
      } else {
        // 主设备不在线：原版走 yunPrint() 云打印，Flutter 由提交时 printtype=10 触发云端打印
        if (mounted) {
          Toast.show('PC打印失败，未连接到PC主设备');
        }
      }
    } else {
      // 云打印：提交时 printtype=10 已触发云端交班单打印
      // 蓝牙打印/接口打印：Flutter 暂未接入本地打印机，同样由云端打印兜底
    }
    _endOperation();
  }

  /// 构造 PC 打印标题（对齐 PCHandTitle）
  Map<String, dynamic> _buildPcHandTitle() {
    final Map<String, dynamic> s = _sumData ?? <String, dynamic>{};
    return <String, dynamic>{
      'storeName': _storeName,
      'machno': SpUtil.getString(Constant.machNo) ?? '',
      'logintime': _loginTime,
      'logouttime': _nowStr(),
      'opername': _getUserName(),
      'billnum': _toDouble(s['salecnt']).toInt().toString(),
      'amt': _fmt(_toDouble(s['saleamt'])),
      'personnum': _toDouble(s['personnum']).toInt().toString(),
      'perpersonprice': _fmt(_toDouble(s['perpersonprice'])),
      'serviceamt': _fmt(_toDouble(s['serviceamt'])),
      'lowamt': _fmt(_toDouble(s['lowamt'])),
    };
  }

  /// 交班完成弹窗（对齐 ExitTipDialog：不可取消 + 3秒倒计时 + 三按钮）
  void _endOperation() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HandoverDoneDialog(
        onExitApp: () => _exitToLogin(unsubscribe: false, clearPwd: false),
        onUnsubscribe: () => _exitToLogin(unsubscribe: true, clearPwd: true),
        onLogout: () => _exitToLogin(unsubscribe: false, clearPwd: true),
      ),
    );
  }

  /// 交班后退出（对齐 ExitTipDialog 三个按钮行为）
  ///
  /// [unsubscribe] 注销：清空记住的账号与密码（对齐 putBusiness/putCode/putPWD/putPhone/putLocalHost）
  /// [clearPwd] 退出登录：保留账号仅清空密码（对齐 putPWD("")）
  void _exitToLogin({required bool unsubscribe, required bool clearPwd}) {
    if (unsubscribe) {
      SpUtil.putString(Constant.rememberPhone, '');
      SpUtil.putString(Constant.rememberPhonePwd, '');
      SpUtil.putString(Constant.rememberMerchantCode, '');
      SpUtil.putString(Constant.rememberMerchantAccount, '');
      SpUtil.putString(Constant.rememberMerchantPwd, '');
      SpUtil.putBool(Constant.rememberPwdEnabled, false);
    } else if (clearPwd) {
      SpUtil.putString(Constant.rememberPhonePwd, '');
      SpUtil.putString(Constant.rememberMerchantPwd, '');
    }
    if (mounted) {
      // 清除登录缓存并回到登录页（对齐 finishAllActivity + LoginActivity）
      logoutAndRedirect(context);
    }
  }

  // ──────────── 开关交互（对齐 ivCountDish / ivCountCategory / ivPrint）────────────

  void _toggleTotalPro() {
    _totalPro = _totalPro == 0 ? -1 : 0;
    SpUtil.putInt(ConstantPrintKey.saleProSummaryFlag, _totalPro);
    setState(() {});
  }

  void _toggleTotalProType() {
    _totalProType = _totalProType == 0 ? -1 : 0;
    SpUtil.putInt(ConstantPrintKey.saleClassSummaryFlag, _totalProType);
    setState(() {});
  }

  void _togglePrintFlag() {
    _handPrintFlag = _handPrintFlag == 0 ? 1 : 0;
    SpUtil.putInt(ConstantPrintKey.handPrintFlag, _handPrintFlag);
    setState(() {});
  }

  // ──────────── UI ────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black87),
          onPressed: () => NavigatorUtils.goBack(context),
        ),
        title: const Text(
          '交接班',
          style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : Column(
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildCashierCard(),
                        _buildSwitchRow(),
                        _buildSaleSummaryCard(),
                        _buildHandoverCard(),
                      ],
                    ),
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
    );
  }

  /// 交班人卡片（对齐 activity_hand_word 第一个白色圆角卡片）
  Widget _buildCashierCard() {
    return Container(
      height: 51,
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      padding: const EdgeInsets.only(left: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.person_outline, size: 26, color: _textBlack),
          const SizedBox(width: 1),
          const Text('交班人', style: TextStyle(fontSize: 19, color: _textBlack)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 15),
              child: Text(
                _getUserName(),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 18, color: _textBlack),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 统计菜品/统计分类开关行（对齐活动页第二个白色区块）
  Widget _buildSwitchRow() {
    return Container(
      height: 43,
      margin: const EdgeInsets.fromLTRB(10, 9, 10, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              color: Colors.white,
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '统计菜品',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 19, color: _textBlack),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: _ToggleSwitch(
                      value: _totalPro == 0,
                      onTap: _toggleTotalPro,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.white,
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '统计分类',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 19, color: _textBlack),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: _ToggleSwitch(
                      value: _totalProType == 0,
                      onTap: _toggleTotalProType,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 销售汇总卡片（对齐 XML：红条标题 + 收入金额/应交金额）
  Widget _buildSaleSummaryCard() {
    // 加上本次交班剩余的押金（对齐 initView：saleamt+bcSyYjSum / payableamt+bcSyYjSum）
    final double bcSyYjSum = _toDouble(_sumData?['bcSyYjSum']);
    final double income = AmountCalcUtils.add(_toDouble(_sumData?['saleamt']), bcSyYjSum);
    final double payable = AmountCalcUtils.add(_toDouble(_sumData?['payableamt']), bcSyYjSum);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 9, 10, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: <Widget>[
          _buildSectionTitle('销售汇总'),
          _buildAmountRow('收入金额:', income),
          _buildAmountRow('应交金额:', payable),
        ],
      ),
    );
  }

  /// 交班单卡片（对齐 XML：详情行 + 支付方式 + 收支合计 + 押金 + 菜品 + 分类）
  Widget _buildHandoverCard() {
    final bool showDish = _totalPro == 0;
    final bool showCategory = _totalProType == 0;
    final bool showYj = _tableYjList.isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 9, 10, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSectionTitle('交班单'),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _rowLineColor, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _detailRow('营业门店', _storeName),
                _detailRow('开始时间', _loginTime),
                _detailRow('结束时间', _logoutTime),
                _detailRow('总单数', _toDouble(_sumData?['salecnt']).toInt().toString()),
                _detailRow('总人数', _toDouble(_sumData?['personnum']).toInt().toString()),
                _detailRow('服务费', '￥${_fmt(_toDouble(_sumData?['serviceamt']))}'),
                _detailRow('人均消费', '￥${_fmt(_toDouble(_sumData?['perpersonprice']))}'),
                _detailRow('消费总额', '￥${_fmt(_toDouble(_sumData?['amt']))}'),
                _detailRow('低消差额', '￥${_fmt(_toDouble(_sumData?['lowamt']))}'),
                // 支付方式明细（过滤 itype==1 && handoverflag==1）
                ..._paywayList.map(_buildPayWayRow),
                // 分割线
                _buildDivider(),
                // 收支合计
                _buildSumRow('收支合计：', '合计金额：￥${_fmt(_toDouble(_sumData?['payableamt']))}'),
                _buildSumRow('支付笔数：${_toDouble(_sumData?['zfcnt']).toInt()}',
                    '支付金额：￥${_fmt(_toDouble(_sumData?['zfamt']))}'),
                _buildSumRow('退款笔数：${_toDouble(_sumData?['returncnt']).toInt()}',
                    '退款金额：￥${_fmt(_toDouble(_sumData?['returnamt']))}'),
                // 押金统计（对齐 ll_yjtj：有桌台押金数据才显示）
                if (showYj) ...[
                  const _DottedLine(color: _dividerColor),
                  const Padding(
                    padding: EdgeInsets.only(left: 6, top: 5),
                    child: Text('押金统计：', style: TextStyle(fontSize: 15, color: _textBlack)),
                  ),
                  ..._tableYjList.map(_buildPayWayRow),
                  const SizedBox(height: 5),
                  const _DottedLine(color: _dividerColor),
                  const _DottedLine(color: _dividerColor),
                  const Padding(
                    padding: EdgeInsets.only(left: 6, top: 5),
                    child: Text('押金合计：', style: TextStyle(fontSize: 15, color: _textBlack)),
                  ),
                  _buildSumRow('支付笔数：${_tableYjNumSum(_tableYjList)}',
                      '金额：￥${_fmt(_tableYjMoneySum(_tableYjList))}'),
                  _buildSumRow('退款笔数：${_tableYjReturNumSum(_tableYjList)}',
                      '金额：￥${_fmt(_tableYjReturnMoneySum(_tableYjList))}'),
                  _buildSumRow('抵扣金额：￥${_fmt(_toDouble(_sumData?['dkYjSum']))}', ''),
                  _buildSumRow('剩余押金：￥${_fmt(_toDouble(_sumData?['syYjSum']))}', ''),
                  _buildDivider(),
                ],
                // 菜品统计（对齐 dishLienarLayout：totalpro==0 才显示）
                if (showDish) ...[
                  _buildHeaderRow('菜品', '数量', '金额'),
                  ..._proList.map(_buildDishRow),
                  _buildDivider(),
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('菜品合计', style: TextStyle(fontSize: 15, color: _textBlack)),
                  ),
                  _buildSumRow('数量：${_numText(_proSum()['billnum'])}',
                      '金额：￥${_fmt(_proSum()['billprice'])}'),
                ],
                // 分类统计（对齐 categoryLienarLayout：totalprotype==0 才显示）
                if (showCategory) ...[
                  _buildHeaderRow('类别', '数量', '金额'),
                  ..._protypeList.map(_buildDishRow),
                  _buildDivider(),
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('分类合计', style: TextStyle(fontSize: 15, color: _textBlack)),
                  ),
                  _buildSumRow('数量：${_numText(_protypeSum()['billnum'])}',
                      '金额：￥${_fmt(_protypeSum()['billprice'])}'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 底部：交班打印开关 + 交班按钮（对齐 ll_print）
  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: 40,
                child: Row(
                  children: <Widget>[
                    const Text('交班打印', style: TextStyle(fontSize: 19, color: _textBlack)),
                    const SizedBox(width: 3),
                    _ToggleSwitch(
                      value: _handPrintFlag == 1,
                      onTap: _togglePrintFlag,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _submitting ? null : _submitHandover,
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _brandRed,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '交班',
                    style: TextStyle(fontSize: 15, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 区块标题：红条 + 文字（对齐 XML 销售汇总/交班单标题行）
  Widget _buildSectionTitle(String title) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 2,
            height: 20,
            color: _brandRed,
          ),
          const SizedBox(width: 4),
          Text(title, style: const TextStyle(fontSize: 19, color: _textBlack)),
        ],
      ),
    );
  }

  /// 销售汇总金额行（对齐 AmountTextView/handTextView）
  Widget _buildAmountRow(String label, double value) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 19, color: _textBlack)),
          Expanded(
            child: Text(
              '￥${_fmt(value)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 20, color: _textGray33),
            ),
          ),
        ],
      ),
    );
  }

  /// 交班单详情行：label 15sp + value 16sp 右对齐，底部灰线
  Widget _detailRow(String label, String value) {
    return Container(
      height: 35,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _rowLineColor, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 15, color: _textBlack)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 16, color: _textBlack),
            ),
          ),
        ],
      ),
    );
  }

  /// 收支/合计行：左文 + 右文（对齐 tv_rramt 等 35dp 行）
  Widget _buildSumRow(String left, String right) {
    return Container(
      height: 35,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(left, style: const TextStyle(fontSize: 15, color: _textBlack)),
          ),
          if (right.isNotEmpty)
            Expanded(
              child: Text(
                right,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15, color: _textBlack),
              ),
            ),
        ],
      ),
    );
  }

  /// 支付方式行（对齐 item_hand_pay：名称 + 支付笔数/金额 + 可选退款行）
  Widget _buildPayWayRow(Map<String, dynamic> e) {
    final int rebillnum = _toInt(e['rebillnum']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 4),
          child: Text(
            e['payway']?.toString() ?? '',
            style: const TextStyle(fontSize: 15, color: _textBlack),
          ),
        ),
        Container(
          height: 35,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '支付笔数：${_toInt(e['billnum'])}',
                  style: const TextStyle(fontSize: 15, color: _textBlack),
                ),
              ),
              Expanded(
                child: Text(
                  '金额：￥${_fmt(_toDouble(e['saleamt']))}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 15, color: _textBlack),
                ),
              ),
            ],
          ),
        ),
        // 退款行：rebillnum>0 才显示（对齐 HandPayWayAdapter）
        if (rebillnum > 0)
          Container(
            height: 35,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '退款笔数：$rebillnum',
                    style: const TextStyle(fontSize: 15, color: _textBlack),
                  ),
                ),
                Expanded(
                  child: Text(
                    '金额：￥${_fmt(_toDouble(e['resaleamt']))}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 15, color: _textBlack),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 菜品/分类行（对齐 item_hand_dishes：名称/数量/金额 权重 2:1:2）
  Widget _buildDishRow(Map<String, dynamic> e) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                e['productname']?.toString() ?? e['typename']?.toString() ?? '',
                style: const TextStyle(fontSize: 15, color: _textBlack),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              _numText(_toDouble(e['qty'])),
              style: const TextStyle(fontSize: 15, color: _textBlack),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '￥${_fmt(_toDouble(e['rramt']))}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15, color: _textBlack),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 列表表头（对齐 dishLienarLayout/categoryLienarLayout 35dp 白底灰线行）
  Widget _buildHeaderRow(String c1, String c2, String c3) {
    return Container(
      height: 35,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _rowLineColor, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(c1, style: const TextStyle(fontSize: 15, color: _textBlack)),
          ),
          Expanded(
            flex: 1,
            child: Text(c2, style: const TextStyle(fontSize: 15, color: _textBlack)),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                c3,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15, color: _textBlack),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 灰色分割线（对齐 #707070 1dp 分割线）
  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: _dividerColor,
    );
  }

  // ──────────── 汇总计算（对齐 HandWordCalcUtils）────────────

  /// 押金支付笔数合计（对齐 getTableYjNumSum：sum billnum）
  int _tableYjNumSum(List<Map<String, dynamic>> list) {
    double sum = 0;
    for (final e in list) {
      sum = AmountCalcUtils.add(sum, _toDouble(e['billnum']));
    }
    return sum.toInt();
  }

  /// 押金金额合计（对齐 getTableYjMoneySum：sum saleamt）
  double _tableYjMoneySum(List<Map<String, dynamic>> list) {
    double sum = 0;
    for (final e in list) {
      sum = AmountCalcUtils.add(sum, _toDouble(e['saleamt']));
    }
    return sum;
  }

  /// 押金退款笔数合计（对齐 getTableYjReturNumSum：sum rebillnum）
  int _tableYjReturNumSum(List<Map<String, dynamic>> list) {
    double sum = 0;
    for (final e in list) {
      sum = AmountCalcUtils.add(sum, _toDouble(e['rebillnum']));
    }
    return sum.toInt();
  }

  /// 押金退款金额合计（对齐 getTableYjReturnMoneySum：sum resaleamt）
  double _tableYjReturnMoneySum(List<Map<String, dynamic>> list) {
    double sum = 0;
    for (final e in list) {
      sum = AmountCalcUtils.add(sum, _toDouble(e['resaleamt']));
    }
    return sum;
  }

  /// 菜品合计（对齐 getProductSumData：qty→billnum、rramt→billprice）
  Map<String, double> _proSum() {
    return _sumList(_proList);
  }

  /// 分类合计（对齐 getPTypeSumData）
  Map<String, double> _protypeSum() {
    return _sumList(_protypeList);
  }

  Map<String, double> _sumList(List<Map<String, dynamic>> list) {
    double qty = 0;
    double price = 0;
    for (final e in list) {
      qty = AmountCalcUtils.add(qty, _toDouble(e['qty']));
      price = AmountCalcUtils.add(price, _toDouble(e['rramt']));
    }
    return <String, double>{'billnum': qty, 'billprice': price};
  }

  // ──────────── 工具方法 ────────────

  String _getUserName() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = json.decode(userStr) as Map<String, dynamic>;
        final String name = userMap['name']?.toString() ?? userMap['username']?.toString() ?? '';
        final String code = userMap['code']?.toString() ?? '';
        return code.isNotEmpty ? '$name($code)' : name;
      }
    } catch (_) {}
    return '';
  }

  String _getStoreName() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = json.decode(storeStr) as Map<String, dynamic>;
        return storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
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

  /// 金额格式化（对齐 UIUtils.getAmtDecimal 默认保留2位小数）
  String _fmt(dynamic v) {
    return _toDouble(v).toStringAsFixed(2);
  }

  /// 数量文本：整数显示整数，小数保留2位
  String _numText(dynamic v) {
    final double d = _toDouble(v);
    return d % 1 == 0 ? d.toInt().toString() : d.toStringAsFixed(2);
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

/// 交班完成弹窗（对齐 ExitTipDialog：不可取消、3秒倒计时、关闭应用/注销登录/退出登录）
class _HandoverDoneDialog extends StatefulWidget {
  const _HandoverDoneDialog({
    required this.onExitApp,
    required this.onUnsubscribe,
    required this.onLogout,
  });

  /// 关闭应用：不清账号密码，直接回到登录页
  final VoidCallback onExitApp;

  /// 注销登录：清空当前账号及记住的密码，回到登录页
  final VoidCallback onUnsubscribe;

  /// 退出登录：保留当前登录账号，仅清空密码，回到登录页
  final VoidCallback onLogout;

  @override
  State<_HandoverDoneDialog> createState() => _HandoverDoneDialogState();
}

class _HandoverDoneDialogState extends State<_HandoverDoneDialog> {
  static const int _totalSeconds = 3;
  late int _seconds = _totalSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 倒计时结束自动退出应用（对齐 ExitTipDialog closetime=3000）
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds--);
      if (_seconds <= 0) {
        t.cancel();
        _closeAnd(widget.onExitApp);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _closeAnd(VoidCallback callback) {
    _timer?.cancel();
    Navigator.of(context).pop();
    callback();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 标题（对齐 tv_title：居中 15sp）
                const SizedBox(
                  height: 30,
                  child: Center(
                    child: Text(
                      '消息提示',
                      style: TextStyle(fontSize: 15, color: Color(0xFF000000)),
                    ),
                  ),
                ),
                // 倒计时 + 提示（对齐 tv_tip / tv_message）
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: <Widget>[
                      Container(
                        height: 35,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '在$_seconds秒后退出应用',
                          style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 35,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          '请选择退出方式？',
                          style: TextStyle(fontSize: 14, color: Color(0xFF000000)),
                        ),
                      ),
                    ],
                  ),
                ),
                // 三按钮（对齐 bt_exit_app / bt_unsubscribe / bt_log_out）
                Padding(
                  padding: const EdgeInsets.fromLTRB(5, 0, 5, 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _dialogButton('关闭应用', red: false, onTap: () => _closeAnd(widget.onExitApp)),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: _dialogButton('注销登录', red: false, onTap: () => _closeAnd(widget.onUnsubscribe)),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: _dialogButton('退出登录', red: true, onTap: () => _closeAnd(widget.onLogout)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogButton(String text, {required bool red, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: red ? const Color(0xFFE13426) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: red ? null : Border.all(color: const Color(0xFFE5E5E5), width: 1),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: red ? Colors.white : const Color(0xFF000000),
          ),
        ),
      ),
    );
  }
}

/// 开关控件（对齐 set_on/set_off：40x24 圆角轨道 + 白色圆钮，开=绿色 关=灰色）
class _ToggleSwitch extends StatelessWidget {
  const _ToggleSwitch({required this.value, required this.onTap});

  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? const Color(0xFF4CAF50) : const Color(0xFFDDDDDD),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// 横向虚线（对齐 line_dotted_bg）
class _DottedLine extends StatelessWidget {
  const _DottedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DottedLinePainter(color),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    const double dashWidth = 4;
    const double dashSpace = 4;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter oldDelegate) => color != oldDelegate.color;
}
