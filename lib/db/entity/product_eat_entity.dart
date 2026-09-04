/// 商品吃法关联表（对齐 ProductEat.kt）
class ProductEatEntity {
  int id;
  int spid;
  int sid;
  String productid;
  double price; // 该商品专属加价
  String groupid;
  String eatcode; // 吃法code 关联t_eat_info.code
  int status; // 1正常 0删除
  String createtime;
  String updatetime;
  String operid;
  String opername;
  int defrecommend; // 是否默认 1是 0否

  ProductEatEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.productid = '', this.price = 0.0,
    this.groupid = '', this.eatcode = '',
    this.status = 1, this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '', this.defrecommend = 0,
  });

  factory ProductEatEntity.fromMap(Map<String, dynamic> m) => ProductEatEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        productid: m['productid']?.toString() ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        groupid: m['groupid']?.toString() ?? '',
        eatcode: m['eatcode']?.toString() ?? '',
        status: m['status'] as int? ?? 1,
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        defrecommend: m['defrecommend'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'productid': productid, 'price': price,
        'groupid': groupid, 'eatcode': eatcode,
        'status': status, 'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername, 'defrecommend': defrecommend,
      };
}
