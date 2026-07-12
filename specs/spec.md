OverCUE 仕様書 v0.1

1. プロジェクト概要

OverCUE は、XPPen ACK05などの小型ショートカットリモコンを、DJソフト向けのCUE打ち補助コントローラーとして利用するためのブリッジアプリである。

日本語での読み・愛称は オバキュー。

主目的は、rekordboxでのCUE打ち作業において、MacBookのトラックパッドやキーボードだけでは負担が大きい「曲内の移動・位置合わせ」を、物理ダイヤル操作に置き換えること。

OverCUEはDJ演奏用コントローラーではなく、仕込み作業、特にCUE打ちに特化した補助入力システムとして設計する。

⸻

2. 背景と課題

rekordboxでCUEを打つ作業では、CUEボタンそのものよりも、CUEを打つべき位置まで曲内を移動する操作が負担になりやすい。

特にMacBook単体運用では、トラックパッドによる押し込みドラッグや細かい波形操作が疲れやすい。

一方で、CUE打ち専用の小型・安価・可搬・無線対応デバイスは一般流通ではほぼ存在しない。

そこで、安価で入手性が高く、無線接続と物理ダイヤルを備える XPPen ACK05 を標準ターゲットデバイスとして採用し、OverCUEによってDJソフト向けの疑似ジョグ入力へ変換する。

⸻

3. 正式名称

* プロジェクト名: OverCUE
* 読み / 愛称: オバキュー
* アプリ名候補: OverCUE Bridge
* CLI / 内部名候補: overcue

⸻

4. 標準ターゲットデバイス

4.1 採用デバイス

* XPPen ACK05 Wireless Shortcut Remote

4.2 採用理由

ACK05は以下の理由から、OverCUEの標準デバイスとして採用する。

* 価格が比較的安い
* 入手性が高い
* 無線接続できる
* 可搬性が高い
* 10個のキーを持つ
* 24デテントの滑らかなダイヤルを持つ
* ダイヤル入力がCUE打ち用途に向いている
* 多くのDJが手軽に入手できる
* 中華マクロパッド系に比べ、仕様変更・生産中止リスクが比較的低い
* CUE打ち専用デバイスの空白を埋める実験機材として適している

4.3 破棄した案

Joy-ConをDJソフト向けコントローラー化する案は破棄する。

理由:

* Bluetooth接続や再接続の安定性に懸念がある
* ゲームコントローラー文脈が強く、DJ向け説明コストが高い
* 他のDJへ展開しにくい
* スティック入力はジョグ/ダイヤル操作の身体感覚と異なる
* OverCUEの標準デバイスとしてはACK05の方が現実的

⸻

5. 対応OS

OverCUEは以下の両対応を目指す。

* macOS
* Windows

5.1 macOS

macOSでは、ACK05が以下のHIDデバイスとして認識されることを確認済み。

* Product: Shortcut Remote
* Manufacturer: HANWUGEE
* Vendor ID: 10429 / 0x28BD
* Product ID: 514 / 0x0202

5.2 Windows

Windows対応も初期仕様に含める。

ただし、MVP段階ではmacOSでの検証を優先してよい。
設計上はWindowsでもHID入力取得と仮想MIDI出力に差し替え可能な構造にする。

⸻

6. ACK05実機検証メモ

6.1 XPPenPenTabletとの関係

XPPenPenTabletが起動している場合、ACK05の入力はXPPen側に横取り・加工され、Karabiner-EventViewerでは入力を取得できない。

XPPenPenTabletを終了すると、ACK05の入力はHIDキーイベントとして取得できる。

したがって、OverCUE MVPでは以下の方針とする。

* XPPenPenTabletには依存しない
* XPPenPenTabletは終了した状態を前提にする
* OverCUE側でACK05入力を取得・解釈する

6.2 ドライバフリー時の公式デフォルトマッピング

ACK05のドライバフリー時のキー割り当ては以下。

K1  = Ctrl + O
K2  = Ctrl + N
K3  = F5
K4  = Shift
K5  = Ctrl
K6  = Alt
K7  = Ctrl + S
K8  = Ctrl + Z
K9  = Space
K10 = Ctrl + Shift + Z

これらはrekordboxやOS操作と競合する可能性があるため、OverCUE起動中は原則としてOverCUE側で吸収・変換し、生キー入力をDJソフトへ漏らさない設計を目指す。

