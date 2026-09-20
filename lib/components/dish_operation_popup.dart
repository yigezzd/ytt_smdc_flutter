import 'package:flutter/material.dart';

import '../util/store_mode_utils.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE63F31);

/// 菜品操作类型（对齐 smdcapp OperationPopup / CartActionNames 常量）
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

  /// 套餐明细操作（对齐 smdcapp SetMealOperationPopup）
  static const String comboSubCook = '明细做法';
  static const String comboSubModify = '明细修改';

  /// 已下单菜品的专属操作（对齐 smdcapp OperationAction.buildOrderedActions）
  static const String refund = '退菜';
  static const String urge = '催菜';
  static const String startDish = '起菜';
  static const String transferDish = '转菜';
  static const String reweigh = '称重';
  static const String serveDish = '划菜';
}

/// 操作按钮（action=逻辑类型，label=实际显示文案，可随状态变化）
class DishOperation {
  const DishOperation(this.action, this.label, {this.isCancel = false});

  final String action;
  final String label;

  /// 是否为"取消"态（取消赠送/取消挂起/取消打包），用于高亮
  final bool isCancel;
}

/// 已下单菜品菜单（对齐 smdcapp OperationAction.buildOrderedActions）
///
/// 订单详情页单品弹窗与订单确认页已下单标签共用，保证两处菜单一致。
/// 待下单菜品请使用 [DishOperationPopup] 的默认（待下单）菜单。
List<DishOperation> buildOrderedOperations({
  bool isGift = false,
  bool isCut = false,
  bool showWeigh = false,
}) {
  return <DishOperation>[
    const DishOperation(DishOperationType.discount, '打折'),
    DishOperation(
      DishOperationType.gift,
      isGift ? '取消\n赠送' : '赠送',
      isCancel: isGift,
    ),
    const DishOperation(DishOperationType.changePrice, '改价'),
    const DishOperation(DishOperationType.refund, '退菜'),
    const DishOperation(DishOperationType.urge, '催菜'),
    const DishOperation(DishOperationType.startDish, '起菜'),
    const DishOperation(DishOperationType.waiter, '服务员'),
    const DishOperation(DishOperationType.transferDish, '转菜'),
    // 称重菜且开启"称重二次确认"参数时才出现（对齐 smdcapp: weighflag==1 && isReweigh()）
    if (showWeigh) const DishOperation(DishOperationType.reweigh, '称重'),
    DishOperation(
      DishOperationType.serveDish,
      isCut ? '取消\n划菜' : '划菜',
      isCancel: isCut,
    ),
  ];
}

/// 菜品操作弹窗（对齐 smdcapp GoodsSingleOperationPopup）
///
/// 居中弹窗，标题"菜品操作--{菜品名}"，3列圆形按钮网格，底部关闭按钮。
/// 菜单按菜品状态切换（对齐 smdcapp DetailListBean.id == 0 判定）：
/// - 待下单（默认）：对齐 OperationAction.buildPendingActions
///   · 正餐：打折、赠送、改价、挂起、打包、备注、删除、服务员、套餐/规格做法、改名
///   · 快餐：打折、改价、赠送、打包、备注、服务员、套餐/规格做法、改名、删除
/// - 已下单（[isOrdered]）：对齐 OperationAction.buildOrderedActions
///   · 打折、赠送、改价、退菜、催菜、起菜、服务员、转菜、[称重]、划菜
/// 赠送/挂起/打包/划菜在已处于该状态时，文案切换为"取消XX"。
class DishOperationPopup extends StatelessWidget {
  const DishOperationPopup({
    super.key,
    required this.dishName,
    required this.onOperation,
    this.isCookProduct = false,
    this.isComboProduct = false,
    this.isSuspended = false,
    this.isGift = false,
    this.isBag = false,
    this.isOrdered = false,
    this.isCut = false,
    this.showWeigh = false,
  });

  /// 菜品名称（显示在标题上）
  final String dishName;

  /// 操作回调，参数为操作类型（DishOperationType 常量）
  final ValueChanged<String> onOperation;

  /// 是否普通商品（有做法可选，对齐 smdcapp isShowCook: cookflag==0 && combflag!=1）
  final bool isCookProduct;

  /// 是否套餐商品（对齐 smdcapp isShowComb: combflag==1）
  final bool isComboProduct;

  /// 是否已挂起（对齐 smdcapp hangflag==1，文案切换为取消挂起）
  final bool isSuspended;

  /// 是否已赠送（对齐 smdcapp presentflag==1，文案切换为取消赠送）
  final bool isGift;

  /// 是否已打包（对齐 smdcapp bagstatus==1，文案切换为取消打包）
  final bool isBag;

  /// 是否已下单菜品（对齐 smdcapp DetailListBean.id != 0）
  final bool isOrdered;

  /// 是否已划菜（对齐 smdcapp cutflag==1，文案切换为取消划菜）
  final bool isCut;

