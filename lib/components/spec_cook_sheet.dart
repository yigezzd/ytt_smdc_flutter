import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 商品图片 OSS 前缀
const String _kImgAddress = 'http://byyoupic.oss-cn-shenzhen.aliyuncs.com/';

/// 弹窗模式
enum SpecCookSheetMode {
  /// 加购模式（对齐 smdcapp SpecificationPopup3）：
  /// 点菜页点击"选规格" → 选规格/做法/数量 → 加入购物车/立即下单
  add,

  /// 做法修改模式（对齐 smdcapp SpecCookPopup2）：
  /// 购物车条目"修改做法" → 仅做法选择（支持私有/全局Tab+回显）→ 确认修改
  modify,
}

/// 做法修改结果（对齐 smdcapp SpecCookPopup2 确认修改回调）
class CookModifyResult {
  const CookModifyResult({
    required this.cookText,
    required this.cookExtra,
  });

  /// 做法描述文本（不含规格名）
  final String cookText;

  /// 做法整份加价（ptype=1）
  final double cookExtra;
}

/// 规格做法统一弹窗（合并原 SpecCookSheet + DishCookModifySheet）
///
/// 通过 [mode] 区分两种业务场景：
/// - [SpecCookSheetMode.add]：完整规格选择（商品图片/规格网格/做法/数量/加购下单）
/// - [SpecCookSheetMode.modify]：做法修改（仅做法选择+私有/全局Tab+回显+确认修改）
class SpecCookSheet extends StatefulWidget {
  const SpecCookSheet({
    super.key,
    this.mode = SpecCookSheetMode.add,
    required this.specData,
    // ── 加购模式参数 ──
    this.product,
    this.onAddToCart,
    this.onBuyNow,
    // ── 修改模式参数 ──
    this.dishName = '',
    this.unitPrice = 0,
    this.currentSpecText = '',
  });

  /// 弹窗模式
  final SpecCookSheetMode mode;

  /// 规格做法数据
  final DishSpecData specData;

  // ── 加购模式参数 ──

  /// 商品（加购模式必传）
  final DishProduct? product;

  /// 加入购物车回调(数量, 规格做法描述, 单份销售价, 整份加价)
  final void Function(int quantity, String specText, double unitPrice, double wholeExtra)? onAddToCart;

  /// 立即下单回调
  final void Function(int quantity, String specText, double unitPrice, double wholeExtra)? onBuyNow;

  // ── 修改模式参数 ──

  /// 菜品名称（修改模式）
  final String dishName;

  /// 当前单价（修改模式，展示用）
  final double unitPrice;

  /// 当前规格做法描述（修改模式，用于回显已选做法）
  final String currentSpecText;

  /// 加购模式显示弹窗
  static Future<void> show(
    BuildContext context, {
    required DishProduct product,
    required DishSpecData specData,
    required void Function(int quantity, String specText, double unitPrice, double wholeExtra) onAddToCart,
    void Function(int quantity, String specText, double unitPrice, double wholeExtra)? onBuyNow,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpecCookSheet(
        mode: SpecCookSheetMode.add,
        product: product,
        specData: specData,
        onAddToCart: onAddToCart,
        onBuyNow: onBuyNow,
      ),
    );
  }

  /// 修改模式显示弹窗，返回 CookModifyResult 或 null（取消）
  static Future<CookModifyResult?> showModify(
    BuildContext context, {
    required String dishName,
    required double unitPrice,
    required DishSpecData specData,
    String currentSpecText = '',
  }) {
    return showModalBottomSheet<CookModifyResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpecCookSheet(
        mode: SpecCookSheetMode.modify,
        specData: specData,
        dishName: dishName,
        unitPrice: unitPrice,
        currentSpecText: currentSpecText,
      ),
    );
  }

  @override
  State<SpecCookSheet> createState() => _SpecCookSheetState();
}

