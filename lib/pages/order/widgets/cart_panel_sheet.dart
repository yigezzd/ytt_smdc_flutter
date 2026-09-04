import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/dish_operation_dialogs.dart';
import 'package:flutter_deer/components/dish_operation_popup.dart';
import 'package:flutter_deer/components/spec_cook_sheet.dart';
import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/pages/order/widgets/set_meal_sheet.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 购物车展开面板（点击购物车图标弹出的底部抽屉）
///
/// 功能：
/// 1. 展示购物车商品列表（名称 + 规格 + 单价 + 数量加减）
/// 2. 清空购物车
/// 3. 合计金额
/// 4. 点击菜品名称弹出菜品操作弹窗（对齐 smdcapp OperationPopup）
class CartPanelSheet extends StatefulWidget {
  const CartPanelSheet({
    super.key,
    required this.cartItems,
    required this.onAdd,
    required this.onRemove,
    required this.onClear,
    this.onItemChanged,
    this.onDelete,
  });

  final List<CartItem> cartItems;

  /// 增加某条目数量
  final ValueChanged<CartItem> onAdd;

  /// 减少某条目数量
  final ValueChanged<CartItem> onRemove;

  /// 清空购物车
  final VoidCallback onClear;

  /// 菜品操作后条目变更回调（刷新页面状态）
  final ValueChanged<CartItem>? onItemChanged;

  /// 删除某条目回调
  final ValueChanged<CartItem>? onDelete;

