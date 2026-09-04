/// 促销商品或分类表（对齐 MPProductOrType.kt，含 @Ignore 字段）
class MpProductOrTypeEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  double discount; // 折扣（分类促销折扣从这里取）
  double price; // 特价菜用到
  String billid;
  String ruleid; // 关联规则表t_mp_pt_rule
  String productid;
  String typeid;
  String specid; // 规格唯一标识
  String saletype; // 1需要这些商品或分类来满足规则 2赠送的

  // ── @Ignore 字段（不入库） ──
  int billType; // 促销类型 1.分类折扣 2.菜品折扣 3.特价菜 4.买赠 5.满量折扣 6.满减 7.满赠 8.满折
  double tempPrice; // 临时价格
  double tempDiscount; // 临时折扣

  MpProductOrTypeEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.discount = 0.0, this.price = 0.0,
    this.billid = '', this.ruleid = '',
    this.productid = '', this.typeid = '',
    this.specid = '', this.saletype = '',
    this.billType = 0, this.tempPrice = 0.0, this.tempDiscount = 0.0,
  });

  factory MpProductOrTypeEntity.fromMap(Map<String, dynamic> m) =>
      MpProductOrTypeEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0.0,
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        billid: m['billid']?.toString() ?? '',
        ruleid: m['ruleid']?.toString() ?? '',
        productid: m['productid']?.toString() ?? '',
        typeid: m['typeid']?.toString() ?? '',
        specid: m['specid']?.toString() ?? '',
        saletype: m['saletype']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'discount': discount, 'price': price,
        'billid': billid, 'ruleid': ruleid,
        'productid': productid, 'typeid': typeid,
        'specid': specid, 'saletype': saletype,
      };
}
