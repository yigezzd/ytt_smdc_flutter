/// 商品信息表（对齐 ProductBean.kt，含 @Ignore 字段）
///
/// 持久化字段对应 t_bi_product 表列；@Ignore 字段仅用于内存计算 / UI 状态。
class ProductBeanEntity {
  // ── 持久化字段 ──
  int id; // PrimaryKey
  int spid; // 总部ID
  int sid; // 分店ID
  String productid; // 商品id
  String barcode; // 商品条码
  String name; // 商品名称
  String typeid; // 菜品分类id
  String typeid1; // 菜品分类id
  String typeid2; // 菜品分类id
  String helpcode; // 检索码
  String unit; // 单位
  double sellprice; // 售价
  double mprice1; // 会员价1
  double mprice2; // 会员价2
  double mprice3; // 会员价3
  double inprice; // 成本价
  int isort; // 排序号
  int dscflag; // 折扣标记：开1；关0
  int printflag; // 厨打标记：开1；关0
  int labelflag; // 打印标签：开1；关0
  int pointflag; // 积分标识：开1；关0
  int minsaleflag; // 计入低消：开1；关0
  int presentflag; // 是否可赠送：开1；关0
  int curflag; // 时价菜标记：开1；关0
  int stockflag; // 库存管理：开1；关0
  int eatinstoreflag; // 扫码限堂食：开1；关0
  int bagflag; // 打包必选：开1；关0
  int recommendflag; // 推荐菜：开1；关0
  int pcshowflag; // pc端显示：开1；关0
  int scanshowflag; // 扫码点餐显示：开1；关0
  int padshowflag; // 平板端显示：开1；关0
  int mobileshowflag; // 员工端显示：开1；关0
  int sellclearflag; // 1 沽清了 0没沽清
  int saledateflag; // 售卖日期：不限：1；指定日期2
  int stopflag; // 是否停用1是 0否
  int cookflag; // 多做法标识 1是 0否
  int specflag; // 多规格标识 1是 0否
  int combflag; // 1套餐
  int weighflag; // 称重菜品 1是 0否
  int hangflag; // 1挂菜
  int callflag; // 1起菜code
  int urgeflag; // 1催菜
  int status; // 1有效,0无效
  int typeproisort; // 同分类下的菜品排序字段
  String imageurl; // 菜品图片
  String createtime; // 创建时间
  String updatetime; // 更新时间
  String operid; // 操作员id
  String opername; // 操作员名称
  String code; // 条码
  double rrprice;
  double stockqty; // 沽清库存数量
  double discount; // 活动折扣率
  String typename; // 分类名称
  double cookaddamt; // 做法加价
  double startsellqty; // 起售数量（默认1）
  int servicefeeflag; // 是否收服务费（默认1）
  double addsellqty; // 增售卖数量（默认1）
  double maxsellqty; // 每单限量点几份
  String jcmbillid; // 基础促销活动ID
  int chooseqtyflag; // 点菜时选择数量
  int moreeatflag; // 一菜多吃开关
  int combsource;
  int datetype; // 售卖日期
  int cycletype; // 售卖周期
  String saletime;
  int rawflag;
  double saleqty;
  double deductvalue;
  int deducttype;
  String saleweek;
  String begindate;
  int timetype;
  int combtype;
  String enddate;
  String salemonth;

