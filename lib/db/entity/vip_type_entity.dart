/// 会员分类表（对齐 smdcapp VipType.java）
///
/// 对应数据库表 t_vip_type，包含会员分类的基础信息 + 优惠配置。
/// 注意：与 [MpVipTypeEntity]（t_mp_pt_vip_type，促销VIP类型）不同。
class VipTypeEntity {
  int id;
  int spid;
  int sid;
  String typeid;
  String code;
  String name;

  /// 优惠类型：0=无优惠, 1=零售价折扣, 2=会员价1, 3=会员价2, 4=会员价3
  int prefetype;

  /// 折扣率（如 90 表示 9折）
  int discount;

  int birthdiscount;
  double birthpointratio;
  int vipdaydiscount;
  double vipdaypointratio;
  int pointflag;
  int pointtype;
  int pointbase;
  double point;
  double salemoney;
  double beginpoint;
  double endpoint;
  int isvipmoney;
  String backgroundImg;
  String privilegeRem;
  int validdays;
  double nowmoney;
  int usepointflag;
  double usepoints;
  double usepointtomoney;
  int salelimittype;
  double salelimitamt;
  double salelimitset;
  int isort;
  int status;
  String operid;
  String opername;
  String createtime;
  String updatetime;
  double lowaddmoney;
  int saledaycount;
  int stopflag;
  int validflag;
  double capitalrate;
  double giverate;
  int rechargeflag;
  int rechargetype;
  double rechargepoint;
  double rechargeamt;

  /// 附加费（服务费）折扣开关：0=关, 1=开
  int fjflag;

  /// 附加费（服务费）折扣率
  double fjfdiscount;

  VipTypeEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.typeid = '', this.code = '', this.name = '',
    this.prefetype = 0, this.discount = 100,
    this.birthdiscount = 0, this.birthpointratio = 0,
    this.vipdaydiscount = 0, this.vipdaypointratio = 0,
    this.pointflag = 0, this.pointtype = 0, this.pointbase = 0,
    this.point = 0, this.salemoney = 0,
    this.beginpoint = 0, this.endpoint = 0,
    this.isvipmoney = 0, this.backgroundImg = '', this.privilegeRem = '',
    this.validdays = 0, this.nowmoney = 0,
    this.usepointflag = 0, this.usepoints = 0, this.usepointtomoney = 0,
    this.salelimittype = 0, this.salelimitamt = 0, this.salelimitset = 0,
    this.isort = 0, this.status = 0,
    this.operid = '', this.opername = '',
    this.createtime = '', this.updatetime = '',
    this.lowaddmoney = 0, this.saledaycount = 0,
    this.stopflag = 0, this.validflag = 0,
    this.capitalrate = 0, this.giverate = 0,
    this.rechargeflag = 0, this.rechargetype = 0,
    this.rechargepoint = 0, this.rechargeamt = 0,
    this.fjflag = 0, this.fjfdiscount = 0,
  });

  factory VipTypeEntity.fromMap(Map<String, dynamic> m) => VipTypeEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        typeid: m['typeid']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        prefetype: m['prefetype'] as int? ?? 0,
        discount: m['discount'] as int? ?? 100,
        birthdiscount: m['birthdiscount'] as int? ?? 0,
        birthpointratio: (m['birthpointratio'] as num?)?.toDouble() ?? 0,
        vipdaydiscount: m['vipdaydiscount'] as int? ?? 0,
        vipdaypointratio: (m['vipdaypointratio'] as num?)?.toDouble() ?? 0,
        pointflag: m['pointflag'] as int? ?? 0,
        pointtype: m['pointtype'] as int? ?? 0,
        pointbase: m['pointbase'] as int? ?? 0,
        point: (m['point'] as num?)?.toDouble() ?? 0,
        salemoney: (m['salemoney'] as num?)?.toDouble() ?? 0,
        beginpoint: (m['beginpoint'] as num?)?.toDouble() ?? 0,
        endpoint: (m['endpoint'] as num?)?.toDouble() ?? 0,
        isvipmoney: m['isvipmoney'] as int? ?? 0,
        backgroundImg: m['background_img']?.toString() ?? '',
        privilegeRem: m['privilege_remark']?.toString() ?? '',
        validdays: m['validdays'] as int? ?? 0,
        nowmoney: (m['nowmoney'] as num?)?.toDouble() ?? 0,
        usepointflag: m['usepointflag'] as int? ?? 0,
        usepoints: (m['usepoints'] as num?)?.toDouble() ?? 0,
        usepointtomoney: (m['usepointtomoney'] as num?)?.toDouble() ?? 0,
        salelimittype: m['salelimittype'] as int? ?? 0,
        salelimitamt: (m['salelimitamt'] as num?)?.toDouble() ?? 0,
        salelimitset: (m['salelimitset'] as num?)?.toDouble() ?? 0,
        isort: m['isort'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        lowaddmoney: (m['lowaddmoney'] as num?)?.toDouble() ?? 0,
        saledaycount: m['saledaycount'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        validflag: m['validflag'] as int? ?? 0,
        capitalrate: (m['capitalrate'] as num?)?.toDouble() ?? 0,
        giverate: (m['giverate'] as num?)?.toDouble() ?? 0,
        rechargeflag: m['rechargeflag'] as int? ?? 0,
        rechargetype: m['rechargetype'] as int? ?? 0,
        rechargepoint: (m['rechargepoint'] as num?)?.toDouble() ?? 0,
        rechargeamt: (m['rechargeamt'] as num?)?.toDouble() ?? 0,
        fjflag: m['fjflag'] as int? ?? 0,
        fjfdiscount: (m['fjfdiscount'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'typeid': typeid, 'code': code, 'name': name,
        'prefetype': prefetype, 'discount': discount,
        'birthdiscount': birthdiscount,
        'birthpointratio': birthpointratio,
        'vipdaydiscount': vipdaydiscount,
        'vipdaypointratio': vipdaypointratio,
        'pointflag': pointflag, 'pointtype': pointtype,
        'pointbase': pointbase, 'point': point,
        'salemoney': salemoney,
        'beginpoint': beginpoint, 'endpoint': endpoint,
        'isvipmoney': isvipmoney,
        'background_img': backgroundImg,
        'privilege_remark': privilegeRem,
        'validdays': validdays, 'nowmoney': nowmoney,
        'usepointflag': usepointflag,
        'usepoints': usepoints,
        'usepointtomoney': usepointtomoney,
        'salelimittype': salelimittype,
        'salelimitamt': salelimitamt,
        'salelimitset': salelimitset,
        'isort': isort, 'status': status,
        'operid': operid, 'opername': opername,
        'createtime': createtime, 'updatetime': updatetime,
        'lowaddmoney': lowaddmoney,
        'saledaycount': saledaycount,
        'stopflag': stopflag, 'validflag': validflag,
        'capitalrate': capitalrate, 'giverate': giverate,
        'rechargeflag': rechargeflag,
        'rechargetype': rechargetype,
        'rechargepoint': rechargepoint,
        'rechargeamt': rechargeamt,
        'fjflag': fjflag, 'fjfdiscount': fjfdiscount,
      };
}
