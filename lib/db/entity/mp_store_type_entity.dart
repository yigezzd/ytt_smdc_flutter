/// 促销门店分类表（对齐 MPStoreType.kt）
class MpStoreTypeEntity {
  int id;
  int spid; // 总店id
  int sid; // 活动门店id
  int setflag;
  String billflag; // CX：促销计划，TJ：调价单
  String sbillid; // 活动id
  String typeid; // 分类id

  MpStoreTypeEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.setflag = 0, this.billflag = '',
    this.sbillid = '', this.typeid = '',
  });

  factory MpStoreTypeEntity.fromMap(Map<String, dynamic> m) => MpStoreTypeEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        setflag: m['setflag'] as int? ?? 0,
        billflag: m['billflag']?.toString() ?? '',
        sbillid: m['sbillid']?.toString() ?? '',
        typeid: m['typeid']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'setflag': setflag, 'billflag': billflag,
        'sbillid': sbillid, 'typeid': typeid,
      };
}