  // ── @Ignore 字段（不入库） ──
  int mustflag; // 必点菜标识
  int tpdishflag; // 1 临时菜标识
  int douyinflag; // 1 团购菜标识
  int tpdscflag; // 1 临时菜是否可以打折
  double combaddamt; // 套餐加减价
  String opertime; // 敏感操作时间
  String dishid; // 档口id1
  String dishidzd; // 档口id2
  double ptypt1Price; // 做法整份加价格，不计算数量
  double dySellprice; // 团购券临时变量分摊后的售价
  double isSellQty; // 临时变量，记录已经点了多少数量
  String cartCreatetime;
  double operamt; // 临时变量，敏感操作金额
  String operRemark; // 临时变量，敏感操作备注
  int productType; // 0普通商品 1必点菜固定 2必点菜可选
  double mustNum; // 必点菜数量
  String specid; // 临时的规格id
  String specname; // 临时的规格名称
  double maxNum; // 最大可选
  double discountamt; // 折扣金额
  String onlyid; // 唯一ID
  double weighNum; // 称重菜重量
  String singleRemark; // 单品备注
  String disRemark; // 打折备注
  String giveRemark; // 赠送备注
  String returnRemark; // 退菜备注
  String sperRemark; // 口味规格备注
  String querytoken; // 团购商品对应券的唯一ID
  bool isDis; // 是否已经打折了
  bool isTC; // 是否退菜
  bool isBag; // 是否已经打包了
  bool isChangePrice; // 是否修改了价格
  double bagPrice; // 单个打包价
  double bagAllPrice; // 打包总价
  double cPrice; // 修改后的价格
  double discountPrice; // 折扣价
  String remark;
  double singleDiscount; // 单品折扣率
  double zsNum; // 赠送数量
  double subqty; // 退菜数量
  bool isGive; // 是否赠送
  bool checked; // 是否选中
  double allDisMprice; // 临时的商品会员总价（计算了数量）
  double selectNum; // 临时的数量
  double productQty; // 当前商品在购物车中的总数量
  double allSellPrice; // 临时的商品销售总价（计算了数量）
  double allMprice; // 临时的商品会员总价（计算了数量）
  String cartKey; // 商品在购物车里的key
  Map<String, int>? lastPos; // 上一次选择的做法下标
  int bxxpxxflag; // 满减送标识 1买x赠x 2满量折扣 3满减 4满赠 5满折
  int specpriceflag; // 特价标识 0非特价 1分类折扣 2菜品折扣 3特价 4手工折扣
  String cxmbillid; // 促销主单id
  bool isCheck;
  double giveNum; // 促销活动买满赠已赠送数量
  List<List<ProductBeanEntity>>? sendList; // 促销已赠送商品
  int billtype; // 1.分类折扣 2.菜品折扣 3.特价菜 4.买赠 5.满量折扣 6.满减 7.满赠 8.满折
  double disPrice; // 折扣金额（一共省了多少钱）
  double allDisSellPrice; // 临时的商品销售总价（计算了数量，没有计算折扣）
  dynamic specBean; // 临时的多规格做法详情（SpecProductBean）
  dynamic setMealBean; // 临时的套餐详情（SetMealBean）
  Map<String, String>? specContent;
  String lastSpecContent; // 最后一次加入购物车的sku组合文本
  String parenttypeid;
  String tempBillid; // 临时必点菜区域id
  int opertype; // 敏感操作字段 操作类型 1正常 2退菜 3赠送 4菜品打折
  List<dynamic>? tempBillidType; // 当前商品同时包含的促销活动（MPProductOrType列表）
  double tempAllPrice; // 临时总现单价
  double tempAllOPrice; // 临时总原价
  double tempAllMemberPrice; // 临时总会员价
  double tempAllDisPrice; // 临时总折扣价
  String salesid; // 业务员、服务员id
  String salesname; // 业务员、服务员名称
  String signtype; // 团购核销选商品是用到
  bool isOpenComb; // 团购核销选商品是否展开套餐
  double temprrPrice; // 临时现价

