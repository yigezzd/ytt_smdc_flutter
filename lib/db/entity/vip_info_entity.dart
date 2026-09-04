/// 会员信息表（对齐 smdcapp VipInfo.java）
///
/// 对应数据库表 t_vip_info，包含会员基础信息、余额、积分等。
class VipInfoEntity {
  int id;
  int spid;
  int sid;
  String typeid;
  String vipid;
  String vipno;
  String vipname;
  String mobile;
  String address;
  String password;
  String birthday;
  String birthdaylan;
  String sex;
  String idcardno;
  String rfcardid;
  String jscardid;
  String wxopenid;

  /// 有效期控制标识：0=不控制 1=按年 2=按月 3=自定义
  int validflag;
  String validdate;

  /// 欠款消费标识：0=不可以 1=可以
  int overflag;
  double overmoney;
  double nowpoint;
  double nowmoney;
  double capitalmoney;
  double givemoney;
  double alladdmoney;
  double allsalemoney;
  double pocketmoney;
  String usedate;
  String refunddate;
  String lastsaledate;

  /// 0=未发卡 1=正常 2=挂失 3=作废
  int cardstatus;
  int issuesid;
  String memo;
  int status;
  String createid;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  String imageurl;

  /// 微会员主卡标识
  int usecardflag;

  /// 会员生日修改次数
  int birthdayednum;

  /// 第三方系统会员id
  String thirdvipid;
  String helpcode;

  /// 注册类型 1=线下注册 2=后台注册 3=安卓注册 4=小程序注册
  int regtype;
  String nickname;
  String faceid;
  double arrearages;

  /// 证件类型 1=身份证 2=护照 3=军官证
  int cardtype;

  VipInfoEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.typeid = '', this.vipid = '', this.vipno = '',
    this.vipname = '', this.mobile = '', this.address = '',
    this.password = '', this.birthday = '', this.birthdaylan = '',
    this.sex = '', this.idcardno = '', this.rfcardid = '',
    this.jscardid = '', this.wxopenid = '',
    this.validflag = 0, this.validdate = '',
    this.overflag = 0, this.overmoney = 0,
    this.nowpoint = 0, this.nowmoney = 0,
    this.capitalmoney = 0, this.givemoney = 0,
    this.alladdmoney = 0, this.allsalemoney = 0,
    this.pocketmoney = 0,
    this.usedate = '', this.refunddate = '', this.lastsaledate = '',
    this.cardstatus = 0, this.issuesid = 0,
    this.memo = '', this.status = 0,
    this.createid = '', this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '', this.imageurl = '',
    this.usecardflag = 0, this.birthdayednum = 0,
    this.thirdvipid = '', this.helpcode = '',
    this.regtype = 0, this.nickname = '', this.faceid = '',
    this.arrearages = 0, this.cardtype = 0,
  });

  factory VipInfoEntity.fromMap(Map<String, dynamic> m) => VipInfoEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        typeid: m['typeid']?.toString() ?? '',
        vipid: m['vipid']?.toString() ?? '',
        vipno: m['vipno']?.toString() ?? '',
        vipname: m['vipname']?.toString() ?? '',
        mobile: m['mobile']?.toString() ?? '',
        address: m['address']?.toString() ?? '',
        password: m['password']?.toString() ?? '',
        birthday: m['birthday']?.toString() ?? '',
        birthdaylan: m['birthdaylan']?.toString() ?? '',
        sex: m['sex']?.toString() ?? '',
        idcardno: m['idcardno']?.toString() ?? '',
        rfcardid: m['rfcardid']?.toString() ?? '',
        jscardid: m['jscardid']?.toString() ?? '',
        wxopenid: m['wxopenid']?.toString() ?? '',
        validflag: m['validflag'] as int? ?? 0,
        validdate: m['validdate']?.toString() ?? '',
        overflag: m['overflag'] as int? ?? 0,
        overmoney: (m['overmoney'] as num?)?.toDouble() ?? 0,
        nowpoint: (m['nowpoint'] as num?)?.toDouble() ?? 0,
        nowmoney: (m['nowmoney'] as num?)?.toDouble() ?? 0,
        capitalmoney: (m['capitalmoney'] as num?)?.toDouble() ?? 0,
        givemoney: (m['givemoney'] as num?)?.toDouble() ?? 0,
        alladdmoney: (m['alladdmoney'] as num?)?.toDouble() ?? 0,
        allsalemoney: (m['allsalemoney'] as num?)?.toDouble() ?? 0,
        pocketmoney: (m['pocketmoney'] as num?)?.toDouble() ?? 0,
        usedate: m['usedate']?.toString() ?? '',
        refunddate: m['refunddate']?.toString() ?? '',
        lastsaledate: m['lastsaledate']?.toString() ?? '',
        cardstatus: m['cardstatus'] as int? ?? 0,
        issuesid: m['issuesid'] as int? ?? 0,
        memo: m['memo']?.toString() ?? '',
        status: m['status'] as int? ?? 0,
        createid: m['createid']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        imageurl: m['imageurl']?.toString() ?? '',
        usecardflag: m['usecardflag'] as int? ?? 0,
        birthdayednum: m['birthdayednum'] as int? ?? 0,
        thirdvipid: m['thiirdvipid']?.toString() ?? '',
        helpcode: m['helpcode']?.toString() ?? '',
        regtype: m['regtype'] as int? ?? 0,
        nickname: m['nickname']?.toString() ?? '',
        faceid: m['faceid']?.toString() ?? '',
        arrearages: (m['arrearages'] as num?)?.toDouble() ?? 0,
        cardtype: m['cardtype'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'typeid': typeid, 'vipid': vipid, 'vipno': vipno,
        'vipname': vipname, 'mobile': mobile, 'address': address,
        'password': password, 'birthday': birthday,
        'birthdaylan': birthdaylan, 'sex': sex,
        'idcardno': idcardno, 'rfcardid': rfcardid,
        'jscardid': jscardid, 'wxopenid': wxopenid,
        'validflag': validflag, 'validdate': validdate,
        'overflag': overflag, 'overmoney': overmoney,
        'nowpoint': nowpoint, 'nowmoney': nowmoney,
        'capitalmoney': capitalmoney, 'givemoney': givemoney,
        'alladdmoney': alladdmoney, 'allsalemoney': allsalemoney,
        'pocketmoney': pocketmoney,
        'usedate': usedate, 'refunddate': refunddate,
        'lastsaledate': lastsaledate,
        'cardstatus': cardstatus, 'issuesid': issuesid,
        'memo': memo, 'status': status,
        'createid': createid, 'createtime': createtime,
        'updatetime': updatetime,
        'operid': operid, 'opername': opername,
        'imageurl': imageurl,
        'usecardflag': usecardflag,
        'birthdayednum': birthdayednum,
        'thiirdvipid': thirdvipid,
        'helpcode': helpcode,
        'regtype': regtype, 'nickname': nickname,
        'faceid': faceid, 'arrearages': arrearages,
        'cardtype': cardtype,
      };
}
