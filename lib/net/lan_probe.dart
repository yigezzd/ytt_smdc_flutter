import 'dart:io';

/// 判断 [host] 是否可能与本机处于同一局域网。
///
/// 移动数据下本机网卡都不在主设备的私网网段，主设备探活必然失败，
/// 调用方可据此跳过探活，避免白等连接超时。
/// - [host] 不是 IPv4 字面量（域名/IPv6）或读取网卡失败时返回 true，
///   保持原探活行为，避免误判。
Future<bool> isHostInLocalSubnet(String host) async {
  final InternetAddress? target = InternetAddress.tryParse(host);
  if (target == null || target.type != InternetAddressType.IPv4) {
    return true;
  }
  try {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final NetworkInterface interface in interfaces) {
      for (final InternetAddress address in interface.addresses) {
        if (_isSameLan(address.rawAddress, target.rawAddress)) {
          return true;
        }
      }
    }
  } catch (_) {
    return true;
  }
  return false;
}

bool _isSameLan(List<int> local, List<int> target) {
  if (local.length != 4 || target.length != 4) {
    return false;
  }
  // Android 模拟器经 QEMU(10.0.2.x)/Genymotion(10.0.3.x) NAT 出网，可直连宿主机
  // 局域网内的主设备；自身网段虽与主设备不同但实际可达，按可达处理避免误跳过探活。
  if (local[0] == 10 && local[1] == 0 && (local[2] == 2 || local[2] == 3)) {
    return true;
  }
  // 门店内网多为 192.168.x.0/24 或 10.x/172.16-31.x 的 /16，按此粒度判断
  if (local[0] == 192 && local[1] == 168) {
    return target[0] == 192 && target[1] == 168 && target[2] == local[2];
  }
  return local[0] == target[0] && local[1] == target[1];
}
