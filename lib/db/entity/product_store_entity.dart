/// 商品门店价格表（对齐 smdcapp ProductStore.kt）
///
/// 对应数据库表 t_bi_product_store，包含商品在各门店的价格信息。
class ProductStoreEntity {
  int id;
  int spid;
  int sid;

  /// 0启用 1停用
  int stopflag;

  /// 1正常 0删除
  int status;

  /// 商品id
  String productid;

  /// 进价
  double inprice;

  /// 售价
  double sellprice;

  /// 会员价1
  double mprice1;

  /// 会员价2
  double mprice2;

  /// 会员价3
  double mprice3;

  String createtime;
  String updatetime;
  String operid;
  String opername;

  ProductStoreEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.stopflag = 0, this.status = 0,
    this.productid = '',
    this.inprice = 0, this.sellprice = 0,
    this.mprice1 = 0, this.mprice2 = 0, this.mprice3 = 0,
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
  });

  factory ProductStoreEntity.fromMap(Map<String, dynamic> m) => ProductStoreEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        productid: m['productid']?.toString() ?? '',
        inprice: (m['inprice'] as num?)?.toDouble() ?? 0,
        sellprice: (m['sellprice'] as num?)?.toDouble() ?? 0,
        mprice1: (m['mprice1'] as num?)?.toDouble() ?? 0,
        mprice2: (m['mprice2'] as num?)?.toDouble() ?? 0,
        mprice3: (m['mprice3'] as num?)?.toDouble() ?? 0,
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'stopflag': stopflag, 'status': status,
        'productid': productid,
        'inprice': inprice, 'sellprice': sellprice,
        'mprice1': mprice1, 'mprice2': mprice2, 'mprice3': mprice3,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
      };
}
