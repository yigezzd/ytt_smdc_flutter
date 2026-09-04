/// 后台数据表名常量（对齐 smdcapp TableName.kt）
///
/// 仅包含通过 [TableDownloadManager] 从云端下载的后台数据表，
/// 本地业务表（销售单、交班等）不在此定义。
class DbTableName {
  DbTableName._();

  // ── 商品相关 ──
  static const String tBiProduct = 't_bi_product';
  static const String tBiType = 't_bi_type';
  static const String tBiSpec = 't_bi_spec';
  static const String tBiProductSpec = 't_bi_product_spec';
  static const String tBiProductDate = 't_bi_product_date';
  static const String tBiUnit = 't_bi_unit';
  static const String tBiCombSet = 't_bi_comb_set';
  static const String tBiProductStore = 't_bi_product_store';
  static const String tProductCook = 't_product_cook';
  static const String tCookInfo = 't_cook_info';
  static const String tCookGroup = 't_cook_group';
  static const String tRecommendedProduct = 't_recommended_product';

  // ── 桌台相关 ──
  static const String tTableAreaType = 't_table_area_type';
  static const String tTableArea = 't_table_area';
  static const String tTablePricingmodeTime = 't_table_pricingmode_time';
  static const String tTableType = 't_table_type';

  // ── 会员相关 ──
  static const String tVipType = 't_vip_type';
  static const String tVipInfo = 't_vip_info';
  static const String tVipFlow = 't_vip_flow';

  // ── 促销相关 ──
  static const String tMpPtVipType = 't_mp_pt_vip_type';
  static const String tMpPtTime = 't_mp_pt_time';
  static const String tMpPtRule = 't_mp_pt_rule';
  static const String tMpPtProductOrType = 't_mp_pt_product_or_type';
  static const String tMpPtNodate = 't_mp_pt_nodate';
  static const String tMpPtMaster = 't_mp_pt_master';
  static const String tMpStoreType = 't_mp_store_type';
  static const String tMpStore = 't_mp_store';

  // ── 必点菜 ──
  static const String tMustMaster = 't_must_master';
  static const String tMustProduct = 't_must_product';
  static const String tMustTablearea = 't_must_tablearea';

  // ── 一菜多吃 ──
  static const String tEatGroup = 't_eat_group';
  static const String tEatInfo = 't_eat_info';
  static const String tProductEat = 't_product_eat';

  // ── 系统/门店 ──
  static const String sysStore = 'sys_store';
  static const String sysMachine = 'sys_machine';
  static const String sysAuth = 'sys_auth';
  static const String sysUser = 'sys_user';

  // ── 其他 ──
  static const String tBiPayway = 't_bi_payway';
  static const String tBiParameter = 't_bi_parameter';
  static const String tBiReasonInfo = 't_bi_reason_info';
  static const String tReserveMaster = 't_reserve_master';

  /// 全部后台数据表（与 [TableDownloadManager.tableRemarkMap] 的 key 完全一致）
  static const List<String> backendTables = <String>[
    tBiProduct,
    tBiUnit,
    tBiType,
    tMustMaster,
    tMustProduct,
    tMustTablearea,
    sysStore,
    tBiProductDate,
    tBiProductStore,
    tBiSpec,
    tBiProductSpec,
    tProductCook,
    tCookInfo,
    tCookGroup,
    tBiCombSet,
    sysMachine,
    tMpPtMaster,
    tMpPtNodate,
    tMpPtProductOrType,
    tMpPtRule,
    tMpPtTime,
    sysAuth,
    tMpStoreType,
    tMpStore,
    tMpPtVipType,
    tBiReasonInfo,
    tBiPayway,
    tBiParameter,
    tReserveMaster,
    tVipFlow,
    sysUser,
    tTableType,
    tVipInfo,
    tVipType,
    tTablePricingmodeTime,
    tTableAreaType,
    tTableArea,
    tProductEat,
    tEatGroup,
    tEatInfo,
  ];
}