6.3 ダイヤル入力

Karabiner-EventViewerにて、ACK05のダイヤル入力は以下として確認済み。

左回転

keypad_hyphen + left_control

イベント例:

[
  {
    "type": "down",
    "name": {"key_code": "keypad_hyphen"},
    "usagePage": "7 (0x0007)",
    "usage": "86 (0x0056)"
  },
  {
    "type": "down",
    "name": {"key_code": "left_control"},
    "usagePage": "7 (0x0007)",
    "usage": "224 (0x00e0)"
  },
  {
    "type": "up",
    "name": {"key_code": "keypad_hyphen"},
    "usagePage": "7 (0x0007)",
    "usage": "86 (0x0056)"
  },
  {
    "type": "up",
    "name": {"key_code": "left_control"},
    "usagePage": "7 (0x0007)",
    "usage": "224 (0x00e0)"
  }
]

右回転

keypad_plus + left_control

イベント例:

[
  {
    "type": "down",
    "name": {"key_code": "keypad_plus"},
    "usagePage": "7 (0x0007)",
    "usage": "87 (0x0057)"
  },
  {
    "type": "down",
    "name": {"key_code": "left_control"},
    "usagePage": "7 (0x0007)",
    "usage": "224 (0x00e0)"
  },
  {
    "type": "up",
    "name": {"key_code": "keypad_plus"},
    "usagePage": "7 (0x0007)",
    "usage": "87 (0x0057)"
  },
  {
    "type": "up",
    "name": {"key_code": "left_control"},
    "usagePage": "7 (0x0007)",
    "usage": "224 (0x00e0)"
  }
]

連続回転時も同じ値として安定入力される。

6.4 中央ボタン

ACK05のダイヤル中央ボタンは、ドライバフリー状態ではOS入力として取得できない。

そのため、当初想定していた「中央ボタンによるJogScratch / JogPitchBend切り替え」はMVPでは採用しない。

代替として、K1〜K10のいずれかをモード切り替えキーとして使う。

6.5 HID生レポート検証結果

2026年7月11日、macOS上でIOHIDManagerを使用し、Bluetooth Low Energy接続したACK05の入力レポートを取得できることを確認した。

検出情報:

* Product: Shortcut Remote
* Manufacturer: HANWUGEE
* Vendor ID: 0x28BD
* Product ID: 0x0202
* Transport: Bluetooth Low Energy
* Primary Usage Page: 0x0001
* Primary Usage: 0x0002
* Input Report ID: 0x06
* Input Report Length: 8 bytes

各操作の押下時レポートは以下。

```text
Dial CW  = 06 01 57 00 00 00 00 00
Dial CCW = 06 01 56 00 00 00 00 00

K1  = 06 01 12 00 00 00 00 00  # Ctrl + O
K2  = 06 01 11 00 00 00 00 00  # Ctrl + N
K3  = 06 00 3E 00 00 00 00 00  # F5
K4  = 06 02 00 00 00 00 00 00  # Left Shift
K5  = 06 01 00 00 00 00 00 00  # Left Control
K6  = 06 04 00 00 00 00 00 00  # Left Alt / Option
K7  = 06 01 16 00 00 00 00 00  # Ctrl + S
K8  = 06 01 1D 00 00 00 00 00  # Ctrl + Z
K9  = 06 00 2C 00 00 00 00 00  # Space
K10 = 06 03 1D 00 00 00 00 00  # Ctrl + Shift + Z
```

すべての操作で、解放時レポートは以下。

```text
06 00 00 00 00 00 00 00
```

ダイヤル左右を複数デテント連続して操作した場合も、各デテントで同じ押下・解放レポートが繰り返されることを確認した。

IOHIDManagerの排他オープンでもACK05を正常に検出できた。これにより、ACK05の生入力をOverCUEで取得しながら、同デバイスのデフォルトキー入力をmacOSや他アプリへ流さない実装が可能と判断する。

⸻

7. OverCUEの基本構造

OverCUEは以下の変換ブリッジとして動作する。

ACK05
↓
HID入力
↓
OverCUE
↓
DJソフト向けMIDI / ショートカット / 将来拡張用出力
↓
rekordboxなどのDJソフト

rekordbox向けには、DDJ-SX系のジョグ入力を参考に、JogTouch / JogScratch / JogPitchBend相当のMIDI入力を送出することを目指す。

⸻

