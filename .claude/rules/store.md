---
description: Models.swift（AppStore/永続化/モデル）を編集するときの非交渉ルール。単一ストア・寛容Codable。
paths:
  - "BucketList/Models.swift"
---

# ルール：ストアとモデル（Models.swift）

正典：[設計原則§5・§9](../../docs/philosophy/02-設計原則.md) / [architecture/overview](../../docs/architecture/overview.md)

- **単一の真実源**：状態は `AppStore: ObservableObject` に集約（per-screen MVVM を作らない）。
  変更メソッドはローカルコピーを編集して一度だけ代入 → `didSet` が**1回だけ**永続化する形を保つ。
- **データを壊さない（寛容な永続化）**：
  - デコード失敗でストア全体を空に上書きしない。`StoreLoad`（`.absent`/`.loaded`/`.unreadable`）を区別し、
    読めない時はバックアップ復旧。
  - 要素ごとにデコード（`LossyArray`/`LossyDocument`）＝1件破損はその1件だけスキップ。
  - 新フィールドは既定値フォールバック（`BucketItem` の手書き `Codable`）。旧データが読めなくなる変更を入れない。
- **破壊操作には undo**（`pendingUndo` ＋トースト）。削除・一括削除・タグ削除で undo を外さない。
- **App Group 整合**：正典は `SharedStore`（`NSFileCoordinator`＋1世代バックアップ）。拡張は `.forMerging` で追記し
  互いの書き込みを潰さない。`appGroupID = "group.teratech.BucketList"` を変えない。
- **3軸モデルを守る**：季節は `SeasonTag`（空=いつでも、旧"m4"は季節へ畳み込み）。月単位指定を復活させない
  （[ADR 0001](../../docs/decisions/0001-3軸モデル.md)）。タグは固定4＋カスタム最大10。
- **AI は候補・ユーザーが主役**：自動分類 OFF（`Tweaks.autoClassify`）を尊重する。
