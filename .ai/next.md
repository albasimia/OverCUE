# Next

## 現在のフェーズ

PERFORMANCE 4Deck構造の実装とmacOSローカルビルドは完了し、実データ／実機検証へ移る段階。

## 次の目的

Deck 4のcommandId規則と、GroupごとのDeck 1〜4操作がrekordbox実動作に一致することを確認する。

## 次の行動

- [ ] rekordboxでDeck 4のPlay/Pause、Cue、Hot Cue、Memory Cue、Beat Jump、Quantize、Pitch Bendへ一時的にショートカットを割り当て、保存された選択中KeyMappings XMLを既存ローダーで読む。
- [ ] Deck 1〜4で同一ActionのcommandId suffixを比較し、`33xx`規則を実データで確認する。
- [ ] ACK05でGroup切り替え、対象Deck、Group別波形位置、Cue hold、Jump repeat、コード操作を確認する。
- [ ] 確認結果をcore checks、`specs/current-spec.md`、AAL historyへ反映する。

## ブロッカー

現在選択中の`Performance 1 (Preset)`にはDeck 4の割り当て行がない。直接確認にはrekordbox側でDeck 4ショートカットを保存する操作と、アクセシビリティ／入力監視権限、ACK05実機が必要。

## 完了条件

- Deck 4の対象Action commandIdを実データで確認できる。
- PERFORMANCEのGroup 1〜4をDeck 1〜4へ割り当て、期待したDeckだけが操作される。
- 未割り当て操作とEXPORTモードの従来挙動が維持される。
- `./Scripts/verify-macos.sh`が成功し、実機確認結果が仕様とhistoryへ記録される。

## 保留

- GitHub Actionsの復旧。
- 複数ACK05の完全な同時操作対応。
- Developer ID署名とnotarization。
