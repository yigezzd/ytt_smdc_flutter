import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/barcode_scanner_page.dart';

/// 品牌红（对齐本项目 spec_cook_sheet 等较新弹窗组件）
const Color _kBrandRed = Color(0xFFE63F31);

/// 商品图片 OSS 前缀
const String _kImgAddress = 'http://byyoupic.oss-cn-shenzhen.aliyuncs.com/';

/// 团券核销结果（对齐 smdcapp VerifyDishesEvent2：券信息 + 选中商品明细）
class VerifyDishesResult {
  const VerifyDishesResult({
    required this.coupon,
    required this.selectedDetails,
    this.realcount = 1,
    this.remark = '',
  });

  /// 券信息（getTuanGouCoupunInfo 返回的 data，对齐 VerifyDishesBean.DataBean）
  final Map<String, dynamic> coupon;

  /// 选中的商品明细（对齐 smdcapp VerifyDishesPopup3 确认后 list）
  ///
  /// 每条为 prolist[].detail[] 原始 Map 的副本，额外携带：
  /// - cookText：已选做法描述
  /// - cooklist：已选做法明细（下单时上传）
  /// - cookWholeExtra / cookUnitExtra：做法加价
  final List<Map<String, dynamic>> selectedDetails;

  /// 核销券数量（对齐 smdcapp proBean.realcount，默认券张数）
  final double realcount;

  /// 整单备注（对齐 smdcapp proBean.zdremark）
  final String remark;
}

/// 点菜页团券核销弹窗（对齐 smdcapp DishesVerifyPopup + VerifyDishesPopup3）
///
/// 流程：输入/扫描券号 → getTuanGouCoupunInfo 查询券信息 →
/// 券商品头图/核销数量/整单备注 → 商品组选择（全部核销锁定 / 任选一项单选）→
/// 加入购物车返回选中明细。核销(prepare)与加购由调用方处理。
class VerifyDishesSheet extends StatefulWidget {
  const VerifyDishesSheet({super.key});

  /// 显示团券核销弹窗，返回核销选择结果（取消返回 null）
  static Future<VerifyDishesResult?> show(BuildContext context) {
    return showModalBottomSheet<VerifyDishesResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VerifyDishesSheet(),
    );
  }

  @override
  State<VerifyDishesSheet> createState() => _VerifyDishesSheetState();
}

