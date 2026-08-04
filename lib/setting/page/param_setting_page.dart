import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 参数设置页（对齐 smdcapp SettingActivity）
/// 各项开关本地持久化，部分需同步服务端（锁台开关等）
class ParamSettingPage extends StatefulWidget {
  const ParamSettingPage({super.key});

  @override
  State<ParamSettingPage> createState() => _ParamSettingPageState();
}

class _ParamSettingPageState extends State<ParamSettingPage> {
  // ==================== 开关状态（对齐 smdcapp ConstantSetKey + SpUtils） ====================
  bool _printBill = false;       // 打印账单（MMKV print_bill）
  bool _fullPayment = true;      // 默认全款付（MMKV full_payment）
  bool _enableNfc = false;       // 开启NFC（MMKV ENABLE_NFC）
  bool _enableKd = true;         // 客单开关（MMKV ENABLE_KD）
  bool _enableProductNum = true; // 数字角标（MMKV ENABLE_PRODUCT_NUM）
  bool _reweigh = false;         // 称重二次确认（MMKV WeightTwoConfirm 字符串 "0"/"1"）
  bool _kqZj = false;            // 开启暂结（MMKV KQ_ZJ）
  bool _lockTable = false;       // 启用锁台（MMKV ClockTableFlag 字符串 "0"/"1"）
  bool _qyPrint = false;         // 接单打印聚合码（MMKV qy_print 字符串 "0"/"1"）
  bool _showWaiter = false;      // 显示服务员（MMKV setting_ShowWaiter）
  bool _productScans = false;    // 扫码点餐（MMKV setting_product_is_scans）
  bool _displayWaiter = false;   // 显示点菜人名称（MMKV setting_show_display_waiter）
  bool _showPublicCook = true;   // 显示公共做法（MMKV setting_show_public_cook 默认true）
  bool _checkDownGoods = false;  // 下单确认（MMKV setting_check_down_goods）
  bool _singleCook = true;       // 单品无需选规格（MMKV setting_single_cook 默认true）

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _printBill = SpUtil.getBool('print_bill') ?? false;
    _fullPayment = SpUtil.getBool('full_payment', defValue: true) ?? true;
    _enableNfc = SpUtil.getBool('ENABLE_NFC') ?? false;
    _enableKd = SpUtil.getBool('ENABLE_KD', defValue: true) ?? true;
    _enableProductNum = SpUtil.getBool('ENABLE_PRODUCT_NUM', defValue: true) ?? true;
    // 对齐 smdcapp SpUtils.isReweigh: MMKVUtil.decodeString("WeightTwoConfirm", "0")
    _reweigh = (SpUtil.getString('WeightTwoConfirm') ?? '0') == '1';
    _kqZj = SpUtil.getBool('KQ_ZJ') ?? false;
    // 对齐 smdcapp ConstantSetKey.QY_ST = "ClockTableFlag"
    _lockTable = (SpUtil.getString('ClockTableFlag') ?? '0') == '1';
    _qyPrint = (SpUtil.getString('qy_print') ?? '0') == '1';
    // 对齐 smdcapp SpUtils: setting_ShowWaiter / setting_product_is_scans / ...
    _showWaiter = SpUtil.getBool('setting_ShowWaiter') ?? false;
    _productScans = SpUtil.getBool('setting_product_is_scans') ?? false;
    _displayWaiter = SpUtil.getBool('setting_show_display_waiter') ?? false;
    _showPublicCook = SpUtil.getBool('setting_show_public_cook', defValue: true) ?? true;
    _checkDownGoods = SpUtil.getBool('setting_check_down_goods') ?? false;
    _singleCook = SpUtil.getBool('setting_single_cook', defValue: true) ?? true;
  }

  // ==================== 开关切换事件 ====================

  void _togglePrintBill(bool v) {
    setState(() => _printBill = v);
    SpUtil.putBool('print_bill', v);
  }

  void _toggleFullPayment(bool v) {
    setState(() => _fullPayment = v);
    SpUtil.putBool('full_payment', v);
  }

  void _toggleNfc(bool v) {
    setState(() => _enableNfc = v);
    SpUtil.putBool('ENABLE_NFC', v);
  }

  void _toggleKd(bool v) {
    setState(() => _enableKd = v);
    SpUtil.putBool('ENABLE_KD', v);
  }

  void _toggleProductNum(bool v) {
    setState(() => _enableProductNum = v);
    SpUtil.putBool('ENABLE_PRODUCT_NUM', v);
  }

  /// 称重二次确认（对齐 smdcapp SettingActivity.cl_reweigh:
  /// 先调 setDishesParams（字段"10"）同步服务端，成功后才保存本地）
  Future<void> _toggleReweigh(bool v) async {
    final String newValue = v ? '1' : '0';
    try {
      await _syncSetParams('10', <String, String>{'WeightTwoConfirm': newValue});
      SpUtil.putString('WeightTwoConfirm', newValue);
      setState(() => _reweigh = v);
      Toast.show('保存成功');
    } catch (_) {
      Toast.show('保存失败');
    }
  }

  void _toggleKqZj(bool v) {
    setState(() => _kqZj = v);
    SpUtil.putBool('KQ_ZJ', v);
  }

  /// 启用锁台（对齐 smdcapp SettingActivity.cl_qyst:
  /// 先本地保存，再调 set9Params（字段"9"）同步服务端）
  void _toggleLockTable(bool v) {
    setState(() => _lockTable = v);
    SpUtil.putString('ClockTableFlag', v ? '1' : '0');
    _syncSetParams('9', <String, String>{'ClockTableFlag': v ? '1' : '0'})
        .then((_) => Toast.show('保存成功'))
        .catchError((_) => Toast.show('保存失败'));
  }

  void _toggleQyPrint(bool v) {
    setState(() => _qyPrint = v);
    SpUtil.putString('qy_print', v ? '1' : '0');
  }

  void _toggleShowWaiter(bool v) {
    setState(() => _showWaiter = v);
    SpUtil.putBool('setting_ShowWaiter', v);
  }

  void _toggleProductScans(bool v) {
    setState(() => _productScans = v);
    SpUtil.putBool('setting_product_is_scans', v);
  }

  void _toggleDisplayWaiter(bool v) {
    setState(() => _displayWaiter = v);
    SpUtil.putBool('setting_show_display_waiter', v);
  }

  void _toggleShowPublicCook(bool v) {
    setState(() => _showPublicCook = v);
    SpUtil.putBool('setting_show_public_cook', v);
  }

  void _toggleCheckDownGoods(bool v) {
    setState(() => _checkDownGoods = v);
    SpUtil.putBool('setting_check_down_goods', v);
  }

  void _toggleSingleCook(bool v) {
    setState(() => _singleCook = v);
    SpUtil.putBool('setting_single_cook', v);
  }

  /// 同步参数到服务端（对齐 smdcapp LoginApi.setDishesParams / set9Params）
  ///
  /// 接口：POST /YttSvr/app/set/setParams（form-urlencoded + HMAC-MD5 签名）
  /// [field] 为表单字段名："9" = set9Params，"10" = setDishesParams
  /// [paramMap] 序列化为 JSON 字符串作为该字段的值，如 9={"ClockTableFlag":"1"}
  Future<void> _syncSetParams(String field, Map<String, String> paramMap) {
    return requestForm(
      HttpApi.setParams,
      <String, dynamic>{field: jsonEncode(paramMap)},
      showError: false,
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black87),
          onPressed: () => NavigatorUtils.goBack(context),
        ),
        title: const Text(
          '参数设置',
          style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          _buildSection('结账设置', [
            _buildSwitchItem('打印账单', _printBill, _togglePrintBill),
            _buildSwitchItem('默认全款付', _fullPayment, _toggleFullPayment),
            _buildSwitchItem('开启暂结', _kqZj, _toggleKqZj),
          ]),
          const SizedBox(height: 12),
          _buildSection('点菜设置', [
            _buildSwitchItem('数字角标', _enableProductNum, _toggleProductNum),
            _buildSwitchItem('客单开关', _enableKd, _toggleKd),
            _buildSwitchItem('称重二次确认', _reweigh, _toggleReweigh),
            _buildSwitchItem('显示公共做法', _showPublicCook, _toggleShowPublicCook),
            _buildSwitchItem('下单确认', _checkDownGoods, _toggleCheckDownGoods),
            _buildSwitchItem('单品无需选规格', _singleCook, _toggleSingleCook),
            _buildSwitchItem('扫码点餐', _productScans, _toggleProductScans),
          ]),
          const SizedBox(height: 12),
          _buildSection('桌台设置', [
            _buildSwitchItem('启用锁台', _lockTable, _toggleLockTable),
          ]),
          const SizedBox(height: 12),
          _buildSection('显示设置', [
            _buildSwitchItem('显示服务员', _showWaiter, _toggleShowWaiter),
            _buildSwitchItem('显示点菜人名称', _displayWaiter, _toggleDisplayWaiter),
          ]),
          const SizedBox(height: 12),
          _buildSection('其他', [
            _buildSwitchItem('开启NFC', _enableNfc, _toggleNfc),
            _buildSwitchItem('接单打印聚合码', _qyPrint, _toggleQyPrint),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchItem(String title, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFE13426),
          ),
        ],
      ),
    );
  }
}
