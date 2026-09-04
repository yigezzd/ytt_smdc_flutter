/// 促销活动VIP类型表（对齐 MPVipType.kt）
class MpVipTypeEntity {
  int id;
  int spid;
  int sid;
  String billid;
  String name;
  String typeid;

  MpVipTypeEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.billid = '', this.name = '', this.typeid = '',
  });

  factory MpVipTypeEntity.fromMap(Map<String, dynamic> m) => MpVipTypeEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        billid: m['billid']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        typeid: m['typeid']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'billid': billid, 'name': name, 'typeid': typeid,
      };
}