  /// 是否显示"称重"（对齐 smdcapp weighflag==1 && SpUtils.isReweigh()）
  final bool showWeigh;

  /// 显示弹窗
  static Future<String?> show(
    BuildContext context, {
    required String dishName,
    bool isCookProduct = false,
    bool isComboProduct = false,
    bool isSuspended = false,
    bool isGift = false,
    bool isBag = false,
    bool isOrdered = false,
    bool isCut = false,
    bool showWeigh = false,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => DishOperationPopup(
        dishName: dishName,
        isCookProduct: isCookProduct,
        isComboProduct: isComboProduct,
        isSuspended: isSuspended,
        isGift: isGift,
        isBag: isBag,
        isOrdered: isOrdered,
        isCut: isCut,
        showWeigh: showWeigh,
        onOperation: (String type) {
          Navigator.of(context).pop(type);
        },
      ),
    );
  }

  /// 构建按钮列表（待下单调 buildPendingActions，已下单调 buildOrderedActions）
  List<DishOperation> _buildOperations() {
    if (isOrdered) {
      return buildOrderedOperations(
        isGift: isGift,
        isCut: isCut,
        showWeigh: showWeigh,
      );
    }

    final bool isFast = StoreModeUtils.isFastMode();

    final DishOperation gift = DishOperation(
      DishOperationType.gift,
      isGift ? '取消\n赠送' : '赠送',
      isCancel: isGift,
    );
    final DishOperation bag = DishOperation(
      DishOperationType.bag,
      isBag ? '取消\n打包' : '打包',
      isCancel: isBag,
    );
    final DishOperation cookOrCombo = isComboProduct
        ? const DishOperation(DishOperationType.combo, '套餐')
        : const DishOperation(DishOperationType.cook, '规格\n做法');

    final DishOperation discount = const DishOperation(DishOperationType.discount, '打折');
    final DishOperation changePrice = const DishOperation(DishOperationType.changePrice, '改价');
    final DishOperation remark = const DishOperation(DishOperationType.remark, '备注');
    final DishOperation del = const DishOperation(DishOperationType.delete, '删除');
    final DishOperation waiter = const DishOperation(DishOperationType.waiter, '服务员');
    final DishOperation rename = const DishOperation(DishOperationType.rename, '改名');
    final DishOperation suspend = DishOperation(
      DishOperationType.suspend,
      isSuspended ? '取消\n挂起' : '挂起',
      isCancel: isSuspended,
    );

    if (isFast) {
      // 快餐模式：无挂起
      return <DishOperation>[
        discount, changePrice, gift, bag, remark, waiter, cookOrCombo, rename, del,
      ];
    }
    return <DishOperation>[
      discount, gift, changePrice, suspend, bag, remark, del, waiter, cookOrCombo, rename,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final List<DishOperation> operations = _buildOperations();

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
  Widget _buildOperationButton(BuildContext context, DishOperation op, bool isDark) {
    // 取消态用品牌红描边+文字，便于一眼识别当前已生效的操作
    final Color fg = op.isCancel
        ? _kBrandRed
        : (isDark ? Colors.white : const Color(0xFF333333));
    return _buildRoundButton(context, op, isDark, fg);
  }

  Widget _buildRoundButton(
    BuildContext context,
    DishOperation op,
    bool isDark,
    Color fg,
  ) {
    return GestureDetector(
      onTap: () => onOperation(op.action),
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
              border: op.isCancel ? Border.all(color: _kBrandRed, width: 1) : null,
            ),
            child: Center(
              child: Text(
                op.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: op.label.contains('\n') ? 12 : 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 套餐明细操作弹窗（对齐 smdcapp SetMealOperationPopup：做法 / 修改）
class ComboSubOperationPopup extends StatelessWidget {
  const ComboSubOperationPopup({
    super.key,
    required this.title,
    required this.onOperation,
  });

  final String title;
  final ValueChanged<String> onOperation;

  static Future<String?> show(
    BuildContext context, {
    required String title,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => ComboSubOperationPopup(
        title: title,
        onOperation: (String type) => Navigator.of(context).pop(type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const List<DishOperation> ops = <DishOperation>[
      DishOperation(DishOperationType.comboSubCook, '做法'),
      DishOperation(DishOperationType.comboSubModify, '修改'),
    ];
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2D2E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
                      '订单操作--$title',
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
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.0,
                ),
                itemCount: ops.length,
                itemBuilder: (BuildContext context, int index) {
                  final DishOperation op = ops[index];
                  final Color fg =
                      isDark ? Colors.white : const Color(0xFF333333);
                  return GestureDetector(
                    onTap: () => onOperation(op.action),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? const Color(0xFF3A3C3D)
                                : const Color(0xFFF5F5F5),
                          ),
                          child: Center(
                            child: Text(
                              op.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
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
}
