/// 系统门店表（对齐 smdcapp SysStore.kt）
///
/// 对应数据库表 sys_store，包含门店基础信息与配置。
class SysStoreEntity {
  int id;
  int dbid;
  int spid;
  int sid;
  int status;
  int isort;

  /// 0启用 1停用
  int stopflag;
  String dbname;
  String account;
  String daprovince;
  String dacity;
  String dacounty;
  String linkman;
  String linkaddr;
  String linkmobile;
  int mobilepay;
  int paytype;
  int vertype;
  int vipflag;
  int termmaxnum;
  int invitecode;
  int storemodel;
  int viprechargeflag;

  /// 扫码点餐
  int scanbarcodeflag;

  /// 外卖平台
  int takeoutflag;

  /// 微商城
  int vipmallflag;

  /// 排队取号
  int linenumberflag;

  /// 门店商品配置
  int itemtypeconfig;

  /// 1=按商品分类 2=按商品档案
  int itemtypeflag;

  /// 0=简易 1=快餐 2=正餐
  int miniverflag;
  String vendorcode;
  String vendorname;
  String terminalsn;
  String terminalkey;
  String registtime;
  String validtime;
  String starttime;
  String endtime;
  String trade;
  String code;
  String name;
  String roleid;
  String mobile;
  String lng;
  String lat;
  String pwd;
  String rfid;
  String lastlogin;
  String lastip;
  int logincount;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  String imgurl;
  String jobid;
  int sex;
  String icard;
  String entrytime;
  String birthtime;
  double viewrepamtrate;
  double attendancegroupid;
  String areaid;
  int proflag;
  double distpricerate;
  double distprice;
  String shopid;
  int settlementflag;
  String clearalltime;
  int termmaxnumAgent;

  SysStoreEntity({
    this.id = 0, this.dbid = 0, this.spid = 0, this.sid = 0,
    this.status = 0, this.isort = 0, this.stopflag = 0,
    this.dbname = '', this.account = '',
    this.daprovince = '', this.dacity = '', this.dacounty = '',
    this.linkman = '', this.linkaddr = '', this.linkmobile = '',
    this.mobilepay = 0, this.paytype = 0, this.vertype = 0,
    this.vipflag = 0, this.termmaxnum = 0, this.invitecode = 0,
    this.storemodel = 0, this.viprechargeflag = 0,
    this.scanbarcodeflag = 0, this.takeoutflag = 0,
    this.vipmallflag = 0, this.linenumberflag = 0,
    this.itemtypeconfig = 0, this.itemtypeflag = 0,
    this.miniverflag = 2,
    this.vendorcode = '', this.vendorname = '',
    this.terminalsn = '', this.terminalkey = '',
    this.registtime = '', this.validtime = '',
    this.starttime = '', this.endtime = '',
    this.trade = '', this.code = '', this.name = '',
    this.roleid = '', this.mobile = '',
    this.lng = '', this.lat = '',
    this.pwd = '', this.rfid = '',
    this.lastlogin = '', this.lastip = '', this.logincount = 0,
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '', this.imgurl = '',
    this.jobid = '', this.sex = 0, this.icard = '',
    this.entrytime = '', this.birthtime = '',
    this.viewrepamtrate = 0, this.attendancegroupid = 0,
    this.areaid = '', this.proflag = 0,
    this.distpricerate = 0, this.distprice = 0,
    this.shopid = '', this.settlementflag = 0,
    this.clearalltime = '', this.termmaxnumAgent = 0,
  });

