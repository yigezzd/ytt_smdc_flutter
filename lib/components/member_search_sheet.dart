import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';

/// 会员搜索弹窗（对齐 smdcapp MemberActivity 会员登录页）
///
/// 支持通过卡号/姓名/手机号搜索会员，选中后返回 VipMember。
/// 用法：
/// ```dart
/// final member = await MemberSearchSheet.show(context);
/// if (member != null) { ... }
/// ```
class MemberSearchSheet extends StatefulWidget {
  const MemberSearchSheet({super.key});

  /// 弹出会员搜索弹窗，返回选中的会员（取消返回 null）
  static Future<VipMember?> show(BuildContext context) {
    return showModalBottomSheet<VipMember>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MemberSearchSheet(),
    );
  }

  @override
  State<MemberSearchSheet> createState() => _MemberSearchSheetState();
}

class _MemberSearchSheetState extends State<MemberSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final List<VipMember> _results = <VipMember>[];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final String cond = _searchController.text.trim();
    if (cond.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final List<VipMember> list = await OrderRepository.fetchVipList(cond);
      if (mounted) {
        setState(() {
          _results
            ..clear()
            ..addAll(list);
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.of(context).size.height * 0.65;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 拖拽指示条
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E6EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('录入会员',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1D2129))),
          ),
          // 搜索栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _doSearch(),
                    decoration: InputDecoration(
                      hintText: '输入卡号/姓名/手机号',
                      hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF86909C)),
                      filled: true,
                      fillColor: const Color(0xFFF7F8FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isSearching ? null : _doSearch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE13426),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('搜索',
                        style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF2F3F5)),
          // 结果列表
          Flexible(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (!_hasSearched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Text('输入关键字搜索会员', style: TextStyle(fontSize: 13, color: Color(0xFFC9CDD4))),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Text('没有找到会员', style: TextStyle(fontSize: 13, color: Color(0xFFC9CDD4))),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF2F3F5)),
      itemBuilder: (BuildContext context, int index) {
        final VipMember member = _results[index];
        return _buildMemberItem(member);
      },
    );
  }

  Widget _buildMemberItem(VipMember member) {
    return InkWell(
      onTap: () => Navigator.pop(context, member),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            // 头像占位
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Center(
                child: Icon(Icons.person, size: 20, color: Color(0xFFE13426)),
              ),
            ),
            const SizedBox(width: 12),
            // 会员信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        member.vipname,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF1D2129)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7E8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          member.typename,
                          style: const TextStyle(fontSize: 10, color: Color(0xFFD4A017)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '卡号：${member.vipno}  余额：¥${_formatAmt(member.nowmoney)}  积分：${_formatAmt(member.nowpoint)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF86909C)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC9CDD4)),
          ],
        ),
      ),
    );
  }

  String _formatAmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}
