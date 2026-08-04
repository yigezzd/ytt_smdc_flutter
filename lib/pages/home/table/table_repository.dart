import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';

/// 桌台数据仓库（对齐 smdcapp TableDao 的双模式分发逻辑）
///
/// 根据 [masterDevice]（即 ConnectionManager.pcAlive）决定走云服务还是主设备：
/// - 云服务：路径 `/table/xxx`，响应 `{retcode, retmsg, data:{list:[]}}`
/// - 主设备：路径 `/api/table/xxx`，响应 `{Success, Message, Data}`（区域 Data 为数组，桌台 Data.tableMasterTmpList）
class TableRepository {
  TableRepository._();

  /// 查询桌台区域列表
  ///
  /// 对齐 smdcapp TableDao.getAreaList：
  /// stopflag=0、is_page=2、page=1、pagesize=99、infototalflag=1（含各区域桌台数量与状态统计）
  static Future<List<TableArea>> fetchAreaList({
    required bool masterDevice,
    String name = '',
  }) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'stopflag': '0',
      'name': name,
      'is_page': 2,
      'page': 1,
      'pagesize': 99,
      'infototalflag': 1,
      // 云服务额外携带排序字段（对齐 smdcapp TableHttpUtil.getAreaList）
      if (!masterDevice) 'field': 'isort',
      if (!masterDevice) 'type': 'asc',
    };

    final String url =
        masterDevice ? HttpApi.pcTableAreaList : HttpApi.tableAreaList;
    final Map<String, dynamic> resp = await requestForm(
      url,
      params,
      masterDevice: masterDevice,
      showError: false,
    );

    final List<dynamic> rawList = _extractAreaList(resp, masterDevice);
    return rawList
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> e) =>
            TableArea.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 查询桌台信息列表
  ///
  /// 对齐 smdcapp TableDao.getTableList：
  /// is_page=1、areastatus=1（启用区域）、stopflag=0（启用桌台）、infototalflag=1
  static Future<List<TableInfo>> fetchTableInfoList({
    required bool masterDevice,
    String areaid = '',
    String tablestatus = '',
    int page = 1,
    int pagesize = 100,
    String cond = '',
    bool showPrePrintOnly = false,
  }) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'is_page': 1,
      'page': page,
      'pagesize': pagesize,
      'tableid': '',
      'areaid': areaid,
      'tablestatus': tablestatus,
      'areastatus': '1',
      'stopflag': '0',
      'tabletypeid': '',
      'infototalflag': '1',
      if (masterDevice) 'showpreprintonly': showPrePrintOnly,
      if (!masterDevice) 'field': 'isort',
      if (!masterDevice) 'type': 'asc',
      if (!masterDevice) 'cond': cond,
      if (!masterDevice) 'preprintflag': showPrePrintOnly ? '1' : '',
    };

    final String url =
        masterDevice ? HttpApi.pcTableInfoList : HttpApi.tableInfoList;
    final Map<String, dynamic> resp = await requestForm(
      url,
      params,
      masterDevice: masterDevice,
      showError: false,
    );

    final List<dynamic> rawList = _extractTableList(resp, masterDevice);
    return rawList
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> e) =>
            TableInfo.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 提取区域数组
  ///
  /// 主设备：`Data` 直接为数组（PCRootDataListBean）；
  /// 云服务：`data.list` 为数组（RootDataBean<PageListBean>）。
  static List<dynamic> _extractAreaList(
      Map<String, dynamic> resp, bool masterDevice) {
    if (masterDevice) {
      final dynamic data = resp['Data'];
      return data is List ? data : <dynamic>[];
    }
    final dynamic data = resp['data'];
    if (data is Map) {
      final dynamic list = data['list'];
      return list is List ? list : <dynamic>[];
    }
    return <dynamic>[];
  }

  /// 提取桌台数组
  ///
  /// 主设备：`Data.tableMasterTmpList`（PCTableDataBTOBean）；
  /// 云服务：`data.list`（PageListBean）。
  static List<dynamic> _extractTableList(
      Map<String, dynamic> resp, bool masterDevice) {
    if (masterDevice) {
      final dynamic data = resp['Data'];
      if (data is Map) {
        final dynamic list = data['tableMasterTmpList'];
        return list is List ? list : <dynamic>[];
      }
      return <dynamic>[];
    }
    final dynamic data = resp['data'];
    if (data is Map) {
      final dynamic list = data['list'];
      return list is List ? list : <dynamic>[];
    }
    return <dynamic>[];
  }
}
