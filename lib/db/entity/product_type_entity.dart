/// 商品分类表（对齐 ProductType.kt，含 @Ignore 字段）
class ProductTypeEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  int status;
  int isort;
  int stopflag; // 0启用 1停用
  String typeid;
  String code;
  String name;
  String parenttypeid;
  int level;
  String typeid1;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  int discount;
  int pcshowflag;
  int padshowflag;
  int mobileshowflag;
  int scanshowflag;

  // ── @Ignore 字段（不入库） ──
  bool isCheck;
  double typeProductNum; // 购物车分类商品数量
  double num; // 当前商品添加的数量
  List<ProductTypeEntity>? children; // 二级子分类

  ProductTypeEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.status = 0, this.isort = 0, this.stopflag = 0,
    this.typeid = '', this.code = '', this.name = '',
    this.parenttypeid = '', this.level = 0, this.typeid1 = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
    this.discount = 0, this.pcshowflag = 0, this.padshowflag = 0,
    this.mobileshowflag = 0, this.scanshowflag = 0,
    this.isCheck = false, this.typeProductNum = 0.0,
    this.num = 0.0, this.children,
  });

  factory ProductTypeEntity.fromMap(Map<String, dynamic> m) => ProductTypeEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        typeid: m['typeid']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        parenttypeid: m['parenttypeid']?.toString() ?? '',
        level: m['level'] as int? ?? 0,
        typeid1: m['typeid1']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        discount: m['discount'] as int? ?? 0,
        pcshowflag: m['pcshowflag'] as int? ?? 0,
        padshowflag: m['padshowflag'] as int? ?? 0,
        mobileshowflag: m['mobileshowflag'] as int? ?? 0,
        scanshowflag: m['scanshowflag'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'status': status, 'isort': isort, 'stopflag': stopflag,
        'typeid': typeid, 'code': code, 'name': name,
        'parenttypeid': parenttypeid, 'level': level, 'typeid1': typeid1,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
        'discount': discount, 'pcshowflag': pcshowflag,
        'padshowflag': padshowflag, 'mobileshowflag': mobileshowflag,
        'scanshowflag': scanshowflag,
      };

  /// 深拷贝（对齐 cloneBean）
  ProductTypeEntity cloneBean() => ProductTypeEntity(
        id: id, spid: spid, sid: sid, status: status, isort: isort,
        stopflag: stopflag, typeid: typeid, code: code, name: name,
        parenttypeid: parenttypeid, level: level, typeid1: typeid1,
        createtime: createtime, updatetime: updatetime,
        operid: operid, opername: opername, discount: discount,
        pcshowflag: pcshowflag, padshowflag: padshowflag,
        mobileshowflag: mobileshowflag, scanshowflag: scanshowflag,
        isCheck: isCheck, typeProductNum: typeProductNum, num: num,
        children: children?.map((c) => c.cloneBean()).toList(),
      );
}
