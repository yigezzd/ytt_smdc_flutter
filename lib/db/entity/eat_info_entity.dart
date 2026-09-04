/// 吃法信息表（对齐 EatInfo.kt，含 @Ignore 字段）
class EatInfoEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  String code;
  String name;
  int ptype; // 加价类型 0不加价 1按整份加 2按数量加
  double price;
  String groupid;
  int stopflag; // 0启用 1停用
  int status; // 1正常 0删除
  int isort;
  int groupisort;
  String outlet; // 出品档口
  String createtime;
  String updatetime;
  String operid;
  String opername;

  // ── @Ignore 字段（不入库） ──
  String saleid;
  String onlyid;
  String groupname;
  String eatonlyid; // 吃法唯一ID
  String qty;

  EatInfoEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.code = '', this.name = '', this.ptype = 0,
    this.price = 0.0, this.groupid = '',
    this.stopflag = 0, this.status = 1,
    this.isort = 0, this.groupisort = 0,
    this.outlet = '', this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
    this.saleid = '', this.onlyid = '', this.groupname = '',
    this.eatonlyid = '', this.qty = '',
  });

  factory EatInfoEntity.fromMap(Map<String, dynamic> m) => EatInfoEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        code: m['code']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        ptype: m['ptype'] as int? ?? 0,
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        groupid: m['groupid']?.toString() ?? '',
        stopflag: m['stopflag'] as int? ?? 0,
        status: m['status'] as int? ?? 1,
        isort: m['isort'] as int? ?? 0,
        groupisort: m['groupisort'] as int? ?? 0,
        outlet: m['outlet']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'code': code, 'name': name, 'ptype': ptype,
        'price': price, 'groupid': groupid,
        'stopflag': stopflag, 'status': status,
        'isort': isort, 'groupisort': groupisort,
        'outlet': outlet, 'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
      };
}
