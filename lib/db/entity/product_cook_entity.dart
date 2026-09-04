/// 商品做法表（对齐 ProductCook.kt）
class ProductCookEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  int status;
  int maximumflag;
  int maximum;
  int mandatoryflag;
  double mandatoryqty;
  int defrecommend;
  String productid;
  String groupid;
  String cookcode;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  double price; // 做法加价
  String cookname;
  String groupname;
  String cupstickercode;
  int ptype; // 加价类型：0不加 1整份加；2数量加
  int editqtyflag; // 1修改数量

  // ── @Ignore 字段（不入库） ──
  int isort; // 排序
  int selectCookNum; // 选中的数量
  int parentPos; // 父级下标
  int sellclearflag; // 是否沽清
  bool isCheck;

  ProductCookEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.status = 0, this.maximumflag = 0, this.maximum = 0,
    this.mandatoryflag = 0, this.mandatoryqty = 0.0, this.defrecommend = 0,
    this.productid = '', this.groupid = '', this.cookcode = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
    this.price = 0.0, this.cookname = '', this.groupname = '',
    this.cupstickercode = '', this.ptype = 0, this.editqtyflag = 0,
    this.isort = 0, this.selectCookNum = 0, this.parentPos = 0,
    this.sellclearflag = 0, this.isCheck = false,
  });

  factory ProductCookEntity.fromMap(Map<String, dynamic> m) => ProductCookEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        maximumflag: m['maximumflag'] as int? ?? 0,
        maximum: m['maximum'] as int? ?? 0,
        mandatoryflag: m['mandatoryflag'] as int? ?? 0,
        mandatoryqty: (m['mandatoryqty'] as num?)?.toDouble() ?? 0.0,
        defrecommend: m['defrecommend'] as int? ?? 0,
        productid: m['productid']?.toString() ?? '',
        groupid: m['groupid']?.toString() ?? '',
        cookcode: m['cookcode']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        cookname: m['cookname']?.toString() ?? '',
        groupname: m['groupname']?.toString() ?? '',
        cupstickercode: m['cupstickercode']?.toString() ?? '',
        ptype: m['ptype'] as int? ?? 0,
        editqtyflag: m['editqtyflag'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'status': status, 'maximumflag': maximumflag, 'maximum': maximum,
        'mandatoryflag': mandatoryflag, 'mandatoryqty': mandatoryqty,
        'defrecommend': defrecommend,
        'productid': productid, 'groupid': groupid, 'cookcode': cookcode,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
        'price': price, 'cookname': cookname, 'groupname': groupname,
        'cupstickercode': cupstickercode, 'ptype': ptype, 'editqtyflag': editqtyflag,
      };
}
