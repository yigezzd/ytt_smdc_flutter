/// 必点菜区域表（对齐 MustTablearea.kt）
class MustTableareaEntity {
  int id;
  int spid;
  int sid;
  String areaid;
  String billid;

  MustTableareaEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.areaid = '', this.billid = '',
  });

  factory MustTableareaEntity.fromMap(Map<String, dynamic> m) => MustTableareaEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        areaid: m['areaid']?.toString() ?? '',
        billid: m['billid']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'areaid': areaid, 'billid': billid,
      };
}