class _VerifyDishesSheetState extends State<VerifyDishesSheet> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();
  bool _querying = false;

  /// 券信息（对齐 smdcapp VerifyDishesBean.DataBean）
  Map<String, dynamic>? _coupon;

  /// 商品组列表（对齐 smdcapp prolist）
  final List<_VerifyGroup> _groups = <_VerifyGroup>[];

  /// 核销数量 / 券张数上限（对齐 smdcapp VerifyDishesPopup3 etNum / count）
  int _voucherQty = 1;
  int _voucherMax = 1;

  @override
  void initState() {
    super.initState();
    _codeCtrl.addListener(_onCodeChanged);
  }

  void _onCodeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _codeCtrl.removeListener(_onCodeChanged);
    _codeCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  /// 券号去空格（复制券号常带空格/换行，对齐后端只认纯数字券号）
  String get _cleanCode => _codeCtrl.text.replaceAll(RegExp(r'\s+'), '');

  /// 扫码（对齐 smdcapp DishesVerifyPopup iv_scan → MipcaActivityCapture）
  Future<void> _scan() async {
    if (!Device.isMobile) {
      Toast.show('当前平台暂不支持扫码');
      return;
    }
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute<Object>(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || !mounted) return;
    _codeCtrl.text = code.toString().replaceAll(RegExp(r'\s+'), '');
    await _query();
  }

  /// 查询券信息（对齐 smdcapp DishesVerifyPopup.getDyCoupunInfo → getTuanGouCoupunInfo）
  Future<void> _query() async {
    final String code = _cleanCode;
    if (code.isEmpty) {
      Toast.show('请输入券号');
      return;
    }
    if (_codeCtrl.text != code) {
      _codeCtrl.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
    }
    FocusScope.of(context).unfocus();
    setState(() => _querying = true);
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getTuanGouCoupunInfo,
        <String, dynamic>{'code': code},
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (!mounted) return;
      if (data is Map<String, dynamic> && data.isNotEmpty) {
        final double count = _toDouble(data['count']);
        final int maxQty = count >= 1 ? count.floor() : 1;
        setState(() {
          _coupon = data;
          _voucherMax = maxQty;
          _voucherQty = maxQty;
          _groups
            ..clear()
            ..addAll(_parseGroups(data));
        });
      } else {
        final String msg = resp['retmsg']?.toString() ??
            resp['Message']?.toString() ??
            resp['message']?.toString() ??
            '';
        Toast.show(msg.isNotEmpty ? msg : '查询券信息失败');
      }
    } catch (e) {
      if (!mounted) return;
      final String msg = e.toString().replaceFirst('Exception: ', '');
      Toast.show(
          msg.contains('已核销') || msg.contains('过期') || msg.contains('失效')
              ? msg
              : '查询券信息失败');
    } finally {
      if (mounted) setState(() => _querying = false);
    }
  }

  /// 重新查询：回到券号输入状态
  void _resetQuery() {
    setState(() {
      _coupon = null;
      _groups.clear();
      _voucherQty = 1;
      _voucherMax = 1;
      _remarkCtrl.clear();
    });
  }

  /// 解析商品组（对齐 smdcapp prolist：signtype 0=全部核销 1=任选一项）
  List<_VerifyGroup> _parseGroups(Map<String, dynamic> data) {
    final List<_VerifyGroup> result = <_VerifyGroup>[];
    final dynamic prolist = data['prolist'];
    if (prolist is! List) return result;
    for (final dynamic g in prolist) {
      if (g is! Map) continue;
      final String signtype = g['signtype']?.toString() ?? '0';
      final dynamic detail = g['detail'];
      final List<_VerifyDetail> details = <_VerifyDetail>[];
      if (detail is List) {
        for (final dynamic d in detail) {
          if (d is! Map) continue;
          final Map<String, dynamic> raw = Map<String, dynamic>.from(d);
          details.add(_VerifyDetail(
            raw: raw,
            cookGroups: _parseCookGroups(raw['cooklist'] ?? raw['cookList']),
            // 对齐 smdcapp onBind：非任选分组默认勾选且不可取消
            checked: signtype != '1',
          ));
        }
      }
      result.add(_VerifyGroup(
        productgroupname: g['productgroupname']?.toString() ?? '',
        signtype: signtype,
        details: details,
      ));
    }
    return result;
  }

  /// 做法选项解析（对齐 smdcapp ProductCook：defrecommend=1 默认选中）
  List<_CookGroupOption> _parseCookGroups(dynamic rawCookList) {
    final List<_CookGroupOption> groups = <_CookGroupOption>[];
    if (rawCookList is! List) return groups;
    for (final dynamic g in rawCookList) {
      if (g is! Map) continue;
      final List<_CookOption> options = <_CookOption>[];
      final dynamic inner = g['cooklist'];
      if (inner is List) {
        for (final dynamic c in inner) {
          if (c is! Map) continue;
          final String name =
              c['cookname']?.toString() ?? c['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          options.add(_CookOption(
            name: name,
            code: (c['cookcode'] ?? c['code'])?.toString() ?? '',
            cupstickercode: c['cupstickercode']?.toString() ?? '',
            price: _toDouble(c['price']),
            ptype: _toInt(c['ptype']),
            editqtyflag: _toInt(c['editqtyflag']),
            maximumflag: _toInt(c['maximumflag']),
            maximum: _toInt(c['maximum']),
            mandatoryflag: _toInt(c['mandatoryflag']),
            mandatoryqty: _toDouble(c['mandatoryqty']),
            checked: _toInt(c['defrecommend']) == 1,
          ));
        }
      }
      if (options.isNotEmpty) {
        groups.add(_CookGroupOption(
          name: g['groupname']?.toString() ?? '做法',
          options: options,
        ));
      }
    }
    return groups;
  }

  /// 商品组行点击（对齐 smdcapp ll_itemview：
  /// 任选一项组内单选且可取消；全部核销组不可取消）
  void _onDetailTap(_VerifyGroup group, _VerifyDetail detail) {
    if (!group.single) {
      Toast.show('当前分组核销全部，不能取消');
      return;
    }
    setState(() {
      final bool wasChecked = detail.checked;
      for (final _VerifyDetail d in group.details) {
        d.checked = false;
      }
      detail.checked = !wasChecked;
    });
  }

  /// 打开选做法弹窗
  Future<void> _openCookPicker(_VerifyDetail detail) async {
    final List<_CookGroupOption> cloned = detail.cookGroups
        .map((_CookGroupOption g) => g.clone())
        .toList();
    final List<_CookGroupOption>? result =
        await showModalBottomSheet<List<_CookGroupOption>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CookPickerSheet(
        title: detail.displayName,
        groups: cloned,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => detail.cookGroups = result);
  }

  /// 确定（对齐 smdcapp VerifyDishesPopup3 tvAddCart 选择逻辑）
  void _confirm() {
    if (_coupon == null) {
      _query();
      return;
    }
    if (_groups.isEmpty) {
      Toast.show('没有商品信息');
      return;
    }
    final List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
    for (final _VerifyGroup g in _groups) {
      if (g.details.isEmpty) continue;
      if (!g.single) {
        // 全部核销（对齐 smdcapp signtype != "1" → addAll）
        list.addAll(g.details.map(_buildSelectedDetail));
      } else {
        // 任选一项：必须单选一项（对齐 smdcapp "${groupname}组未选择商品"）
        final int idx = g.details.indexWhere((_VerifyDetail d) => d.checked);
        if (idx < 0) {
          Toast.show('${g.productgroupname}组未选择商品');
          return;
        }
        list.add(_buildSelectedDetail(g.details[idx]));
      }
    }
    if (list.isEmpty) {
      Toast.show('没有有效的商品信息');
      return;
    }
    Navigator.of(context).pop(VerifyDishesResult(
      coupon: _coupon!,
      selectedDetails: list,
      realcount: _voucherQty.toDouble(),
      remark: _remarkCtrl.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
    ));
  }

  /// 输出明细：覆盖 cooklist 为已选做法，供下单直接上传
  Map<String, dynamic> _buildSelectedDetail(_VerifyDetail detail) {
    final Map<String, dynamic> out = Map<String, dynamic>.from(detail.raw);
    out['cookText'] = detail.cookText;
    out['cooklist'] = detail.selectedCookMaps;
    out['cookWholeExtra'] = detail.wholeExtra;
    out['cookUnitExtra'] = detail.unitExtra;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool loaded = _coupon != null;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildHeader(isDark),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                physics: const BouncingScrollPhysics(),
                child: loaded ? _buildLoadedBody(isDark) : _buildQueryBody(isDark),
              ),
            ),
            _buildBottomBar(isDark),
          ],
        ),
      ),
    );
  }

  /// 标题栏：红条 + 团券核销 + 重新查询 + 关闭
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: _kBrandRed,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '团券核销',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          if (_coupon != null)
            GestureDetector(
              onTap: _resetQuery,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  '重新查询',
                  style: TextStyle(fontSize: 13, color: _kBrandRed),
                ),
              ),
            ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 18,
                color: isDark ? Colors.white70 : const Color(0xFF86909C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 第一步：券号输入
  Widget _buildQueryBody(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                  decoration: const InputDecoration(
                    hintText: '请扫码或输入券号',
                    hintStyle: TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _query(),
                ),
              ),
              if (_codeCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () => _codeCtrl.clear(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.cancel,
                      size: 16,
                      color: isDark
                          ? const Color(0xFF666666)
                          : const Color(0xFFC9CDD4),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: _scan,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.qr_code_scanner,
                      size: 22, color: _kBrandRed),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '支持抖音 / 美团 / 快手团购券，查询后选择核销商品加入购物车',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
          ),
        ),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 40),
      ],
    );
  }

  /// 第二步：券信息 + 整单备注 + 商品组
  Widget _buildLoadedBody(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCouponCard(isDark),
        const SizedBox(height: 10),
        _buildRemarkRow(isDark),
        const SizedBox(height: 14),
        ..._groups.map((_VerifyGroup g) => _buildGroup(g, isDark)),
        _buildListFooter(isDark),
      ],
    );
  }

  /// 券商品头：图片 + 名称 + 结算价 + 核销数量步进器（对齐 dialog_erify_dishes2 头部）
  Widget _buildCouponCard(bool isDark) {
    final Map<String, dynamic> c = _coupon!;
    final String name = c['name']?.toString() ?? '团购券';
    final double price =
        _toDouble(c['dealprice']) > 0 ? _toDouble(c['dealprice']) : _toDouble(c['productprice']);
    final String platform = _platformName(c['businesstype']?.toString() ?? '0');
    final String imageUrl = _couponCover(c);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2D2E) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    memCacheWidth: 144,
                    placeholder: (_, __) => _buildImgPlaceholder(),
                    errorWidget: (_, __, dynamic e) => _buildImgPlaceholder(),
                  )
                : _buildImgPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2E3B2E)
                            : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(platform,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF3C9A5F))),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1D2129),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          const Padding(
                            padding: EdgeInsets.only(bottom: 2),
                            child: Text('¥',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _kBrandRed)),
                          ),
                          Text(
                            _fmtPrice(price),
                            style: const TextStyle(
                              fontSize: 20,
                              height: 1.1,
                              fontWeight: FontWeight.bold,
                              color: _kBrandRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildQtyStepper(isDark),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 商品图占位
  Widget _buildImgPlaceholder() {
    return Container(
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
        ),
      ),
      child: const Center(child: Text('🍽', style: TextStyle(fontSize: 28))),
    );
  }

  /// 券商品图：优先取第一个商品组首项图片
  String _couponCover(Map<String, dynamic> c) {
    final dynamic prolist = c['prolist'];
    if (prolist is List) {
      for (final dynamic g in prolist) {
        if (g is! Map) continue;
        final dynamic detail = g['detail'];
        if (detail is List) {
          for (final dynamic d in detail) {
            if (d is! Map) continue;
            final String url = d['imageurl']?.toString() ?? '';
            if (url.isNotEmpty && url != 'null') {
              return url.startsWith('http') ? url : '$_kImgAddress$url';
            }
          }
        }
      }
    }
    return '';
  }

  /// 核销数量步进器（对齐 smdcapp etNum：1 ~ count 张）
  Widget _buildQtyStepper(bool isDark) {
    final bool canMinus = _voucherQty > 1;
    final bool canPlus = _voucherQty < _voucherMax;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GestureDetector(
          onTap: () {
            if (!canMinus) return;
            setState(() => _voucherQty--);
          },
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: canMinus
                    ? _kBrandRed
                    : (isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB)),
              ),
            ),
            child: Icon(
              Icons.remove,
              size: 16,
              color: canMinus
                  ? _kBrandRed
                  : (isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4)),
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$_voucherQty',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            if (!canPlus) {
              Toast.show('最多核销$_voucherMax张');
              return;
            }
            setState(() => _voucherQty++);
          },
          child: Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: <Color>[Color(0xFFF0503F), _kBrandRed],
              ),
            ),
            child: Icon(
              Icons.add,
              size: 16,
              color: canPlus ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ],
    );
  }

  /// 整单备注（对齐 dialog_erify_dishes2 ll_all_price）
  Widget _buildRemarkRow(bool isDark) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '整单备注',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _remarkCtrl,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
              decoration: const InputDecoration(
                hintText: '请输入备注',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFFC9CDD4)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 商品组（对齐 item_verify_dishes_group：标题 + 商品行）
  Widget _buildGroup(_VerifyGroup group, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: <Widget>[
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  color: _kBrandRed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                group.productgroupname,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1D2129),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                group.single ? '（任选一项）' : '（核销全部）',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                ),
              ),
            ],
          ),
        ),
        ...group.details.map((_VerifyDetail d) => _buildDetailRow(group, d, isDark)),
        const SizedBox(height: 6),
      ],
    );
  }

  /// 商品行：复选框 + 图片 + 名称/数量/做法 + 选做法
  Widget _buildDetailRow(
      _VerifyGroup group, _VerifyDetail detail, bool isDark) {
    final bool showCook =
        detail.cookflag == 1 && detail.cookGroups.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onDetailTap(group, detail),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2D2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: detail.checked && group.single
                ? const Color(0xFFFFD7D2)
                : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _buildCheckBox(detail.checked),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: detail.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: detail.imageUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      placeholder: (_, __) => _buildDetailPlaceholder(),
                      errorWidget: (_, __, dynamic e) =>
                          _buildDetailPlaceholder(),
                    )
                  : _buildDetailPlaceholder(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          detail.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color:
                                isDark ? Colors.white : const Color(0xFF1D2129),
                          ),
                        ),
                      ),
                      if (detail.isComb)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3D2826)
                                : const Color(0xFFFFF1F0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '套餐',
                            style:
                                TextStyle(fontSize: 10, color: _kBrandRed),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Text(
                        'x ${_fmtQty(detail.qty)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF999999)
                              : const Color(0xFF86909C),
                        ),
                      ),
                      const Spacer(),
                      if (showCook)
                        GestureDetector(
                          onTap: () => _openCookPicker(detail),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _kBrandRed,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '选做法',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (detail.cookText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '做法：${detail.cookText}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFF999999)
                              : const Color(0xFF86909C),
                        ),
                      ),
                    ),
                  if (detail.combChildren.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        detail.combChildren
                            .map((String s) => '· $s')
                            .join('  '),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: isDark
                              ? const Color(0xFF999999)
                              : const Color(0xFF86909C),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
        ),
      ),
      child: const Center(child: Text('🍽', style: TextStyle(fontSize: 24))),
    );
  }

  Widget _buildCheckBox(bool checked) {
    return Container(
      width: 21,
      height: 21,
      decoration: BoxDecoration(
        color: checked ? _kBrandRed : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: checked ? _kBrandRed : const Color(0xFFC9CDD4),
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : null,
    );
  }

  /// 列表到底提示（对齐 item_verify_dishes_group tv_btn_title）
  Widget _buildListFooter(bool isDark) {
    final Color lineColor =
        isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Divider(color: lineColor, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '已经到底了',
              style: TextStyle(
                fontSize: 11,
                color:
                    isDark ? const Color(0xFF666666) : const Color(0xFF86909C),
              ),
            ),
          ),
          Expanded(child: Divider(color: lineColor, height: 1)),
        ],
      ),
    );
  }

  /// 底部操作栏（取消 + 查询/加入购物车，对齐 dialog_erify_dishes2 按钮）
  Widget _buildBottomBar(bool isDark) {
    final bool loaded = _coupon != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3C3D)
                      : const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _kBrandRed),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '取消',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kBrandRed),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _querying ? null : (loaded ? _confirm : _query),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kBrandRed.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _querying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        loaded ? '加入购物车' : '查询',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _platformName(String bt) {
    switch (bt) {
      case '0':
        return '抖音';
      case '1':
        return '美团';
      case '3':
        return '快手';
      default:
        return '团购';
    }
  }
}

