/// 系统用户表（对齐 smdcapp SysUserBean.java）
///
/// 对应数据库表 sys_user，包含系统用户/员工信息。
class SysUserEntity {
  int id;
  int sid;
  int spid;
  String userid;
  String code;
  String name;
  String roleid;
  String mobile;
  String pwd;
  int stopflag;
  String wxopenid;
  String lastlogin;
  String lastip;
  int logincount;
  String createtime;
  int status;
  String updatetime;
  String operid;
  String opername;

  /// 电子邮箱
  String emall;

  /// 收银授权码
  String rfid;

  /// 提成标记 0=不参与 1=参与
  int rechargeflag;

  /// 头像
  String imgurl;

  /// 微信网站应用唯一标识
  String openid;

  SysUserEntity({
    this.id = 0, this.sid = 0, this.spid = 0,
    this.userid = '', this.code = '', this.name = '',
    this.roleid = '', this.mobile = '', this.pwd = '',
    this.stopflag = 0, this.wxopenid = '',
    this.lastlogin = '', this.lastip = '', this.logincount = 0,
    this.createtime = '', this.status = 0,
    this.updatetime = '', this.operid = '', this.opername = '',
    this.emall = '', this.rfid = '',
    this.rechargeflag = 0, this.imgurl = '', this.openid = '',
  });

  factory SysUserEntity.fromMap(Map<String, dynamic> m) => SysUserEntity(
        id: m['id'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        userid: m['userid']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        roleid: m['roleid']?.toString() ?? '',
        mobile: m['mobile']?.toString() ?? '',
        pwd: m['pwd']?.toString() ?? '',
        stopflag: m['stopflag'] as int? ?? 0,
        wxopenid: m['wxopenid']?.toString() ?? '',
        lastlogin: m['lastlogin']?.toString() ?? '',
        lastip: m['lastip']?.toString() ?? '',
        logincount: m['logincount'] as int? ?? 0,
        createtime: m['createtime']?.toString() ?? '',
        status: m['status'] as int? ?? 0,
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        emall: m['emall']?.toString() ?? '',
        rfid: m['rfid']?.toString() ?? '',
        rechargeflag: m['rechargeflag'] as int? ?? 0,
        imgurl: m['imgurl']?.toString() ?? '',
        openid: m['openid']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'sid': sid, 'spid': spid,
        'userid': userid, 'code': code, 'name': name,
        'roleid': roleid, 'mobile': mobile, 'pwd': pwd,
        'stopflag': stopflag, 'wxopenid': wxopenid,
        'lastlogin': lastlogin, 'lastip': lastip,
        'logincount': logincount,
        'createtime': createtime, 'status': status,
        'updatetime': updatetime,
        'operid': operid, 'opername': opername,
        'emall': emall, 'rfid': rfid,
        'rechargeflag': rechargeflag,
        'imgurl': imgurl, 'openid': openid,
      };
}
