-- 7 SHADES OF S:EVEN 戦績管理システム用 Supabase スキーマ
-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください
--
-- ★このファイルは「全部まとめて貼り付けて実行」して大丈夫です（何度実行しても壊れません）。
--   2026-08-28にそう作り直しました。それ以前は、
--     ・create policy に drop policy if exists が無く「既に存在します」でエラー
--     ・alter publication ... add table が「既に入っています」でエラー
--   となり、**途中でエラーが出るとそれ以降の行が実行されない**（＝末尾に追記した新しい設定が
--   反映されない）状態でした。全 create policy に drop を前置し、publication への追加は
--   「まだ入っていなければ」の判定で包んであります。
--   テーブル・列・索引は元から create table if not exists / add column if not exists なので安全です。

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
drop policy if exists "players_select" on players;
create policy "players_select" on players for select using (true);
drop policy if exists "players_insert" on players;
create policy "players_insert" on players for insert with check (true);
drop policy if exists "players_update" on players;
create policy "players_update" on players for update using (true);
drop policy if exists "players_delete" on players;
create policy "players_delete" on players for delete using (true);

drop policy if exists "matches_select" on matches;
create policy "matches_select" on matches for select using (true);
drop policy if exists "matches_insert" on matches;
create policy "matches_insert" on matches for insert with check (true);
drop policy if exists "matches_update" on matches;
create policy "matches_update" on matches for update using (true);
drop policy if exists "matches_delete" on matches;
create policy "matches_delete" on matches for delete using (true);

drop policy if exists "app_settings_select" on app_settings;
create policy "app_settings_select" on app_settings for select using (true);
drop policy if exists "app_settings_update" on app_settings;
create policy "app_settings_update" on app_settings for update using (true);

-- Realtime配信を有効化(他の端末の変更を自動反映するため)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'players') then
    alter publication supabase_realtime add table players;
  end if;
end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'matches') then
    alter publication supabase_realtime add table matches;
  end if;
end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'app_settings') then
    alter publication supabase_realtime add table app_settings;
  end if;
end $$;

-- 追加修正: Storageバケット(avatars, match-proofs)へのアップロードを許可するポリシー
-- (バケットの「Public」設定は閲覧のみを許可するもので、アップロードには別途ポリシーが必要なため)
drop policy if exists "avatars_insert" on storage.objects;
create policy "avatars_insert" on storage.objects for insert
  with check (bucket_id = 'avatars');
drop policy if exists "avatars_select" on storage.objects;
create policy "avatars_select" on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "match_proofs_insert" on storage.objects;
create policy "match_proofs_insert" on storage.objects for insert
  with check (bucket_id = 'match-proofs');
drop policy if exists "match_proofs_select" on storage.objects;
create policy "match_proofs_select" on storage.objects for select
  using (bucket_id = 'match-proofs');

-- 追加修正: 戦績申請に「感想・フィードバック」コメント欄を追加
alter table matches add column if not exists feedback text default '';

-- 追加機能: プレイヤー単位の「ゲームについてのコメント」(特定の戦績とは無関係な感想・フィードバック)
create table if not exists game_comments (
  id text primary key,
  player_id text not null,
  comment text not null,
  created_at bigint not null
);
alter table game_comments enable row level security;
drop policy if exists "game_comments_select" on game_comments;
create policy "game_comments_select" on game_comments for select using (true);
drop policy if exists "game_comments_insert" on game_comments;
create policy "game_comments_insert" on game_comments for insert with check (true);
drop policy if exists "game_comments_delete" on game_comments;
create policy "game_comments_delete" on game_comments for delete using (true);
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'game_comments') then
    alter publication supabase_realtime add table game_comments;
  end if;
end $$;

-- 追加機能: 公開前の初期戦績(ベース値)をプレイヤーごとに設定できるようにする
alter table players add column if not exists seed_matches_count integer not null default 0;
alter table players add column if not exists seed_wins_count integer not null default 0;

-- 追加機能: 運営枠(ランキング集計から除外するプレイヤー)の設定
alter table players add column if not exists is_staff boolean not null default false;

-- 追加機能: アクセスログ(管理者コンソールで訪問数を確認できるようにする)
create table if not exists page_visits (
  id text primary key,
  visitor_id text not null,
  visited_at bigint not null
);
alter table page_visits enable row level security;
drop policy if exists "page_visits_select" on page_visits;
create policy "page_visits_select" on page_visits for select using (true);
drop policy if exists "page_visits_insert" on page_visits;
create policy "page_visits_insert" on page_visits for insert with check (true);

-- 追加機能: 戦績申請に「プレイ時間(約●分・任意)」を追加
alter table matches add column if not exists duration_minutes integer;

-- 追加機能: 「ゲームについてコメントする」の匿名投稿を許可
alter table game_comments alter column player_id drop not null;

