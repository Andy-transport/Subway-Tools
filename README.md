# Beijing subway motion（地铁配线图 iOS 应用）

北京市轨道交通线路配置图，做成 iPhone 应用。中文名：地铁交路；英文名：Beijing subway motion。

- 地图来源：[SierraQin/metro](https://github.com/SierraQin/metro)（CC0 1.0 协议），正式版 2.8.0（2026-07-14）
- 应用：一个 WKWebView 壳，里面是完全离线的地图网页——地图 SVG、PDF 和 JS 库都打在包里，不用联网、不用 VPN
- 功能：整张配线图，捏合缩放、拖动；液态玻璃底栏（线路图 / 车站 / 更多）；车站搜索（中文、拼音、首字母，点车站定位到图上，420 个车站，来自地图 SVG 本身）；横竖屏都全覆盖显示；底栏可点可左右滑动切换

## 打包

GitHub Actions（macOS）跑 `bash build.sh`：先把离线网页拼出来，再用 `swiftc` 编译 Swift 壳（不签名），打包成未签名的 IPA，侧载安装时用自己的 Apple ID 重新签名。

## 说明

原作者在 README 里注明：本图由互联网公开资料结合作者乘车经历整理推测而成，不保证内容真实性和准确性；仅表示线路和车站之间的逻辑关系，并非按真实比例绘制，不应被作为规划出行的依据。