8. rekordbox対応方針

8.1 対応モード

rekordboxについては、以下の両モードでの利用可能性を検証する。

* Performance mode
* Export mode

MVPではPerformance modeを優先する。

理由:

* MIDI Learnや外部コントローラー入力はPerformance mode前提の可能性が高い
* Performance modeでもCUE打ちはショートカットで可能
* ジョグ入力偽装もPerformance modeの方が成立可能性が高い

8.2 モード判定

可能であれば、OverCUE側でrekordboxの現在モードを判定する。

判定対象:

* Performance mode
* Export mode

実装候補:

* アクティブウィンドウタイトル
* UI要素検出
* rekordboxプロセス状態
* 設定による手動切り替え

MVPでは自動判定が難しい場合、手動モード選択でもよい。

8.3 Freeプラン対応

rekordbox Freeプランでは、Hardware Unlock対象機器を接続していない状態で、汎用MIDI/HID機器からPERFORMANCEモードを操作できない。

一方、コンピューター上のマウス・キーボードによるPERFORMANCEモード操作はFreeプランでも利用できるため、OverCUEはMIDIを使用しないマウス出力モードを提供する。

マウス出力モード:

1. ACK05をIOHIDManagerで排他的に取得する
2. CoreMIDI仮想ソースは作成しない
3. ユーザーがrekordboxの拡大波形上へポインターを置く
4. K8を押しながらK1を押して波形操作位置を記録する
5. ダイヤル回転中、記録位置から水平方向のマウスドラッグを生成する
6. 最終回転から150ms無入力でマウスボタンを解放する
7. 操作終了後、ポインターを操作前の位置へ戻す

初期値:

* 低速回転時は1デテントあたり1ピクセル
* 高速回転時は最大20ピクセル
* 右回転で波形を左へドラッグ
* 左回転で波形を右へドラッグ
* ドラッグ解放タイムアウト150ms

回転速度による加速:

* 各デテントの入力間隔を単調時計で計測する
* 入力間隔200ms以上では1ピクセルの微調整とする
* 入力間隔35ms以下では最大10ピクセルとする
* 35ms〜200msの間は4次カーブで補間し、中低速域の変化を緩やかにする
* 現在の入力間隔を35%、直前の平滑値を65%として速度を平滑化する
* 最初の高速入力は200msを基準とした平滑値から開始し、複数デテントかけて加速する
* 回転方向を反転した最初のデテントは加速をリセットして1ピクセルとする
* 150ms無入力でドラッグを終了し、次の回転は再び1ピクセルから開始する

コマンドラインオプションにより、低速時の移動ピクセル数、最大移動ピクセル数、加速の無効化、方向反転、解放タイムアウトを調整可能にする。小数ピクセルも指定可能とし、Retinaディスプレイでの細かな位置合わせに対応する。

この方式はrekordboxのHardware Unlock認証を偽装せず、Freeプランで許可されているコンピューター操作経路を使用する。ただし、rekordboxの画面レイアウトやウィンドウ位置へ依存するため、MIDI方式よりも環境変化に弱い。

8.4 ACK05標準キーマッピング

ACK05を縦向きで使用し、以下を標準配置とする。

```text
K1  Hot Cue C
K2  Delete Memory Cue
K3  Jump Forward（長押しで連続、押下時間に応じて加速）
K4  Hot Cue B
K5  Set Memory Cue
K6  Jump Backward（長押しで連続、押下時間に応じて加速）
K7  Quantize ON/OFF（解放時に実行、長押し中は独自修飾キー）
K8  Hot Cue A
K9  Cue（長押し中のみ再生し、解放時にCUE位置へ戻る）
K10 Play/Pause

K8 + K1  波形操作位置を記録
K7 + K8  Hot Cue Aを削除
K7 + K4  Hot Cue Bを削除
K7 + K1  Hot Cue Cを削除
K7 + K3  次のMemory Cueを呼び出す
K7 + K6  前のMemory Cueを呼び出す
```

OverCUEは起動時にrekordboxのKeyMappings XMLを読み、各操作のcommandIdから現在のショートカットを解決する。ExportとPerformanceは割り当てが異なるため、起動オプションで対象モードを指定する。初期値はCUE仕込みを優先してExportとする。

K8はK1とのコード判定を行うため、単体操作をキー解放時に送信する。K8を保持した状態でK1を検出した場合、K8とK1の単体操作を抑止して波形位置登録のみを行う。

