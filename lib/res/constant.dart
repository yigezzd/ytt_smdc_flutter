import 'package:flutter/foundation.dart';

class Constant {

  /// App运行在Release环境时，inProduction为true；当App运行在Debug和Profile环境时，inProduction为false
  static const bool inProduction  = kReleaseMode;

  static bool isDriverTest  = false;
  static bool isUnitTest  = false;
  
  static const String data = 'data';
  static const String message = 'message';
  static const String code = 'code';
  
  static const String keyGuide = 'keyGuide';
  static const String phone = 'phone';
  static const String accessToken = 'accessToken';
  static const String refreshToken = 'refreshToken';

  static const String theme = 'AppTheme';

  /// 登录相关存储 key
  static const String token = 'token';
  static const String user = 'user';
  static const String store = 'store';
  static const String rolemap = 'rolemap';
  static const String sysStoreAccount = 'sysStoreAccount';
  static const String allLoginData = 'allLoginData';
  static const String loginParamResp = 'loginParamResp';

  /// 登录返回 verservicelist 相关标志（对齐 smdcapp SpUtils putVerService615/612）
  static const String verserviceList = 'verservicelist';      // 增值服务列表完整 JSON
  static const String verservice615 = 'verservice_verid_615'; // 聚合外卖平台（verid=615 且 status=1）
  static const String verservice612 = 'verservice_dy_pay';    // 抖音/美团核销（verid=612 且 status=1）

  /// 登录返回主设备停用标志（对齐 smdcapp SpUtils putMastermachstopflag：0启用 1停止）
  static const String mastermachstopflag = 'mastermachstopflag';

  /// 登录返回最大单号（对齐 smdcapp SpUtils billNoMax）
  static const String billNoMax = 'billnomax';

  /// 登录返回 role 折扣权限上限（对齐 smdcapp LoginModel role 处理）
  static const String monthDiscountAmt = 'monthdiscountamt'; // 每月折免总金额上限
  static const String proDiscount = 'prodiscount';           // 菜品打折单次打折上限
  static const String orderDiscount = 'orderdiscount';       // 订单打折单次打折上限
  static const String proGiveAmt = 'progiveamt';             // 菜品单次赠送上限

  /// 商业模式相关存储 key（对齐 smdcapp SpUtils STORE_MODEL_3）
  static const String storeMode = 'store_mode'; // 当前商业模式：1=快餐 2=正餐

  /// 双模式连接相关存储 key
  static const String localhost = 'localhost';     // 主设备地址（登录返回，如 http://192.168.8.47:9094）
  static const String serverType = 'server_type';  // 连接模式：0=不限 1=仅主设备 2=仅云服务

  /// RabbitMQ 推送相关存储 key（对齐 smdcapp SpUtils RABBIT_ADDRESS/MACHNO/STORECODE/BUSINESS_NUMBER）
  static const String rabbitAddress = 'rabbit_address';   // MQ服务器地址（登录返回，默认 ysp01.yun8609.net）
  static const String rabbitPort = 'rabbit_port';         // MQ端口（默认 5672）
  static const String machNo = 'mach_no';                 // 设备机号（登录返回 mach.code）
  static const String storeCode = 'store_code';           // 门店编码（登录返回 store.code）
  static const String businessNumber = 'business_number'; // 商户号（登录返回 store.account）

  /// 记住密码相关存储 key
  static const String rememberLoginType = 'remember_login_type'; // 上次登录方式 0:手机号 1:商户号
  static const String rememberPhone = 'remember_phone';           // 手机号模式-手机号
  static const String rememberPhonePwd = 'remember_phone_pwd';    // 手机号模式-密码
  static const String rememberMerchantCode = 'remember_merchant_code';     // 商户号模式-商户号
  static const String rememberMerchantAccount = 'remember_merchant_account'; // 商户号模式-账号
  static const String rememberMerchantPwd = 'remember_merchant_pwd';         // 商户号模式-密码
  static const String rememberPwdEnabled = 'remember_pwd_enabled';           // 记住密码开关

  /// pstore（总店）功能标志（对齐 smdcapp LoginBean.pstore）
  static const String pstoreVipflag = 'pstore_vipflag';         // 会员功能标志
  static const String pstoreTakeoutflag = 'pstore_takeoutflag'; // 外卖功能标志
  static const String pstoreMiniverflag = 'pstore_miniverflag'; // 小程序标志
  static const String pstorePaytype = 'pstore_paytype';         // 支付平台类型（1=收钱吧 2=乐刷 4=优支付）
  static const String pstoreMobilepay = 'pstore_mobilepay';     // 移动支付配置

  /// mach（设备）字段（对齐 smdcapp LoginBean.mach）
  static const String machTerminalsnLeshua = 'mach_terminalsn_leshua'; // 乐刷终端号
  static const String machGettakeoutorder = 'mach_gettakeoutorder';     // 外卖接单标志
  static const String machMasterflag = 'mach_masterflag';               // 主设备标志
  static const String machClienttype = 'mach_clienttype';               // 客户端类型

}

