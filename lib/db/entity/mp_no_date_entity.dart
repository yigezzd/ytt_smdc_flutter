/// 促销不可用日期表（对齐 MPNoDate.kt）
class MpNoDateEntity {
  int id;
  int spid;
  int sid;
  String billid;
  String startdate; // 不可用开始日期
  String enddate; // 不可用结束日期

  MpNoDateEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.billid = '', this.startdate = '', this.enddate = '',
  });

  factory MpNoDateEntity.fromMap(Map<String, dynamic> m) => MpNoDateEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        billid: m['billid']?.toString() ?? '',
        startdate: m['startdate']?.toString() ?? '',
        enddate: m['enddate']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'billid': billid, 'startdate': startdate, 'enddate': enddate,
      };
}