K9のCueはタップではなく保持型として扱う。K9押下時にrekordboxのCueショートカットをkeydownし、K9解放時にkeyupすることで、Cue Point Samplerと同じ「押している間だけ再生し、離すとCUE位置へ戻る」操作を実現する。

K7は独自の修飾キーを兼ねるため、単体のQuantize操作をキー解放時に送信する。K7を保持した状態でK8、K4、K1を押すと、それぞれHot Cue A、B、Cの削除ショートカットを送信し、K7のQuantize操作と各キーの通常Hot Cue操作を抑止する。K7を保持したまま複数のHot Cueを続けて削除できる。

K3とK6は押下時に1回ジャンプする。400ms以上保持すると連続ジャンプを開始し、約2秒かけて送信間隔を180msから35msまで滑らかに短縮する。解放時は直ちに連続送信を停止する。

対象操作がrekordbox側で未割り当ての場合、OverCUEは代替キーを推測せずログへ警告する。Performance 1プリセットではQuantizeが未割り当てのため、rekordbox側で一度ショートカットを設定する必要がある。

8.5 外部設定ファイル

マウスモードの初回起動時に `~/Library/Application Support/OverCUE/config.json` を生成する。設定はJSON形式とし、複数のプロファイル、デフォルトプロファイル名、デバイスIDとプロファイルの対応を保持する。各プロファイルは波形操作位置、ACK05各キーの操作割り当て、コード操作の割り当てを持つ。`--config` により任意の設定ファイルを指定可能とする。

K8+K1などCapture Waveform Positionを割り当てたコードで取得した座標は、取得直後に設定ファイルへアトミック保存する。次回起動時は保存済み座標を復元し、再登録せずダイヤル操作を開始可能とする。キーマップとコードマップの編集内容は次回起動時に読み込む。不明なキー名、操作名、設定バージョンは黙って無視せず起動エラーとして通知する。

コードはK1〜K10から異なる2キーを任意に選択可能とする。`K5+K1`のように先頭キーを修飾キー、後続キーをトリガーとして扱い、修飾キーを先に保持してからトリガーを押す。コードが成立した場合は両キーの単体操作を抑止する。成立しなかった場合、修飾キーの単体操作は解放時に1回実行する。コード判定を優先するため、修飾キーに割り当てたCueの保持動作とJumpの長押し加速は無効となる。ACK05の修飾キーのみを送る物理キーや重複するHIDレポートも、直前の押下状態を用いて組み合わせを復元する。

設定version 7では `deviceProfiles` のキーにACK05の `PhysicalDeviceUniqueID`、値にプロファイル名を指定する。未登録デバイスは `defaultProfile` を使用し、初回入力時にその対応を設定ファイルへ保存する。シリアル番号が公開されない場合はDeviceAddress、LocationIDの順で識別子をフォールバックする。各プロファイルはグループ1〜4のwaveformPosition、keyMap、2〜10キーの任意数chordMap、dialMap、キー保持＋ダイヤル用dialChordMapを持ち、安定したAction IDまたはrekordbox command IDを保存する。version 1〜6設定は原本を `config.vN.backup.json` へ保存し、プロファイル共通の波形位置を全グループへ引き継いでversion 7へ自動移行する。デフォルトマップはCoreのJSONリソースとして管理する。

8.6 Action Layer

物理入力、論理Action、対象ソフト固有Adapter、出力処理を分離する。ACK05の単体キーとコードはInputActionResolverによりActionEventへ変換される。ActionEventはAction ID、triggered/pressed/released/repeatedのphase、入力元キーと表示ラベルを持つ。Cue保持とJump長押しはActionの動作特性として定義し、物理キー位置から独立させる。

rekordboxのcommandId対応はRekordboxActionAdapterだけが保持する。capture_waveform_positionはrekordboxへ渡さずInternal Action Handlerで波形位置保存として処理する。これにより将来の別DJソフトAdapterや入力デバイスを追加しても、設定のAction IDと入力状態機械を維持できる。

⸻

9. ジョグ入力仕様

9.1 目的

ACK05のダイヤルを、rekordbox上の疑似ジョグホイールとして利用する。

主目的はスクラッチ演奏ではなく、CUE打ちのための曲内位置合わせである。

9.2 JogScratch

MVPで最優先する機能。

