import 'package:flutter/material.dart';

/// 商品标签(新/热/荐)
enum ProductTag {
  isNew('新', Color(0xFF00B42A)),
  isHot('热', Color(0xFFFF8547)),
  isRecommend('荐', Color(0xFFE63F31));

  const ProductTag(this.label, this.color);

  final String label;
  final Color color;
}

/// 规格选项
class SpecOption {
  const SpecOption({
    required this.name,
    this.extraPrice = 0,
    this.isRecommend = false,
  });

  final String name;

  /// 加价
  final double extraPrice;

  /// 是否推荐(右上角"推荐"角标)
  final bool isRecommend;

  String get priceSuffix => extraPrice > 0 ? ' ¥${extraPrice.toStringAsFixed(0)}' : '';
}

/// 规格组(规格/口味/做法)
class SpecGroup {
  const SpecGroup({required this.name, required this.options, this.defaultIndex = 0});

  final String name;
  final List<SpecOption> options;
  final int defaultIndex;
}

/// 商品
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.originalPrice,
    this.desc = '产品简介',
    this.emoji = '🍜',
    this.gradient = const <Color>[Color(0xFFFFF1F0), Color(0xFFFFE7E3)],
    this.tag,
    this.soldOut = false,
    this.specGroups = const <SpecGroup>[],
    this.mprice1 = 0,
    this.mprice2 = 0,
    this.mprice3 = 0,
    this.dscflag = 1,
  });

  final String id;
  final String name;
  final double price;
  final double? originalPrice;
  final String desc;

  /// 用emoji+渐变底色代替商品图
  final String emoji;
  final List<Color> gradient;

  final ProductTag? tag;

  /// 已售罄
  final bool soldOut;

  /// 规格组(非空时需要“选规格”)
  final List<SpecGroup> specGroups;

  /// 会员价1（对齐 smdcapp mprice1，prefetype=2时使用）
  final double mprice1;

  /// 会员价2（对齐 smdcapp mprice2，prefetype=3时使用）
  final double mprice2;

  /// 会员价3（对齐 smdcapp mprice3，prefetype=4时使用）
  final double mprice3;

  /// 是否可打折 1=可打折 0=不可打折（对齐 smdcapp dscflag）
  final int dscflag;

  bool get hasSpec => specGroups.isNotEmpty;
}

/// 商品分类
class ProductCategory {
  const ProductCategory({required this.id, required this.name, required this.products});

  final String id;
  final String name;
  final List<Product> products;
}

/// 套餐已选明细项快照（对齐 smdcapp ProductCombSet 选中态 → DetailListBean 核心字段）
///
/// 下单时按此生成套餐子行（combflag=0, combid=主行onlyid），
/// 而非拼接进主行 spec（smdcapp 主行 spec 为空，见 OrderModel.productToDetailBean）
class ComboSelectedItem {
  const ComboSelectedItem({
    required this.productid,
    required this.productname,
    required this.qty,
    this.combaddamt = 0,
    this.groupid = '',
    this.combsetproductid = '',
    this.specname = '',
    this.sellprice = 0,
    this.unit = '',
  });

  /// 子商品ID（对齐 combproductid 之外的明细商品 productid）
  final String productid;

  /// 子商品名称
  final String productname;

  /// 每份套餐内的实际数量（对齐 smdcapp combsetqty）
  final double qty;

  /// 每份套餐的加减价（对齐 smdcapp getSetMealInfo 明细 combaddamt，未乘套餐数量）
  final double combaddamt;

  /// 套餐分组ID（对齐 combgroupid）
  final String groupid;

  /// 套餐明细配置ID（对齐 combsetproductid）
  final String combsetproductid;

  /// 子商品规格名（对齐 smdcapp d.setSpec(specname)）
  final String specname;

  /// 子商品单价（对齐 smdcapp rrprice = combSet.price）
  final double sellprice;

  /// 单位
  final String unit;
}

/// 购物车条目
class CartItem {
  CartItem({
    required this.product,
    this.quantity = 1,
    this.specText = '',
    this.extraPrice = 0,
    this.weighNum = 0,
    this.combItems = const <ComboSelectedItem>[],
  });

  final Product product;
  int quantity;

  /// 称重菜重量（对齐 smdcapp weighNum），0=非称重商品
  /// 称重菜计价按 单价×重量，数量固定为1份
  double weighNum;

  /// 已选规格做法描述, 如 "中份、微辣、加肉"（做法修改时可更新）
  String specText;

  /// 套餐已选明细（仅套餐商品非空，对齐 smdcapp DetailListBean.itemList）
  /// 非 final：套餐修改操作需整体替换明细列表
  List<ComboSelectedItem> combItems;

