import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 商品图片 OSS 前缀
const String _kImgAddress = 'http://byyoupic.oss-cn-shenzhen.aliyuncs.com/';

/// 套餐选择结果
class SetMealResult {
  SetMealResult({
    required this.quantity,
    required this.specText,
    required this.unitPrice,
    required this.combAddAmt,
    required this.selectedItems,
  });

  /// 套餐数量
  final int quantity;

  /// 套餐SKU描述（选中明细拼接，仅展示用；不上传 spec 字段，
  /// 对齐 smdcapp getSetMealPrice str[2]）
  final String specText;

  /// 套餐单价（sellprice）
  final double unitPrice;

  /// 套餐加减价总额
  final double combAddAmt;

  /// 选中明细快照（下单时生成套餐子行，对齐 smdcapp getSetMealInfo）
  final List<ComboSelectedItem> selectedItems;
}

/// 套餐弹窗（对齐 smdcapp SetMealPopup 完整UI与业务逻辑）
///
/// 功能：
/// 1. 商品图片 + 名称 + 价格展示
/// 2. 套餐分组选择（N选M、按数量/按项、可重复选择）
/// 3. 默认选中（defflag=1，校验库存）
/// 4. 实时价格计算（对齐 ShoppingCartUtil.getSetMealPrice）
/// 5. 必选校验（对齐 CombHelper.validateSetMealSelection）
/// 6. 加入购物车 / 立即下单
class SetMealSheet extends StatefulWidget {
  const SetMealSheet({
    super.key,
    required this.product,
    required this.comboData,
    this.onAddToCart,
    this.onBuyNow,
    this.isEditMode = false,
    this.initialSelection,
    this.onConfirmEdit,
  });

  final DishProduct product;
  final ComboMealData comboData;

  /// 加入购物车回调
  final void Function(SetMealResult result)? onAddToCart;

  /// 立即下单回调
  final void Function(SetMealResult result)? onBuyNow;

  /// 编辑模式（对齐 smdcapp CombPopup2 isChange：修改已选套餐内容）
  final bool isEditMode;

  /// 编辑模式已选明细（用于恢复选中状态，对齐 smdcapp 购物车 bean 保留 setMealBean 选中态）
  final List<ComboSelectedItem>? initialSelection;

  /// 编辑模式确认修改回调
  final void Function(SetMealResult result)? onConfirmEdit;

  /// 显示弹窗
  static Future<void> show(
    BuildContext context, {
    required DishProduct product,
    required ComboMealData comboData,
    void Function(SetMealResult result)? onAddToCart,
    void Function(SetMealResult result)? onBuyNow,
    bool isEditMode = false,
    List<ComboSelectedItem>? initialSelection,
    void Function(SetMealResult result)? onConfirmEdit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SetMealSheet(
        product: product,
        comboData: comboData,
        onAddToCart: onAddToCart,
        onBuyNow: onBuyNow,
        isEditMode: isEditMode,
        initialSelection: initialSelection,
        onConfirmEdit: onConfirmEdit,
      ),
    );
  }

  @override
  State<SetMealSheet> createState() => _SetMealSheetState();
}