  ProductBeanEntity({
    this.id = 0,
    this.spid = 0,
    this.sid = 0,
    this.productid = '',
    this.barcode = '',
    this.name = '',
    this.typeid = '',
    this.typeid1 = '',
    this.typeid2 = '',
    this.helpcode = '',
    this.unit = '',
    this.sellprice = 0.0,
    this.mprice1 = 0.0,
    this.mprice2 = 0.0,
    this.mprice3 = 0.0,
    this.inprice = 0.0,
    this.isort = 0,
    this.dscflag = 0,
    this.printflag = 0,
    this.labelflag = 0,
    this.pointflag = 0,
    this.minsaleflag = 0,
    this.presentflag = 0,
    this.curflag = 0,
    this.stockflag = 0,
    this.eatinstoreflag = 0,
    this.bagflag = 0,
    this.recommendflag = 0,
    this.pcshowflag = 0,
    this.scanshowflag = 0,
    this.padshowflag = 0,
    this.mobileshowflag = 0,
    this.sellclearflag = 0,
    this.saledateflag = 0,
    this.stopflag = 0,
    this.cookflag = 0,
    this.specflag = 0,
    this.combflag = 0,
    this.weighflag = 0,
    this.hangflag = 0,
    this.callflag = 0,
    this.urgeflag = 0,
    this.status = 0,
    this.typeproisort = 0,
    this.imageurl = '',
    this.createtime = '',
    this.updatetime = '',
    this.operid = '',
    this.opername = '',
    this.code = '',
    this.rrprice = 0.0,
    this.stockqty = 0.0,
    this.discount = 0.0,
    this.typename = '',
    this.cookaddamt = 0.0,
    this.startsellqty = 1.0,
    this.servicefeeflag = 1,
    this.addsellqty = 1.0,
    this.maxsellqty = 0.0,
    this.jcmbillid = '',
    this.chooseqtyflag = 0,
    this.moreeatflag = 0,
    this.combsource = 0,
    this.datetype = 0,
    this.cycletype = 0,
    this.saletime = '',
    this.rawflag = 0,
    this.saleqty = 0.0,
    this.deductvalue = 0.0,
    this.deducttype = 0,
    this.saleweek = '',
    this.begindate = '',
    this.timetype = 0,
    this.combtype = 0,
    this.enddate = '',
    this.salemonth = '',
    // @Ignore
    this.mustflag = 0,
    this.tpdishflag = 0,
    this.douyinflag = 0,
    this.tpdscflag = 0,
    this.combaddamt = 0.0,
    this.opertime = '',
    this.dishid = '',
    this.dishidzd = '',
    this.ptypt1Price = 0.0,
    this.dySellprice = 0.0,
    this.isSellQty = 0.0,
    this.cartCreatetime = '',
    this.operamt = 0.0,
    this.operRemark = '',
    this.productType = 0,
    this.mustNum = 0.0,
    this.specid = '',
    this.specname = '',
    this.maxNum = 0.0,
    this.discountamt = 0.0,
    this.onlyid = '',
    this.weighNum = 0.0,
    this.singleRemark = '',
    this.disRemark = '',
    this.giveRemark = '',
    this.returnRemark = '',
    this.sperRemark = '',
    this.querytoken = '',
    this.isDis = false,
    this.isTC = false,
    this.isBag = false,
    this.isChangePrice = false,
    this.bagPrice = 0.0,
    this.bagAllPrice = 0.0,
    this.cPrice = 0.0,
    this.discountPrice = 0.0,
    this.remark = '',
    this.singleDiscount = 0.0,
    this.zsNum = 0.0,
    this.subqty = 0.0,
    this.isGive = false,
    this.checked = false,
    this.allDisMprice = 0.0,
    this.selectNum = 0.0,
    this.productQty = 0.0,
    this.allSellPrice = 0.0,
    this.allMprice = 0.0,
    this.cartKey = '',
    this.lastPos,
    this.bxxpxxflag = 0,
    this.specpriceflag = 0,
    this.cxmbillid = '',
    this.isCheck = false,
    this.giveNum = 0.0,
    this.sendList,
    this.billtype = 0,
    this.disPrice = 0.0,
    this.allDisSellPrice = 0.0,
    this.specBean,
    this.setMealBean,
    this.specContent,
    this.lastSpecContent = '',
    this.parenttypeid = '',
    this.tempBillid = '',
    this.opertype = -1,
    this.tempBillidType,
    this.tempAllPrice = 0.0,
    this.tempAllOPrice = 0.0,
    this.tempAllMemberPrice = 0.0,
    this.tempAllDisPrice = 0.0,
    this.salesid = '',
    this.salesname = '',
    this.signtype = '',
    this.isOpenComb = false,
    this.temprrPrice = 0.0,
  });