-- 追加機能: メール通知のON/OFF設定 (どのイベントで通知するか管理者が選べる)
alter table app_settings add column if not exists notify_on_match boolean not null default true;
alter table app_settings add column if not exists notify_on_comment boolean not null default true;
alter table app_settings add column if not exists notify_on_player boolean not null default true;

-- 追加機能: 承認シミュレーターの案内ポップアップのON/OFF設定
alter table app_settings add column if not exists show_approval_simulator boolean not null default true;

-- 追加機能: 管理者からのニュース投稿(ニュースティッカー用)
create table if not exists admin_news (
  id text primary key,
  message text not null,
  created_at bigint not null
);
alter table admin_news enable row level security;
drop policy if exists "admin_news_select" on admin_news;
create policy "admin_news_select" on admin_news for select using (true);
drop policy if exists "admin_news_insert" on admin_news;
create policy "admin_news_insert" on admin_news for insert with check (true);
drop policy if exists "admin_news_delete" on admin_news;
create policy "admin_news_delete" on admin_news for delete using (true);
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'admin_news') then
    alter publication supabase_realtime add table admin_news;
  end if;
end $$;

-- 追加機能: 「ゲームについてコメントする」の返信機能
alter table game_comments add column if not exists parent_id text references game_comments(id) on delete cascade;

-- 追加機能: 戦績の「感想・フィードバック」への返信機能
create table if not exists match_feedback_replies (
  id text primary key,
  match_id text not null references matches(id) on delete cascade,
  player_id text,
  comment text not null,
  created_at bigint not null
);
alter table match_feedback_replies enable row level security;
drop policy if exists "match_feedback_replies_select" on match_feedback_replies;
create policy "match_feedback_replies_select" on match_feedback_replies for select using (true);
drop policy if exists "match_feedback_replies_insert" on match_feedback_replies;
create policy "match_feedback_replies_insert" on match_feedback_replies for insert with check (true);
drop policy if exists "match_feedback_replies_delete" on match_feedback_replies;
create policy "match_feedback_replies_delete" on match_feedback_replies for delete using (true);
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'match_feedback_replies') then
    alter publication supabase_realtime add table match_feedback_replies;
  end if;
end $$;

-- 追加機能: 管理者ニュースに「非表示フラグ」を追加(削除せず一時的に隠せるように)
alter table admin_news add column if not exists is_hidden boolean not null default false;

-- 追加修正: admin_newsテーブルにUPDATE(非表示フラグの更新)を許可するポリシーが抜けていたので追加
drop policy if exists "admin_news_update" on admin_news;
create policy "admin_news_update" on admin_news for update using (true);

-- 追加機能: ニュースティッカーの流れる速度を管理者が調整できるようにする(秒数=1周にかかる時間。大きいほどゆっくり)
alter table app_settings add column if not exists ticker_speed_seconds integer not null default 50;

-- 追加修正(2026-08-28): コメント2テーブルにUPDATEポリシーが無く、プレイヤー統合時の
-- 「投稿者の付け替え」（match_feedback_replies.player_id / game_comments.player_id の更新）が
-- **エラーも出ずに0行しか更新されない**状態だった（RLSでポリシーが無いUPDATEは、拒否ではなく
-- 「対象0行」として静かに成功する）。そのため統合後のコメントが「不明なプレイヤー」表示のまま
-- 残り、管理者コンソールの付け替えツールを押しても何も変わらなかった。
-- admin_news のUPDATEポリシーが抜けていた時と同じ対処。
drop policy if exists "match_feedback_replies_update" on match_feedback_replies;
create policy "match_feedback_replies_update" on match_feedback_replies for update using (true);

drop policy if exists "game_comments_update" on game_comments;
create policy "game_comments_update" on game_comments for update using (true);

-- 追加機能(2026-08-28): 称号（デジタル版のマイページで集めて、1つをお気に入りに選ぶ）。
-- デジタル版側の so7_user_profiles は「自分の行しか読めない」RLSのため、他人の称号を表示できない。
-- players は全員が読める（players_select using(true)）ので、選んだ称号のキーはこちらに持たせる。
-- 解禁状況そのものは保存しない（その時々の戦績から毎回計算する。src/titles.js のコメント参照）。
alter table players add column if not exists title_key text;

-- 追加(2026-09-05): 管理者コンソールの「直近のアクセス」にプレイヤー名を出す。
-- page_visits は端末ごとのランダムな visitor_id しか持っておらず「誰が見に来たか」が
-- 分からなかった。ログイン中ならアカウント(auth.users.id)も一緒に記録しておき、
-- 表示時に players.user_id と突き合わせて名前を出す（未ログインは「ゲスト」と表示）。
-- 列が無い環境でもアクセス記録自体は落ちないようクライアント側で退避してあるので、
-- 実行するまでは今までどおり日時だけが並ぶ。
alter table page_visits add column if not exists user_id uuid;