/// 商品组（对齐 smdcapp VerifyDishesBean.ProlistBean）
class _VerifyGroup {
  _VerifyGroup({
    required this.productgroupname,
    required this.signtype,
    required this.details,
  });

  final String productgroupname;

  /// 核销类型：0=全部核销 1=任选一项（单选）
  final String signtype;
  final List<_VerifyDetail> details;

  bool get single => signtype == '1';
}

/// 商品明细（对齐 smdcapp VerifyDishesPopup3 中的 ProductBean 临时数据）
class _VerifyDetail {
  _VerifyDetail({
    required this.raw,
    required this.cookGroups,
    required this.checked,
  });

  final Map<String, dynamic> raw;
  List<_CookGroupOption> cookGroups;
  bool checked;

  String get productname =>
      raw['productname']?.toString() ?? raw['name']?.toString() ?? '';

  String get specname {
    final String s = raw['specname']?.toString() ?? '';
    return s == 'null' ? '' : s;
  }

  String get displayName => specname.isEmpty ? productname : '$productname($specname)';

  String get imageurl => raw['imageurl']?.toString() ?? '';

  String get imageUrl {
    final String url = imageurl;
    if (url.isEmpty || url == 'null') return '';
    return url.startsWith('http') ? url : '$_kImgAddress$url';
  }

