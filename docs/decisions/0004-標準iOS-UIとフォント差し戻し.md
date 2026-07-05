# 0004. 装飾を避け標準 iOS UI。カスタムフォントを system font へ差し戻し

- Status: Accepted
- Date: 2026-06

## Context
デザイン初期案は「紙＋クレヨン」風で、Zen Maru Gothic / Zen Kaku Gothic New / Klee One /
JetBrains Mono などのカスタム書体と装飾を想定していた。だがターゲット（20代）が迷わず使え、
"仕事感/管理感"を出さない（コアコンセプト§6）には、奇抜さより**見慣れた標準**が勝る。

## Decision
- 装飾・独自操作を避け、一般的な標準 iOS の見た目・操作にする（plain / familiar）。
- `Theme.Font` の全ロールを **system font**（`.system(design: .default)`）へ写像。丸ゴシック/セリフ体は落とす。
- 達成演出は**トースト＋undo のみ**。confetti / キラキラは入れない。
- リストの「done」は分割セクションにせず、単一フラットリスト内でディム＋打ち消し線。

## Consequences
- 学習コストと違和感を最小化。Apple 標準体験と地続き。
- カスタム書体が再度必要になれば、`.ttf` をバンドルに入れ `Theme.Font` を `.custom(...)` に戻せる（余地は残す）。
- [設計原則§1](../philosophy/02-設計原則.md)（標準UI）・[§2](../philosophy/02-設計原則.md)（控えめ統一）として恒久化。
- フローティングのクロームだけは例外的に**本物の Liquid Glass** を使う（[設計原則§3](../philosophy/02-設計原則.md)）。
