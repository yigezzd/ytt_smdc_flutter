/// 必点菜商品表（对齐 MustProduct.kt）
class MustProductEntity {
  int id;
  int spid;
  int sid;
  String productid;
  String specid;
  String billid;
  String specname;
  double mustqty;

  MustProductEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.productid = '', this.specid = '',
    this.billid = '', this.specname = '', this.mustqty = 1.0,
  });

  factory MustProductEntity.fromMap(Map<String, dynamic> m) => MustProductEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        productid: m['productid']?.toString() ?? '',
        specid: m['specid']?.toString() ?? '',
        billid: m['billid']?.toString() ?? '',
        specname: m['specname']?.toString() ?? '',
        mustqty: (m['mustqty'] as num?)?.toDouble() ?? 1.0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'productid': productid, 'specid': specid,
        'billid': billid, 'specname': specname,
        'mustqty': mustqty,
      };
}