ダイヤル入力を検知したら、OverCUEは以下を行う。

ダイヤル変化あり
→ JogTouch ON
→ JogScratch相当の相対値を送出
→ 一定時間無入力でJogTouch OFF

初期値:

右回転 → JogScratch +1
左回転 → JogScratch -1

DDJ系ジョグ入力の参考値:

中立値 = 64
右回転 = 65以上
左回転 = 63以下

初期実装では以下でよい。

右回転 → 65
左回転 → 63

DDJ-SX公式MIDIメッセージリストに基づくDeck 1の実送信値:

```text
JogTouch ON  = 90 36 7F
JogTouch OFF = 90 36 00
JogScratch CW  = B0 22 41
JogScratch CCW = B0 22 3F
```

JogTouchはNote 54（0x36）、Vinyl On状態のJogScratchはCC 34（0x22）を使用する。
Deck 2〜4では、ステータスバイトのMIDIチャンネルをそれぞれ1〜3へ変更する。

参考資料:

* Pioneer DJ DDJ-SX List of MIDI Messages ver. 1.00
  https://www.pioneerdj.com/-/media/pioneerdj/software-info/controller/ddj-sx/ddj-sx_list_of_midi_messages_e.pdf

9.3 JogTouch

ACK05にはタッチセンサーがないため、OverCUE側で自動的にJogTouchを生成する。

仕様:

ダイヤル入力開始
→ JogTouch ON
無入力タイムアウト
→ JogTouch OFF

初期タイムアウト候補:

120ms〜180ms
初期値: 150ms

9.4 JogPitchBend

JogPitchBendはMVP後の拡張機能とする。

モード切り替えキーを押している間、またはトグル切り替え時に、ダイヤル入力をJogScratchではなくJogPitchBendとして扱う。

中央ボタンは取得できないため、モード切り替えにはK1〜K10のいずれかを使う。

⸻

10. キーマッピング機能

OverCUEは、ダイヤル以外のキーに対してキーマッピング可能な設計にする。

10.1 対象

* K1〜K10
* 将来的には他デバイスのキー
* ダイヤル回転
* モード切り替えキー

10.2 マッピング可能なアクション

初期候補:

Play / Pause
Cue
Set Memory Cue
Delete Memory Cue
Call Previous Memory Cue
Call Next Memory Cue
Hot Cue A
Hot Cue B
Hot Cue C
Hot Cue D
JogScratch Mode
JogPitchBend Mode
Waveform Zoom In
Waveform Zoom Out
Beat Jump Forward
Beat Jump Reverse

10.3 入力吸収

ACK05のデフォルト入力には Ctrl+O, Ctrl+S, Ctrl+Z など、通常アプリ操作と競合しやすいものが含まれる。

そのため、OverCUE起動中はACK05からの対象入力を吸収し、DJソフトへ生キー入力として漏らさないことを目指す。

⸻

11. 将来的なDJソフト対応

OverCUEはrekordbox専用アプリとして閉じず、将来的に他のDJソフトにも対応可能な構造にする。

想定ソフト:

* rekordbox
* Serato DJ
* Traktor
* VirtualDJ
* djay
* Mixxx

設計方針:

入力層: ACK05 / HID / 将来の別デバイス
変換層: OverCUE内部アクション
出力層: rekordbox / 他DJソフト向けプロファイル

アプリ内部では、ACK05の入力を直接rekordbox操作へ結びつけず、抽象アクションへ変換する。

例:

ACK05 Dial CW
→ Action: JogForward
rekordbox profile
→ DDJ-SX風MIDI
Mixxx profile
→ Mixxx向けMIDI / shortcut

⸻

12. MVP仕様

12.1 MVPの目的

OverCUE MVPでは、ACK05のダイヤルをrekordbox上でCUE打ち用の疑似ジョグとして使えるかを検証する。

12.2 MVP対象

* OS: macOS優先
* デバイス: XPPen ACK05
* DJソフト: rekordbox Performance mode優先
* 入力: ダイヤル右回転 / 左回転
* 出力: JogTouch + JogScratch相当MIDI

12.3 MVP機能

1. ACK05をHIDデバイスとして検出
2. VendorID/ProductIDでACK05を識別
3. ダイヤル右回転/左回転を検出
4. 入力イベントを必要に応じて吸収
5. JogTouch ON/OFFを生成
6. JogScratch相当のMIDI値を送信
7. 無入力150msでJogTouch OFF

