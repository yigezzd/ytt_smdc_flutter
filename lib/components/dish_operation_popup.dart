import 'package:flutter/material.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 菜品操作类型（对齐 smdcapp OperationPopup companion 常量）
class DishOperationType {
  DishOperationType._();

  static const String discount = '打折';
  static const String gift = '赠送';
  static const String changePrice = '改价';
  static const String suspend = '挂起';
  static const String bag = '打包';
  static const String remark = '备注';
  static const String delete = '删除';
  static const String waiter = '服务员';
  static const String cook = '做法';
  static const String combo = '套餐';
  static const String rename = '改名';
}

/// 菜品操作弹窗（对齐 smdcapp OperationPopup）
///
/// 居中弹窗，标题"菜品操作--{菜品名}"，3列圆形按钮网格，底部关闭按钮。
/// 按钮列表逻辑对齐 smdcapp：
/// - tab=0（待下单）单品操作：打折、赠送、改价、挂起、打包、备注、删除
/// - 始终追加：服务员
/// - 普通商品（cookflag==0 且非套餐）追加：做法
/// - 套餐商品追加：套餐
/// - 待下单追加：改名
class DishOperationPopup extends StatelessWidget {
  const DishOperationPopup({
    super.key,
    required this.dishName,
    required this.onOperation,
    this.isCookProduct = false,
    this.isComboProduct = false,
    this.isSuspended = false,
  });

  /// 菜品名称（显示在标题上）
  final String dishName;

  /// 操作回调，参数为操作类型（DishOperationType 常量）
  final ValueChanged<String> onOperation;

  /// 是否普通商品（有做法可选，对齐 smdcapp isShowCook: cookflag==0 && combflag!=1）
  final bool isCookProduct;

  /// 是否套餐商品（对齐 smdcapp isShowComb: combflag==1）
  final bool isComboProduct;

  /// 是否已挂起（已挂起时不显示挂起按钮）
  final bool isSuspended;

  /// 显示弹窗
  static Future<String?> show(
    BuildContext context, {
    required String dishName,
    bool isCookProduct = false,
    bool isComboProduct = false,
    bool isSuspended = false,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => DishOperationPopup(
        dishName: dishName,
        isCookProduct: isCookProduct,
        isComboProduct: isComboProduct,
        isSuspended: isSuspended,
        onOperation: (String type) {
          Navigator.of(context).pop(type);
        },
      ),
    );
  }

  /// 构建按钮列表（对齐 smdcapp OperationPopup init 逻辑）
  List<String> _buildOperations() {
    final List<String> list = <String>[];
    // tab=0, pos>=0, 非门店模式（storemodel!=1）的单品操作按钮
    list.add(DishOperationType.discount);
    list.add(DishOperationType.gift);
    list.add(DishOperationType.changePrice);
    if (!isSuspended) {
      list.add(DishOperationType.suspend);
    }
    list.add(DishOperationType.bag);
    list.add(DishOperationType.remark);
    list.add(DishOperationType.delete);
    // 始终追加服务员
    list.add(DishOperationType.waiter);
    // 做法（普通商品）
    if (isCookProduct) {
      list.add(DishOperationType.cook);
    }
    // 套餐（套餐商品）
    if (isComboProduct) {
      list.add(DishOperationType.combo);
    }
    // 待下单追加改名
    list.add(DishOperationType.rename);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final List<String> operations = _buildOperations();

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2D2E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 标题（对齐 smdcapp: "菜品操作--${titleText}"）
              Row(
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
                      '菜品操作--$dishName',
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
              const SizedBox(height: 20),
              // 按钮网格（对齐 smdcapp rv.grid(3)）
              Flexible(
                child: SingleChildScrollView(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: operations.length,
                    itemBuilder: (BuildContext context, int index) {
                      return _buildOperationButton(
                        context,
                        operations[index],
                        isDark,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 底部关闭按钮（对齐 smdcapp iv_close）
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4),
                      width: 1.2,
                    ),
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
        ),
      ),
    );
  }

  /// 圆形操作按钮（对齐 smdcapp item_peration 布局）
  Widget _buildOperationButton(BuildContext context, String label, bool isDark) {
    return GestureDetector(
      onTap: () => onOperation(label),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF333333),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
