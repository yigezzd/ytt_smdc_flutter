/// 系统备注表（对齐 smdcapp ReasonInfo.kt）
///
/// 对应数据库表 t_bi_reason_info，包含系统备注/原因信息。
class ReasonInfoEntity {
  int id;
  int spid;
  int sid;
  int status;
  String value;
  String code;
  String typeid;
  String createtime;
  String updatetime;
  String operid;
  String opername;

  ReasonInfoEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.status = 0,
    this.value = '', this.code = '', this.typeid = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
  });

  factory ReasonInfoEntity.fromMap(Map<String, dynamic> m) => ReasonInfoEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        value: m['value']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        typeid: m['typeid']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'status': status,
        'value': value, 'code': code, 'typeid': typeid,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
      };
}
