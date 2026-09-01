# default GUI controlはlive default Profile deviceだけへ送る

- Change ID: `20260901T134728-af2367`
- 状態: 採用


## 背景

default Profile用GUIはdefault Profile deviceのGroup / Mode / Deckを操作する。しかしtargetが未確定の場合にglobal runtime controlへフォールバックすると、non-default Profile deviceだけが接続中でもそのcontrollerがcontrolを受ける。default device切断後に古いsession targetを保持する場合は送信不能となり、どちらもGUI表示対象と実際のcontrol対象が一致しない。

## 決定

- default Profile用GUIのruntime controlは、default Profile statusから取得したlive session device IDへのdevice scopeだけで送る。
- non-default Profile statusはtargetを更新せず、そのdeviceのinput highlightもdefault GUIへ表示しない。
- live default targetがない場合はcontrolを送らない。global fallbackは使わない。
- target device切断時はtargetを解放し、再接続statusで新しいsession IDを取得する。
- controlには想定Profile名を含める。CLIは最新config reload後にPhysical Binding / Logical Device / Profileを再評価し、対象deviceが別Profileへ解決された場合はcontrolを拒否する。

## 理由

接続前のsingle-device UXよりも、複数device環境で別Profileを誤操作しない境界を優先する。CLIはdevice接続時と通常key / dial入力時にstatusをpublishするため、正常接続したdefault deviceではGUIがlive targetを取得できる。target不在は「操作対象が確認できない」状態であり、global送信で推測するより送信しない方が安全である。

## 影響

- default deviceのstatus受信前または切断後は、GUIで設定は保存できるがruntime Group / Mode controlは送信されない。
- 再接続時は旧session IDを再利用せず、CLI statusの新session IDへ追従する。
- 将来non-default ProfileをGUIで直接編集する場合は、UI contextと同じProfile / Logical Deviceから独立したlive targetを明示的に管理する必要がある。
- global scope自体はCoreの明示機能として残すが、default Profile設定GUIのfallbackには使用しない。

## 代替案

- target不在時にglobal送信する案: non-default controllerを誤操作できるため不採用。
- 切断後も旧device IDを保持する案: controller消滅後にcontrolが配送不能となり、再接続sessionへ追従できないため不採用。
- Profile名を通知せずdevice IDだけで配送する案: control直前のPhysical Binding変更でdeviceのProfileが変わった場合を検出できないため不採用。