  factory SysStoreEntity.fromMap(Map<String, dynamic> m) => SysStoreEntity(
        id: m['id'] as int? ?? 0,
        dbid: m['dbid'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        dbname: m['dbname']?.toString() ?? '',
        account: m['account']?.toString() ?? '',
        daprovince: m['daprovince']?.toString() ?? '',
        dacity: m['dacity']?.toString() ?? '',
        dacounty: m['dacounty']?.toString() ?? '',
        linkman: m['linkman']?.toString() ?? '',
        linkaddr: m['linkaddr']?.toString() ?? '',
        linkmobile: m['linkmobile']?.toString() ?? '',
        mobilepay: m['mobilepay'] as int? ?? 0,
        paytype: m['paytype'] as int? ?? 0,
        vertype: m['vertype'] as int? ?? 0,
        vipflag: m['vipflag'] as int? ?? 0,
        termmaxnum: m['termmaxnum'] as int? ?? 0,
        invitecode: m['invitecode'] as int? ?? 0,
        storemodel: m['storemodel'] as int? ?? 0,
        viprechargeflag: m['viprechargeflag'] as int? ?? 0,
        scanbarcodeflag: m['scanbarcodeflag'] as int? ?? 0,
        takeoutflag: m['takeoutflag'] as int? ?? 0,
        vipmallflag: m['vipmallflag'] as int? ?? 0,
        linenumberflag: m['linenumberflag'] as int? ?? 0,
        itemtypeconfig: m['itemtypeconfig'] as int? ?? 0,
        itemtypeflag: m['itemtypeflag'] as int? ?? 0,
        miniverflag: m['miniverflag'] as int? ?? 2,
        vendorcode: m['vendorcode']?.toString() ?? '',
        vendorname: m['vendorname']?.toString() ?? '',
        terminalsn: m['terminalsn']?.toString() ?? '',
        terminalkey: m['terminalkey']?.toString() ?? '',
        registtime: m['registtime']?.toString() ?? '',
        validtime: m['validtime']?.toString() ?? '',
        starttime: m['starttime']?.toString() ?? '',
        endtime: m['endtime']?.toString() ?? '',
        trade: m['trade']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        roleid: m['roleid']?.toString() ?? '',
        mobile: m['mobile']?.toString() ?? '',
        lng: m['lng']?.toString() ?? '',
        lat: m['lat']?.toString() ?? '',
        pwd: m['pwd']?.toString() ?? '',
        rfid: m['rfid']?.toString() ?? '',
        lastlogin: m['lastlogin']?.toString() ?? '',
        lastip: m['lastip']?.toString() ?? '',
        logincount: m['logincount'] as int? ?? 0,
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        imgurl: m['imgurl']?.toString() ?? '',
        jobid: m['jobid']?.toString() ?? '',
        sex: m['sex'] as int? ?? 0,
        icard: m['icard']?.toString() ?? '',
        entrytime: m['entrytime']?.toString() ?? '',
        birthtime: m['birthtime']?.toString() ?? '',
        viewrepamtrate: (m['viewrepamtrate'] as num?)?.toDouble() ?? 0,
        attendancegroupid: (m['attendancegroupid'] as num?)?.toDouble() ?? 0,
        areaid: m['areaid']?.toString() ?? '',
        proflag: m['proflag'] as int? ?? 0,
        distpricerate: (m['distpricerate'] as num?)?.toDouble() ?? 0,
        distprice: (m['distprice'] as num?)?.toDouble() ?? 0,
        shopid: m['shopid']?.toString() ?? '',
        settlementflag: m['settlementflag'] as int? ?? 0,
        clearalltime: m['clearalltime']?.toString() ?? '',
        termmaxnumAgent: m['termmaxnum_agent'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'dbid': dbid, 'spid': spid, 'sid': sid,
        'status': status, 'isort': isort, 'stopflag': stopflag,
        'dbname': dbname, 'account': account,
        'daprovince': daprovince, 'dacity': dacity, 'dacounty': dacounty,
        'linkman': linkman, 'linkaddr': linkaddr, 'linkmobile': linkmobile,
        'mobilepay': mobilepay, 'paytype': paytype, 'vertype': vertype,
        'vipflag': vipflag, 'termmaxnum': termmaxnum,
        'invitecode': invitecode, 'storemodel': storemodel,
        'viprechargeflag': viprechargeflag,
        'scanbarcodeflag': scanbarcodeflag,
        'takeoutflag': takeoutflag,
        'vipmallflag': vipmallflag,
        'linenumberflag': linenumberflag,
        'itemtypeconfig': itemtypeconfig,
        'itemtypeflag': itemtypeflag,
        'miniverflag': miniverflag,
        'vendorcode': vendorcode, 'vendorname': vendorname,
        'terminalsn': terminalsn, 'terminalkey': terminalkey,
        'registtime': registtime, 'validtime': validtime,
        'starttime': starttime, 'endtime': endtime,
        'trade': trade, 'code': code, 'name': name,
        'roleid': roleid, 'mobile': mobile,
        'lng': lng, 'lat': lat,
        'pwd': pwd, 'rfid': rfid,
        'lastlogin': lastlogin, 'lastip': lastip,
        'logincount': logincount,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
        'imgurl': imgurl, 'jobid': jobid,
        'sex': sex, 'icard': icard,
        'entrytime': entrytime, 'birthtime': birthtime,
        'viewrepamtrate': viewrepamtrate,
        'attendancegroupid': attendancegroupid,
        'areaid': areaid, 'proflag': proflag,
        'distpricerate': distpricerate, 'distprice': distprice,
        'shopid': shopid, 'settlementflag': settlementflag,
        'clearalltime': clearalltime,
        'termmaxnum_agent': termmaxnumAgent,
      };
}
