/// 桌台数据构建工具（对齐 smdcapp TableInfoBean 序列化逻辑）
///
/// 主设备模式接口需要提交完整桌台数据（克隆 + 白名单过滤），
/// 本工具类提供默认结构、深度合并、字段白名单过滤等公共方法，
/// 供 order_page（修改开台信息）和 table_operation_dialog（锁台/消台等）复用。
class TableDataUtils {
  TableDataUtils._();

  /// 构建完整的 tmp 默认结构（对齐接口文档 UpdateSaleMasterTmp 的 masterTmpDto.tmp 全字段）
  ///
  /// 服务端 .NET 模型字段缺失时为 null，访问会抛 NullReferenceException，
  /// 因此必须提供完整默认值，再用实际数据覆盖。
  static Map<String, dynamic> defaultTmp() => <String, dynamic>{
        'm_resevrestatus': 0,
        'spid': 0,
        'sid': 0,
        'saleid': '',
        'billno': '',
        'billdate': '',
        'tableid': '',
        'tablecode': '',
        'tablename': '',
        'tableno': '',
        'arrearages': '',
        'tablestatus': 0,
        'tablestatusText': '',
        'vipid': '',
        'vipno': '',
        'vipname': '',
        'vipmobile': '',
        'retailamt': '',
        'dscamt': '',
        'amt': '',
        'addamt': '',
        'payment': '',
        'changeamt': '',
        'billtype': 0,
        'lastbilltype': 0,
        'mallbillid': '',
        'makedataflag': 0,
        'upflag': 0,
        'cashid': '',
        'cashname': '',
        'serverid': '',
        'servername': '',
        'machno': '',
        'takeouttype': 0,
        'localbillno': '',
        'returnbillno': '',
        'personnum': 0,
        'person': 0,
        'dataiflag': 0,
        'unitableid': '',
        'unitableno': '',
        'allunitablenames': '',
        'dataitableid': '',
        'serviceamt': '',
        'remark': '',
        'lockflag': 0,
        'tabletypeid': '',
        'openMinutes': '',
        'rate': '',
        'showamt': '',
        'showPayment': '',
        'showDueinamt': '',
        'dueinamt': '',
        'removeZero': '',
        'roundamt': '',
        'handRemoveZeroAmt': '',
        'lowamt': '',
        'opertype': 0,
        'paytime': '',
        'cxreduceamt': '',
        'takeoutpayamt': '',
        'deliverfee': '',
        'operremark': '',
        'operamt': '',
        'qty': '',
        'rowcount': '',
        'unitablename': '',
        'billflag': 0,
        'tablenobyinput': 0,
        'prodchgflag': 0,
        'realbillno': '',
        'ordernumber': '',
        'printremark': '',
        'takeout': 0,
        'takeoutsort': 0,
        'togoinfo': '',
        'togoflag': 0,
        'resevrestatus': 0,
        'resevremsg': '',
        'resevreVisibility': 0,
        'totalretailamt': '',
        'detailList': <dynamic>[],
        'hangflag': 0,
        'takecode': '',
        'customername': '',
        'tel': '',
        'address': '',
        'psprice': '',
        'bagamt': '',
        'takeoutfavour': '',
        'shopfavour': '',
        'mealtype': 0,
        'printkdflag': 0,
        'printcpdflag': 0,
        'oldtablename': '',
        'oldtablecode': '',
        'newtablename': '',
        'newtablecode': '',
        'newtableid': '',
        'prnretflag': 0,
        'prnpreflag': 0,
        'onlinecode': '',
        'hasdecamt': '',
        'ispaying': '',
        'reRalcPriceFlag': '',
        'printjzflag': 0,
        'confirmqty': '',
        'weightinfo': '',
        'containweight': 0,
        'opermachno': '',
        'delivertime': '',
        'servicebegintime': '',
        'serviceendtime': '',
        'fornowamt': '',
        'fornowlowamt': '',
        'fornowdscamt': '',
        'fornowserviceamt': '',
        'printtype': 0,
        'sendprintflag': 0,
        'depositAmt': '',
        'additionid': '',
        'servicediscount': '',
        'servicetimerange': '',
        'cdflag': 0,
        'cxmbillid': '',
        'retailamtByServiceFeeFlag': '',
        'amtByServiceFeeFlag': '',
        'paymachno': '',
        'uniflowno': 0,
        'uniflownoText': '',
        'orderid': '',
        'wxclientbillno': '',
        'billretflag': 0,
        'ordercreatetime': '',
        'intOpenMinutes': 0,
        'warnedcount': 0,
        'lastwarntime': '',
        'taxrate': '',
        'serviceamtByHand': '',
        'preprintflag': 0,
        'wxpaytype': 0,
        'wxterminalsn': '',
        'wxterminalkey': '',
        'id': 0,
        'status': 0,
        'createtime': '',
        'updatetime': '',
        'opertime': '',
        'createid': '',
        'createname': '',
        'operid': '',
        'opername': '',
      };