  double get qty => _toDouble(raw['qty']);

  int get cookflag => _toInt(raw['cookflag']);

  bool get isComb => _toInt(raw['combflag']) == 1;

  /// 套餐默认选中明细（对齐 smdcapp grouplist defflag=1）
  List<String> get combChildren {
    final dynamic grouplist = raw['grouplist'];
    if (grouplist is! List) return const <String>[];
    final List<String> list = <String>[];
    for (final dynamic g in grouplist) {
      if (g is! Map) continue;
      if (_toInt(g['defflag']) != 1) continue;
      final String name = g['productname']?.toString() ?? '';
      if (name.isEmpty) continue;
      final String spec = g['specname']?.toString() ?? '';
      final String q = _fmtQty(_toDouble(g['qty']));
      list.add(spec.isEmpty || spec == 'null' ? '$name x$q' : '$name($spec) x$q');
    }
    return list;
  }

  /// 已选做法描述
  String get cookText {
    final List<String> names = <String>[];
    for (final _CookGroupOption g in cookGroups) {
      for (final _CookOption o in g.options) {
        if (o.checked) names.add(o.name);
      }
    }
    return names.join('、');
  }

  /// 已选做法明细（下单 cooklist）
  List<Map<String, dynamic>> get selectedCookMaps {
    final List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
    for (final _CookGroupOption g in cookGroups) {
      for (final _CookOption o in g.options) {
        if (!o.checked) continue;
        list.add(<String, dynamic>{
          'code': o.code,
          'name': o.name,
          'cupstickercode': o.cupstickercode,
          'price': o.price,
          'ptype': o.ptype,
          'qty': o.qty,
        });
      }
    }
    return list;
  }

