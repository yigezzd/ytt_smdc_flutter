class HttpApi {
  static const String users = 'users/simplezhli';
  static const String search = 'search/repositories';
  static const String subscriptions = 'users/simplezhli/subscriptions';
  static const String upload = 'uuc/upload-inco';

  /// 基础域名（正式环境）
  static const String baseUrlYtt = 'https://yun.bypos.net/YttSvr/app';
  // static const String baseUrlYtt = 'http://dev.bypos.net/YttSvr/app';

  /// 基础域名-根路径（不含 /app 前缀，用于 deposit/save、deposit/update 等接口）
  static const String baseUrlYttRoot = 'https://yun.bypos.net/YttSvr';
  // static const String baseUrlYttRoot = 'http://dev.bypos.net/YttSvr';
  
  /// 登录接口（表单编码 POST）
  static const String yttLogin = '/yttlogin';
  
  /// 获取多商户列表（手机号/商户号绑定多个商户时）
  static const String mobileStoreList = '/mobileStoreList';
  
  /// APP版本检查更新
  static const String appCheckVersion = '/version/getversion';
  
  /// 权限相关 API
  static const String roleGetInfoRetMap = '/role/getRoleInfo';

  // ==================== 云服务桌台接口 ====================
  // 路径相对于 baseUrlYtt（已含 /YttSvr/app 前缀），对齐 smdcapp TableApi。

  /// 云服务-查询桌台区域列表（对齐 smdcapp /YttSvr/app/table/area/getAreaList）
  static const String tableAreaList = '/table/area/getAreaList';

  /// 云服务-查询桌台信息列表（对齐 smdcapp /YttSvr/app/table/info/getTableInfoList）
  static const String tableInfoList = '/table/info/getTableInfoList';

  // ==================== 主设备（直连PC）接口 ====================
  // 主设备 base URL 为登录返回的 localhost，路径以 /api/ 开头，
  // 响应结构为 PCRootDataBean（Success/Message/Data），与云端 retcode/retmsg 不同。

  /// 主设备探活（同步时间），用于检测主设备是否可达
  static const String pcGetHostSyncTime = '/api/host/GetHostSyncTime';

  /// 主设备-查询桌台区域列表
  static const String pcTableAreaList = '/api/table/QueryTableAreaList';

  /// 主设备-查询桌台信息列表
  static const String pcTableInfoList = '/api/table/GetTableInfoList';

  // ==================== 桌台操作接口 ====================

  /// 云服务-消台（对齐 smdcapp /YttSvr/app/sale/cancelTable）
  static const String cancelTable = '/sale/cancelTable';

  /// 主设备-消台（对齐 smdcapp PCTableApi /api/table/TableCancel，参数 tablemaster JSON）
  static const String pcCancelTable = '/api/table/TableCancel';

  /// 云服务-锁台/解锁（对齐 smdcapp /YttSvr/app/sale/lockFlagTable）
  static const String lockFlagTable = '/sale/lockFlagTable';

  /// 主设备-锁台/解锁（对齐 smdcapp DishesApi /api/table/TableLock）
  static const String pcTableLock = '/api/table/TableLock';

  // ==================== 开台接口 ====================

  /// 云服务-开台（对齐 smdcapp /YttSvr/app/sale/beginTable）
  static const String beginTable = '/sale/beginTable';

  /// 主设备-开台（对齐 smdcapp PCTableApi /api/table/TableOpeFull，参数为 tablemaster JSON）
  static const String pcBeginTable = '/api/table/TableOpeFull';

  // ==================== 修改开台信息接口 ====================

  /// 云服务-修改开台信息（对齐 smdcapp /YttSvr/app/sale/updateMasterTmp）
  static const String updateMasterTmp = '/sale/updateMasterTmp';

  /// 主设备-修改开台信息（对齐 smdcapp PCTableApi /api/table/UpdateSaleMasterTmp）
  static const String pcUpdateMasterTmp = '/api/table/UpdateSaleMasterTmp';

  // ==================== 菜品接口 ====================
  // 注意：smdcapp 中菜品分类/商品列表接口固定走云服务（DishesHttpUtil baseUrl = 云域名），
  // 主设备无 /api/bi/... 端点，因此不存在主设备版本的菜品接口。

  /// 云服务-获取菜品分类（对齐 smdcapp /YttSvr/app/bi/type/getTypeListandCode）
  static const String getTypeList = '/bi/type/getTypeListandCode';

  /// 云服务-获取商品列表（对齐 smdcapp /YttSvr/app/bi/product/getProductList）
  static const String getProductList = '/bi/product/getProductList';

  /// 云服务-获取商品规格和做法（对齐 smdcapp /YttSvr/app/bi/product/getProductCookSpec）
  static const String getProductCookSpec = '/bi/product/getProductCookSpec';

  /// 云服务-获取套餐详情（对齐 smdcapp /YttSvr/app/bi/comb/getInfo）
  static const String getProductComb = '/bi/comb/getInfo';

  /// 云服务-获取服务员列表（对齐 smdcapp /YttSvr/app/user/getList）
  static const String getUserList = '/user/getList';

  /// 云服务-统一表下载（对齐 smdcapp TableApi /YttSvr/app/update/tabledown）
  /// 参数：tablename（表名）、page、pagesize；响应 data 为该表行列表。
  static const String tabledown = '/update/tabledown';

  // ==================== 下单接口 ====================

  /// 云服务-上传临时台桌数据/下单（对齐 smdcapp /YttSvr/app/sale/upSaleMasterTmp）
  /// 参数：master(主单JSON), detail(明细JSON数组), printmaster, printtype, printalltype
  static const String upSaleMasterTmp = '/sale/upSaleMasterTmp';

  /// 主设备-上传临时台桌数据/下单（对齐 smdcapp /api/table/UpSaleMasterTmp）
  static const String pcUpSaleMasterTmp = '/api/table/UpSaleMasterTmp';

  /// 主设备-保存桌台未落单菜品（对齐 smdcapp /api/Table/SaveProduct）
  /// 参数：tablemaster(主单JSON，含 detailList)
  static const String pcSaveProduct = '/api/Table/SaveProduct';

  // ==================== 会员接口 ====================

  /// 云服务-查询会员列表（对齐 smdcapp SettleApi /YttSvr/app/vip/getList）
  /// 参数：cardstatus=1, cond=卡号/姓名/手机号, sids=0
  static const String getVipList = '/vip/getList';

  // ==================== 订单详情接口 ====================

  /// 云服务-获取单个桌台临时点菜明细/订单详情（对齐 smdcapp /YttSvr/app/sale/getSaleTmpDetail）
  /// 参数：saleid；响应 data 为 PlacedOrder（含 detailList）
  static const String getSaleTmpDetail = '/sale/getSaleTmpDetail';

  /// 主设备-获取单个桌台临时点菜明细/订单详情（对齐 smdcapp /api/table/GetTableDetailList）
  /// 参数：tablemaster(PCMasterBean JSON，含 tmp)；响应 Data 为 PlacedOrder
  static const String pcGetTableDetailList = '/api/table/GetTableDetailList';

  // ==================== 结账接口 ====================

  /// 云服务-获取支付方式列表（对齐 smdcapp SettleApi /YttSvr/app/payinfo/getPayInfoList）
  /// 参数：cond, stopflag, pagesize, field, type
  static const String getPayInfoList = '/payinfo/getPayInfoList';

  /// 云服务-单据上传/结账流水（对齐 smdcapp SettleApi /YttSvr/app/sale/saleflow）
  /// 参数：data(SaleBean JSON数组), printtype, printalltype, newprinttype, seq
  static const String saleflow = '/sale/saleflow';

  /// 云服务-清台（对齐 smdcapp SettleApi /YttSvr/app/sale/clearTable）
  /// 参数：saleid, tableid, tableno
  static const String clearTable = '/sale/clearTable';

  /// 主设备-清台（对齐 smdcapp PcSettleHttpUtil /api/table/TableClear）
  /// 参数：tablemaster(JSON)
  static const String pcClearTable = '/api/table/TableClear';

  /// 云服务-获取服务器时间（对齐 smdcapp SettleApi /YttSvr/app/getTime）
  static const String getTime = '/getTime';

  /// 云服务-会员支付（对齐 smdcapp SettleApi /YttSvr/app/vip/pay）
  static const String vipPay = '/vip/pay';

  // ==================== 交接班接口 ====================

  /// 云服务-获取最后交班时间（对齐 smdcapp SetApi /YttSvr/cashrecon/getMaxLogoutTime）
  /// 注意：交班接口固定走根路径（无 /app 前缀），对齐 YttPhone SetApi + NetHelpUtils.currentUrl(根域名)
  static const String getMaxLogoutTime = '$baseUrlYttRoot/cashrecon/getMaxLogoutTime';

  /// 云服务-查询交班数据（对齐 smdcapp SetApi /YttSvr/cashrecon/reportOnShiftByMachno）
  /// 参数：cashid, logintime, logouttime, proflag, typeflag, retireflag
  static const String reportOnShift = '$baseUrlYttRoot/cashrecon/reportOnShiftByMachno';

  /// 云服务-提交交班（对齐 smdcapp SetApi /YttSvr/cashrecon/addShifthandover）
  /// 参数：master(JSON), details(JSON), printtype, totalprotype, totalpro, totalproret, totalpropre
  static const String addShifthandover = '$baseUrlYttRoot/cashrecon/addShifthandover';

  /// 云服务-设置参数（对齐 smdcapp LoginApi /YttSvr/app/set/setParams）
  /// 表单字段 "9" → set9Params（如 ClockTableFlag）；字段 "10" → setDishesParams（如 WeightTwoConfirm）
  static const String setParams = '/set/setParams';

  // ==================== 菜品操作接口 ====================

  /// 云服务-获取出品档口/厨打列表（对齐 smdcapp DishesApi /YttSvr/app/kitchen/getList）
  /// 参数：opertype(1收银打印配置 2出品打印配置 3标签打印配置), field, type, page, pagesize
  static const String kitchenGetList = '/kitchen/getList';

  /// 云服务-生成菜品条码（对齐 smdcapp DishesApi /YttSvr/app/bi/product/getBarcode）
  /// 参数：value(分类ID), type, spid, sid
  static const String productGetBarcode = '/bi/product/getBarcode';

  /// 云服务-添加菜品资料（对齐 smdcapp DishesApi /YttSvr/app/bi/product/add，临时菜保存资料）
  static const String productAdd = '/bi/product/add';

  /// 云服务-获取系统备注/原因列表（对齐 smdcapp /YttSvr/app/reason/getReasonList）
  /// 参数：typeid（01=备注, 02=退菜原因, 03=打折原因）
  static const String getReasonList = '/reason/getReasonList';

  /// 云服务-单品催菜/起菜/挂起标记（对齐 smdcapp /YttSvr/app/sale/updateDetailSign）
  /// 参数：spid, saleid, hangflag, callflag, urgeflag, onlyid
  static const String updateDetailSign = '/sale/updateDetailSign';

  /// 云服务-整单催菜/起菜/挂起（对齐 smdcapp /YttSvr/app/sale/updateAllDetailSign）
  /// 参数：spid, saleid, hangflag, callflag, urgeflag
  static const String updateAllDetailSign = '/sale/updateAllDetailSign';

  /// 云服务-更新沽清数量（对齐 smdcapp /YttSvr/app/warn/updateQtyWarnPro）
  static const String updateQtyWarnPro = '/warn/updateQtyWarnPro';

  /// 云服务-获取沽清列表（对齐 smdcapp /YttSvr/app/warn/findList）
  static const String findWarnList = '/warn/findList';

  /// 主设备-获取沽清列表（对齐 smdcapp /api/productwarn/GetProductWarnList）
  static const String pcGetProductWarnList = '/api/productwarn/GetProductWarnList';

  /// 主设备-更新沽清数据（对齐 smdcapp /api/productwarn/ReplaceProductWarnList）
  static const String pcReplaceProductWarnList = '/api/productwarn/ReplaceProductWarnList';

  /// 云服务-必点菜（对齐 smdcapp /YttSvr/app/must/yxMust）
  static const String yxMust = '/must/yxMust';

  /// 云服务-获取促销列表（对齐 smdcapp /YttSvr/app/mp/getSalesPromotionList）
  static const String getSalesPromotionList = '/mp/getSalesPromotionList';

  /// 云服务-促销折扣计算（对齐 smdcapp /YttSvr/app/mp/amountAfterDiscount）
  static const String amountAfterDiscount = '/mp/amountAfterDiscount';

  /// 云服务-检测用户折免上限（对齐 smdcapp /YttSvr/app/user/checkUserDec）
  static const String checkUserDec = '/user/checkUserDec';

  /// 云服务-检查负库存（对齐 smdcapp /YttSvr/app/sale/checkOrderStock）
  static const String checkOrderStock = '/sale/checkOrderStock';

  /// 云服务-撤单（对齐 smdcapp /YttSvr/sale/withdrawTable）
  static const String withdrawTable = '/sale/withdrawTable';

  /// 主设备-撤单（对齐 smdcapp /api/table/TableWithdraw）
  static const String pcWithdrawTable = '/api/table/TableWithdraw';

  /// 云服务-并台（对齐 smdcapp /YttSvr/app/sale/uniTable）
  static const String uniTable = '/sale/uniTable';

  /// 主设备-并台（对齐 smdcapp /api/table/TableUnion）
  static const String pcUniTable = '/api/table/TableUnion';

  /// 云服务-获取可并台桌台（对齐 smdcapp /YttSvr/app/sale/getCanUniTables）
  static const String getCanUniTables = '/sale/getCanUniTables';

  /// 主设备-获取可并台桌台（对齐 smdcapp /api/table/GetCanUniTables）
  static const String pcGetCanUniTables = '/api/table/GetCanUniTables';

  /// 主设备-换台（对齐 smdcapp /api/table/TableChange）
  static const String pcTableChange = '/api/table/TableChange';

  /// 云服务-转台（对齐 smdcapp /YttSvr/app/sale/transProMaster）
  static const String transProMaster = '/sale/transProMaster';

  /// 主设备-转菜（对齐 smdcapp /api/table/TableChangeProduct）
  static const String pcTableChangeProduct = '/api/table/TableChangeProduct';

  /// 云服务-重打/预打（对齐 smdcapp /YttSvr/app/print/restPrint）
  static const String restPrint = '/print/restPrint';

  /// 主设备-预打（对齐 smdcapp /api/print/RePrint）
  static const String pcRePrint = '/api/print/RePrint';

  /// 主设备-补打客单（对齐 smdcapp /api/print/PrintKDInfo）
  static const String pcPrintKDInfo = '/api/print/PrintKDInfo';

  /// 云服务-更新预打印标识（对齐 smdcapp /YttSvr/app/sale/updateMasterTmpPrePrintFlag）
  static const String updateMasterTmpPrePrintFlag = '/sale/updateMasterTmpPrePrintFlag';

  /// 主设备-更新预打印标识（对齐 smdcapp /api/Table/UpdateMasterTmpPrePrintFlag）
  static const String pcUpdateMasterTmpPrePrintFlag = '/api/Table/UpdateMasterTmpPrePrintFlag';

  /// 主设备-获取桌台锁定状态（对齐 smdcapp /api/table/GetTableLockStatus）
  static const String pcGetTableLockStatus = '/api/table/GetTableLockStatus';

  /// 主设备-获取保存的未落单菜品（对齐 smdcapp /api/Table/GetSaveProductList）
  static const String pcGetSaveProductList = '/api/Table/GetSaveProductList';

  /// 主设备-获取最新桌台明细（对齐 smdcapp /api/Table/GetSaleDetailTmpList）
  static const String pcGetSaleDetailTmpList = '/api/Table/GetSaleDetailTmpList';

  // ==================== 押金接口 ====================

  /// 云服务-新增押金流水（对齐 smdcapp /YttSvr/deposit/save，注意无 /app 前缀）
  static const String depositSave = '$baseUrlYttRoot/deposit/save';

  /// 云服务-查询押金列表（对齐 smdcapp /YttSvr/app/deposit/findList）
  static const String depositFindList = '/deposit/findList';

  /// 云服务-押金更新/退款（对齐 smdcapp /YttSvr/deposit/update，注意无 /app 前缀）
  static const String depositUpdate = '$baseUrlYttRoot/deposit/update';

  /// 云服务-新增并修改押金流水（对齐 smdcapp /YttSvr/app/deposit/saveList）
  static const String depositSaveList = '/deposit/saveList';

  /// 云服务-按saleid查押金（对齐 smdcapp /YttSvr/app/deposit/findListBySaleid）
  static const String depositFindListBySaleid = '/deposit/findListBySaleid';

  // ==================== 暂结接口 ====================

  /// 云服务-暂结部分退款（对齐 smdcapp /YttSvr/app/fornowsale/refundPartPayInfo）
  static const String refundPartPayInfo = '/fornowsale/refundPartPayInfo';

  /// 云服务-修改暂结支付状态（对齐 smdcapp /YttSvr/app/fornowsale/updatePayInfo）
  static const String updatePayInfo = '/fornowsale/updatePayInfo';

  /// 主设备-暂结（对齐 smdcapp /api/table/InsertPayawyFornow）
  static const String pcInsertPayawyFornow = '/api/table/InsertPayawyFornow';

  /// 云服务-上传暂结单（对齐 smdcapp /YttSvr/app/fornowsale/upPayInfo）
  static const String upPayInfo = '/fornowsale/upPayInfo';

  /// 云服务-获取暂结单列表（对齐 smdcapp /YttSvr/app/fornowsale/getUpPayList）
  static const String getUpPayList = '/fornowsale/getUpPayList';

  /// 主设备-获取暂结列表（对齐 smdcapp /api/table/GetTableSalePayFornowList）
  static const String pcGetTableSalePayFornowList = '/api/table/GetTableSalePayFornowList';

  /// 主设备-暂结整单退款（对齐 smdcapp /api/Table/ReturnFornow）
  static const String pcReturnFornow = '/api/Table/ReturnFornow';

  /// 主设备-暂结部分退款（对齐 smdcapp /api/Table/PartReturnFornow）
  static const String pcPartReturnFornow = '/api/Table/PartReturnFornow';

  // ==================== 会员/优惠券接口 ====================

  /// 云服务-会员优惠券列表（对齐 smdcapp /YttSvr/app/vip/searchVipFavList）
  static const String searchVipFavList = '/vip/searchVipFavList';

  /// 云服务-优惠券核销（对齐 smdcapp /YttSvr/app/vip/voucherVerify）
  static const String voucherVerify = '/vip/voucherVerify';

  /// 云服务-优惠券撤销（对齐 smdcapp SettleApi /YttSvr/app/vip/unVerify）
  /// 参数：vipid, billno
  static const String vipUnVerify = '/vip/unVerify';

  /// 云服务-优惠券支付核销（对齐 smdcapp SettleApi /YttSvr/app/vip/verify）
  /// 参数：vipid, master, projectlist, clienttype, fav
  static const String vipVerify = '/vip/verify';

  /// 云服务-会员挂账（对齐 smdcapp /YttSvr/app/vip/overPay）
  static const String vipOverPay = '/vip/overPay';

  // ==================== 聚客一卡通接口 ====================

  /// 云服务-聚客一卡通查询会员（对齐 smdcapp SettleApi /YttSvr/app/jk-card/getVipInfo）
  /// 参数：cond(卡号/姓名/手机号)
  static const String jkCardGetVipInfo = '/jk-card/getVipInfo';

  /// 云服务-聚客一卡通支付（对齐 smdcapp SettleApi /YttSvr/app/jk-card/pay）
  /// 参数：vipid, vipno, payid, payname, saleid, salename, billno, payamt
  static const String jkCardPay = '/jk-card/pay';

  // ==================== 团购核销接口 ====================

  /// 云服务-获取抖音/美团核销券信息（对齐 smdcapp /YttSvr/douyin/getDyCoupunInfo）
  static const String getDyCoupunInfo = '/douyin/getDyCoupunInfo';

  /// 云服务-自动识别团购券（对齐 smdcapp /YttSvr/douyin/getTuanGouCoupunInfo）
  static const String getTuanGouCoupunInfo = '/douyin/getTuanGouCoupunInfo';

  /// 云服务-验券/核销（对齐 smdcapp /YttSvr/douyin/prepare）
  static const String douyinPrepare = '/douyin/prepare';

  /// 云服务-撤销验券（对齐 smdcapp SettleApi /YttSvr/douyin/cancelPrepare）
  /// 参数：saleid, businesstype, signinfo(可选，指定退的验券id，多张逗号分割)
  static const String douyinCancelPrepare = '/douyin/cancelPrepare';

  // ==================== 外卖接口 ====================

  /// 外卖-获取所有订单（对齐 smdcapp /WmSvr/common/orderGetAll.do）
  static const String wmOrderGetAll = '/WmSvr/common/orderGetAll.do';

  /// 外卖-查询完成订单（对齐 smdcapp /WmSvr/common/queryFinishOrder.do）
  static const String wmQueryFinishOrder = '/WmSvr/common/queryFinishOrder.do';

  /// 外卖-接单（对齐 smdcapp /WmSvr/common/orderConfirm.do）
  static const String wmOrderConfirm = '/WmSvr/common/orderConfirm.do';

  /// 外卖-取消订单/不接单（对齐 smdcapp /WmSvr/common/orderCancel.do）
  static const String wmOrderCancel = '/WmSvr/common/orderCancel.do';

  /// 外卖-同意退单（对齐 smdcapp /WmSvr/common/orderRefundAgree.do）
  static const String wmOrderRefundAgree = '/WmSvr/common/orderRefundAgree.do';

  /// 外卖-拒绝退单（对齐 smdcapp /WmSvr/common/orderRefundDisAgree.do）
  static const String wmOrderRefundDisAgree = '/WmSvr/common/orderRefundDisAgree.do';

  /// 外卖-回复催单（对齐 smdcapp /WmSvr/common/orderReplyReminder.do）
  static const String wmOrderReplyReminder = '/WmSvr/common/orderReplyReminder.do';

  /// 外卖-订单送达（对齐 smdcapp /WmSvr/common/orderReceived.do）
  static const String wmOrderReceived = '/WmSvr/common/orderReceived.do';

  /// 外卖-订单配送（对齐 smdcapp /WmSvr/common/orderDeliver.do）
  static const String wmOrderDeliver = '/WmSvr/common/orderDeliver.do';

  /// 外卖-营业/打烊（对齐 smdcapp /WmSvr/common/openStore.do）
  static const String wmOpenStore = '/WmSvr/common/openStore.do';

  /// 外卖-查询店铺状态（对齐 smdcapp /WmSvr/common/queryStore.do）
  static const String wmQueryStore = '/WmSvr/common/queryStore.do';

  // ==================== 扫码点餐订单接口 ====================

  /// 云服务-获取扫码点餐订单列表（对齐 smdcapp /YttSvr/app/apporder/getOrderList）
  static const String appOrderGetList = '/apporder/getOrderList';

  /// 云服务-取消扫码点餐订单（对齐 smdcapp /YttSvr/app/apporder/cancelOrder）
  static const String appOrderCancel = '/apporder/cancelOrder';

  /// 云服务-更新接单状态（对齐 smdcapp /YttSvr/app/saleapporder/updateOrderStatus）
  static const String updateOrderStatus = '/saleapporder/updateOrderStatus';

  /// 云服务-获取待接单数据（对齐 smdcapp /YttSvr/app/saleapporder/getUnFinishOrder）
  static const String getUnFinishOrder = '/saleapporder/getUnFinishOrder';

  // ==================== 松鼠屋渠道接口 ====================

  /// 云服务-松鼠屋推单（对齐 smdcapp ChannelApi /YttSvr/app/ssw/channel/sswOrderAdd）
  /// 参数：saleid, opertype, source(默认other)
  static const String sswOrderAdd = '/ssw/channel/sswOrderAdd';

  /// 云服务-松鼠屋页面URL（对齐 smdcapp ChannelApi /YttSvr/app/ssw/channel/sswOrderUrl）
  /// 参数：billno, module(orderDetail订单详情/setting我的页面设置)
  static const String sswOrderUrl = '/ssw/channel/sswOrderUrl';

  // ==================== 叫号接口 ====================

  /// 云服务-叫号（对齐 smdcapp /YttSvr/take/snack/getTakeSnackcode）
  static const String getTakeSnackcode = '/take/snack/getTakeSnackcode';

  /// 云服务-按设置叫号（对齐 smdcapp /YttSvr/take/snack/getTakeSnackCodeBySet，返回取餐号）
  static const String getTakeSnackCodeBySet = '/take/snack/getTakeSnackCodeBySet';

  /// 云服务-更新桌台状态（对齐 smdcapp /YttSvr/app/sale/updateMasterTmpStatus）
  static const String updateMasterTmpStatus = '/sale/updateMasterTmpStatus';

  // ==================== 预订接口 ====================

  /// 云服务-查询预订列表（对齐 smdcapp /YttSvr/app/reserve/findList）
  static const String reserveFindList = '/reserve/findList';

  /// 云服务-获取预订详情（对齐 smdcapp /YttSvr/app/reserve/getInfo）
  static const String reserveGetInfo = '/reserve/getInfo';

  /// 云服务-新增/编辑预订（对齐 smdcapp /YttSvr/app/reserve/save）
  static const String reserveSave = '/reserve/save';

  /// 云服务-取消预订（对齐 smdcapp /YttSvr/app/reserve/cancel）
  static const String reserveCancel = '/reserve/cancel';

  /// 云服务-预订开台（对齐 smdcapp /YttSvr/app/reserve/opentable）
  static const String reserveOpenTable = '/reserve/opentable';

  /// 云服务-已逾期预订退款（对齐 smdcapp /YttSvr/app/reserve/retPayamt）
  static const String reserveRetPayamt = '/reserve/retPayamt';

  /// 云服务-预订冲突检测（对齐 smdcapp YDApi /YttSvr/app/reserve/toTableAboutTime）
  /// 参数：arrivaltime, tablelist, nobillid
  static const String reserveToTableAboutTime = '/reserve/toTableAboutTime';

  /// 云服务-预订报表查询（对齐 smdcapp YDApi /YttSvr/trade/getPredetermineList）
  /// 参数：bsid, billno, mobile, operid, tabname, datetype, status, name, startdate, enddate, page, pagesize, cond, field, type
  static const String getPredetermineList = '/trade/getPredetermineList';

  // ==================== 云打印管理接口 ====================

  /// 云服务-获取云打印机列表（对齐 smdcapp SetApi /YttSvr/app/print/getList）
  static const String printGetList = '/print/getList';

  /// 云服务-提交云打印任务（对齐 smdcapp SetApi /YttSvr/app/print/printTask）
  static const String printTask = '/print/printTask';

  /// 云服务-绑定云打印机（对齐 smdcapp SetApi /YttSvr/app/print/bindPrint）
  static const String bindPrint = '/print/bindPrint';

  /// 云服务-解绑云打印机（对齐 smdcapp SetApi /YttSvr/app/print/unBindPrint）
  static const String unBindPrint = '/print/unBindPrint';

  /// 云服务-云打印测试（对齐 smdcapp SetApi /YttSvr/app/print/printTest）
  static const String printTest = '/print/printTest';

  /// 云服务-接口打印通知（对齐 smdcapp DishesApi /YttSvr/app/print/printMsgNotice）
  static const String printMsgNotice = '/print/printMsgNotice';

  /// 云服务-重打PC模式（对齐 smdcapp DishesApi /YttSvr/app/print/restPrintPc）
  static const String restPrintPc = '/print/restPrintPc';

  /// 主设备-打印结账信息（对齐 smdcapp SettleApi /api/print/PrintPayInfo）
  static const String pcPrintPayInfo = '/api/print/PrintPayInfo';

  /// 主设备-暂结打印（对齐 smdcapp SettleApi /api/print/PrintTempPayInfo）
  static const String pcPrintTempPayInfo = '/api/print/PrintTempPayInfo';

  /// 主设备-押金打印（对齐 smdcapp SettleApi /api/print/PrintDepositInfo）
  static const String pcPrintDepositInfo = '/api/print/PrintDepositInfo';

  /// 主设备-交班打印（对齐 smdcapp PCSetApi /api/print/PrintHandOver）
  static const String pcPrintHandOver = '/api/print/PrintHandOver';

  // ==================== 权限授权接口 ====================

  /// 云服务-授权码验证（对齐 smdcapp SettleApi /YttSvr/weChat/boss/vip/searchUserAuth）
  /// 参数：menuid(权限码), rfid(授权码), time(时间，可选)
  static const String searchUserAuth = '/weChat/boss/vip/searchUserAuth';

  /// 云服务-用户授权验证（对齐 smdcapp SettleApi /YttSvr/weChat/boss/vip/getUserAuth）
  /// 参数：roleid, rfid
  static const String getUserAuth = '/weChat/boss/vip/getUserAuth';

  // ==================== 日志接口 ====================

  /// 云服务-上传敏感操作日志（对齐 smdcapp /YttSvr/app/salelog/setLog）
  /// 参数：data(OrderLog JSON数组字符串)
  static const String saleLogSetLog = '/salelog/setLog';
}
