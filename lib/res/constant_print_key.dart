/// 打印配置常量 Key（对齐 smdcapp ConstantPrintKey.java）
///
/// 用于本地持久化存储打印相关配置。
class ConstantPrintKey {
  ConstantPrintKey._();

  // ──────────── 打印机类型 ─────────────────────────────────────────

  /// 打印机类型（PC打印|云打印|蓝牙打印|接口打印）
  static const String printerType = 'PRITER_TYPE';

  /// 机型 PrintTypeEnum int类型（对齐 smdcapp MACH_TYPE）
  static const String machType = 'MACH_TYPE';

  // ──────────── 蓝牙打印 ─────────────────────────────────────────

  /// 连接到的蓝牙设备地址
  static const String bluetoothAddr = 'BLUETOOTH_EQUIPMENT_ADDR';

  /// 连接到的蓝牙设备名字
  static const String bluetoothName = 'BLUETOOTH_EQUIPMENT_NAME';

  // ──────────── 网口打印 ─────────────────────────────────────────

  /// 打印机IP地址
  static const String ipAddress = 'IP_ADDRESS';

  /// 打印机端口
  static const String portAddress = 'PORT_ADDRESS';

  // ──────────── 远程/PC打印 ─────────────────────────────────────────

  /// 远程打印机设备名字
  static const String remotePrinterName = 'REMOTE_PRINTER_EQUIPMENT_NAME';

  /// 远程打印设备编号/地址
  static const String remotePrinterAddr = 'REMOTE_PRINTER_EQUIPMENT_ADDR';

  // ──────────── 云打印 ─────────────────────────────────────────

  /// 云打印机模板类型（默认0）
  static const String yunPrintTemplate = 'save_yun_print_template';

  /// 选中的云打印机信息（JSON）
  static const String yunPrintInfo = 'save_select_yun_print_info';

  // ──────────── 结账打印配置 ─────────────────────────────────────────

  /// 结账打印是否提示（0询问、1自动）
  static const String printInquiryJz = 'SAVE_PRINT_INQUIRY_JZ';

  /// 结账打印份数（默认1）
  static const String printNumJz = 'SAVE_PRINT_NUM_JZ';

  /// 结账打印样式（0=58mm简约, 1=80mm标准, 2=80mm详细）
  static const String printStyleJz = 'SAVE_PRINT_STYLE_JZ';

  /// 结账打印规格（58mm/80mm）
  static const String printSizeJz = 'SAVE_PRINT_SIZE_JZ';

  // ──────────── 客单打印配置 ─────────────────────────────────────────

  /// 客单打印是否提示（0询问、1自动）
  static const String printInquiryKd = 'SAVE_PRINT_INQUIRY_KD';

  /// 客单打印份数（默认1）
  static const String printNumKd = 'SAVE_PRINT_NUM_KD';

  /// 客单打印样式
  static const String printStyleKd = 'SAVE_PRINT_STYLE_KD';

  /// 客单打印规格（58mm/80mm）
  static const String printSizeKd = 'SAVE_PRINT_SIZE_KD';

  // ──────────── 厨打配置 ─────────────────────────────────────────

  /// 厨打是否提示（0询问、1自动）
  static const String printInquiryCd = 'SAVE_PRINT_INQUIRY_CD';

  /// 厨打份数（默认1）
  static const String printNumCd = 'SAVE_PRINT_NUM_CD';

  /// 厨打样式
  static const String printStyleCd = 'SAVE_PRINT_STYLE_CD';

  /// 厨打规格（58mm/80mm）
  static const String printSizeCd = 'SAVE_PRINT_SIZE_CD';

  // ──────────── 标签打印 ─────────────────────────────────────────

  /// 标签打印规格
  static const String printLableSize = 'PRINT_LABLE_SIZE';

  /// 标签打印数量
  static const String printLableNum = 'save_print_lable_num';

  /// 标签打印样式
  static const String printLableStyle = 'save_print_lable_style';

  // ──────────── 其他 ─────────────────────────────────────────

  /// 票尾走纸行数（小票打印完毕后额外走纸行数）
  static const String ticketFeedLine = 'TICKET_FEED_LINE';

  /// 打印指令类型（ESC/TSC）
  static const String printCmdType = 'PRINTTYPE';

  // ──────────── 打印类型枚举值 ─────────────────────────────────────────

  /// 打印类型选项列表（对齐 smdcapp PrintSetActivity.clickPrintType）
  static const List<String> printerTypeOptions = ['PC打印', '云打印', '蓝牙打印', '接口打印'];

  /// 默认打印类型
  static const String defaultPrinterType = 'PC打印';

  // ──────────── printalltype 枚举（对齐 smdcapp TickerTypeEnum）─────────────────

  /// 打印单据类型枚举
  static const int printTypeNone = -1;       // 不打印
  static const int printTypeZanJie = 1;      // 暂结单
  static const int printTypeJieZhang = 2;    // 结账单
  static const int printTypeChuPin = 3;      // 出品单（厨打）
  static const int printTypeTuiCai = 4;      // 退菜单
  static const int printTypeCuiCai = 5;      // 催菜单
  static const int printTypeGuaQi = 6;       // 挂起单
  static const int printTypeQiCai = 7;       // 起菜单
  static const int printTypeYuDa = 8;        // 预打单
  static const int printTypeChongZhi = 9;    // 充值单
  static const int printTypeJiaoBan = 10;    // 交班单
  static const int printTypeYuDing = 11;     // 预订单
  static const int printTypeJiCun = 12;      // 寄存单
  static const int printTypeYaJin = 13;      // 押金单
  static const int printTypeBeiTie = 14;     // 杯帖
  static const int printTypeKeDan = 15;      // 客单
  static const int printTypeZhuanTai = 18;   // 转台单
}
