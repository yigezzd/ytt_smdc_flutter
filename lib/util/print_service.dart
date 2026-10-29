import 'dart:convert';

import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant_print_key.dart';
import 'package:flutter_deer/util/log_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
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
  /// [withLabel] 本批含杯贴商品（明细 labelflag==1）时，云打印模式随出品单
  ///   补发杯贴(14)通知（对齐 smdcapp createPrintInfo 下单成功后默认附带杯贴票据）
  /// 在 order_confirm_page 下单成功后调用
  Future<bool> triggerCookPrint({
    required String saleid,
    required String billno,
    bool withKd = true,
    bool withCpd = true,
    bool withCpdBranch = false,
    bool withLabel = false,
  }) async {
    if (isPcPrint) {
      // PC模式：下单时 printtype/printkdflag/printcpdflag 已传给主设备，由 PC 出票
      return true;
    }
    if (isCloudPrint) {
      // R28/R47：服务端 restPrint 支持按 saleid+opertype 重建票据。
      // 15=客单，3=出品单，23=出品分单，14=杯贴
      bool ok = false;
      if (withKd) {
        ok = await cloudReprint(
                saleid: saleid, billno: billno, opertype: '15') ||
            ok;
      }
      if (withCpd) {
        ok = await cloudReprint(
                saleid: saleid, billno: billno, opertype: '3') ||
            ok;
      }
      if (withCpdBranch) {
        await cloudReprint(saleid: saleid, billno: billno, opertype: '23');
      }
      if (withLabel) {
        await cloudReprint(saleid: saleid, billno: billno, opertype: '14');
      }
      return ok;
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
      // 结账单：服务端按 saleid 重建票据（restPrint），不再只发通知
      return cloudReprint(saleid: saleid, billno: billno, opertype: '2');
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

  /// 预打单打印（对齐 smdcapp 预打流程 postInfo("8")）
  ///
  /// 主设备模式：对齐 OrderModel.ydPC → POST /api/print/RePrint，
  ///   参数 tablemaster = PCMasterBean JSON（tableMaster + detailList），
  ///   由主设备按预打单（打印类型8）出票
  /// 云服务模式：对齐 sendPrint → printMsgNotice 推送云打印任务，opertype=8（预打单）
  ///   （主单/明细已由 upSaleMasterTmp printtype=8 printalltype=1 上传）
  Future<bool> prePrint({
    required String saleid,
    String billno = '',
    String pcMasterJson = '',
  }) async {
    try {
      if (ConnectionManager.pcAlive) {
        await requestForm(HttpApi.pcRePrint, <String, dynamic>{
          'tablemaster': pcMasterJson,
        }, masterDevice: true);
        return true;
      }
      // 预打单：服务端按 saleid 重建票据（restPrint opertype=8）
      return cloudReprint(saleid: saleid, billno: billno, opertype: '8');
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

  /// 押金单打印/补打（对齐 smdcapp JYJPopup.PcSendPrint / YJOrderActivity：
  /// PC 模式 POST /api/print/PrintDepositInfo，data=押金单 JSON）
  Future<bool> printDeposit(String data) async {
    // R23/R24：有主设备地址时优先走 PC 打印接口（云服务模式下前台仍可出押金单）；
    // 无主设备时回退云打印（opertype=13 押金单）
    final bool canPc = ConnectionManager.pcAlive ||
        ConnectionManager.getLocalhost().startsWith('http');
    if (canPc) {
      try {
        await requestForm(
          HttpApi.pcPrintDepositInfo,
          <String, dynamic>{'data': data},
          masterDevice: true,
        );
        return true;
      } catch (e) {
        Log.e('PrintService.printDeposit pc error: $e');
      }
    }
    try {
      final Map<String, dynamic> bean =
          json.decode(data) as Map<String, dynamic>;
      final String saleid = bean['saleid']?.toString() ?? '';
      final String billno = bean['billno']?.toString() ??
          bean['billno']?.toString() ??
          '';
      if (saleid.isEmpty && billno.isEmpty) return false;
      await requestForm(HttpApi.restPrint, <String, dynamic>{
        'jobcontent': saleid.isNotEmpty ? saleid : billno,
        'opertype': '13',
        'billno': billno,
      });
      return true;
    } catch (e) {
      Log.e('PrintService.printDeposit cloud error: $e');
      return false;
    }
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
  /// 云打印重打/补打（对齐 smdcapp OrderModel.restPrint：jobcontent=saleid）
  ///
  /// 服务端按 saleid + opertype 重建单据内容，支持 3出品单/6挂起单/7起菜单/
  /// 13押金单/15客单/21转菜单 等类型。
  Future<bool> cloudReprint({
    required String saleid,
    required String billno,
    required String opertype,
  }) async {
    try {
      await requestForm(HttpApi.restPrint, <String, dynamic>{
        'jobcontent': saleid,
        'opertype': opertype,
        'billno': billno,
      });
      _offlineNotified = false;
      retryPending();
      return true;
    } catch (e) {
      Log.e('PrintService.cloudReprint error: $e');
      // R25：打印机离线时提示并缓存任务，待后续打印恢复后补发
      _cachePendingJob(saleid: saleid, billno: billno, opertype: opertype);
      return false;
    }
  }

  static const String _pendingPrintKey = 'pending_print_jobs';
  static bool _offlineNotified = false;

  /// 缓存未成功的打印任务（R25）
  void _cachePendingJob({
    required String saleid,
    required String billno,
    required String opertype,
  }) {
    if (saleid.isEmpty && billno.isEmpty) return;
    try {
      final String raw = SpUtil.getString(_pendingPrintKey) ?? '';
      final List<dynamic> list =
          raw.isEmpty ? <dynamic>[] : (json.decode(raw) as List<dynamic>);
      final Map<String, dynamic> job = <String, dynamic>{
        'saleid': saleid,
        'billno': billno,
        'opertype': opertype,
        'time': DateTime.now().millisecondsSinceEpoch,
      };
      final bool exists = list.any((dynamic e) =>
          e is Map &&
          e['saleid'] == saleid &&
          e['opertype'] == opertype &&
          e['billno'] == billno);
      if (!exists) {
        list.add(job);
        SpUtil.putString(_pendingPrintKey, json.encode(list));
      }
      if (!_offlineNotified) {
        _offlineNotified = true;
        Toast.show('打印机离线，打印任务已缓存，恢复后将自动补打');
      }
    } catch (_) {}
  }

  /// 补发缓存的打印任务（R25）
  Future<void> retryPending() async {
    try {
      final String raw = SpUtil.getString(_pendingPrintKey) ?? '';
      if (raw.isEmpty) return;
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      if (list.isEmpty) return;
      final List<dynamic> remain = <dynamic>[];
      for (final dynamic e in list) {
        if (e is! Map) continue;
        final String saleid = e['saleid']?.toString() ?? '';
        final String billno = e['billno']?.toString() ?? '';
        final String opertype = e['opertype']?.toString() ?? '';
        try {
          await requestForm(HttpApi.restPrint, <String, dynamic>{
            'jobcontent': saleid,
            'opertype': opertype,
            'billno': billno,
          });
        } catch (_) {
          remain.add(e);
        }
      }
      SpUtil.putString(_pendingPrintKey, json.encode(remain));
    } catch (_) {}
  }

  Future<bool> cloudPrintNotice({
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
      Log.e('PrintService.cloudPrintNotice error: $e');
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
