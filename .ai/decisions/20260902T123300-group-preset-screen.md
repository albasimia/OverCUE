# Group Preset専用画面をトップレベルへ追加する

- Date: 2026-09-02
- Status: accepted
- AAL-Change-Id: 20260902T123300-group-preset-screen

## Context

Group Presetは複数Logical Deviceの開始Presetをまとめる親設定として実装済みだが、編集UIはDevices画面内に分散していた。

3Deck構成では、Group Presetごとに「どのLogical Deviceを含めるか」「含めた各Logical DeviceがどのPresetを参照するか」を横断的に確認・編集する必要がある。Device詳細を1台ずつ開く方式だけでは全体構成を把握しづらい。

## Decision

- トップレベルナビゲーションに`Group Preset`を追加する。
- 主要ナビゲーションは`Shortcuts / Devices / Group Preset / Settings`の4セクションとする。
- Group Preset専用画面では、active Group Presetの選択・追加・rename・deleteと、全Logical Deviceのinclusion / Preset参照を一画面で編集できるようにする。
- Devices画面内の既存Group Preset編集導線は残す。専用画面は横断編集、Devices画面は個別Device文脈での編集として併存させる。
- config schema、Group Preset runtime semantics、Cycle Presetの一時runtime stateには変更を加えない。

## Supersedes

`.ai/project.md`にある「主要ナビゲーションは当面3タブ」とする記述のうち、タブ数と構成だけをこのDecisionで置換する。