12.4 MVP成功条件

- ACK05のダイヤル回転をOverCUEが取得できる
- ダイヤル右/左を安定して判定できる
- rekordbox側で曲内位置移動として反応する
- トラックパッドよりCUE地点へ移動しやすい
- ショートカット割り当てによるCUE打ちと併用できる

⸻

13. 実装方針

制作はCodexを使って進める。

13.1 技術候補

macOS入力取得

候補:

* Swift + IOHIDManager
* Swift + CGEventTap
* Node.js + node-hid
* Electron + Native helper

Windows入力取得

候補:

* hidapi
* node-hid
* Raw Input API

MIDI送出

macOS:

* CoreMIDI
* IAC Driver

Windows:

* loopMIDI
* WinMM / RtMidi / node-midi

13.2 初期実装案

MVPでは以下のどちらかを優先する。

案A: HID直読み

ACK05をVendorID/ProductIDで検出
↓
HIDレポートを直接読む
↓
OverCUEで変換
↓
MIDI送出

メリット:

* ACK05を明確に識別できる
* 将来的に安全
* KarabinerやXPPenPenTabletに依存しない

懸念:

* HIDレポート解析が必要
* macOSの権限やBluetooth挙動で詰まる可能性

案B: CGEventTap方式

macOSキーイベントを取得
↓
Ctrl + keypad_plus / Ctrl + keypad_hyphen を検出
↓
イベントを吸収
↓
MIDI送出

メリット:

* 既にKarabiner-EventViewerで見えている入力を利用できる
* 実装が早い

懸念:

* ACK05専用判定が難しい可能性
* 他キーボードの同一入力と衝突する可能性

初期は案Aを試し、難しければ案BでMVPを通す。

⸻

14. 非目標

OverCUE v0.1では以下を目標にしない。

- DJ演奏用フルコントローラー化
- スクラッチ演奏用途の完全再現
- DDJ-FLX4 / DDJ-SXの全機能再現
- Joy-Con対応
- TourBoxなど高額デバイス対応
- 複数DJソフト完全対応
- 美麗UI
- ACK05本体ファームウェア書き換え
- XPPenPenTabletの完全代替

⸻

15. 今後の検証タスク

15.1 ACK05 HID直読み検証

1. VendorID 10429 / ProductID 514 のHIDデバイスを列挙
2. device pathを取得
3. HIDデバイスをopen
4. ダイヤル回転時の生データをログ出力
5. K1〜K10の生データもログ出力

15.2 MIDI送出検証

実装・確認済み:

1. OverCUE自身がCoreMIDI仮想ソース「OverCUE」を作成
2. ACK05ダイヤル入力からJogTouchとJogScratchメッセージを生成
3. 右回転時に `90 36 7F` → `B0 22 41` → 150ms後 `90 36 00` を送出
4. 左回転時に `90 36 7F` → `B0 22 3F` → 150ms後 `90 36 00` を送出
5. 連続回転中はJogTouch ONを重複送信せず、最終入力から150ms後にOFF
6. ACK05の共有オープン・排他オープンの両方で送出成功

CoreMIDI仮想ソースを直接公開するため、現在の実装ではIAC Driverを必須としない。

未確認:

1. rekordbox Performance modeで「OverCUE」ソースを受信
2. DDJ-SX風ジョグ入力として曲内位置が移動するか確認

15.3 rekordbox反応検証

1. JogTouch ONを送る
2. JogScratch +1 / -1を送る
3. JogTouch OFFを送る
4. 曲内位置が動くか確認
5. touchOffDelayを調整する

15.4 Export mode検証

1. Export modeでMIDI入力が効くか確認
2. 効かない場合はショートカットベース運用を検討
3. Performance mode専用として割り切るか判断

⸻

16. 現時点の結論

OverCUEは、XPPen ACK05を標準デバイスとして採用する。

ACK05は既にショートカットキー割り当てによるCUE打ち体験が良好であり、ダイヤル操作も24デテントで滑らかであることを確認済み。

今後の最重要課題は、ACK05のダイヤルをrekordbox上の疑似ジョグホイールとして機能させること。

MVPでは、まずACK05のダイヤル入力をJogTouch + JogScratch相当のMIDI入力へ変換し、rekordbox Performance modeでCUE打ち用の曲内移動が可能かを検証する。