  /// 是否套餐商品（对齐 smdcapp combflag==1）
  bool get isCombo => combItems.isNotEmpty;

  /// 规格做法加价合计(单份，做法修改时可更新)
  double extraPrice;

  // ---- 菜品操作状态（对齐 smdcapp ProductBean 操作字段）----

  /// 自定义名称（改名操作，对齐 smdcapp b.name 修改）
  String? customName;

  /// 折扣率 0~100，100=不打折（对齐 smdcapp singleDiscount）
  double discount = 100;

  /// 打折原因（对齐 smdcapp disRemark）
  String discountRemark = '';

  /// 是否赠送（对齐 smdcapp isGive）
  bool isGift = false;

  /// 赠送备注（对齐 smdcapp giveRemark）
  String giftRemark = '';

  /// 自定义价格，null=未改价（对齐 smdcapp cPrice / isChangePrice）
  double? customPrice;

  /// 是否挂起（对齐 smdcapp hangflag）
  bool isSuspended = false;

  /// 打包费，0=不打包（对齐 smdcapp bagPrice / isBag）
  double bagPrice = 0;

  /// 单品备注（对齐 smdcapp singleRemark）
  String remark = '';

  /// 服务员名称（对齐 smdcapp salesname）
  String waiterName = '';

  /// 会员优惠后单价（null=未录入会员，对齐 smdcapp getMemberPrice 计算结果）
  double? memberUnitPrice;

  /// 已下单商品的服务端行总额（对齐 smdcapp rramt），非 null 时 totalPrice 直接使用此值
  double? orderedAmt;

  /// 已退数量（对齐 smdcapp subqty，>0 时显示"退N"标记）
  double subqty = 0;

  /// 是否退菜记录（对齐 smdcapp presentflag==2）
  bool isRefunded = false;

  // ---- 临时菜字段（对齐 smdcapp DetailListBean tpdish*）----

  /// 临时菜标识（对齐 smdcapp tpdishflag，1=临时菜）
  int tpdishflag = 0;

  /// 临时菜是否可打折（对齐 smdcapp tpdscflag，1=可折）
  int tpdscflag = 0;

  /// 临时菜厨打方案1（对齐 smdcapp tpdishid，-1=不打印）
  String tpdishid = '';

  /// 临时菜厨打方案2（对齐 smdcapp tpdishidzd，-1=不打印）
  String tpdishidzd = '';

  // ---- 团券核销字段（对齐 smdcapp DetailListBean douyinflag/querytoken）----

  /// 团券菜标识（对齐 smdcapp douyinflag，1=团购核销菜）
  int douyinflag = 0;

  // ---- 必点菜字段（对齐 smdcapp DetailListBean mustflag/mustType）----

  /// 必点菜标识（对齐 smdcapp mustflag，1=必点菜）
  int mustflag = 0;

  /// 必点菜类型（对齐 smdcapp mustType，0=固定必点 1=可选必点）
  int mustType = 0;

  /// 是否必点菜
  bool get isMust => mustflag == 1;

  /// 团券商品绑定券的唯一ID（对齐 smdcapp querytoken，用于退团券）
  String querytoken = '';

  // ---- 临时菜上传补充字段（对齐 smdcapp DetailListBean unit/typeid/typename）----

  /// 单位（临时菜录入）
  String unit = '';

  /// 分类ID（临时菜录入）
  String typeid = '';

  /// 分类名称（临时菜录入）
  String typename = '';

  /// 显示名称（优先自定义名称）
  String get displayName => (customName != null && customName!.isNotEmpty)
      ? customName!
      : product.name;

  /// 是否称重商品（对齐 smdcapp weighflag==1 且 weighNum>0）
  bool get isWeigh => weighNum > 0;

  /// 计价数量（称重菜按重量计价，普通菜按数量计价，对齐 smdcapp 单价×重量逻辑）
  double get priceQty => isWeigh ? weighNum : quantity.toDouble();

  /// 单份实际价格（改价 > 会员价 > 原价+规格加价）
  double get unitPrice => customPrice ?? memberUnitPrice ?? (product.price + extraPrice);

  /// 折扣后单价
  double get discountedUnitPrice =>
      discount < 100 ? unitPrice * discount / 100 : unitPrice;

  /// 是否打折
  bool get isDiscounted => discount < 100 && discount > 0;

  /// 是否打包
  bool get isBag => bagPrice > 0;

  /// 总价（对齐 smdcapp ShoppingCartUtil：赠送商品不计入合计金额；称重菜按单价×重量）
  /// 已下单商品直接使用服务端 rramt（对齐 smdcapp PriceUtil.formatPrice(bean.rramt)）
  double get totalPrice => orderedAmt ?? (isGift ? 0 : discountedUnitPrice * priceQty);