  static Future<void> show(
    BuildContext context, {
    required List<CartItem> cartItems,
    required ValueChanged<CartItem> onAdd,
    required ValueChanged<CartItem> onRemove,
    required VoidCallback onClear,
    ValueChanged<CartItem>? onItemChanged,
    ValueChanged<CartItem>? onDelete,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CartPanelSheet(
        cartItems: cartItems,
        onAdd: onAdd,
        onRemove: onRemove,
        onClear: onClear,
        onItemChanged: onItemChanged,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<CartPanelSheet> createState() => _CartPanelSheetState();
}

class _CartPanelSheetState extends State<CartPanelSheet> {
  double get _totalPrice =>
      widget.cartItems.fold(0, (double sum, CartItem item) => sum + item.totalPrice);

  int get _totalCount =>
      widget.cartItems.fold(0, (int sum, CartItem item) => sum + item.quantity);

  void _handleAdd(CartItem item) {
    widget.onAdd(item);
    setState(() {});
  }

  void _handleRemove(CartItem item) {
    widget.onRemove(item);
    setState(() {});
  }

  /// 清空购物车前弹窗确认
  Future<void> _confirmClear() async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定要清空购物车吗？',
    );
    if (confirmed && mounted) {
      widget.onClear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double maxHeight = MediaQuery.of(context).size.height * 0.6;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildHeader(isDark),
          Flexible(
            child: widget.cartItems.isEmpty
                ? _buildEmpty(isDark)
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.cartItems.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5),
                    ),
                    itemBuilder: (BuildContext context, int index) {
                      return _buildCartItem(widget.cartItems[index], isDark);
                    },
                  ),
          ),
          if (widget.cartItems.isNotEmpty) _buildFooter(context, isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
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
            width: 3.5,
            height: 16,
            decoration: BoxDecoration(
              color: _kBrandRed,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '购物车',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1D2129),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($_totalCount)',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _confirmClear,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '清空',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.shopping_cart_outlined,
              size: 44,
              color: isDark ? const Color(0xFF4A4C4D) : const Color(0xFFE5E6EB),
            ),
            const SizedBox(height: 10),
            Text(
              '购物车还是空的',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItem(CartItem item, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          // 名称 + 规格（点击弹出菜品操作弹窗，对齐 smdcapp showOperation）
          Expanded(
            child: GestureDetector(
              onTap: () => _showDishOperation(item),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1D2129),
                            decoration: item.isSuspended
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      // 操作状态标记（对齐 smdcapp tvHang/tvBag 角标）
                      if (item.isWeigh) _buildTag('称', const Color(0xFF722ED1)),
                      if (item.isSuspended) _buildTag('挂', const Color(0xFFFF8547)),
                      if (item.isGift) _buildTag('赠', const Color(0xFF00B42A)),
                      if (item.isDiscounted) _buildTag('折', _kBrandRed),
                      if (item.isBag) _buildTag('包', const Color(0xFF86909C)),
                      // 必点菜标识（对齐 smdcapp DishesTagHelper：mustflag==1 红色“必”标）
                      if (item.mustflag == 1) _buildTag('必', _kBrandRed),
                    ],
                  ),
                  if (item.specText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        item.specText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                        ),
                      ),
                    ),
                  if (item.remark.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '备注：${item.remark}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFFFF8547)),
                      ),
                    ),
                  if (item.waiterName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '服务员：${item.waiterName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '¥${_formatPrice(item.discountedUnitPrice)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _kBrandRed,
                          ),
                        ),
                        // 打折时显示原价划线
                        if (item.isDiscounted)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '¥${_formatPrice(item.unitPrice)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        if (item.isGift)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Text(
                              '赠送',
                              style: TextStyle(fontSize: 11, color: Color(0xFF00B42A)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 数量控制（称重菜显示重量且禁用加减，对齐 smdcapp 称重商品不可直接改数量）
          if (item.isWeigh)
            SizedBox(
              width: 84,
              child: Center(
                child: Text(
                  '×${_formatQty(item.weighNum)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1D2129),
                  ),
                ),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                GestureDetector(
                  onTap: () => _handleRemove(item),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.remove,
                      size: 12,
                      color: isDark ? Colors.white70 : const Color(0xFF86909C),
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Center(
                    child: Text(
                      '${item.quantity}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1D2129),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _handleAdd(item),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: _kBrandRed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 12),
          // 小计
          SizedBox(
            width: 60,
            child: Text(
              '¥${_formatPrice(item.totalPrice)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16,
        12 + MediaQuery.of(context).padding.bottom,
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
          Text(
            '合计',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF4E5969),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '¥${_formatPrice(_totalPrice)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _kBrandRed,
            ),
          ),
        ],
      ),
    );
  }

  /// 状态角标
  Widget _buildTag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  /// 显示菜品操作弹窗（对齐 smdcapp AwaitOrderFragment.showOperation）
  Future<void> _showDishOperation(CartItem item) async {
    final String? operation = await DishOperationPopup.show(
      context,
      dishName: item.displayName,
      // 对齐 smdcapp: isShowCook(combflag!=1) / isShowComb(combflag==1)
      isCookProduct: !item.isCombo,
      isComboProduct: item.isCombo,
      isSuspended: item.isSuspended,
    );
    if (operation == null || !mounted) return;
    _handleOperation(operation, item);
  }

  /// 处理菜品操作（对齐 smdcapp OperationPopup.OperationListener.onCallBack）
  Future<void> _handleOperation(String type, CartItem item) async {
    switch (type) {
      case DishOperationType.discount:
        // 对齐 smdcapp: 赠送商品不能打折
        if (item.isGift) {
          Toast.show('赠送商品不能打折');
          return;
        }
        final DiscountResult? result = await DishDiscountSheet.show(
          context,
          dishName: item.displayName,
          currentDiscount: item.discount,
        );
        if (result != null) {
          item.discount = result.discount;
          // 对齐 smdcapp updataDis：100% 时不打折，清空打折原因
          item.discountRemark = result.discount >= 100 ? '' : result.remark;
          _notifyChanged(item);
        }

      case DishOperationType.gift:
        // 对齐 smdcapp GiveNumPopup 赠送逻辑
        final GiveResult? result = await DishGiveSheet.show(
          context,
          dishName: item.displayName,
          maxNum: item.quantity.toDouble(),
          isGive: item.isGift,
        );
        if (result != null) {
          if (item.isGift) {
            // 取消赠送
            item.isGift = false;
            item.giftRemark = '';
          } else {
            item.isGift = true;
            item.giftRemark = result.remark;
          }
          _notifyChanged(item);
        }

      case DishOperationType.changePrice:
        // 对齐 smdcapp: 赠送商品不能改价
        if (item.isGift) {
          Toast.show('赠送商品不能改价');
          return;
        }
        final double? price = await DishChangePriceSheet.show(
          context,
          dishName: item.displayName,
          currentPrice: item.unitPrice,
        );
        if (price != null) {
          // 对齐 smdcapp: price == sellprice 时取消改价
          if (price == item.product.price + item.extraPrice) {
            item.customPrice = null;
          } else {
            item.customPrice = price;
          }
          _notifyChanged(item);
        }

      case DishOperationType.suspend:
        // 对齐 smdcapp: hangflag == 0 时才能挂起
        if (!item.isSuspended) {
          item.isSuspended = true;
          _notifyChanged(item);
          Toast.show('已挂起');
        }

      case DishOperationType.bag:
        // 对齐 smdcapp BagPricePopup
        final double? bagPrice = await DishBagSheet.show(
          context,
          dishName: item.displayName,
          currentBagPrice: item.bagPrice,
        );
        if (bagPrice != null) {
          if (bagPrice <= -1) {
            item.bagPrice = 0;
          } else {
            item.bagPrice = bagPrice;
          }
          _notifyChanged(item);
        }

      case DishOperationType.remark:
        // 对齐 smdcapp RemarkPopup
        final String? remark = await DishRemarkSheet.show(
          context,
          dishName: item.displayName,
          currentRemark: item.remark,
        );
        if (remark != null) {
          item.remark = remark;
          _notifyChanged(item);
        }

      case DishOperationType.delete:
        // 对齐 smdcapp: 删除商品
        if (widget.onDelete != null) {
          widget.onDelete!(item);
        } else {
          widget.cartItems.remove(item);
          _notifyChanged(item);
        }

      case DishOperationType.waiter:
        // 对齐 smdcapp WaiterPopup
        final Waiter? waiter = await DishWaiterSheet.show(
          context,
          dishName: item.displayName,
          currentWaiter: item.waiterName,
        );
        if (waiter != null) {
          item.waiterName = waiter.name;
          _notifyChanged(item);
        }

      case DishOperationType.cook:
        // 做法修改（对齐 smdcapp checkSpec + SpecCookPopup2 修改模式）
        await _handleCookModify(item);

      case DishOperationType.combo:
        // 套餐修改（对齐 smdcapp NAME_COMB → handleChangeComb）
        await _handleComboModify(item);

      case DishOperationType.rename:
        // 对齐 smdcapp ChangeNamePopup: 修改名称+价格
        final RenameResult? result = await DishRenameSheet.show(
          context,
          dishName: item.displayName,
          currentPrice: item.unitPrice,
        );
        if (result != null) {
          item.customName = result.name;
          item.customPrice = result.price;
          _notifyChanged(item);
        }
    }
  }

  void _notifyChanged(CartItem item) {
    setState(() {});
    widget.onItemChanged?.call(item);
  }

  /// 做法修改（对齐 smdcapp checkSpec + SpecCookPopup2）
  ///
  /// 1. 调 getProductCookSpec 获取规格做法数据
  /// 2. 普通商品（无规格）直接展示全部做法；多规格商品展示私有/全局做法 Tab
  /// 3. 确认修改后更新购物车条目的做法描述与加价
  Future<void> _handleCookModify(CartItem item) async {
    // 显示加载中
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
    DishSpecData specData;
    try {
      specData = await OrderRepository.fetchProductCookSpec(item.product.id);
      // 全局做法：对齐 smdcapp SpecCookPopup2.initCookTab:
      // isPublicValid = SpUtils.isShowPublicCook() && publicCook.isNotEmpty()
      // 仅当"显示公共做法"开关开启时才拉取公共做法
      final bool showPublicCook = SpUtil.getBool('setting_show_public_cook', defValue: true) ?? true;
      if (showPublicCook && specData.publiccook.isEmpty) {
        final List<DishCookGroup> publicCooks = await OrderRepository.fetchPublicCooks();
        if (publicCooks.isNotEmpty) {
          specData = DishSpecData(
            specdata: specData.specdata,
            cookdata: specData.cookdata,
            publiccook: publicCooks,
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading
      Toast.show('获取做法信息失败');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭 loading

    if (specData.cookdata.isEmpty && specData.publiccook.isEmpty) {
      Toast.show('该菜品没有做法可选');
      return;
    }

    final CookModifyResult? result = await SpecCookSheet.showModify(
      context,
      dishName: item.displayName,
      unitPrice: item.unitPrice,
      specData: specData,
      currentSpecText: item.specText,
    );
    if (result == null || !mounted) return;

    // 重建规格做法描述：保留规格名前缀，替换做法部分
    final String specPrefix = _deriveSpecPrefix(item, specData);
    item.specText = specPrefix.isEmpty
        ? result.cookText
        : (result.cookText.isEmpty ? specPrefix : '$specPrefix、${result.cookText}');
    item.extraPrice = result.cookExtra;
    _notifyChanged(item);
  }

  /// 套餐修改（对齐 smdcapp OperationPopup.NAME_COMB → handleChangeComb：
  /// 拉取套餐配置，编辑模式打开套餐弹窗，确认后替换明细与加减价）
  Future<void> _handleComboModify(CartItem item) async {
    // 显示加载中
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
    ComboMealData? comboData;
    try {
      comboData = await OrderRepository.fetchProductComb(item.product.id);
    } catch (_) {
      comboData = null;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭 loading

    if (comboData == null || comboData.prolist.isEmpty) {
      Toast.show('暂无套餐数据');
      return;
    }

    await SetMealSheet.show(
      context,
      product: DishProduct(
        productid: item.product.id,
        name: item.product.name,
        sellprice: item.product.price,
        combflag: 1,
      ),
      comboData: comboData,
      isEditMode: true,
      initialSelection: item.combItems,
      onConfirmEdit: (SetMealResult result) {
        item.combItems = result.selectedItems;
        item.extraPrice = result.combAddAmt;
        item.specText = result.specText;
        _notifyChanged(item);
      },
    );
  }

  /// 从当前 specText 中推导规格名前缀（多规格商品保留规格名）
  String _deriveSpecPrefix(CartItem item, DishSpecData specData) {
    if (specData.specdata.isEmpty || item.specText.isEmpty) return '';
    for (final DishSpec spec in specData.specdata) {
      if (item.specText == spec.specname) return spec.specname;
      if (item.specText.startsWith('${spec.specname}、')) return spec.specname;
    }
    return '';
  }

  static String _formatPrice(double price) {
    if (price == price.roundToDouble()) return price.toInt().toString();
    return price.toStringAsFixed(2);
  }

  /// 格式化重量/数量（整数不带小数点，对齐 smdcapp PriceUtil.formatQty）
  static String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) return qty.toInt().toString();
    return qty.toString();
  }
}
