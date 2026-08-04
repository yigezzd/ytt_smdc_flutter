import 'dart:convert';

import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant_print_key.dart';
import 'package:flutter_deer/util/log_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 打印服务（对齐 smdcapp 打印体系）
///
/// 支持两种打印模式：
/// - PC打印：通过主设备 /api/print/* 接口触发PC端打印
/// - 云打印：通过 YttSvr /print/* 接口触发云打印机
///
/// 打印触发时机（对齐 smdcapp）：
/// - 下单确认 → 出品单(厨打) printalltype=3
/// - 结账完成 → 结账单 printalltype=2
/// - 退菜 → 退菜单 printalltype=4
/// - 催菜 → 催菜单 printalltype=5
/// - 起菜 → 起菜单 printalltype=7
/// - 预打 → 预打单 printalltype=8
/// - 客单补打 → 客单 printalltype=15
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  // ──────────── 配置读取 ─────────────────────────────────────────

  /// 获取当前打印类型（PC打印/云打印/蓝牙打印/接口打印）
  String get printerType {
    return SpUtil.getString(ConstantPrintKey.printerType) ??
        ConstantPrintKey.defaultPrinterType;
  }

  /// 设置打印类型
  void setPrinterType(String type) {
    SpUtil.putString(ConstantPrintKey.printerType, type);
  }

  /// 是否为PC打印模式
  bool get isPcPrint => printerType == 'PC打印';

  /// 是否为云打印模式
  bool get isCloudPrint => printerType == '云打印';

  /// 获取打印纸规格（58mm/80mm）
  String get printSize {
    return SpUtil.getString(ConstantPrintKey.printSizeJz) ?? '58mm';
  }

  /// 获取票尾走纸行数
  int get feedLineCount {
    return SpUtil.getInt(ConstantPrintKey.ticketFeedLine) ?? 0;
  }

  /// 获取结账打印份数
  int get settlePrintCopies {
    return SpUtil.getInt(ConstantPrintKey.printNumJz) ?? 1;
  }

  /// 获取客单打印份数
  int get kdPrintCopies {
    return SpUtil.getInt(ConstantPrintKey.printNumKd) ?? 1;
  }

  /// 获取厨打份数
  int get cookPrintCopies {
    return SpUtil.getInt(ConstantPrintKey.printNumCd) ?? 1;
  }

  /// 结账打印是否自动（true=自动, false=询问）
  bool get isSettleAutoPrint {
    final v = SpUtil.getInt(ConstantPrintKey.printInquiryJz) ?? 1;
    return v == 1;
  }

  /// 客单打印是否自动
  bool get isKdAutoPrint {
    final v = SpUtil.getInt(ConstantPrintKey.printInquiryKd) ?? 1;
    return v == 1;
  }

  /// 厨打是否自动
  bool get isCookAutoPrint {
    final v = SpUtil.getInt(ConstantPrintKey.printInquiryCd) ?? 1;
    return v == 1;
  }

  /// 获取选中的云打印机信息
  Map<String, dynamic>? get yunPrintInfo {
    final s = SpUtil.getString(ConstantPrintKey.yunPrintInfo) ?? '';
    if (s.isEmpty) return null;
    try {
      return json.decode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 获取云打印机名称
  String get yunPrintName {
    return yunPrintInfo?['name']?.toString() ?? '';
  }

  // ──────────── 打印触发（业务层调用）─────────────────

  /// 下单后触发出品单/厨打（对齐 smdcapp upSaleMasterTmp printtype 参数）
  ///
  /// [printtype] 对应 printalltype: 3=出品单
  /// 在 order_confirm_page 下单成功后调用
  Future<bool> triggerCookPrint({
    required String saleid,
    required String billno,
  }) async {
    if (isPcPrint) {
      // PC模式：下单时 printtype 参数已传给主设备，主设备自动处理厨打
      // 无需额外调用
      return true;
    }
    if (isCloudPrint) {
      return _cloudPrintNotice(saleid: saleid, billno: billno, opertype: '3');
    }
    return false;
  }

  /// 结账后触发结账单打印（对齐 smdcapp saleflow printtype=2）
  ///
  /// 在 settle_page 结账成功后调用
  Future<bool> triggerSettlePrint({
    required String saleid,
    required String billno,
    String data = '',
  }) async {
    if (isPcPrint && ConnectionManager.pcAlive) {
      return _pcPrintPayInfo(data);
    }
    if (isCloudPrint) {
      return _cloudPrintNotice(saleid: saleid, billno: billno, opertype: '2');
    }
    return false;
  }

  /// 重打客单（对齐 smdcapp restPrint / restPrintPC）
  ///
  /// [billno] 单号
  /// [opertype] 操作类型（15=客单）
  Future<bool> reprintCustomerTicket({
    required String billno,
    String opertype = '15',
    String jobcontent = '',
  }) async {
    try {
      if (isPcPrint && ConnectionManager.pcAlive) {
        // 主设备模式：调用 /api/print/PrintKDInfo
        await requestForm(HttpApi.pcPrintKDInfo, <String, dynamic>{
          'billno': billno,
          'opertype': opertype,
        }, masterDevice: true);
        return true;
      }
      // 云服务模式：调用 /print/restPrint
      await requestForm(HttpApi.restPrint, <String, dynamic>{
        'jobcontent': jobcontent,
        'opertype': opertype,
        'billno': billno,
      });
      return true;
    } catch (e) {
      Log.e('PrintService.reprintCustomerTicket error: $e');
      return false;
    }
  }

  /// 预打（对齐 smdcapp updateMasterTmpPrePrintFlag + RePrint）
  Future<bool> prePrint({required String saleid}) async {
    try {
      if (ConnectionManager.pcAlive) {
        await requestForm(HttpApi.pcRePrint, <String, dynamic>{
          'saleid': saleid,
          'preprintflag': '1',
        }, masterDevice: true);
      } else {
        await requestForm(HttpApi.updateMasterTmpPrePrintFlag, <String, dynamic>{
          'saleid': saleid,
          'preprintflag': '1',
        });
      }
      return true;
    } catch (e) {
      Log.e('PrintService.prePrint error: $e');
      return false;
    }
  }

  /// 暂结打印（对齐 smdcapp PrintTempPayInfo）
  Future<bool> printTempPayInfo(String data) async {
    if (isPcPrint && ConnectionManager.pcAlive) {
      return _pcPrintTempPayInfo(data);
    }
    return false;
  }

  /// 交班打印（对齐 smdcapp PCSetApi /api/print/PrintHandOver）
  Future<bool> printHandOver(String data) async {
    if (isPcPrint && ConnectionManager.pcAlive) {
      try {
        await requestForm(HttpApi.pcPrintHandOver, <String, dynamic>{
          'data': data,
        }, masterDevice: true);
        return true;
      } catch (e) {
        Log.e('PrintService.printHandOver error: $e');
        return false;
      }
    }
    return false;
  }

  // ──────────── 云打印管理 ─────────────────────────────────────────

  /// 获取云打印机列表（对齐 smdcapp SetApi getYunPrintList）
  Future<List<dynamic>> getCloudPrinterList() async {
    try {
      final resp = await requestForm(HttpApi.printGetList, <String, dynamic>{});
      // requestForm 失败时抛异常，到达此处即为成功
      final dynamic data = resp['data'];
      if (data is List) return data;
      if (data is Map<String, dynamic> && data['list'] is List) {
        return data['list'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      Log.e('PrintService.getCloudPrinterList error: $e');
      return [];
    }
  }

  /// 绑定云打印机（对齐 smdcapp SetApi addYunPrint）
  Future<bool> bindCloudPrinter(Map<String, dynamic> params) async {
    try {
      await requestForm(HttpApi.bindPrint, params);
      // requestForm 失败时抛异常，到达此处即为成功
      return true;
    } catch (e) {
      Log.e('PrintService.bindCloudPrinter error: $e');
      return false;
    }
  }

  /// 解绑云打印机（对齐 smdcapp SetApi delYunPrint）
  Future<bool> unbindCloudPrinter(Map<String, dynamic> params) async {
    try {
      await requestForm(HttpApi.unBindPrint, params);
      // requestForm 失败时抛异常，到达此处即为成功
      return true;
    } catch (e) {
      Log.e('PrintService.unbindCloudPrinter error: $e');
      return false;
    }
  }

  /// 云打印测试（对齐 smdcapp SetApi testYunPrint）
  Future<bool> testCloudPrinter(Map<String, dynamic> params) async {
    try {
      await requestForm(HttpApi.printTest, params);
      // requestForm 失败时抛异常，到达此处即为成功
      return true;
    } catch (e) {
      Log.e('PrintService.testCloudPrinter error: $e');
      return false;
    }
  }

  // ──────────── 内部方法 ─────────────────────────────────────────

  /// 云打印通知（对齐 smdcapp DishesApi printMsgNotice）
  Future<bool> _cloudPrintNotice({
    required String saleid,
    required String billno,
    required String opertype,
  }) async {
    try {
      final data = json.encode({
        'saleid': saleid,
        'billno': billno,
        'opertype': opertype,
      });
      await requestForm(HttpApi.printMsgNotice, <String, dynamic>{
        'data': data,
      });
      return true;
    } catch (e) {
      Log.e('PrintService._cloudPrintNotice error: $e');
      return false;
    }
  }

  /// PC打印结账信息（对齐 smdcapp SettleApi /api/print/PrintPayInfo）
  Future<bool> _pcPrintPayInfo(String data) async {
    try {
      await requestForm(HttpApi.pcPrintPayInfo, <String, dynamic>{
        'data': data,
      }, masterDevice: true);
      return true;
    } catch (e) {
      Log.e('PrintService._pcPrintPayInfo error: $e');
      return false;
    }
  }

  /// PC暂结打印（对齐 smdcapp SettleApi /api/print/PrintTempPayInfo）
  Future<bool> _pcPrintTempPayInfo(String data) async {
    try {
      await requestForm(HttpApi.pcPrintTempPayInfo, <String, dynamic>{
        'data': data,
      }, masterDevice: true);
      return true;
    } catch (e) {
      Log.e('PrintService._pcPrintTempPayInfo error: $e');
      return false;
    }
  }
}