  /// 构建完整的 masterTmpDto 默认结构（对齐接口文档 UpdateSaleMasterTmp 全字段）
  static Map<String, dynamic> defaultMasterTmpDto() => <String, dynamic>{
        'isSelected': '',
        'tmp': defaultTmp(),
        'unionPayFlag': 0,
        'unionTableIds': '',
        'unionTableCodes': '',
        'unionTablNames': '',
        'billtype': 0,
        'unitableid': '',
        'newtableid': '',
        'dataiflag': 0,
        'unionSaleIds': '',
        'serviceamt': '',
        'lowamt': '',
        'person': 0,
        'printkdflag': 0,
        'payways': <dynamic>[],
        'paydetail': <dynamic>[],
        'saleid': '',
        'prnpreflag': 0,
        'autogenedflag': '',
        'androidoperflag': 0,
        'noprintdishflag': 0,
        'transInTableReCalcServiceAmtFlag': 0,
        'isTimeOut': 0,
        'timeOutMinutes': '',
        'surplusMinutes': '',
        'version': 0,
        'spid': 0,
        'sid': 0,
        'tableid': '',
        'code': '',
        'name': '',
        'areaid': '',
        'areaname': '',
        'tabletypeid': '',
        'tabletypename': '',
        'stopflag': 0,
        'isort': 0,
        'reservationflag': 0,
        'opentimeout': 0,
        'warnbefore': 0,
        'warncount': 0,
        'warninterval': 0,
        'id': 0,
        'status': 0,
        'createtime': '',
        'updatetime': '',
        'opertime': '',
        'createid': '',
        'createname': '',
        'operid': '',
        'opername': '',
      };

  /// 深度合并：[overrides] 中的实际数据覆盖 [defaults] 默认值，
  /// 嵌套 Map 递归合并；null 值不覆盖默认值，保证服务端所需的全部字段都存在且非空。
  static Map<String, dynamic> deepMerge(
    Map<String, dynamic> defaults,
    Map<String, dynamic> overrides,
  ) {
    final Map<String, dynamic> result = Map<String, dynamic>.from(defaults);
    overrides.forEach((String key, dynamic value) {
      if (value == null) {
        return; // null 不覆盖默认值，避免服务端空引用
      }
      if (value is Map && result[key] is Map) {
        result[key] = deepMerge(
          (result[key] as Map).cast<String, dynamic>(),
          value.cast<String, dynamic>(),
        );
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  /// smdcapp TableDetailBean 定义的 tmp 字段白名单。
  ///
  /// 桌台列表接口返回的 tmp 含大量额外字段（isSelected/arrearages/tablestatusText/
  /// rate/taxrate/ispaying/Showamt 等），且部分类型为 boolean/number，
  /// 而服务端 C# 模型期望 string。smdcapp 重新序列化时只保留其 Java 模型定义的字段，
  /// 因此我们必须同样过滤，否则多余字段导致 .NET 空引用。
  static const Set<String> kTmpFields = <String>{
    'vipname', 'saleid', 'vipid', 'preprintflag', 'detailList', 'mustfreeflag',
    'cashid', 'uniflowno', 'cdflag', 'servicetimerange', 'servicediscount',
    'tabletypeid', 'additionid', 'servicebegintime', 'serviceendtime', 'operid',
    'opername', 'opermachno', 'tablestatus', 'containweight', 'amt', 'retailamt',
    'roundamt', 'serviceamt', 'lowamt', 'remark', 'personnum', 'spid', 'serverid',
    'vipno', 'localbillno', 'sid', 'vipmobile', 'billtype', 'lastbilltype',
    'dataiflag', 'billdate', 'servername', 'tableid', 'id', 'tablecode', 'billno',
    'unitableid', 'unitableno', 'unitablename', 'machno', 'tablename', 'hangflag',
    'lockflag', 'withdrawmemo', 'dscamt', 'addamt', 'payment', 'printkdflag',
    'printcpdflag', 'sendprintflag', 'confirmqty', 'createtime', 'updatetime',
    'appVersionName',
  };

  /// smdcapp TableInfoBean 定义的 masterTmpDto 外层字段白名单。
  static const Set<String> kTableFields = <String>{
    'tabletypename', 'createtime', 'code', 'areaname', 'tabletypeid', 'tablestatus',
    'operid', 'spid', 'sid', 'createname', 'stopflag', 'areaid', 'person', 'flag',
    'dieshesType', 'createid', 'opername', 'isalltype', 'tmp', 'name', 'billtype',
    'tableid', 'isort', 'id', 'updatetime', 'unicount', 'status', 'lowtype',
    'serviceamt', 'dataitableid', 'trueflag', 'reservationflag', 'lowamt',
    'minsalesamtflag', 'servicetype', 'virtulflag', 'excesstime', 'exceedtype',
    'virtualflag', 'newtableid',
  };

  /// 按 smdcapp 模型字段白名单过滤 masterTmpDto，丢弃桌台列表原始 JSON 中的多余字段。
  static Map<String, dynamic> filterMasterTmpDto(Map<String, dynamic> tableBean) {
    final Map<String, dynamic> result = <String, dynamic>{};
    tableBean.forEach((String key, dynamic value) {
      if (!kTableFields.contains(key)) {
        return; // 丢弃外层多余字段
      }
      if (key == 'tmp' && value is Map) {
        final Map<String, dynamic> filteredTmp = <String, dynamic>{};
        value.cast<String, dynamic>().forEach((String tk, dynamic tv) {
          if (kTmpFields.contains(tk)) {
            filteredTmp[tk] = tv;
          }
        });
        result['tmp'] = filteredTmp;
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  /// 构建完整桌台数据（对齐 smdcapp objectClone 逻辑）：
  /// 1. 用 rawJson（桌台列表原始数据）深度合并默认结构
  /// 2. 按 smdcapp 字段白名单过滤
  ///
  /// [rawJson] 为桌台列表接口返回的原始 JSON（TableInfo.rawJson）
  /// [fallback] 为 rawJson 为空时的兜底最小数据
  static Map<String, dynamic> buildFullTableBean({
    required Map<String, dynamic>? rawJson,
    required Map<String, dynamic> fallback,
  }) {
    final Map<String, dynamic> actual = rawJson ?? fallback;
    final Map<String, dynamic> tableBean = deepMerge(defaultMasterTmpDto(), actual);
    return filterMasterTmpDto(tableBean);
  }
}