class _SpecCookSheetState extends State<SpecCookSheet> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;

  /// 数量（加购模式）
  int _quantity = 1;

  /// 当前做法 Tab：0=私有做法 1=全局做法（修改模式）
  int _cookTab = 0;

  bool get _isModify => widget.mode == SpecCookSheetMode.modify;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _slideAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    if (_isModify) {
      _preselectCooks();
    } else {
      _initDefaultSelection();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ==================== 初始化 ====================

  /// 加购模式：初始化默认选中（对齐 smdcapp：默认选中 defsizeflag=1 的规格，defrecommend=1 的做法）
  void _initDefaultSelection() {
    final List<DishSpec> specs = widget.specData.specdata;
    if (specs.isNotEmpty) {
      final bool hasChecked = specs.any((DishSpec s) => s.isCheck);
      if (!hasChecked) {
        for (final DishSpec spec in specs) {
          if (spec.defsizeflag == 1) {
            if (spec.sellclearflag == 0 || spec.stockqty > 0) {
              spec.isCheck = true;
              break;
            }
          }
        }
        // 没有默认规格就选第一个可用的
        if (!specs.any((DishSpec s) => s.isCheck)) {
          for (final DishSpec spec in specs) {
            if (!spec.isSoldOut) {
              spec.isCheck = true;
              break;
            }
          }
        }
      }
    }
    // 做法默认选中推荐项
    for (final DishCookGroup group in widget.specData.cookdata) {
      for (final DishCook cook in group.cooklist) {
        if (cook.defrecommend == 1) {
          cook.isCheck = true;
          cook.selectCookNum = 1;
        }
      }
    }
  }

  /// 修改模式：回显已选做法（根据当前 specText 中的做法名匹配）
  void _preselectCooks() {
    final String cur = widget.currentSpecText;
    if (cur.isEmpty) return;
    void mark(List<DishCookGroup> groups) {
      for (final DishCookGroup g in groups) {
        for (final DishCook c in g.cooklist) {
          if (cur.contains(c.cookname)) {
            c.isCheck = true;
            c.selectCookNum = 1;
          }
        }
      }
    }
    mark(widget.specData.cookdata);
    mark(widget.specData.publiccook);
  }

  // ==================== 价格计算（对齐 ShoppingCartUtil.getSpecPrice） ====================

  /// 当前选中规格
  DishSpec? get _checkedSpec {
    for (final DishSpec s in widget.specData.specdata) {
      if (s.isCheck) return s;
    }
    return null;
  }

  /// 单份基础销售价（规格价）
  double get _basePrice {
    final DishSpec? spec = _checkedSpec;
    if (spec != null) return spec.actualPrice;
    return widget.product?.sellprice ?? widget.unitPrice;
  }

  /// 整份加价合计（ptype=1，不乘商品数量）
  /// 加购模式：仅 cookdata；修改模式：cookdata + publiccook
  double get _wholeExtraPrice {
    double total = 0;
    void sum(List<DishCookGroup> groups) {
      for (final DishCookGroup g in groups) {
        for (final DishCook c in g.cooklist) {
          if (c.isCheck && c.ptype == 1) {
            total += c.editqtyflag == 1 ? c.price * c.selectCookNum : c.price;
          }
        }
      }
    }
    sum(widget.specData.cookdata);
    if (_isModify) sum(widget.specData.publiccook);
    return total;
  }

  /// 数量加价合计（ptype=2，需乘商品数量，加购模式）
  double get _qtyExtraPrice {
    double total = 0;
    for (final DishCookGroup group in widget.specData.cookdata) {
      for (final DishCook cook in group.cooklist) {
        if (cook.isCheck && cook.ptype == 2) {
          total += cook.editqtyflag == 1 ? cook.price * cook.selectCookNum : cook.price;
        }
      }
    }
    return total;
  }

  /// 单份实际销售价 = 规格价 + 数量加价（加购模式）
  double get _unitPrice => _basePrice + _qtyExtraPrice;

  /// 总价 = 单份价 × 数量 + 整份加价（加购模式）
  double get _totalPrice => _unitPrice * _quantity + _wholeExtraPrice;

  /// 原价（划线价，加购模式）
  double get _originalTotal {
    final DishSpec? spec = _checkedSpec;
    final double base = spec?.sellprice ?? widget.product?.sellprice ?? widget.unitPrice;
    return base * _quantity + _wholeExtraPrice + _qtyExtraPrice * _quantity;
  }

  /// SKU 描述文本（对齐 smdcapp: 规格名、做法名(¥价格)xN、...）
  /// 加购模式：规格名 + cookdata 做法；修改模式：cookdata + publiccook 做法（不含规格名）
  String get _specText {
    final List<String> parts = <String>[];
    if (!_isModify) {
      final DishSpec? spec = _checkedSpec;
      if (spec != null) parts.add(spec.specname);
    }
    void collect(List<DishCookGroup> groups) {
      for (final DishCookGroup g in groups) {
        for (final DishCook c in g.cooklist) {
          if (c.isCheck) {
            String text = c.cookname;
            if (c.ptype != 0 && c.price > 0) {
              final String priceStr = c.price == c.price.roundToDouble()
                  ? c.price.toInt().toString()
                  : c.price.toStringAsFixed(2);
              text += '(¥$priceStr)';
            }
            if (c.selectCookNum > 1) text += 'x${c.selectCookNum}';
            parts.add(text);
          }
        }
      }
    }
    collect(widget.specData.cookdata);
    if (_isModify) collect(widget.specData.publiccook);
    return parts.join('、');
  }

  // ==================== 做法 Tab（修改模式，对齐 smdcapp initCookTab） ====================

  /// 私有做法是否有效（对齐 smdcapp: cookdata 非空）
  bool get _isPrivateValid => widget.specData.cookdata.isNotEmpty;

  /// 全局做法是否有效（对齐 smdcapp: publicCook 非空）
  bool get _isPublicValid => widget.specData.publiccook.isNotEmpty;

  /// 是否显示 Tab（对齐 smdcapp initCookTab：私有和全局做法都存在时显示，不要求多规格）
  bool get _showTab => _isModify && _isPrivateValid && _isPublicValid;

  /// 当前 Tab 对应的做法分组（修改模式）
  List<DishCookGroup> get _activeGroups =>
      _cookTab == 0 ? widget.specData.cookdata : widget.specData.publiccook;

  // ==================== 交互逻辑（对齐 SpecificationPopup3） ====================

  /// 点击规格项（单选，加购模式）
  void _onSpecTap(DishSpec spec) {
    if (spec.isSoldOut) {
      Toast.show('已售罄');
      return;
    }
    setState(() {
      for (final DishSpec s in widget.specData.specdata) {
        s.isCheck = false;
      }
      spec.isCheck = true;
    });
  }

  /// 点击做法项（对齐 SpecificationPopup3 的完整选择逻辑）
  void _onCookTap(DishCookGroup group, DishCook cook) {
    setState(() {
      final List<DishCook> cooks = group.cooklist;

      if (cook.maximum == 1 && cook.editqtyflag != 1) {
        // 单选模式：取消其他，选中当前
        for (final DishCook c in cooks) {
          c.isCheck = false;
          c.selectCookNum = 0;
        }
        cook.isCheck = true;
        cook.selectCookNum = 1;
      } else if (cook.maximum == 1 && cook.editqtyflag == 1) {
        // 只能选一个但可加数量
        if (cook.isCheck) {
          Toast.show('已选最大数量');
          return;
        }
        final bool anyChecked = cooks.any((DishCook c) => c.isCheck);
        if (anyChecked) {
          Toast.show('已选最大数量');
          return;
        }
        cook.isCheck = true;
        cook.selectCookNum += 1;
      } else {
        // 多选模式
        final int selectedCount = cooks.fold(
            0, (int sum, DishCook c) => c.isCheck ? sum + c.selectCookNum : sum);

        if (cook.maximumflag == 1 && cook.editqtyflag == 1) {
          if (selectedCount >= cook.maximum) {
            Toast.show('已选最大数量');
            return;
          }
        } else if (cook.maximumflag == 1 && cook.editqtyflag != 1) {
          // 超出上限时取消最早选中的
          if (selectedCount >= cook.maximum && !cook.isCheck) {
            final DishCook firstChecked = cooks.firstWhere(
                (DishCook c) => c.isCheck && c != cook,
                orElse: () => cook);
            if (firstChecked != cook) {
              firstChecked.isCheck = false;
              firstChecked.selectCookNum = 0;
            }
          }
        }

        if (cook.editqtyflag == 1) {
          // 可重复：点击自增
          if (cook.isCheck) {
            cook.selectCookNum += 1;
          } else {
            cook.isCheck = true;
            cook.selectCookNum = 1;
          }
        } else {
          // 普通切换
          cook.isCheck = !cook.isCheck;
          cook.selectCookNum = cook.isCheck ? 1 : 0;
        }
      }
    });
  }

  /// 做法减号
  void _onCookMinus(DishCook cook) {
    setState(() {
      if (cook.selectCookNum > 1) {
        cook.selectCookNum--;
      } else {
        cook.selectCookNum = 0;
        cook.isCheck = false;
      }
    });
  }

  /// 校验必选做法组（对齐 ShoppingCartUtil.isSatisfyCart）
  /// 加购模式校验 cookdata；修改模式校验当前 Tab 分组
  String _validateCooks() {
    final List<DishCookGroup> groups =
        _isModify ? _activeGroups : widget.specData.cookdata;
    for (final DishCookGroup group in groups) {
      if (group.cooklist.isEmpty) continue;
      final DishCook first = group.cooklist[0];
      if (first.mandatoryflag == 1) {
        final int selected = group.cooklist.where((DishCook c) => c.isCheck).length;
        if (selected < first.mandatoryqty) {
          final String qty = first.mandatoryqty == first.mandatoryqty.roundToDouble()
              ? first.mandatoryqty.toInt().toString()
              : first.mandatoryqty.toString();
          return '做法组${group.groupname}至少选择$qty项';
        }
      }
    }
    return '';
  }

  /// 加购模式提交（加购/下单）
  void _submit({required bool buyNow}) {
    final DishProduct product = widget.product!;
    // 规格校验
    if (widget.specData.specdata.isNotEmpty && _checkedSpec == null) {
      Toast.show('请选择规格');
      return;
    }
    // 做法校验
    if (product.cookflag == 1) {
      final String error = _validateCooks();
      if (error.isNotEmpty) {
        Toast.show(error);
        return;
      }
    }
    if (buyNow) {
      widget.onBuyNow?.call(_quantity, _specText, _unitPrice, _wholeExtraPrice);
    } else {
      widget.onAddToCart?.call(_quantity, _specText, _unitPrice, _wholeExtraPrice);
      Toast.show('已加入购物车');
    }
    Navigator.of(context).pop();
  }

  /// 修改模式确认
  void _confirmModify() {
    final String error = _validateCooks();
    if (error.isNotEmpty) {
      Toast.show(error);
      return;
    }
    Navigator.of(context).pop(
      CookModifyResult(cookText: _specText, cookExtra: _wholeExtraPrice),
    );
  }

  // ==================== UI 构建 ====================

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double maxHeight =
        MediaQuery.of(context).size.height * (_isModify ? 0.8 : 0.85);

    final Widget sheet = Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _isModify ? _buildModifyHeader(isDark) : _buildAddHeader(isDark),
          if (_showTab) _buildCookTab(isDark),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              child: _isModify ? _buildModifyBody(isDark) : _buildAddBody(isDark),
            ),
          ),
          _isModify ? _buildModifyBottomBar(isDark) : _buildAddBottomBar(isDark),
        ],
      ),
    );

    // 加购模式保留滑入动画
    if (!_isModify) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(_slideAnimation),
        child: sheet,
      );
    }
    return sheet;
  }

  // ── 加购模式头部：商品图 + 名称 + 价格 + 关闭 ──

  Widget _buildAddHeader(bool isDark) {
    final DishProduct product = widget.product!;
    final String imgUrl = product.imageurl.startsWith('http')
        ? product.imageurl
        : '$_kImgAddress${product.imageurl}';

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 商品图
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.imageurl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imgUrl,
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
          // 名称 + 价格
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1D2129),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '¥${_formatPrice(_basePrice)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kBrandRed,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/${product.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                      ),
                    ),
                  ],
                ),
                // 已选规格描述
                if (_specText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '已选：$_specText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _kBrandRed),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 关闭按钮
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
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

  // ── 修改模式头部：名称 + 价格 + 关闭 ──

  Widget _buildModifyHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
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
              '做法--${widget.dishName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          Text(
            '¥${_formatPrice(widget.unitPrice)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _kBrandRed,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(
              Icons.close,
              size: 20,
              color: isDark ? Colors.white70 : const Color(0xFF86909C),
            ),
          ),
        ],
      ),
    );
  }

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
      child: const Center(child: Text('🍜', style: TextStyle(fontSize: 30))),
    );
  }

  /// 私有做法/全局做法 Tab（修改模式，对齐 smdcapp SpecCookPopup2 chageTab）
  Widget _buildCookTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _cookTab = 0),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: _cookTab == 0
                      ? _kBrandRed
                      : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5)),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                ),
                child: Center(
                  child: Text(
                    '私有做法',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _cookTab == 0
                          ? Colors.white
                          : (isDark ? Colors.white70 : const Color(0xFF333333)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _cookTab = 1),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: _cookTab == 1
                      ? _kBrandRed
                      : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5)),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
                ),
                child: Center(
                  child: Text(
                    '全局做法',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _cookTab == 1
                          ? Colors.white
                          : (isDark ? Colors.white70 : const Color(0xFF333333)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 内容区 ──

  /// 加购模式内容区：规格网格 + 做法分组 + 数量行
  Widget _buildAddBody(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.specData.specdata.isNotEmpty) ...<Widget>[
          _buildSectionTitle('规格', isDark),
          _buildSpecGrid(isDark),
          const SizedBox(height: 16),
        ],
        if (widget.specData.cookdata.isNotEmpty)
          ...widget.specData.cookdata.map(
              (DishCookGroup group) => _buildCookGroup(group, isDark)),
        const SizedBox(height: 12),
        _buildQuantityRow(isDark),
        const SizedBox(height: 16),
      ],
    );
  }

  /// 修改模式内容区：当前 Tab 做法分组
  Widget _buildModifyBody(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 12),
        if (_activeGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                '暂无做法数据',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                ),
              ),
            ),
          )
        else
          ..._activeGroups.map(
              (DishCookGroup group) => _buildCookGroup(group, isDark)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
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
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
        ],
      ),
    );
  }

  /// 规格网格（加购模式，对齐 smdcapp: 选中红底白字，未选灰底黑字，显示库存）
  Widget _buildSpecGrid(bool isDark) {
    final List<DishSpec> specs = widget.specData.specdata;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: specs.map((DishSpec spec) {
        final bool checked = spec.isCheck;
        final bool soldOut = spec.isSoldOut;
        return GestureDetector(
          onTap: () => _onSpecTap(spec),
          child: Container(
            width: (MediaQuery.of(context).size.width - 32 - 40) / 3,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: checked
                  ? _kBrandRed
                  : soldOut
                      ? (isDark ? const Color(0xFF2A2B2C) : const Color(0xFFF7F8FA))
                      : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5)),
              borderRadius: BorderRadius.circular(8),
              border: checked ? null : Border.all(
                color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${spec.specname} ¥${_formatPrice(spec.sellprice)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: checked ? FontWeight.bold : FontWeight.normal,
                    color: checked
                        ? Colors.white
                        : soldOut
                            ? const Color(0xFFC9CDD4)
                            : (isDark ? Colors.white : const Color(0xFF333333)),
                  ),
                ),
                if (spec.sellclearflag == 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      spec.stockqty > 0
                          ? '剩余:${spec.stockqty == spec.stockqty.roundToDouble() ? spec.stockqty.toInt() : spec.stockqty}'
                          : '已售罄',
                      style: TextStyle(
                        fontSize: 10,
                        color: checked ? Colors.white.withValues(alpha: 0.8) : const Color(0xFFC9CDD4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 做法分组（对齐 smdcapp: 组标题+约束说明+网格选项）
  Widget _buildCookGroup(DishCookGroup group, bool isDark) {
    final bool isEditQty = group.cooklist.isNotEmpty && group.cooklist[0].editqtyflag == 1;
    final int crossCount = isEditQty ? 2 : 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8547),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${group.groupname}${group.titleSuffix}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 40,
          ),
          itemCount: group.cooklist.length,
          itemBuilder: (BuildContext context, int index) {
            final DishCook cook = group.cooklist[index];
            return _buildCookItem(group, cook, isDark);
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 做法选项（对齐 smdcapp: 选中红框/红底，可重复时显示加减号+右上角数量角标）
  Widget _buildCookItem(DishCookGroup group, DishCook cook, bool isDark) {
    final bool checked = cook.isCheck;
    final bool isEditQty = cook.editqtyflag == 1;
    final String priceStr = cook.price == cook.price.roundToDouble()
        ? cook.price.toInt().toString()
        : cook.price.toStringAsFixed(2);
    final String label = cook.ptype == 0 || cook.price <= 0
        ? cook.cookname
        : '${cook.cookname}(\uFFE5$priceStr)';

    return GestureDetector(
      onTap: () => _onCookTap(group, cook),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: checked
                  ? (isEditQty
                      ? (isDark ? const Color(0xFF3D2826) : const Color(0xFFFCEBEB))
                      : _kBrandRed)
                  : (isDark ? const Color(0xFF3A3C3D) : Colors.white),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: checked
                    ? _kBrandRed
                    : (isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB)),
                width: checked ? 1 : 0.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // 减号（可重复模式）
                if (isEditQty)
                  GestureDetector(
                    onTap: () => _onCookMinus(cook),
                    child: SizedBox(
                      width: 30,
                      height: 40,
                      child: Center(
                        child: Icon(
                          Icons.remove_circle_outline,
                          size: 16,
                          color: checked
                              ? _kBrandRed
                              : (isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4)),
                        ),
                      ),
                    ),
                  ),
                // 名称
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
                        color: checked && !isEditQty
                            ? Colors.white
                            : checked
                                ? _kBrandRed
                                : (isDark ? Colors.white : const Color(0xFF333333)),
                      ),
                    ),
                  ),
                ),
                // 加号（可重复模式）
                if (isEditQty)
                  SizedBox(
                    width: 30,
                    height: 40,
                    child: Center(
                      child: Icon(
                        Icons.add_circle_outline,
                        size: 16,
                        color: checked
                            ? _kBrandRed
                            : (isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 数量角标（可重复模式，右上角展示）
          if (isEditQty && cook.selectCookNum > 0)
            Positioned(
              top: -6,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _kBrandRed,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Center(
                  child: Text(
                    '${cook.selectCookNum}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 数量行（加购模式）
  Widget _buildQuantityRow(bool isDark) {
    final DishProduct product = widget.product!;
    return Row(
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
          '数量',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1D2129),
          ),
        ),
        const Spacer(),
        // 减
        GestureDetector(
          onTap: () {
            if (_quantity > 1) setState(() => _quantity--);
          },
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _quantity > 1
                    ? (isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4))
                    : (isDark ? const Color(0xFF3A3C3D) : const Color(0xFFE5E6EB)),
                width: 1.2,
              ),
            ),
            child: Icon(
              Icons.remove,
              size: 13,
              color: _quantity > 1
                  ? (isDark ? Colors.white70 : const Color(0xFF86909C))
                  : const Color(0xFFC9CDD4),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Center(
            child: Text(
              '$_quantity',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
        ),
        // 加
        GestureDetector(
          onTap: () {
            // 库存校验（对齐 smdcapp）
            final DishSpec? spec = _checkedSpec;
            if (product.specflag == 1 && spec != null) {
              if (_quantity >= spec.stockqty && spec.sellclearflag == 1) {
                Toast.show('最大数量${spec.stockqty == spec.stockqty.roundToDouble() ? spec.stockqty.toInt() : spec.stockqty}');
                return;
              }
            } else if (_quantity >= product.stockqty && product.sellclearflag == 1) {
              Toast.show('最大数量${product.stockqty == product.stockqty.roundToDouble() ? product.stockqty.toInt() : product.stockqty}');
              return;
            }
            setState(() => _quantity++);
          },
          child: Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: _kBrandRed,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, size: 13, color: Colors.white),
          ),
        ),
      ],
    );
  }

  // ── 底部栏 ──

  /// 加购模式底部：总价 + 立即下单 + 加入购物车
  Widget _buildAddBottomBar(bool isDark) {
    final bool showOriginal = _originalTotal > _totalPrice;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 10, 16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1D2129).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          // 价格区
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '¥${_formatPrice(_totalPrice)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kBrandRed,
                        height: 1.2,
                      ),
                    ),
                    if (showOriginal) ...<Widget>[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '¥${_formatPrice(_originalTotal)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_specText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _specText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 立即下单（副按钮）
          GestureDetector(
            onTap: () => _submit(buyNow: true),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBrandRed),
              ),
              child: const Center(
                child: Text(
                  '立即下单',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kBrandRed,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 加入购物车（主按钮）
          GestureDetector(
            onTap: () => _submit(buyNow: false),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _kBrandRed.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '加入购物车',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 修改模式底部：做法加价 + 确认修改
  Widget _buildModifyBottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 10, 16,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '做法加价',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                  ),
                ),
                Text(
                  '¥${_formatPrice(_wholeExtraPrice)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _kBrandRed,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _confirmModify,
            child: Container(
              width: 150,
              height: 44,
              decoration: BoxDecoration(
                color: _kBrandRed,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Center(
                child: Text(
                  '确认修改',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 价格格式化（整数不带小数点）
  static String _formatPrice(double price) {
    if (price == price.roundToDouble()) return price.toInt().toString();
    return price.toStringAsFixed(2);
  }
}