  /// 做法整份加价（ptype=1）
  double get wholeExtra {
    double total = 0;
    for (final _CookGroupOption g in cookGroups) {
      for (final _CookOption o in g.options) {
        if (o.checked && o.ptype == 1) total += o.price * o.qty;
      }
    }
    return total;
  }

  /// 做法数量加价（ptype=2，单份口径）
  double get unitExtra {
    double total = 0;
    for (final _CookGroupOption g in cookGroups) {
      for (final _CookOption o in g.options) {
        if (o.checked && o.ptype == 2) total += o.price * o.qty;
      }
    }
    return total;
  }
}

/// 做法分组（对齐 smdcapp ProductCook 分组）
class _CookGroupOption {
  _CookGroupOption({required this.name, required this.options});

  final String name;
  final List<_CookOption> options;

  bool get multi {
    if (options.isEmpty) return false;
    final _CookOption first = options.first;
    return options.any((_CookOption o) => o.editqtyflag == 1) ||
        (first.maximumflag == 1 && first.maximum > 1);
  }

  int get maximum =>
      options.isEmpty || options.first.maximumflag != 1
          ? 0
          : options.first.maximum;

  int get mandatoryCount {
    if (options.isEmpty || options.first.mandatoryflag != 1) return 0;
    final double q = options.first.mandatoryqty;
    return q <= 0 ? 1 : q.ceil();
  }

