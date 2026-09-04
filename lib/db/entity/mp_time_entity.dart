/// 促销活动时间表（对齐 MPTime.kt）
class MpTimeEntity {
  int id;
  int spid;
  int sid;
  String billid;
  String starttime; // 活动开始时间
  String endtime; // 活动结束时间

  MpTimeEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.billid = '', this.starttime = '', this.endtime = '',
  });

  factory MpTimeEntity.fromMap(Map<String, dynamic> m) => MpTimeEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        billid: m['billid']?.toString() ?? '',
        starttime: m['starttime']?.toString() ?? '',
        endtime: m['endtime']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'billid': billid, 'starttime': starttime, 'endtime': endtime,
      };
}