  double get totalOriginalPrice => (product.originalPrice ?? product.price) * quantity;

  /// 唯一标识: 商品id + 规格组合
  String get uniqueKey => '${product.id}_$specText';
}

/// 模拟数据源(后续可替换为后端接口)
class OrderMockData {
  OrderMockData._();

  static const List<ProductCategory> categories = <ProductCategory>[
    ProductCategory(
      id: 'recommend',
      name: '店长推荐',
      products: <Product>[
        Product(
          id: 'p01',
          name: '土豆烧牛腩',
          price: 18.88,
          originalPrice: 28.80,
          desc: '精选牛腩慢炖两小时，软烂入味',
          emoji: '🥘',
          gradient: <Color>[Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
          tag: ProductTag.isRecommend,
          specGroups: <SpecGroup>[
            SpecGroup(name: '规格', defaultIndex: 1, options: <SpecOption>[
              SpecOption(name: '大份'),
              SpecOption(name: '中份'),
              SpecOption(name: '小份'),
            ]),
            SpecGroup(name: '口味', defaultIndex: 1, options: <SpecOption>[
              SpecOption(name: '微辣'),
              SpecOption(name: '中辣'),
              SpecOption(name: '特辣'),
            ]),
            SpecGroup(name: '做法', options: <SpecOption>[
              SpecOption(name: '默认'),
              SpecOption(name: '加肉', extraPrice: 3, isRecommend: true),
              SpecOption(name: '加咸菜', extraPrice: 1),
            ]),
          ],
        ),
        Product(
          id: 'p02',
          name: '红烧狮子头',
          price: 18.88,
          originalPrice: 25.00,
          desc: '肥瘦相间，入口即化',
          emoji: '🍖',
          gradient: <Color>[Color(0xFFFCE4EC), Color(0xFFF8BBD0)],
          tag: ProductTag.isHot,
          specGroups: <SpecGroup>[
            SpecGroup(name: '规格', options: <SpecOption>[
              SpecOption(name: '双丸'),
              SpecOption(name: '四丸'),
            ]),
            SpecGroup(name: '口味', options: <SpecOption>[
              SpecOption(name: '原味'),
              SpecOption(name: '蟹粉'),
            ]),
          ],
        ),
        Product(
          id: 'p03',
          name: '烧烤皮皮虾',
          price: 18.88,
          desc: '鲜活现烤，肉质弹嫩',
          emoji: '🦐',
          gradient: <Color>[Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
          tag: ProductTag.isNew,
        ),
        Product(
          id: 'p04',
          name: '旺仔牛奶复原乳',
          price: 18.88,
          originalPrice: 22.00,
          desc: '12盒/箱，童年味道',
          emoji: '🥛',
          gradient: <Color>[Color(0xFFFFFDE7), Color(0xFFFFF9C4)],
        ),
      ],
    ),
    ProductCategory(
      id: 'discount',
      name: '折扣专区',
      products: <Product>[
        Product(
          id: 'p05',
          name: '土豆烧牛腩',
          price: 18.88,
          originalPrice: 28.80,
          desc: '限时特惠，精选牛腩慢炖入味',
          emoji: '🥘',
          gradient: <Color>[Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
          tag: ProductTag.isRecommend,
          specGroups: <SpecGroup>[
            SpecGroup(name: '规格', defaultIndex: 1, options: <SpecOption>[
              SpecOption(name: '大份'),
              SpecOption(name: '中份'),
              SpecOption(name: '小份'),
            ]),
            SpecGroup(name: '口味', options: <SpecOption>[
              SpecOption(name: '微辣'),
              SpecOption(name: '中辣'),
              SpecOption(name: '特辣'),
            ]),
            SpecGroup(name: '做法', options: <SpecOption>[
              SpecOption(name: '默认'),
              SpecOption(name: '加肉', extraPrice: 3, isRecommend: true),
              SpecOption(name: '加咸菜', extraPrice: 1),
            ]),
          ],
        ),
        Product(
          id: 'p06',
          name: '红烧狮子头',
          price: 18.88,
          originalPrice: 26.00,
          desc: '折扣价，经典淮扬风味',
          emoji: '🍖',
          gradient: <Color>[Color(0xFFFCE4EC), Color(0xFFF8BBD0)],
          specGroups: <SpecGroup>[
            SpecGroup(name: '规格', options: <SpecOption>[
              SpecOption(name: '双丸'),
              SpecOption(name: '四丸'),
            ]),
          ],
        ),
        Product(
          id: 'p07',
          name: '烧烤皮皮虾',
          price: 18.88,
          originalPrice: 32.00,
          desc: '限时6折，鲜活现烤',
          emoji: '🦐',
          gradient: <Color>[Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
          tag: ProductTag.isHot,
        ),
        Product(
          id: 'p08',
          name: '红烧狮子头',
          price: 18.88,
          desc: '今日售罄，明日请早',
          emoji: '🍖',
          gradient: <Color>[Color(0xFFECEFF1), Color(0xFFCFD8DC)],
          soldOut: true,
        ),
      ],
    ),
    ProductCategory(
      id: 'snack',
      name: '美味小吃',
      products: <Product>[
        Product(
          id: 'p09',
          name: '香酥炸鸡翅',
          price: 12.80,
          originalPrice: 16.80,
          desc: '外酥里嫩，6只/份',
          emoji: '🍗',
          gradient: <Color>[Color(0xFFFFF8E1), Color(0xFFFFECB3)],
          tag: ProductTag.isHot,
        ),
        Product(
          id: 'p10',
          name: '黄金薯条',
          price: 9.90,
          desc: '现炸酥脆，配番茄酱',
          emoji: '🍟',
          gradient: <Color>[Color(0xFFFFFDE7), Color(0xFFFFF59D)],
        ),
        Product(
          id: 'p11',
          name: '凉拌黄瓜',
          price: 8.80,
          desc: '爽口开胃，蒜香四溢',
          emoji: '🥒',
          gradient: <Color>[Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
          tag: ProductTag.isNew,
        ),
        Product(
          id: 'p12',
          name: '盐酥鸡米花',
          price: 15.80,
          originalPrice: 19.90,
          desc: '台式风味，越吃越香',
          emoji: '🍿',
          gradient: <Color>[Color(0xFFFBE9E7), Color(0xFFFFCCBC)],
        ),
      ],
    ),
    ProductCategory(
      id: 'combo',
      name: '人气套餐',
      products: <Product>[
        Product(
          id: 'p13',
          name: '白领商务套餐',
          price: 30.00,
          originalPrice: 38.00,
          desc: '两荤一素一汤一饭',
          emoji: '🍱',
          gradient: <Color>[Color(0xFFE8EAF6), Color(0xFFC5CAE9)],
          tag: ProductTag.isHot,
          specGroups: <SpecGroup>[
            SpecGroup(name: '主食', options: <SpecOption>[
              SpecOption(name: '米饭'),
              SpecOption(name: '面条'),
            ]),
          ],
        ),
        Product(
          id: 'p14',
          name: '双人分享套餐',
          price: 58.00,
          originalPrice: 76.00,
          desc: '三荤两素两汤两饭',
          emoji: '🍲',
          gradient: <Color>[Color(0xFFEDE7F6), Color(0xFFD1C4E9)],
          tag: ProductTag.isRecommend,
        ),
        Product(
          id: 'p15',
          name: '家庭欢乐套餐',
          price: 98.00,
          originalPrice: 128.00,
          desc: '五荤四素四汤四饭',
          emoji: '🥡',
          gradient: <Color>[Color(0xFFE0F2F1), Color(0xFFB2DFDB)],
        ),
      ],
    ),
    ProductCategory(
      id: 'drink',
      name: '酒水饮料',
      products: <Product>[
        Product(
          id: 'p16',
          name: '旺仔牛奶复原乳',
          price: 18.88,
          originalPrice: 22.00,
          desc: '12盒/箱，童年味道',
          emoji: '🥛',
          gradient: <Color>[Color(0xFFFFFDE7), Color(0xFFFFF9C4)],
          tag: ProductTag.isHot,
        ),
        Product(
          id: 'p17',
          name: '冰镇酸梅汤',
          price: 6.80,
          desc: '古法熬制，冰爽解腻',
          emoji: '🧋',
          gradient: <Color>[Color(0xFFEFEBE9), Color(0xFFD7CCC8)],
        ),
        Product(
          id: 'p18',
          name: '鲜榨橙汁',
          price: 12.00,
          originalPrice: 15.00,
          desc: '5个鲜橙现榨',
          emoji: '🍊',
          gradient: <Color>[Color(0xFFFFF3E0), Color(0xFFFFCC80)],
          tag: ProductTag.isNew,
        ),
        Product(
          id: 'p19',
          name: '青岛啤酒',
          price: 8.00,
          desc: '500ml/瓶，冰镇',
          emoji: '🍺',
          gradient: <Color>[Color(0xFFFFF8E1), Color(0xFFFFE082)],
        ),
      ],
    ),
  ];
}
