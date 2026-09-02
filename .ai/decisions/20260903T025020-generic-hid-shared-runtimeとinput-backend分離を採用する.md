# Generic HID shared runtimeとinput backend分離を採用する

Date: 2026-09-03
Status: accepted

Supersedes the Generic HID runtime exclusive-open portions of Decisions
`20260902T234000-generic-hid-learnとruntimeをadapter-sidecarで実装する`,
`20260903T001500-generic-hid-native-event-suppression`, and
`20260903T012500-generic-hid-shortcuts-single-mapping-surface`.

## Context

登録済みSIDE-KEYBOARDのnative入力はshared IOHID observerで取得・抑止できる一方、Action runtimeには同じraw eventが届かない実機症状を確認した。

Action runtimeは`IOHIDManagerOpen(...SeizeDevice)`を先に実行し、`kIOReturnNotPrivileged`のときだけsharedへfallbackしていた。しかし対象keyboard-class interfaceがmanager open後にmatchする場合、manager open自体はsuccessとなり、遅れて発生するexclusive claim failureを検出できない。この状態ではdevice matchだけが発生しinput value callbackが届かなかった。

またACK05 CLIのexclusive open失敗・終了時に、正常なGeneric HID runtime / native suppressorまで停止していた。終了済みGUIが子`overcue-cli`を残した場合、孤児CLIがACK05を保持して新GUIのACK05 openを失敗させ、このall-or-nothing停止がGeneric HIDも使用不能にした。

## Decision

- 登録済みGeneric HIDのAction runtimeは最初からshared IOHIDで監視する。native macOS入力の抑止責務は登録deviceだけを相関する`GenericHIDNativeEventSuppressor`へ一本化する。
- Shortcuts Learnは同じshared runtimeをcapture modeへ切り替えて利用し、別managerへのownership handoffを作らない。
- ACK05 CLIとGeneric HID runtimeは独立backendとして扱う。一方の起動失敗・終了で他方を停止しない。片方だけ動作中ならUIはdegraded statusを表示する。
- アプリが起動した`overcue-cli`へparent PIDを渡し、親GUI消失時はCLI自身が終了する。terminalから直接起動するCLIにはparent監視を強制しない。
- Devices Identify / Rebind中のruntime停止は一時停止とし、controller inputのUserDefaultsをOFFへ永続化しない。

## Consequences

- keyboard-class composite HIDでも遅延match時のexclusive claim結果に依存せず、3 interfaceすべてのraw inputをAction Layerへ渡せる。
- ACK05だけが使用不能でも登録Generic HIDは動作し、その逆も維持できる。
- 未登録Generic HIDは従来どおりraw相関・抑止・Action変換の対象外で、通常キーボードを巻き込まない。
- root / privileged helperは不要なまま維持する。

## Evidence

- Serial `3F8701678182`の3 interfaceをshared runtimeで同一sessionへ束ねた。
- Key2 `0x5A`→`rekordbox:300b`→`F`、Key3 `0x5B`→`rekordbox:300a`→`D`、Consumer `0xE9`→`rekordbox:305b`→`shift+E`の解決と、rekordbox最前面時のCGEvent送信を実機ログで確認した。
- 接続中の別SIDE-KEYBOARDはSerial `592B14678182`で、登録済み個体と異なるpersistent identityを持つことをIORegistryで確認した。現行configにbindingがないため、その個体がfail-openするのは意図した安全動作である。
