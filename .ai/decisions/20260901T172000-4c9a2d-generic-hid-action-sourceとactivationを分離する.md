# Generic HIDのAction source identityとactivationを分離する

- Change ID: `20260901T172000-4c9a2d`
- 状態: 採用

## 背景

Generic HID Core追加後のレビューで、`ActionEvent.sourceKey`がACK05固有型のまま残り、Generic HIDのhold / repeat sourceをAction Layerへ表現できないこと、relative inputがdescriptorだけでmappingされるためCW / CCW相当の正負方向を別Actionへ割り当てられないことが判明した。またRebindはpersistent Serialの一意性だけを見ており、Identify後に対象sessionが切断されたstale descriptorでも別sessionの同一Serialを根拠にbindingできる余地があった。

## 決定

- `ActionEvent`の正本source identityはadapter非依存の`ActionSourceID(namespace, identifier)`とする。
- 既存ACK05コードの移行を局所化するため`sourceKey`はACK05互換accessorとして一時的に残すが、新しいadapterは`sourceID`を使用する。
- Generic HIDのmapping identityはpersistent element descriptorだけでなくactivationを含む`GenericHIDInputBindingKey`とする。activationは少なくとも`press`、`relativePositive`、`relativeNegative`を区別する。
- relative deltaの符号はAction選択に使い、絶対値は`ActionEvent.activationCount`へ保持する。実機ごとの高解像度deltaを何回のrekordbox操作へ変換するかはprobe結果を得るまで決めない。
- Generic HID hold / accelerating-repeat stateはACK05Keyではなくgeneric `ActionSourceID`で保持する。同一descriptorを持つ別session deviceの状態を混同しない。
- Rebindは引数descriptorのsession identifierが現在のconnected setに存在し、descriptor自体も一致することを最初に確認する。切断済みなら`deviceNotConnected`で拒否し、再Identifyを要求する。
- Generic HID mappingのconfig永続化は引き続き実機identity待ちとし、config version 9を維持する。

## 理由

- Action Layerから物理adapter固有型を必須条件として外すことで、ACK05とGeneric HIDを同じAction境界へ接続できる。
- relative directionをdescriptorと別軸にすることで、一つのencoder elementへCW / CCWで異なるActionを割り当てられる。
- delta量を捨てずに保持することで、低解像度detentと高解像度wheelの差を実機確認後にruntime policyで扱える。
- Rebind時にlive session存在を要求することで、Identifyした実機と保存されるpersistent identityの対応を切断・差し替え越しに推測しない。

## 影響

- `GenericHIDLogicalInputBinding`はdirection-awareなbinding keyを正本とする。
- 旧descriptor-only Generic HID mapping APIは互換用deprecated overloadとして残し、relative正負を同じActionへ向ける従来挙動だけを維持する。
- `ActionEvent.activationCount`は現時点でCore payloadとして保持するだけで、Generic HID runtime mappingが未接続のため既存ACK05の送信回数は変わらない。
- Devices / Learn UIとconfig v10要否は実機確認後に決める。

## 未確認

- Koolertron encoderのrelative delta単位と符号。
- 同型KoolertronのSerial有無と再接続時descriptor安定性。
- Generic HID runtime接続時のactivationCount→rekordbox操作回数またはacceleration policy。
