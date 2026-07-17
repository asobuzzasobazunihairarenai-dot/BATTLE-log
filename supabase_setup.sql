-- 7 SHADES OF S:EVEN 戦績管理システム用 Supabase スキーマ
-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください

-- プレイヤーテーブル
create table if not exists players (
  id text primary key,
  name text not null,
  discord_id text default '',
  avatar_url text default '',
  custom_triangle_color text default '',
  status text not null default 'pending', -- 'approved' | 'pending'
  edit_pending jsonb,
  created_at timestamptz not null default now()
);

-- 対戦履歴テーブル
create table if not exists matches (
  id text primary key,
  date text not null,
  members jsonb not null,       -- プレイヤーIDの配列 ["p1","p2",...]
  winner_id text not null,
  proof_image_url text default '',
  status text not null default 'pending', -- 'approved' | 'pending'
  created_at bigint not null
);

-- アプリ全体設定(管理者パスワードなど)。1行だけ使う
create table if not exists app_settings (
  id int primary key default 1,
  admin_password text not null default '0000'
);
insert into app_settings (id, admin_password)
  values (1, '0000')
  on conflict (id) do nothing;

-- RLSを有効化
alter table players enable row level security;
alter table matches enable row level security;
alter table app_settings enable row level security;

-- 匿名キー(anon)からの読み書きを許可するポリシー
-- ※このアプリは管理者パスワードをアプリ側(JS)だけでチェックする簡易方式のため、
--   本当の「管理者だけ書き込み可」はDB側では強制していません。
--   身内・友人内での運用を想定した簡易ポリシーです。
create policy "players_select" on players for select using (true);
create policy "players_insert" on players for insert with check (true);
create policy "players_update" on players for update using (true);
create policy "players_delete" on players for delete using (true);

create policy "matches_select" on matches for select using (true);
create policy "matches_insert" on matches for insert with check (true);
create policy "matches_update" on matches for update using (true);
create policy "matches_delete" on matches for delete using (true);

create policy "app_settings_select" on app_settings for select using (true);
create policy "app_settings_update" on app_settings for update using (true);

-- Realtime配信を有効化(他の端末の変更を自動反映するため)
alter publication supabase_realtime add table players;
alter publication supabase_realtime add table matches;
alter publication supabase_realtime add table app_settings;

-- 追加修正: Storageバケット(avatars, match-proofs)へのアップロードを許可するポリシー
-- (バケットの「Public」設定は閲覧のみを許可するもので、アップロードには別途ポリシーが必要なため)
create policy "avatars_insert" on storage.objects for insert
  with check (bucket_id = 'avatars');
create policy "avatars_select" on storage.objects for select
  using (bucket_id = 'avatars');

create policy "match_proofs_insert" on storage.objects for insert
  with check (bucket_id = 'match-proofs');
create policy "match_proofs_select" on storage.objects for select
  using (bucket_id = 'match-proofs');

-- 追加修正: 戦績申請に「感想・フィードバック」コメント欄を追加
alter table matches add column if not exists feedback text default '';
