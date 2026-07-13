---
layout: default
title: OverCUE for macOS | 设置与使用
lang: zh-Hans
description: 安装 macOS 版 OverCUE、授予权限、设置 ACK05 映射并控制 rekordbox。
locale: zh_CN
canonical_url: https://albasimia.github.io/OverCUE/zh-hans/macos/
og_image: https://albasimia.github.io/OverCUE/assets/ogp/zh-CN.png?v=20260713-3
og_image_alt: macOS 版 OverCUE 设置画面
---

<nav class="language-nav"><a href="../../macos/">日本語</a> ・ <a href="../../en/macos/">English</a> ・ 简体中文</nav>
<nav class="platform-nav"><a href="../">概要</a><span>・</span><strong>macOS</strong><span>・</span><a href="../windows/">Windows</a></nav>

# OverCUE for macOS

<p class="hero-lede">将 ACK05 的旋钮和十个按键映射到 rekordbox 的 Cue、Hot Cue、Jump、Quantize 和波形操作。通用版本同时支持 Apple Silicon 与 Intel Mac。</p>

![macOS 版 OverCUE 设置画面](../../assets/images/overcue-macos-zh-Hans.png)

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 操作系统 | macOS 13 Ventura 或更高版本 |
| Mac | Apple Silicon／Intel |
| 设备 | XPPen ACK05 Wireless Shortcut Remote |
| DJ 软件 | rekordbox 7 |

## 下载与首次启动

1. 从 [GitHub Releases](https://github.com/albasimia/OverCUE/releases/latest) 下载 `OverCUE-vX.Y.Z-macos-universal.zip`。
2. 解压并将 `OverCUE.app` 移到“应用程序”。
3. 打开一次 OverCUE，使 macOS 显示警告。
4. 打开“系统设置”→“隐私与安全性”，为 OverCUE 选择“仍要打开”。
5. 在确认窗口中再次选择“打开”。

<div class="notice">macOS 版尚未使用 Developer ID 签名，也未经过 Apple 公证。无需全局关闭 Gatekeeper，也无需通过 <code>xattr</code> 删除隔离属性。</div>

## 必要权限

请在“隐私与安全性”中允许以下项目，之后退出并重新打开 OverCUE：

- 输入监控：接收 ACK05 的按键与旋钮输入
- 辅助功能：向 rekordbox 发送键盘与鼠标操作

如果 XPPenPenTablet 抢先接收 ACK05 输入，请将其退出。

## 基本使用方法

1. 启动 rekordbox。
2. 连接 ACK05 并启动 OverCUE。
3. 选择分组及 EXPORT／PERFORMANCE 模式。
4. 如需拖动波形，将指针放到 rekordbox 的放大波形上，按 `K8+K1` 保存位置。
5. 将 rekordbox 切换到前台后操作 ACK05。

键盘与鼠标输出仅在 rekordbox 位于前台时有效。关闭窗口后，OverCUE 仍可在菜单栏中运行。

如果找不到所选快捷键文件，OverCUE 会回退到 `Performance 1 (Preset)` 或 `Export (Preset)`。当目标功能没有快捷键时，不会进行推测发送。

## 分组与模式

| 分组 | 初始模式 | 目标 |
| --- | --- | --- |
| 1 | PERFORMANCE | Deck 1 |
| 2 | PERFORMANCE | Deck 2 |
| 3 | EXPORT | Deck 1 |
| 4 | EXPORT | 用户设置 |

## 默认按键映射

| 输入 | 操作 |
| --- | --- |
| K1／K4／K8 | Hot Cue C／B／A |
| K2／K5 | 删除／设置 Memory Cue |
| K3／K6 | 向前／向后 Jump，长按加速 |
| K7 | Quantize 开／关 |
| K9／K10 | Cue／Play・Pause |
| 旋钮左／右 | Jog Search 左／右 |
| K8+K1 | 保存波形位置 |
| K7+K8／K4／K1 | 删除 Hot Cue A／B／C |
| K7+K3／K6 | 下一个／上一个 Memory Cue |
| K7+K2／K5 | 下一个／上一个分组 |
| K7+旋钮左／右 | Pitch Bend −／＋ |

## 编辑映射

已分配的 rekordbox 快捷键按可折叠类别显示。可以按功能名称、按键或 commandId 搜索，点击编辑后输入 ACK05 操作。设备图与列表会互相高亮，设备方向也可按 90 度保存。

## 语言与配置文件

窗口和菜单栏支持日本語、English、简体中文。请从 OverCUE → 设置中选择语言。

```text
~/Library/Application Support/OverCUE/config.json
```

## 故障排除

- 没有 ACK05 输入：检查输入监控权限，退出 XPPenPenTablet，重新连接 ACK05。
- rekordbox 无响应：将 rekordbox 置于前台，检查分组和模式，确认辅助功能权限，并在修改设置后点击“重新加载”。

## 隐私与安全

OverCUE 不包含遥测、广告、账户功能或自动上传。设置与界面状态仅保存在 Mac 内。

[返回概要](../) ・ [Windows 使用指南](../windows/)