  String get titleSuffix {
    if (options.isEmpty) return '';
    final _CookOption first = options.first;
    final List<String> parts = <String>[];
    if (first.editqtyflag == 1) parts.add('可重复');
    if (first.mandatoryflag == 1) {
      parts.add('必选${mandatoryCount}项');
    }
    if (first.maximumflag == 1) parts.add('最多可选${first.maximum}项');
    return parts.isEmpty ? '' : '(${parts.join(',')})';
  }

  int get selectedCount =>
      options.where((_CookOption o) => o.checked).length;

  _CookGroupOption clone() {
    return _CookGroupOption(
      name: name,
      options: options.map((_CookOption o) => o.clone()).toList(),
    );
  }
}

/// 做法选项（对齐 smdcapp ProductCook）
class _CookOption {
  _CookOption({
    required this.name,
    required this.code,
    required this.cupstickercode,
    required this.price,
    required this.ptype,
    required this.editqtyflag,
    required this.maximumflag,
    required this.maximum,
    required this.mandatoryflag,
    required this.mandatoryqty,
    required this.checked,
  });

  final String name;
  final String code;
  final String cupstickercode;
  final double price;
  final int ptype;
  final int editqtyflag;
  final int maximumflag;
  final int maximum;
  final int mandatoryflag;
  final double mandatoryqty;
  bool checked;
  int qty = 1;