class _SetMealSheetState extends State<SetMealSheet> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;

  /// 套餐数量（套餐不允许修改数量，固定为1）
  int _quantity = 1;

  /// 跨组选中下标记录（对齐 smdcapp lastPos，防止跨组选择时数据错乱）
  final Map<String, int> _lastPosMap = <String, int>{};

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _slideAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    if (widget.isEditMode) {
      _restoreEditSelection();
    } else {
      _bindCombCheck();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ==================== 业务逻辑（对齐 smdcapp CombHelper） ====================

  /// 初始化默认选中（对齐 smdcapp CombHelper.bindCombCheck）
  ///
  /// 只有 defflag=1 的商品才默认选中，且需校验：
  /// 1. 库存可用（sellclearflag==0 或 stockqty>0）
  /// 2. 选中数量不超过组的 selectqty
  void _bindCombCheck() {
    final List<ComboGroup> prolist = widget.comboData.prolist;
    for (int groupIndex = 0; groupIndex < prolist.length; groupIndex++) {
      final ComboGroup group = prolist[groupIndex];
      final double selectQty = group.selectqty;
      final bool isFixedQty = group.selecttype == 1; // 1=按数量 2=按项

      for (int itemIndex = 0; itemIndex < group.list.length; itemIndex++) {
        final ComboItem item = group.list[itemIndex];
        if (item.isCheck || item.defflag == 1) {
          // 校验库存
          final bool isStockAvailable =
              item.sellclearflag == 0 || (item.sellclearflag == 1 && item.stockqty > 0);
          if (isStockAvailable) {
            final double checkSelectQty = isFixedQty ? item.qty : 1.0;
            final double checkStockQty = isFixedQty ? item.qty : 1.0 * item.qty;
            final bool valid = item.sellclearflag == 1
                ? checkStockQty <= item.stockqty
                : checkSelectQty <= selectQty;
            if (valid) {
              item.isCheck = true;
              item.selectSetMealNum = isFixedQty ? item.qty : 1.0;
              _lastPosMap[groupIndex.toString()] = itemIndex;
            } else {
              item.isCheck = false;
              item.selectSetMealNum = 0;
            }
          } else {
            item.isCheck = false;
            item.selectSetMealNum = 0;
          }
        }
      }
    }
  }

  /// 编辑模式恢复已选明细选中态
  ///
  /// 匹配规则：优先 combsetproductid（套餐明细配置ID），回退 productid+specname。
  /// 数量还原（对齐 _calcSetMealPrice 明细 qty 口径）：
  /// selecttype==1 时 qty 即 selectSetMealNum；selecttype==2 时 qty = selectSetMealNum × 单次数量。
  void _restoreEditSelection() {
    final List<ComboSelectedItem>? selected = widget.initialSelection;
    if (selected == null || selected.isEmpty) {
      _bindCombCheck();
      return;
    }
    for (final ComboGroup group in widget.comboData.prolist) {
      for (final ComboItem item in group.list) {
        final ComboSelectedItem? match = _findSelected(item, selected);
        if (match == null) continue;
        // 售罄商品不恢复选中（对齐 smdcapp 沽清校验）
        if (item.sellclearflag == 1 && item.stockqty <= 0) continue;
        item.isCheck = true;
        item.selectSetMealNum = item.selecttype == 1
            ? match.qty
            : (item.qty > 0 ? match.qty / item.qty : match.qty);
      }
    }
  }

  /// 查找已选明细对应的配置项
  ComboSelectedItem? _findSelected(ComboItem item, List<ComboSelectedItem> selected) {
    for (final ComboSelectedItem s in selected) {
      if (item.combsetproductid.isNotEmpty &&
          s.combsetproductid == item.combsetproductid) {
        return s;
      }
    }
    final String specname = item.specid.isNotEmpty ? item.specname : '';
    for (final ComboSelectedItem s in selected) {
      if (s.productid == item.productid && s.specname == specname) {
        return s;
      }
    }
    return null;
  }

  /// 计算组内已选总数量（对齐 smdcapp SetMealPopup selectAllNum 逻辑）
  double _getGroupSelectedNum(ComboGroup group, ComboItem currentItem) {
    double selectAllNum = 0;
    for (final ComboItem item in group.list) {
      if (item.isCheck) {
        if (currentItem.repeatflag == 0) {
          selectAllNum += currentItem.selecttype == 1 ? item.qty : 1.0;
        } else if (currentItem.repeatflag == 1 && item.selectSetMealNum > 0) {
          selectAllNum += item.selectSetMealNum;
        }
      }
    }
    return selectAllNum;
  }

  /// 点击套餐明细商品（对齐 smdcapp SetMealPopup tv_size.onClick 完整逻辑）
  void _onItemTap(ComboGroup group, ComboItem item, int groupIndex, int itemIndex) {
    final double selectAllNum = _getGroupSelectedNum(group, item);
    final double selectqty = item.selectqty;
    final int selecttype = item.selecttype;

    // 售罄校验
    if (item.sellclearflag == 1 && item.stockqty <= 0) {
      Toast.show('已售罄');
      return;
    }
    if (item.sellclearflag == 1 && selectAllNum >= item.stockqty) {
      Toast.show('库存不足');
      return;
    }

    if (item.repeatflag == 0) {
      // 不可重复选择
      if (selecttype == 1) {
        // 按数量选择
        if (item.isCheck) {
          item.isCheck = false;
          item.selectSetMealNum = 0;
        } else {
          if (selectAllNum + item.qty <= selectqty) {
            item.isCheck = true;
            item.selectSetMealNum = item.qty;
          } else {
            Toast.show('最大可选数量${_formatQty(selectqty)}');
          }
        }
      } else {
        // 按项选择（单选行为：取消上一个，选新的）
        if (selectAllNum >= selectqty && !item.isCheck) {
          // 取消上次选中的
          final int? lastPos = _lastPosMap[groupIndex.toString()];
          if (lastPos != null && lastPos < group.list.length) {
            final ComboItem lastItem = group.list[lastPos];
            if (lastItem.isCheck) {
              lastItem.isCheck = false;
              lastItem.selectSetMealNum = 0;
            }
          }
          item.isCheck = true;
          item.selectSetMealNum = 1.0;
        } else if (item.isCheck) {
          item.isCheck = false;
          item.selectSetMealNum = 0;
        } else {
          item.isCheck = true;
          item.selectSetMealNum = 1.0;
        }
      }
    } else {
      // 可重复选择
      if (selectAllNum >= selectqty) {
        Toast.show(selecttype == 1 ? '已选最大数量' : '已选最大项数');
        return;
      }
      item.selectSetMealNum += 1;
      item.isCheck = true;
    }

    _lastPosMap[groupIndex.toString()] = itemIndex;
    setState(() {});
  }

  /// 可重复选择的商品减少数量（对齐 smdcapp ll_minus.onClick）
  void _onItemMinus(ComboItem item) {
    if (item.selectSetMealNum > 1) {
      item.selectSetMealNum -= 1;
    } else {
      item.selectSetMealNum = 0;
      item.isCheck = false;
    }
    setState(() {});
  }

  /// 可重复选择的商品增加数量
  void _onItemPlus(ComboGroup group, ComboItem item) {
    final double selectAllNum = _getGroupSelectedNum(group, item);
    if (selectAllNum >= group.selectqty) {
      Toast.show('已选最大数量');
      return;
    }
    item.selectSetMealNum += 1;
    item.isCheck = true;
    setState(() {});
  }

  // ==================== 价格计算（对齐 smdcapp ShoppingCartUtil.getSetMealPrice） ====================

  /// 计算套餐SKU信息、加减价和选中明细（对齐 smdcapp getSetMealPrice + getSetMealInfo）
  ///
  /// 返回 [skuText, combAddAmt, selectedItems]
  /// - skuText: "麻辣子鸡x1,辣椒炒肉x1" 格式（仅展示用）
  /// - combAddAmt: 明细加价总和 - 减价总和
  /// - selectedItems: 选中明细快照（下单时上传套餐子行，避免拼接进 spec 超长）
  List<dynamic> _calcSetMealPrice() {
    final StringBuffer sb = StringBuffer();
    double combAddAmt = 0;
    final List<ComboSelectedItem> selectedItems = <ComboSelectedItem>[];

    for (final ComboGroup group in widget.comboData.prolist) {
      for (final ComboItem item in group.list) {
        if (item.isCheck) {
          sb.write(item.productname);
          sb.write('x');

          final double cutprice = item.cutprice;
          final double addprice = item.addprice;
          double qty = item.selectSetMealNum;

          if (cutprice > 0) {
            combAddAmt += -cutprice * qty;
          }
          if (addprice > 0) {
            combAddAmt += addprice * qty;
          }

          // 明细行数量/加减价（对齐 smdcapp getSetMealInfo 分支）
          double detailQty;
          double detailAddAmt;
          final double baseAdd = (addprice > 0)
              ? addprice * qty
              : ((cutprice > 0) ? -cutprice * qty : 0);
          if (item.selecttype == 1) {
            sb.write(_formatQty(item.selectSetMealNum));
            detailQty = item.selectSetMealNum;
            detailAddAmt = baseAdd;
          } else {
            sb.write(_formatQty(item.selectSetMealNum * item.qty));
            qty = item.selectSetMealNum * item.qty;
            detailQty = qty;
            detailAddAmt = baseAdd;
          }
          sb.write(',');

          selectedItems.add(ComboSelectedItem(
            productid: item.productid,
            productname: item.productname,
            qty: detailQty,
            combaddamt: detailAddAmt,
            groupid: group.groupid,
            combsetproductid: item.combsetproductid,
            specname: item.specid.isNotEmpty ? item.specname : '',
            sellprice: item.price,
            unit: item.unit,
          ));
        }
      }
    }

    String skuText = sb.toString();
    if (skuText.endsWith(',')) {
      skuText = skuText.substring(0, skuText.length - 1);
    }
    return <dynamic>[skuText, combAddAmt, selectedItems];
  }

  /// 套餐总价 = (套餐销售价 + 单份加减价) × 数量
  /// 对齐 smdcapp CombHelper.processComb: combaddamt = qty × 明细加减价总和
  /// 即最终价 = sellprice × qty + combaddamt = (sellprice + 单份加减价) × qty
  double _totalPriceWithAddAmt(double combAddAmt) =>
      (widget.comboData.sellprice + combAddAmt) * _quantity;

  // ==================== 校验（对齐 smdcapp CombHelper.validateSetMealSelection） ====================

  /// 校验套餐选择是否满足加入购物车条件
  /// 返回 '' 表示满足，否则返回错误描述
  String _validateSelection() {
    final List<ComboGroup> prolist = widget.comboData.prolist;
    if (prolist.isEmpty) return '没有商品数据';

    for (final ComboGroup group in prolist) {
      final List<ComboItem> itemList = group.list;
      if (itemList.isNotEmpty) {
        // 检查组配置是否异常
        if (itemList.any((ComboItem i) => i.selectqty == 0)) {
          return '套餐数据配置异常，${group.groupname}组必选数量或项数不能为0';
        }
        // 计算当前组内已勾选的商品总数量
        final double totalSelected = itemList
            .where((ComboItem i) => i.isCheck)
            .fold(0.0, (double sum, ComboItem i) => sum + i.selectSetMealNum);
        // 获取必选数量
        final double requiredQty = itemList.last.selectqty;

        if (totalSelected < requiredQty) {
          return '${group.groupname}组缺少必选项，请检查套餐配置是否正确或商品沽清数量是否不足';
        } else if (totalSelected > requiredQty) {
          return '${group.groupname}组多选了必选项';
        }
      }
    }
    return '';
  }

  // ==================== 操作 ====================

  /// 加入购物车（对齐 smdcapp SetMealPopup addCart）
  void _addCart() {
    final String error = _validateSelection();
    if (error.isNotEmpty) {
      Toast.show(error);
      return;
    }
    final List<dynamic> priceInfo = _calcSetMealPrice();
    widget.onAddToCart?.call(SetMealResult(
      quantity: _quantity,
      specText: priceInfo[0] as String,
      unitPrice: widget.comboData.sellprice,
      combAddAmt: priceInfo[1] as double,
      selectedItems: priceInfo[2] as List<ComboSelectedItem>,
    ));
    Navigator.of(context).pop();
  }

  /// 确认修改（编辑模式，对齐 smdcapp CombPopup2 isChange → tvAddCart "确认修改"）
  void _confirmEdit() {
    final String error = _validateSelection();
    if (error.isNotEmpty) {
      Toast.show(error);
      return;
    }
    final List<dynamic> priceInfo = _calcSetMealPrice();
    widget.onConfirmEdit?.call(SetMealResult(
      quantity: _quantity,
      specText: priceInfo[0] as String,
      unitPrice: widget.comboData.sellprice,
      combAddAmt: priceInfo[1] as double,
      selectedItems: priceInfo[2] as List<ComboSelectedItem>,
    ));
    Navigator.of(context).pop();
  }

  /// 立即下单（对齐 smdcapp SetMealPopup tvOrder.onClick）
  ///
  /// 必须先关闭弹窗再回调跳转：回调会推入下单确认页，若之后再 pop
  /// 会把刚推入的页面弹掉，"下单"就退化为仅加购。
  void _buyNow() {
    final String error = _validateSelection();
    if (error.isNotEmpty) {
      Toast.show(error);
      return;
    }
    final List<dynamic> priceInfo = _calcSetMealPrice();
    Navigator.of(context).pop();
    widget.onBuyNow?.call(SetMealResult(
      quantity: _quantity,
      specText: priceInfo[0] as String,
      unitPrice: widget.comboData.sellprice,
      combAddAmt: priceInfo[1] as double,
      selectedItems: priceInfo[2] as List<ComboSelectedItem>,
    ));
  }

  // ==================== UI构建 ====================

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.of(context).size.height * 0.88;
    final List<dynamic> priceInfo = _calcSetMealPrice();
    final String skuText = priceInfo[0] as String;
    final double combAddAmt = priceInfo[1] as double;

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_slideAnimation),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildGroupSections(),
                ),
              ),
            ),
            _buildBottomBar(skuText, combAddAmt),
          ],
        ),
      ),
    );
  }

  /// 顶部：商品图片 + 名称 + 价格 + 关闭按钮（对齐 dialog_set_meal_bottom.xml 头部）
  Widget _buildHeader() {
    final ComboMealData data = widget.comboData;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF2F3F5), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 商品图片
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _buildCoverImage(data.imageurl),
          ),
          const SizedBox(width: 12),
          // 名称 + 价格
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Text(
                    data.name.isNotEmpty ? data.name : widget.product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1D2129),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 套餐标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '套餐',
                    style: TextStyle(fontSize: 10, color: _kBrandRed, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 8),
                // 价格行
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    const Text(
                      '¥',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kBrandRed),
                    ),
                    Text(
                      _formatPrice(data.sellprice),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kBrandRed,
                        height: 1.1,
                      ),
                    ),
                    if (data.mprice1 > 0 && data.mprice1 != data.sellprice) ...<Widget>[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '¥${_formatPrice(data.mprice1)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF999999),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ],
                  ],
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
                color: const Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 18, color: Color(0xFF999999)),
            ),
          ),
        ],
      ),
    );
  }

  /// 商品封面图
  Widget _buildCoverImage(String imageurl) {
    if (imageurl.isNotEmpty && imageurl != 'null') {
      final String url = imageurl.startsWith('http') ? imageurl : '$_kImgAddress$imageurl';
      return CachedNetworkImage(
        imageUrl: url,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        memCacheWidth: 160,
        placeholder: (_, __) => _buildCoverPlaceholder(),
        errorWidget: (_, __, dynamic error) => _buildCoverPlaceholder(),
      );
    }
    return _buildCoverPlaceholder();
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      width: 80,
      height: 80,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
        ),
      ),
      child: const Center(
        child: Text('🍱', style: TextStyle(fontSize: 32)),
      ),
    );
  }

  /// 套餐分组区域列表
  List<Widget> _buildGroupSections() {
    final List<Widget> sections = <Widget>[];
    final List<ComboGroup> prolist = widget.comboData.prolist;

    for (int groupIndex = 0; groupIndex < prolist.length; groupIndex++) {
      final ComboGroup group = prolist[groupIndex];
      sections.add(_buildGroupTitle(group));
      sections.add(_buildGroupGrid(group, groupIndex));
      if (groupIndex < prolist.length - 1) {
        sections.add(const SizedBox(height: 4));
      }
    }
    sections.add(const SizedBox(height: 12));
    return sections;
  }

  /// 分组标题（对齐 smdcapp dishes_item_specification_title_pop）
  Widget _buildGroupTitle(ComboGroup group) {
    // 计算组内已选进度
    double selected = 0;
    for (final ComboItem item in group.list) {
      if (item.isCheck) {
        selected += group.selecttype == 1 ? item.selectSetMealNum : (item.isCheck ? 1 : 0);
      }
    }
    final bool isFull = selected >= group.selectqty;

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
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
          Expanded(
            child: RichText(
              text: TextSpan(
                children: <TextSpan>[
                  TextSpan(
                    text: group.groupname.isNotEmpty ? group.groupname : '套餐分组',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1D2129),
                    ),
                  ),
                  TextSpan(
                    text: ' ${group.hintText}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                  ),
                ],
              ),
            ),
          ),
          // 选择进度
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isFull ? const Color(0xFFE8F7E8) : const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '已选${_formatQty(selected)}/${_formatQty(group.selectqty)}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isFull ? const Color(0xFF52C41A) : _kBrandRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分组商品网格（对齐 smdcapp：repeatflag==1 时2列，否则3列）
  Widget _buildGroupGrid(ComboGroup group, int groupIndex) {
    final int crossCount = group.repeatflag == 1 ? 2 : 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: group.repeatflag == 1 ? 78 : 52,
      ),
      itemCount: group.list.length,
      itemBuilder: (BuildContext context, int itemIndex) {
        final ComboItem item = group.list[itemIndex];
        return _buildComboItemTile(group, item, groupIndex, itemIndex);
      },
    );
  }

  /// 套餐明细选项卡片（对齐 smdcapp dishes_item_specification_grid_pop）
  Widget _buildComboItemTile(ComboGroup group, ComboItem item, int groupIndex, int itemIndex) {
    final bool isCheck = item.isCheck;
    final bool isRepeat = item.repeatflag == 1;
    final bool soldOut = item.isSoldOut;

    // 商品名称文本（对齐 smdcapp：名称 + *数量 + 加价/减价）
    final StringBuffer label = StringBuffer(item.productname);
    if (item.selecttype == 2 && item.qty > 1) {
      label.write('*${_formatQty(item.qty)}');
    }

    String? priceTag;
    Color priceTagColor = _kBrandRed;
    if (item.addprice > 0) {
      priceTag = '加价¥${_formatQty(item.addprice)}';
      priceTagColor = const Color(0xFFFF8800);
    } else if (item.cutprice > 0) {
      priceTag = '减价¥${_formatQty(item.cutprice)}';
      priceTagColor = const Color(0xFF52C41A);
    }

    return GestureDetector(
      onTap: soldOut ? () => Toast.show('已售罄') : () => _onItemTap(group, item, groupIndex, itemIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: soldOut
              ? const Color(0xFFF7F8FA)
              : isCheck
                  ? (isRepeat ? const Color(0xFFFEF0EF) : _kBrandRed)
                  : (isRepeat ? Colors.white : const Color(0xFFF7F8FA)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            width: 1,
            color: soldOut
                ? const Color(0xFFE5E6EB)
                : isCheck
                    ? (isRepeat ? _kBrandRed : _kBrandRed)
                    : (isRepeat ? const Color(0xFFE5E6EB) : Colors.transparent),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // 名称 + 加价信息（加价/减价用对应颜色显示）
            Flexible(
              child: priceTag != null
                  ? RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: <TextSpan>[
                          TextSpan(
                            text: '$label\n',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isCheck ? FontWeight.w600 : FontWeight.normal,
                              height: 1.3,
                              color: soldOut
                                  ? const Color(0xFFC9CDD4)
                                  : (!isRepeat && isCheck)
                                      ? Colors.white
                                      : const Color(0xFF333333),
                            ),
                          ),
                          TextSpan(
                            text: priceTag,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: (!isRepeat && isCheck && !soldOut)
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : priceTagColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      '$label',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCheck ? FontWeight.w600 : FontWeight.normal,
                        height: 1.3,
                        color: soldOut
                            ? const Color(0xFFC9CDD4)
                            : (!isRepeat && isCheck)
                                ? Colors.white
                                : const Color(0xFF333333),
                      ),
                    ),
            ),
            // 可重复选择时显示加减控件
            if (isRepeat && !soldOut) ...<Widget>[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _buildMiniButton(
                    icon: Icons.remove,
                    enabled: item.selectSetMealNum > 0,
                    onTap: () => _onItemMinus(item),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${item.selectSetMealNum.toInt()}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: item.selectSetMealNum > 0 ? _kBrandRed : const Color(0xFFC9CDD4),
                      ),
                    ),
                  ),
                  _buildMiniButton(
                    icon: Icons.add,
                    enabled: true,
                    onTap: () => _onItemPlus(group, item),
                  ),
                ],
              ),
            ],
            // 售罄标记
            if (soldOut)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('售罄', style: TextStyle(fontSize: 10, color: Color(0xFFC9CDD4))),
              ),
          ],
        ),
      ),
    );
  }

  /// 迷你加减按钮
  Widget _buildMiniButton({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? _kBrandRed : const Color(0xFFE5E6EB),
        ),
        child: Icon(icon, size: 12, color: Colors.white),
      ),
    );
  }

  /// 底部栏：总价 + SKU + 数量 + 按钮（对齐 dialog_set_meal_bottom.xml 底部）
  Widget _buildBottomBar(String skuText, double combAddAmt) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFF2F3F5), width: 0.5),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1D2129).withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 总价 + 数量控制
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            '¥${_formatPrice(_totalPriceWithAddAmt(combAddAmt))}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _kBrandRed,
                              height: 1.2,
                            ),
                          ),
                          if (combAddAmt != 0) ...<Widget>[
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                combAddAmt > 0
                                    ? '含加价¥${_formatPrice(combAddAmt * _quantity)}'
                                    : '已减¥${_formatPrice(-combAddAmt * _quantity)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: combAddAmt > 0 ? const Color(0xFFFF8800) : const Color(0xFF52C41A),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // SKU 描述
                      if (skuText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            skuText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
                          ),
                        ),
                    ],
                  ),
                ),
                // 数量控制（套餐不允许修改数量，对齐 smdcapp）
                Row(
                  children: <Widget>[
                    GestureDetector(
                      onTap: () {
                        if (_quantity > 1) {
                          setState(() => _quantity--);
                        }
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE5E6EB)),
                        ),
                        child: const Icon(Icons.remove, size: 14, color: Color(0xFF666666)),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Center(
                        child: Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Toast.show('套餐不允许修改数量'),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE5E6EB)),
                        ),
                        child: const Icon(Icons.add, size: 14, color: Color(0xFFC9CDD4)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 操作按钮（对齐 smdcapp：编辑模式仅"确认修改"，否则下单 + 加入购物车）
            Row(
              children: <Widget>[
                if (widget.isEditMode)
                  Expanded(
                    child: GestureDetector(
                      onTap: _confirmEdit,
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
                        child: const Center(
                          child: Text(
                            '确认修改',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  )
                else ...<Widget>[
                  if (widget.onBuyNow != null)
                    Expanded(
                      child: GestureDetector(
                        onTap: _buyNow,
                        child: Container(
                          height: 44,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFE5E6EB)),
                          ),
                          child: const Center(
                            child: Text(
                              '下单',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF666666)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _addCart,
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
                        child: const Center(
                          child: Text(
                            '加入购物车',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 8 : 14),
          ],
        ),
      ),
    );
  }
}

/// 格式化价格（对齐 smdcapp PriceUtil.formatPrice）
String _formatPrice(double price) {
  return price == price.roundToDouble() ? price.toInt().toString() : price.toStringAsFixed(2);
}

/// 格式化数量（整数不带小数点）
String _formatQty(double qty) {
  return qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toStringAsFixed(1);
}
