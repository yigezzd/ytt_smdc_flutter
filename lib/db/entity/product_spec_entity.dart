/// 商品规格关联表（对齐 ProductSpec.kt）
class ProductSpecEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  int isort;
  int status; // 1正常 0删除
  String specid;
  String specname;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  String productid;
  double inprice;
  double mprice1;
  double mprice2;
  double mprice3;
  double sellprice;
  int rawflag;
  double rrprice; // 如果是特价菜，这个是现价
  int specpriceflag; // 如果是3就是特价菜
  int defsizeflag; // 如果是1就是默认规格
  double stockqty;

  // ── @Ignore 字段（不入库） ──
  int sellclearflag; // 是否开启沽清
  bool isCheck;
  double discount; // 临时折扣率

  ProductSpecEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.isort = 0, this.status = 0,
    this.specid = '', this.specname = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
    this.productid = '',
    this.inprice = 0.0, this.mprice1 = 0.0, this.mprice2 = 0.0, this.mprice3 = 0.0,
    this.sellprice = 0.0, this.rawflag = 0,
    this.rrprice = 0.0, this.specpriceflag = 0, this.defsizeflag = 0,
    this.stockqty = 0.0,
    this.sellclearflag = 0, this.isCheck = false, this.discount = 0.0,
  });

  factory ProductSpecEntity.fromMap(Map<String, dynamic> m) => ProductSpecEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        specid: m['specid']?.toString() ?? '',
        specname: m['specname']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        productid: m['productid']?.toString() ?? '',
        inprice: (m['inprice'] as num?)?.toDouble() ?? 0.0,
        mprice1: (m['mprice1'] as num?)?.toDouble() ?? 0.0,
        mprice2: (m['mprice2'] as num?)?.toDouble() ?? 0.0,
        mprice3: (m['mprice3'] as num?)?.toDouble() ?? 0.0,
        sellprice: (m['sellprice'] as num?)?.toDouble() ?? 0.0,
        rawflag: m['rawflag'] as int? ?? 0,
        rrprice: (m['rrprice'] as num?)?.toDouble() ?? 0.0,
        specpriceflag: m['specpriceflag'] as int? ?? 0,
        defsizeflag: m['defsizeflag'] as int? ?? 0,
        stockqty: (m['stockqty'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'isort': isort, 'status': status,
        'specid': specid, 'specname': specname,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
        'productid': productid,
        'inprice': inprice, 'mprice1': mprice1, 'mprice2': mprice2, 'mprice3': mprice3,
        'sellprice': sellprice, 'rawflag': rawflag,
        'rrprice': rrprice, 'specpriceflag': specpriceflag,
        'defsizeflag': defsizeflag, 'stockqty': stockqty,
      };
}
