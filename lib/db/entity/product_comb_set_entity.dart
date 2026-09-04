/// 套餐明细表（对齐 ProductCombSet.kt，含 @Ignore 字段）
class ProductCombSetEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  int repeatflag; // 相同菜品可重复选择
  int defflag; // 是否默认
  String specid;
  String combid;
  String productid;
  String groupid;
  String groupname;
  String productname;
  String barcode;
  String unit;
  String size;
  double selectqty; // 三选1
  double price;
  double qty;
  int status;
  int isort;
  int stopflag;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  double cutprice; // 减价
  double addprice; // 加价
  int selecttype; // 选择类型1=按数量 2=按项

  // ── @Ignore 字段（不入库） ──
  String specname;
  String tempOnlyid;
  double mprice1;
  int printflag;
  int curflag;
  double mprice2;
  double mprice3;
  int combflag;
  String imageurl;
  double sellprice;
  String name;
  int? combtype;
  String typeid;
  int labelflag;
  String combsource;
  String cartCreateTime;
  String typename;
  double selectSetMealNum;
  bool isCheck;
  double ptypt1Price;
  double ptypt2Price;
  String productcode;
  double stockqty;
  int sellclearflag;
  int specflag;
  int cookflag;
  int parentPos;
  double parentNum;
  int childParentPos;
  String sku;
  bool isShowAddMinus;
  String combsetproductid;

  ProductCombSetEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.repeatflag = 0, this.defflag = 0,
    this.specid = '', this.combid = '', this.productid = '',
    this.groupid = '', this.groupname = '',
    this.productname = '', this.barcode = '', this.unit = '', this.size = '',
    this.selectqty = 0.0, this.price = 0.0, this.qty = 0.0,
    this.status = 0, this.isort = 0, this.stopflag = 0,
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
    this.cutprice = 0.0, this.addprice = 0.0, this.selecttype = 1,
    this.specname = '', this.tempOnlyid = '',
    this.mprice1 = 0.0, this.printflag = 0, this.curflag = 0,
    this.mprice2 = 0.0, this.mprice3 = 0.0,
    this.combflag = 0, this.imageurl = '', this.sellprice = 0.0,
    this.name = '', this.combtype = 0, this.typeid = '',
    this.labelflag = 0, this.combsource = '', this.cartCreateTime = '',
    this.typename = '', this.selectSetMealNum = 0.0, this.isCheck = false,
    this.ptypt1Price = 0.0, this.ptypt2Price = 0.0,
    this.productcode = '', this.stockqty = 0.0,
    this.sellclearflag = 0, this.specflag = 0, this.cookflag = 0,
    this.parentPos = 0, this.parentNum = 0.0, this.childParentPos = 0,
    this.sku = '', this.isShowAddMinus = false, this.combsetproductid = '',
  });

  factory ProductCombSetEntity.fromMap(Map<String, dynamic> m) => ProductCombSetEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        repeatflag: m['repeatflag'] as int? ?? 0,
        defflag: m['defflag'] as int? ?? 0,
        specid: m['specid']?.toString() ?? '',
        combid: m['combid']?.toString() ?? '',
        productid: m['productid']?.toString() ?? '',
        groupid: m['groupid']?.toString() ?? '',
        groupname: m['groupname']?.toString() ?? '',
        productname: m['productname']?.toString() ?? '',
        barcode: m['barcode']?.toString() ?? '',
        unit: m['unit']?.toString() ?? '',
        size: m['size']?.toString() ?? '',
        selectqty: (m['selectqty'] as num?)?.toDouble() ?? 0.0,
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        qty: (m['qty'] as num?)?.toDouble() ?? 0.0,
        status: m['status'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        cutprice: (m['cutprice'] as num?)?.toDouble() ?? 0.0,
        addprice: (m['addprice'] as num?)?.toDouble() ?? 0.0,
        selecttype: m['selecttype'] as int? ?? 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'repeatflag': repeatflag, 'defflag': defflag,
        'specid': specid, 'combid': combid, 'productid': productid,
        'groupid': groupid, 'groupname': groupname,
        'productname': productname, 'barcode': barcode,
        'unit': unit, 'size': size,
        'selectqty': selectqty, 'price': price, 'qty': qty,
        'status': status, 'isort': isort, 'stopflag': stopflag,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
        'cutprice': cutprice, 'addprice': addprice, 'selecttype': selecttype,
      };
}