  factory ProductBeanEntity.fromMap(Map<String, dynamic> m) => ProductBeanEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        productid: m['productid']?.toString() ?? '',
        barcode: m['barcode']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        typeid: m['typeid']?.toString() ?? '',
        typeid1: m['typeid1']?.toString() ?? '',
        typeid2: m['typeid2']?.toString() ?? '',
        helpcode: m['helpcode']?.toString() ?? '',
        unit: m['unit']?.toString() ?? '',
        sellprice: (m['sellprice'] as num?)?.toDouble() ?? 0.0,
        mprice1: (m['mprice1'] as num?)?.toDouble() ?? 0.0,
        mprice2: (m['mprice2'] as num?)?.toDouble() ?? 0.0,
        mprice3: (m['mprice3'] as num?)?.toDouble() ?? 0.0,
        inprice: (m['inprice'] as num?)?.toDouble() ?? 0.0,
        isort: m['isort'] as int? ?? 0,
        dscflag: m['dscflag'] as int? ?? 0,
        printflag: m['printflag'] as int? ?? 0,
        labelflag: m['labelflag'] as int? ?? 0,
        pointflag: m['pointflag'] as int? ?? 0,
        minsaleflag: m['minsaleflag'] as int? ?? 0,
        presentflag: m['presentflag'] as int? ?? 0,
        curflag: m['curflag'] as int? ?? 0,
        stockflag: m['stockflag'] as int? ?? 0,
        eatinstoreflag: m['eatinstoreflag'] as int? ?? 0,
        bagflag: m['bagflag'] as int? ?? 0,
        recommendflag: m['recommendflag'] as int? ?? 0,
        pcshowflag: m['pcshowflag'] as int? ?? 0,
        scanshowflag: m['scanshowflag'] as int? ?? 0,
        padshowflag: m['padshowflag'] as int? ?? 0,
        mobileshowflag: m['mobileshowflag'] as int? ?? 0,
        sellclearflag: m['sellclearflag'] as int? ?? 0,
        saledateflag: m['saledateflag'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        cookflag: m['cookflag'] as int? ?? 0,
        specflag: m['specflag'] as int? ?? 0,
        combflag: m['combflag'] as int? ?? 0,
        weighflag: m['weighflag'] as int? ?? 0,
        hangflag: m['hangflag'] as int? ?? 0,
        callflag: m['callflag'] as int? ?? 0,
        urgeflag: m['urgeflag'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        typeproisort: m['typeproisort'] as int? ?? 0,
        imageurl: m['imageurl']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        rrprice: (m['rrprice'] as num?)?.toDouble() ?? 0.0,
        stockqty: (m['stockqty'] as num?)?.toDouble() ?? 0.0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0.0,
        typename: m['typename']?.toString() ?? '',
        cookaddamt: (m['cookaddamt'] as num?)?.toDouble() ?? 0.0,
        startsellqty: (m['startsellqty'] as num?)?.toDouble() ?? 1.0,
        servicefeeflag: m['servicefeeflag'] as int? ?? 1,
        addsellqty: (m['addsellqty'] as num?)?.toDouble() ?? 1.0,
        maxsellqty: (m['maxsellqty'] as num?)?.toDouble() ?? 0.0,
        jcmbillid: m['jcmbillid']?.toString() ?? '',
        chooseqtyflag: m['chooseqtyflag'] as int? ?? 0,
        moreeatflag: m['moreeatflag'] as int? ?? 0,
        combsource: m['combsource'] as int? ?? 0,
        datetype: m['datetype'] as int? ?? 0,
        cycletype: m['cycletype'] as int? ?? 0,
        saletime: m['saletime']?.toString() ?? '',
        rawflag: m['rawflag'] as int? ?? 0,
        saleqty: (m['saleqty'] as num?)?.toDouble() ?? 0.0,
        deductvalue: (m['deductvalue'] as num?)?.toDouble() ?? 0.0,
        deducttype: m['deducttype'] as int? ?? 0,
        saleweek: m['saleweek']?.toString() ?? '',
        begindate: m['begindate']?.toString() ?? '',
        timetype: m['timetype'] as int? ?? 0,
        combtype: m['combtype'] as int? ?? 0,
        enddate: m['enddate']?.toString() ?? '',
        salemonth: m['salemonth']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'spid': spid,
        'sid': sid,
        'productid': productid,
        'barcode': barcode,
        'name': name,
        'typeid': typeid,
        'typeid1': typeid1,
        'typeid2': typeid2,
        'helpcode': helpcode,
        'unit': unit,
        'sellprice': sellprice,
        'mprice1': mprice1,
        'mprice2': mprice2,
        'mprice3': mprice3,
        'inprice': inprice,
        'isort': isort,
        'dscflag': dscflag,
        'printflag': printflag,
        'labelflag': labelflag,
        'pointflag': pointflag,
        'minsaleflag': minsaleflag,
        'presentflag': presentflag,
        'curflag': curflag,
        'stockflag': stockflag,
        'eatinstoreflag': eatinstoreflag,
        'bagflag': bagflag,
        'recommendflag': recommendflag,
        'pcshowflag': pcshowflag,
        'scanshowflag': scanshowflag,
        'padshowflag': padshowflag,
        'mobileshowflag': mobileshowflag,
        'sellclearflag': sellclearflag,
        'saledateflag': saledateflag,
        'stopflag': stopflag,
        'cookflag': cookflag,
        'specflag': specflag,
        'combflag': combflag,
        'weighflag': weighflag,
        'hangflag': hangflag,
        'callflag': callflag,
        'urgeflag': urgeflag,
        'status': status,
        'typeproisort': typeproisort,
        'imageurl': imageurl,
        'createtime': createtime,
        'updatetime': updatetime,
        'operid': operid,
        'opername': opername,
        'code': code,
        'rrprice': rrprice,
        'stockqty': stockqty,
        'discount': discount,
        'typename': typename,
        'cookaddamt': cookaddamt,
        'startsellqty': startsellqty,
        'servicefeeflag': servicefeeflag,
        'addsellqty': addsellqty,
        'maxsellqty': maxsellqty,
        'jcmbillid': jcmbillid,
        'chooseqtyflag': chooseqtyflag,
        'moreeatflag': moreeatflag,
        'combsource': combsource,
        'datetype': datetype,
        'cycletype': cycletype,
        'saletime': saletime,
        'rawflag': rawflag,
        'saleqty': saleqty,
        'deductvalue': deductvalue,
        'deducttype': deducttype,
        'saleweek': saleweek,
        'begindate': begindate,
        'timetype': timetype,
        'combtype': combtype,
        'enddate': enddate,
        'salemonth': salemonth,
      };
}