  _CookOption clone() {
    return _CookOption(
      name: name,
      code: code,
      cupstickercode: cupstickercode,
      price: price,
      ptype: ptype,
      editqtyflag: editqtyflag,
      maximumflag: maximumflag,
      maximum: maximum,
      mandatoryflag: mandatoryflag,
      mandatoryqty: mandatoryqty,
      checked: checked,
    )..qty = qty;
  }

  /// 展示文案（加价做法带价格）
  String get label {
    if (price > 0 && ptype != 0) return '$name +¥${_fmtPrice(price)}';
    return name;
  }
}

/// 选做法弹窗（对齐 smdcapp CookPopup：默认选中推荐项、单选/多选、必选校验）
class _CookPickerSheet extends StatefulWidget {
  const _CookPickerSheet({required this.title, required this.groups});

  final String title;
  final List<_CookGroupOption> groups;

  @override
  State<_CookPickerSheet> createState() => _CookPickerSheetState();
}

class _CookPickerSheetState extends State<_CookPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _kBrandRed,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '选做法 · ${widget.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color:
                            isDark ? Colors.white : const Color(0xFF1D2129),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3A3C3D)
                            : const Color(0xFFF5F5F5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color:
                            isDark ? Colors.white70 : const Color(0xFF86909C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.groups
                      .map((_CookGroupOption g) => _buildGroup(g, isDark))
                      .toList(),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                10 +
                    MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom,
              ),
              child: GestureDetector(
                onTap: _confirm,
                child: Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '确定',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(_CookGroupOption group, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${group.name}${group.titleSuffix}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.options
                .map((_CookOption o) => _buildChip(group, o, isDark))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(_CookGroupOption group, _CookOption option, bool isDark) {
    final bool selected = option.checked;
    return GestureDetector(
      onTap: () => _toggle(group, option),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? const Color(0xFF3D2826) : const Color(0xFFFFF1F0))
              : (isDark ? const Color(0xFF2C2D2E) : const Color(0xFFF7F8FA)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? _kBrandRed
                : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB)),
          ),
        ),
        child: Text(
          option.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected
                ? _kBrandRed
                : (isDark ? Colors.white70 : const Color(0xFF4E5969)),
          ),
        ),
      ),
    );
  }

  void _toggle(_CookGroupOption group, _CookOption option) {
    setState(() {
      if (!group.multi) {
        // 单选分组：同组只保留一个（对齐 smdcapp 单选做法）
        for (final _CookOption o in group.options) {
          o.checked = false;
        }
        option.checked = true;
        option.qty = 1;
        return;
      }
      if (!option.checked &&
          group.maximum > 0 &&
          group.selectedCount >= group.maximum) {
        Toast.show('最多可选${group.maximum}项');
        return;
      }
      option.checked = !option.checked;
      if (option.checked) option.qty = 1;
    });
  }

  void _confirm() {
    for (final _CookGroupOption g in widget.groups) {
      if (g.mandatoryCount > 0 && g.selectedCount < g.mandatoryCount) {
        Toast.show('请选择${g.name}');
        return;
      }
    }
    Navigator.of(context).pop(widget.groups);
  }
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

String _fmtPrice(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

/// 数量展示（对齐 smdcapp "x 1.0"：整数也保留一位小数）
String _fmtQty(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(1);
  return v.toString();
}
