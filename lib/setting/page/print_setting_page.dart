import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/res/constant_print_key.dart';
import 'package:flutter_deer/res/resources.dart';
import 'package:flutter_deer/util/print_service.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/click_item.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:sp_util/sp_util.dart';

/// 打印设置页（对齐 smdcapp PrintSetActivity.java）
///
/// 功能：
/// - 选择打印类型（PC打印/云打印/蓝牙打印/接口打印）
/// - 设置打印纸规格（58mm/80mm）
/// - 设置票尾走纸行数
/// - 云打印机管理入口
class PrintSettingPage extends StatefulWidget {
  const PrintSettingPage({super.key});

  @override
  State<PrintSettingPage> createState() => _PrintSettingPageState();
}

class _PrintSettingPageState extends State<PrintSettingPage> {
  late String _printerType;
  late String _printSize;
  late int _feedLineCount;

  @override
  void initState() {
    super.initState();
    _printerType = PrintService.instance.printerType;
    _printSize = SpUtil.getString(ConstantPrintKey.printSizeJz) ?? '58mm';
    _feedLineCount = SpUtil.getInt(ConstantPrintKey.ticketFeedLine) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '打印设置'),
      body: ListView(
        children: [
          Gaps.vGap5,
          // 打印类型选择
          ClickItem(
            title: '打印方式',
            content: _printerType,
            onTap: _showPrinterTypePicker,
          ),
          // 打印设置入口（根据类型显示不同内容）
          ClickItem(
            title: '打印设备',
            content: _getDeviceDesc(),
            onTap: _onPrintDeviceTap,
          ),
          Gaps.vGap15,
          // 纸规格选择（仅蓝牙/接口打印显示）
          if (_printerType == '蓝牙打印' || _printerType == '接口打印') ...[
            _buildSizeSection(),
            Gaps.vGap15,
          ],
          // 票尾走纸行数
          _buildFeedLineSection(),
          Gaps.vGap15,
          // 云打印管理入口
          if (_printerType == '云打印')
            ClickItem(
              title: '云打印机管理',
              content: PrintService.instance.yunPrintName.isNotEmpty
                  ? PrintService.instance.yunPrintName
                  : '未选择',
              onTap: _showCloudPrinterManage,
            ),
        ],
      ),
    );
  }

  /// 打印纸规格选择区域
  Widget _buildSizeSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text('打印规格', style: TextStyle(fontSize: 14, color: Colors.black87)),
          const Spacer(),
          _buildSizeRadio('58mm'),
          Gaps.hGap15,
          _buildSizeRadio('80mm'),
        ],
      ),
    );
  }

  Widget _buildSizeRadio(String size) {
    final bool selected = _printSize == size;
    return GestureDetector(
      onTap: () => _onSizeChanged(size),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: selected ? Theme.of(context).primaryColor : Colors.grey,
          ),
          Gaps.hGap5,
          Text(size, style: TextStyle(fontSize: 14, color: selected ? Colors.black87 : Colors.grey)),
        ],
      ),
    );
  }

  /// 票尾走纸行数区域
  Widget _buildFeedLineSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text('票尾走纸行数', style: TextStyle(fontSize: 14, color: Colors.black87)),
          const Spacer(),
          GestureDetector(
            onTap: _feedLineCount > 0 ? () => _updateFeedLine(_feedLineCount - 1) : null,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.remove, size: 18, color: Colors.black54),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('$_feedLineCount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: _feedLineCount < 30 ? () => _updateFeedLine(_feedLineCount + 1) : null,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.add, size: 18, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 事件处理 ─────────────────────────────────────────

  /// 打印类型选择弹窗（对齐 smdcapp PrintSetActivity.clickPrintType）
  void _showPrinterTypePicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const Text('选择打印方式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
              const Divider(height: 1),
              ...ConstantPrintKey.printerTypeOptions.map((type) {
                return ListTile(
                  title: Text(type),
                  trailing: _printerType == type
                      ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _onPrinterTypeChanged(type);
                  },
                );
              }),
              Gaps.vGap10,
            ],
          ),
        );
      },
    );
  }

  /// 更换打印方式（对齐 smdcapp PrintSetActivity 确认更换逻辑）
  void _onPrinterTypeChanged(String type) {
    if (type == _printerType) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('消息提示'),
        content: const Text('确认更换打印方式吗?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _printerType = type);
              PrintService.instance.setPrinterType(type);
              // 清除蓝牙地址（对齐 smdcapp 切换时清除）
              SpUtil.putString(ConstantPrintKey.bluetoothAddr, '');
              SpUtil.putString(ConstantPrintKey.bluetoothName, '');
              Toast.show('已切换为$type');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 纸规格变更（对齐 smdcapp PrintSetActivity rb58/rb80 逻辑）
  void _onSizeChanged(String size) {
    setState(() => _printSize = size);
    // 对齐 smdcapp: 切换规格时同步设置结账/客单/厨打的 size 和 style
    final int style = size == '58mm' ? 0 : 1;
    SpUtil.putString(ConstantPrintKey.printSizeJz, size);
    SpUtil.putInt(ConstantPrintKey.printStyleJz, style);
    SpUtil.putString(ConstantPrintKey.printSizeKd, size);
    SpUtil.putInt(ConstantPrintKey.printStyleKd, style);
    SpUtil.putString(ConstantPrintKey.printSizeCd, size);
    SpUtil.putInt(ConstantPrintKey.printStyleCd, style);
  }

  /// 走纸行数更新
  void _updateFeedLine(int value) {
    setState(() => _feedLineCount = value);
    SpUtil.putInt(ConstantPrintKey.ticketFeedLine, value);
  }

  /// 打印设备点击
  void _onPrintDeviceTap() {
    if (_printerType == '云打印') {
      _showCloudPrinterManage();
    } else if (_printerType == 'PC打印') {
      Toast.show('PC打印由主设备自动管理');
    } else {
      Toast.show('暂仅支持PC打印和云打印');
    }
  }

  /// 云打印机管理弹窗（对齐 smdcapp YunPrintSetActivity）
  Future<void> _showCloudPrinterManage() async {
    Toast.show('正在获取云打印机列表...');
    final list = await PrintService.instance.getCloudPrinterList();
    if (!mounted) return;
    if (list.isEmpty) {
      Toast.show('暂无可用云打印机');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const Text('选择云打印机', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
              const Divider(height: 1),
              ...list.map((item) {
                final Map<String, dynamic> printer = item is Map<String, dynamic> ? item : {};
                final String name = printer['name']?.toString() ?? '未知打印机';
                final String id = printer['id']?.toString() ?? '';
                final bool isSelected = PrintService.instance.yunPrintName == name;
                return ListTile(
                  title: Text(name),
                  subtitle: Text('ID: $id'),
                  trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectCloudPrinter(printer);
                  },
                );
              }),
              Gaps.vGap10,
            ],
          ),
        );
      },
    );
  }

  /// 选中云打印机（对齐 smdcapp 保存选中云打印机信息）
  void _selectCloudPrinter(Map<String, dynamic> printer) {
    SpUtil.putString(ConstantPrintKey.yunPrintInfo, json.encode(printer));
    Toast.show('已选择: ${printer['name'] ?? ''}');
    setState(() {});
  }

  /// 获取设备描述文字
  String _getDeviceDesc() {
    switch (_printerType) {
      case 'PC打印':
        return '由主设备管理';
      case '云打印':
        final name = PrintService.instance.yunPrintName;
        return name.isNotEmpty ? name : '未配置';
      case '蓝牙打印':
        final name = SpUtil.getString(ConstantPrintKey.bluetoothName) ?? '';
        final addr = SpUtil.getString(ConstantPrintKey.bluetoothAddr) ?? '';
        return name.isNotEmpty ? name : (addr.isNotEmpty ? addr : '未连接');
      case '接口打印':
        return '内置打印机';
      default:
        return '';
    }
  }
}
