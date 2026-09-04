/// 做法信息表（对齐 CookInfo.kt）
class CookInfoEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  int ptype; // 加价类型：0不加 1整份加；2数量加
  int status;
  int editqtyflag; // 1修改数量
  int maximum; // 最多可选几种
  int maximumflag; // 是否开启最多可选
  int mandatoryflag; // 点餐时必选
  int mandatoryqty; // 必选数量
  int defrecommend; // 默认推荐 1推荐
  String code;
  String name;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  int stopflag;
  String cookcode;
  String productid;
  String groupid; // 做法分组id
  String cookname;
  String groupname;
  String cupstickercode;
  double price; // 加价金额
  int? isort; // 做法排序
  int? groupisort; // 做法分组排序

  // ── @Ignore 字段（不入库） ──
  bool isCheck;
  int selectCookNum; // 选中的数量
  int parentPos; // 父级下标

  CookInfoEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.ptype = 0, this.status = 0, this.editqtyflag = 0,
    this.maximum = 0, this.maximumflag = 0,
    this.mandatoryflag = 0, this.mandatoryqty = 0, this.defrecommend = 0,
    this.code = '', this.name = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '', this.stopflag = 0,
    this.cookcode = '', this.productid = '',
    this.groupid = '', this.cookname = '', this.groupname = '',
    this.cupstickercode = '', this.price = 0.0,
    this.isort = 0, this.groupisort = 0,
    this.isCheck = false, this.selectCookNum = 0, this.parentPos = 0,
  });

  factory CookInfoEntity.fromMap(Map<String, dynamic> m) => CookInfoEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        ptype: m['ptype'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        editqtyflag: m['editqtyflag'] as int? ?? 0,
        maximum: m['maximum'] as int? ?? 0,
        maximumflag: m['maximumflag'] as int? ?? 0,
        mandatoryflag: m['mandatoryflag'] as int? ?? 0,
        mandatoryqty: m['mandatoryqty'] as int? ?? 0,
        defrecommend: m['defrecommend'] as int? ?? 0,
        code: m['code']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        stopflag: m['stopflag'] as int? ?? 0,
        cookcode: m['cookcode']?.toString() ?? '',
        productid: m['productid']?.toString() ?? '',
        groupid: m['groupid']?.toString() ?? '',
        cookname: m['cookname']?.toString() ?? '',
        groupname: m['groupname']?.toString() ?? '',
        cupstickercode: m['cupstickercode']?.toString() ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        isort: m['isort'] as int?,
        groupisort: m['groupisort'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'ptype': ptype, 'status': status, 'editqtyflag': editqtyflag,
        'maximum': maximum, 'maximumflag': maximumflag,
        'mandatoryflag': mandatoryflag, 'mandatoryqty': mandatoryqty,
        'defrecommend': defrecommend,
        'code': code, 'name': name,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername, 'stopflag': stopflag,
        'cookcode': cookcode, 'productid': productid,
        'groupid': groupid, 'cookname': cookname, 'groupname': groupname,
        'cupstickercode': cupstickercode, 'price': price,
        'isort': isort, 'groupisort': groupisort,
      };
}
