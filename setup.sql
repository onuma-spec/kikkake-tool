-- きっかけ収集ツール（kikkake）テーブル作成スクリプト
-- 既存の jimujigyou-hyoka Supabase プロジェクトに新テーブルとして追加する想定
-- Supabase の SQL Editor で1回だけ実行してください
--
-- 2026-07-28追記：審査は手動ではなく、送信前のクライアント側チェック（PIIパターン検出）
-- のみで運用する方針のため、reviewed のデフォルトを true（自動公開）にしている。
--
-- 2026-07-28追記：テーブル名は当初 zeigen_kikkake だったが、命名ミス
-- （「減税」の語順違い）に気づき kikkake にリネームした。
--   alter table zeigen_kikkake rename to kikkake;
--   alter sequence zeigen_kikkake_id_seq rename to kikkake_id_seq;
-- （リネームのためデータ・RLSポリシー・権限はそのまま引き継がれる）
--
-- 2026-07-28追記：クライアント側のPIIチェックは、ブラウザを経由しない直接の
-- API呼び出しでは効かないことが判明（実際にcurlでの直接POSTが素通りすることを
-- 確認した）。DB側にも同じパターンのCHECK制約を追加し、投稿経路に関わらず
-- 弾かれるようにした（no_obvious_pii制約、下記CREATE TABLEに含む）。

create table kikkake (
  id            bigserial primary key,
  story_book    text,
  story_life    text,
  story_genba   text,
  story_other   text,
  reviewed      boolean not null default true,
  submitted_at  timestamptz not null default now(),
  constraint at_least_one_field check (
    coalesce(length(story_book), 0)  > 0 or
    coalesce(length(story_life), 0)  > 0 or
    coalesce(length(story_genba), 0) > 0 or
    coalesce(length(story_other), 0) > 0
  ),
  constraint length_limits check (
    coalesce(length(story_book), 0)  <= 1000 and
    coalesce(length(story_life), 0)  <= 1000 and
    coalesce(length(story_genba), 0) <= 1000 and
    coalesce(length(story_other), 0) <= 1000
  ),
  -- DB側でも電話番号・メール・URLの明白なパターンを弾く（ブラウザ経由の投稿・
  -- 直接API経由の投稿の両方に一律で効く。クライアント側チェックの補完）
  constraint no_obvious_pii check (
    story_book  !~ '0\d{1,4}-\d{1,4}-\d{3,4}' and story_book  !~ '[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}' and story_book  !~ 'https?://\S+' and
    story_life  !~ '0\d{1,4}-\d{1,4}-\d{3,4}' and story_life  !~ '[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}' and story_life  !~ 'https?://\S+' and
    story_genba !~ '0\d{1,4}-\d{1,4}-\d{3,4}' and story_genba !~ '[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}' and story_genba !~ 'https?://\S+' and
    story_other !~ '0\d{1,4}-\d{1,4}-\d{3,4}' and story_other !~ '[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}' and story_other !~ 'https?://\S+'
  )
);

alter table kikkake enable row level security;

-- 誰でも投稿できる（reviewedは常にDBのdefault trueになり、クライアントからは上書きできない）
create policy "anyone can insert" on kikkake
  for insert to anon with check (true);

-- 読み取りは審査済み（reviewed = true）の行のみ。将来手動で非公開にした行はanonから見えない
create policy "anyone can select reviewed only" on kikkake
  for select to anon using (reviewed = true);

-- anon が書き込めるのは4つの自由記述欄のみ（reviewedカラムへのINSERT権限を与えないことで、
-- クライアントが reviewed:false を直接送っても常にDBのdefaultが適用される）
grant insert (story_book, story_life, story_genba, story_other) on public.kikkake to anon;
grant select on public.kikkake to anon;
grant usage, select on sequence public.kikkake_id_seq to anon;

-- 運用メモ
-- ・非公開にしたい場合：update kikkake set reviewed = false where id = ...;
-- ・識別情報を伏字にしたい場合：update kikkake set story_book = '[伏字]' where id = ...;
-- ・完全に削除したい場合：delete from kikkake where id = ...;
-- ・テストデータを一括リセットする場合：truncate table kikkake restart identity;
