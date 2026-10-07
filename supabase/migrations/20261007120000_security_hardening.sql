-- =====================================================================
-- Wordlet — Security hardening & server-authoritative duels
--
-- Supabase SQL Editor'da (veya `supabase db push` ile) çalıştırın.
-- Tekrar çalıştırılabilir (idempotent).
--
-- ÖN KOŞUL (bir kere): Push webhook için rastgele, uzun bir secret üretin
-- ve hem Vault'a hem Edge Function secret'larına aynı değeri koyun:
--
--   select vault.create_secret('<UZUN-RASTGELE-DEĞER>', 'push_webhook_secret');
--   supabase secrets set PUSH_WEBHOOK_SECRET=<UZUN-RASTGELE-DEĞER>
-- =====================================================================

begin;

-- =====================================================================
-- 1. PROFILES
-- =====================================================================

-- 1a. Push token'ları herkese açık profiles tablosundan özel tabloya taşı
create table if not exists public.device_tokens (
    user_id    uuid primary key references public.profiles(id) on delete cascade,
    token      text not null,
    apns_env   text not null default 'production' check (apns_env in ('sandbox', 'production')),
    updated_at timestamptz not null default now()
);

alter table public.device_tokens enable row level security;

drop policy if exists "Users manage own device token" on public.device_tokens;
create policy "Users manage own device token"
on public.device_tokens for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'push_token'
  ) then
    insert into public.device_tokens (user_id, token, apns_env)
    select id, push_token, 'sandbox' from public.profiles where push_token is not null
    on conflict (user_id) do nothing;

    alter table public.profiles drop column push_token;
  end if;
end $$;

-- 1b. İstemci sadece kozmetik alanları yazabilir; xp / matches_* sadece sunucu fonksiyonlarıyla değişir
drop policy if exists "Users can insert/update their own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;

create policy "Users can insert own profile"
on public.profiles for insert to authenticated
with check (auth.uid() = id);

create policy "Users can update own profile"
on public.profiles for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

revoke insert, update, delete on public.profiles from anon, authenticated;
grant insert (id, username, display_name, current_level, avatar_emoji) on public.profiles to authenticated;
grant update (username, display_name, current_level, avatar_emoji, updated_at) on public.profiles to authenticated;

alter table public.profiles drop constraint if exists profiles_display_name_len;
alter table public.profiles add constraint profiles_display_name_len
  check (char_length(display_name) between 1 and 40) not valid;

alter table public.profiles drop constraint if exists profiles_username_len;
alter table public.profiles add constraint profiles_username_len
  check (char_length(username) between 3 and 30) not valid;

-- 1c. Kullanıcı adları küçük harf tutulur (arama küçük harfle yapılıyor, kayıt büyük harf istiyordu)
update public.profiles p
   set username = lower(p.username)
 where p.username <> lower(p.username)
   and not exists (
     select 1 from public.profiles q
      where q.id <> p.id and lower(q.username) = lower(p.username)
   );

-- 1d. Kayıt trigger'ı: küçük harf kullanıcı adı + çakışmada kayıt patlamasın
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_base text;
  v_username text;
begin
  v_base := lower(coalesce(
    nullif(new.raw_user_meta_data->>'username', ''),
    split_part(new.email, '@', 1),
    'user'
  ));
  v_username := v_base;

  while exists (select 1 from public.profiles where username = v_username) loop
    v_username := v_base || '_' || floor(random() * 10000)::text;
  end loop;

  insert into public.profiles (id, username, display_name, current_level, xp, matches_won, matches_played, avatar_emoji)
  values (
    new.id,
    v_username,
    left(coalesce(
      nullif(new.raw_user_meta_data->>'full_name', ''),
      coalesce(new.raw_user_meta_data->>'first_name', 'Yeni') || ' ' || coalesce(new.raw_user_meta_data->>'last_name', 'Kullanıcı')
    ), 40),
    'A1', 0, 0, 0, '🚀'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- =====================================================================
-- 2. FRIENDSHIPS
-- =====================================================================

-- 2a. Veri temizliği: kendine istek ve ters yönlü kopyalar (accepted olan / en eski olan kalır)
delete from public.friendships where sender_id = receiver_id;

delete from public.friendships f
using public.friendships g
where f.id <> g.id
  and least(f.sender_id, f.receiver_id)    = least(g.sender_id, g.receiver_id)
  and greatest(f.sender_id, f.receiver_id) = greatest(g.sender_id, g.receiver_id)
  and (
        (g.status = 'accepted' and f.status <> 'accepted')
     or ((g.status = 'accepted') = (f.status = 'accepted') and (g.created_at, g.id) < (f.created_at, f.id))
  );

create unique index if not exists friendships_pair_uniq
  on public.friendships (least(sender_id, receiver_id), greatest(sender_id, receiver_id));

alter table public.friendships drop constraint if exists friendships_no_self;
alter table public.friendships add constraint friendships_no_self check (sender_id <> receiver_id);

-- 2b. Sadece alıcı cevaplayabilir; gönderen kendi isteğini kabul edemez
drop policy if exists "Users can insert friendships where they are the sender" on public.friendships;
create policy "Users can insert friendships where they are the sender"
on public.friendships for insert to authenticated
with check (auth.uid() = sender_id and status = 'pending');

drop policy if exists "Users can update/delete friendships they belong to" on public.friendships;
drop policy if exists "Receiver can answer friend request" on public.friendships;
create policy "Receiver can answer friend request"
on public.friendships for update to authenticated
using (auth.uid() = receiver_id and status = 'pending')
with check (auth.uid() = receiver_id and status in ('accepted', 'rejected'));

revoke update on public.friendships from anon, authenticated;
grant update (status) on public.friendships to authenticated;

-- 2c. İstek gönder: karşı taraf zaten istek attıysa otomatik kabul et
create or replace function public.send_friend_request(p_receiver uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_existing public.friendships;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_receiver = v_uid then raise exception 'cannot befriend yourself'; end if;

  select * into v_existing from public.friendships
   where least(sender_id, receiver_id) = least(v_uid, p_receiver)
     and greatest(sender_id, receiver_id) = greatest(v_uid, p_receiver)
   for update;

  if found then
    if v_existing.status = 'pending' and v_existing.receiver_id = v_uid then
      update public.friendships set status = 'accepted' where id = v_existing.id;
      return 'accepted';
    elsif v_existing.status = 'rejected' and v_existing.sender_id = v_uid then
      update public.friendships set status = 'pending', created_at = now() where id = v_existing.id;
      return 'pending';
    end if;
    return v_existing.status;
  end if;

  insert into public.friendships (sender_id, receiver_id, status) values (v_uid, p_receiver, 'pending');
  return 'pending';
end;
$$;

-- =====================================================================
-- 3. MATCHES
-- =====================================================================

-- 3a. mode kısıtı: istemci "random_3", "friend_1" gibi değerler yazıyor
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
     where conrelid = 'public.matches'::regclass and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%mode%'
  loop
    execute format('alter table public.matches drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.matches add constraint matches_mode_check
  check (mode ~ '^(random|friend|room|bot)(_[0-9]+)?$') not valid;

alter table public.matches add column if not exists player1_finished boolean not null default false;
alter table public.matches add column if not exists player2_finished boolean not null default false;
alter table public.matches add column if not exists finished_at timestamptz;

create index if not exists matches_lobby_idx on public.matches (status, mode, level, created_at);
create index if not exists matches_room_code_idx on public.matches (room_code) where status = 'waiting';
create index if not exists matches_player2_idx on public.matches (player2_id, status);

-- 3b. Insert'te istemcinin gönderdiği skor/durum/isimlere güvenme
create or replace function public.matches_before_insert()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_p1 public.profiles;
  v_p2 public.profiles;
begin
  select * into v_p1 from public.profiles where id = new.player1_id;
  if not found then raise exception 'profile not found'; end if;

  new.player1_name     := v_p1.display_name;
  new.player1_avatar   := v_p1.avatar_emoji;
  new.player1_score    := 0;
  new.player2_score    := 0;
  new.player1_finished := false;
  new.player2_finished := false;
  new.finished_at      := null;
  new.status           := 'waiting';
  new.winner_id        := null;
  new.created_at       := now();
  new.updated_at       := now();

  if coalesce(cardinality(new.word_ids), 0) > 100 then
    raise exception 'too many words';
  end if;

  if new.mode like 'friend%' then
    if new.player2_id is null then raise exception 'friend invite needs player2_id'; end if;
    if not exists (
      select 1 from public.friendships
       where status = 'accepted'
         and least(sender_id, receiver_id) = least(new.player1_id, new.player2_id)
         and greatest(sender_id, receiver_id) = greatest(new.player1_id, new.player2_id)
    ) then
      raise exception 'can only invite friends';
    end if;
    select * into v_p2 from public.profiles where id = new.player2_id;
    new.player2_name   := v_p2.display_name;
    new.player2_avatar := v_p2.avatar_emoji;
  else
    new.player2_id     := null;
    new.player2_name   := null;
    new.player2_avatar := null;
  end if;

  return new;
end;
$$;

drop trigger if exists tr_matches_before_insert on public.matches;
create trigger tr_matches_before_insert
  before insert on public.matches
  for each row execute function public.matches_before_insert();

-- 3c. Politikalar: sadece katılımcılar görür; tüm durum değişiklikleri RPC ile
drop policy if exists "Users can view open or participating matches" on public.matches;
drop policy if exists "Participants can view match" on public.matches;
create policy "Participants can view match"
on public.matches for select to authenticated
using (auth.uid() = player1_id or auth.uid() = player2_id);

drop policy if exists "Users can create matches" on public.matches;
create policy "Users can create matches"
on public.matches for insert to authenticated
with check (auth.uid() = player1_id);

drop policy if exists "Participants can update match" on public.matches;
revoke update, delete on public.matches from anon, authenticated;

-- 3d. Rastgele eşleşme (atomik: iki kişi aynı maça giremez)
create or replace function public.join_random_match(p_mode text, p_level text)
returns setof public.matches
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_match public.matches;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_mode !~ '^random(_[0-9]+)?$' then raise exception 'invalid mode'; end if;

  select * into v_me from public.profiles where id = v_uid;

  -- Terk edilmiş lobileri ve kendi eski lobilerimi kapat
  update public.matches set status = 'cancelled', updated_at = now()
   where status = 'waiting' and mode like 'random%'
     and (created_at < now() - interval '3 minutes' or player1_id = v_uid);

  select * into v_match from public.matches
   where status = 'waiting' and mode = p_mode and level = p_level
     and player2_id is null and player1_id <> v_uid
   order by created_at
   limit 1
   for update skip locked;

  if not found then return; end if;

  update public.matches
     set player2_id = v_uid, player2_name = v_me.display_name, player2_avatar = v_me.avatar_emoji,
         status = 'in_progress', updated_at = now()
   where id = v_match.id
  returning * into v_match;

  return next v_match;
end;
$$;

-- 3e. Oda koduyla katılma
create or replace function public.join_room_match(p_code text)
returns setof public.matches
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_match public.matches;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;

  select * into v_me from public.profiles where id = v_uid;

  select * into v_match from public.matches
   where status = 'waiting' and mode like 'room%' and room_code = trim(p_code)
     and player2_id is null and player1_id <> v_uid
     and created_at > now() - interval '30 minutes'
   order by created_at desc
   limit 1
   for update skip locked;

  if not found then return; end if;

  update public.matches
     set player2_id = v_uid, player2_name = v_me.display_name, player2_avatar = v_me.avatar_emoji,
         status = 'in_progress', updated_at = now()
   where id = v_match.id
  returning * into v_match;

  return next v_match;
end;
$$;

-- 3f. Arkadaş davetini kabul et
create or replace function public.accept_match_invite(p_match_id uuid)
returns setof public.matches
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_match public.matches;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;

  select * into v_me from public.profiles where id = v_uid;

  update public.matches
     set player2_name = v_me.display_name, player2_avatar = v_me.avatar_emoji,
         status = 'in_progress', updated_at = now()
   where id = p_match_id and player2_id = v_uid and status = 'waiting' and mode like 'friend%'
  returning * into v_match;

  if not found then return; end if;
  return next v_match;
end;
$$;

-- 3g. Bekleyen maçı iptal et / daveti reddet
create or replace function public.cancel_match(p_match_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.matches set status = 'cancelled', updated_at = now()
   where id = p_match_id and status = 'waiting'
     and auth.uid() in (player1_id, player2_id);
end;
$$;

-- 3h. Maçı sonuçlandır (iç fonksiyon, istemciye açık değil)
create or replace function public._finalize_match(p_match_id uuid)
returns public.matches
language plpgsql security definer set search_path = public
as $$
declare
  v_match public.matches;
begin
  update public.matches
     set status = 'completed',
         winner_id = case
           when player1_score > player2_score then player1_id
           when player2_score > player1_score then player2_id
           else null end,
         updated_at = now()
   where id = p_match_id and status = 'in_progress'
  returning * into v_match;

  if found then
    update public.profiles
       set matches_played = matches_played + 1,
           matches_won    = matches_won + case when id = v_match.winner_id then 1 else 0 end,
           xp             = xp + case
                                   when v_match.winner_id is null then 25
                                   when id = v_match.winner_id   then 50
                                   else 15 end,
           updated_at     = now()
     where id in (v_match.player1_id, v_match.player2_id);
  else
    select * into v_match from public.matches where id = p_match_id;
  end if;

  return v_match;
end;
$$;

-- 3i. Skor gönder: her oyuncu bir kez; ikisi de gönderince sunucu kazananı belirler
create or replace function public.submit_match_score(p_match_id uuid, p_score integer)
returns setof public.matches
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_match public.matches;
  v_score integer := greatest(0, least(coalesce(p_score, 0), 100));
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found or v_uid not in (v_match.player1_id, coalesce(v_match.player2_id, v_match.player1_id)) then
    raise exception 'match not found';
  end if;

  if v_match.status = 'in_progress' then
    if v_uid = v_match.player1_id and not v_match.player1_finished then
      update public.matches
         set player1_score = v_score, player1_finished = true,
             finished_at = coalesce(finished_at, now()), updated_at = now()
       where id = p_match_id
      returning * into v_match;
    elsif v_uid = v_match.player2_id and not v_match.player2_finished then
      update public.matches
         set player2_score = v_score, player2_finished = true,
             finished_at = coalesce(finished_at, now()), updated_at = now()
       where id = p_match_id
      returning * into v_match;
    end if;

    if v_match.player1_finished and v_match.player2_finished then
      v_match := public._finalize_match(p_match_id);
    end if;
  end if;

  return next v_match;
end;
$$;

-- 3j. Rakip skor göndermeden çıktıysa 20 sn sonra maçı kapat
create or replace function public.finalize_match(p_match_id uuid)
returns setof public.matches
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_match public.matches;
begin
  select * into v_match from public.matches where id = p_match_id for update;
  if not found or v_uid not in (v_match.player1_id, coalesce(v_match.player2_id, v_match.player1_id)) then
    raise exception 'match not found';
  end if;

  if v_match.status = 'in_progress' and v_match.finished_at < now() - interval '20 seconds' then
    v_match := public._finalize_match(p_match_id);
  end if;

  return next v_match;
end;
$$;

-- =====================================================================
-- 4. ROBOT DÜELLOLARI — sınırlı XP (sıralama robotla şişirilemesin)
-- =====================================================================

create table if not exists public.bot_duel_log (
    id         bigint generated always as identity primary key,
    user_id    uuid not null references public.profiles(id) on delete cascade,
    won        boolean not null,
    created_at timestamptz not null default now()
);
alter table public.bot_duel_log enable row level security;  -- politika yok: sadece fonksiyon yazar
create index if not exists bot_duel_log_user_idx on public.bot_duel_log (user_id, created_at);

create or replace function public.record_bot_duel(p_won boolean)
returns public.profiles
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today integer;
  v_xp integer := 0;
  v_profile public.profiles;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;

  select count(*) into v_today from public.bot_duel_log
   where user_id = v_uid and created_at > now() - interval '24 hours';

  insert into public.bot_duel_log (user_id, won) values (v_uid, coalesce(p_won, false));

  if v_today < 20 then
    v_xp := case when p_won then 20 else 5 end;
  end if;

  update public.profiles set xp = xp + v_xp, updated_at = now()
   where id = v_uid
  returning * into v_profile;

  return v_profile;
end;
$$;

-- =====================================================================
-- 5. FONKSİYON YETKİLERİ
-- =====================================================================

revoke all on function public._finalize_match(uuid)               from public, anon, authenticated;
revoke all on function public.join_random_match(text, text)       from public, anon;
revoke all on function public.join_room_match(text)               from public, anon;
revoke all on function public.accept_match_invite(uuid)           from public, anon;
revoke all on function public.cancel_match(uuid)                  from public, anon;
revoke all on function public.submit_match_score(uuid, integer)   from public, anon;
revoke all on function public.finalize_match(uuid)                from public, anon;
revoke all on function public.record_bot_duel(boolean)            from public, anon;
revoke all on function public.send_friend_request(uuid)           from public, anon;
revoke all on function public.matches_before_insert()             from public, anon, authenticated;
revoke all on function public.handle_new_user()                   from public, anon, authenticated;

grant execute on function public.join_random_match(text, text)     to authenticated;
grant execute on function public.join_room_match(text)             to authenticated;
grant execute on function public.accept_match_invite(uuid)         to authenticated;
grant execute on function public.cancel_match(uuid)                to authenticated;
grant execute on function public.submit_match_score(uuid, integer) to authenticated;
grant execute on function public.finalize_match(uuid)              to authenticated;
grant execute on function public.record_bot_duel(boolean)          to authenticated;
grant execute on function public.send_friend_request(uuid)         to authenticated;

-- =====================================================================
-- 6. PUSH TRIGGER'LARI — secret header ile
-- =====================================================================

create or replace function public._push_webhook_secret()
returns text
language sql security definer set search_path = public
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;
$$;
revoke all on function public._push_webhook_secret() from public, anon, authenticated;

create or replace function public.notify_match_invite()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.player2_id is not null and new.status = 'waiting' and new.mode like 'friend%' then
    perform net.http_post(
      url := 'https://bmzlgmvtybdsyfgpxpgl.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', coalesce(public._push_webhook_secret(), '')
      ),
      body := jsonb_build_object(
        'recipient_user_id', new.player2_id,
        'title', 'Kelime Düellosu Daveti! ⚔️',
        'body', coalesce(new.player1_name, 'Bir arkadaşın') || ' seni kelime düellosuna davet etti!',
        'data', jsonb_build_object('match_id', new.id, 'type', 'match_invite')
      )
    );
  end if;
  return new;
end;
$$;

create or replace function public.notify_friend_request()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  sender_name text;
begin
  if new.status = 'pending' then
    select display_name into sender_name from public.profiles where id = new.sender_id;

    perform net.http_post(
      url := 'https://bmzlgmvtybdsyfgpxpgl.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', coalesce(public._push_webhook_secret(), '')
      ),
      body := jsonb_build_object(
        'recipient_user_id', new.receiver_id,
        'title', 'Yeni Arkadaşlık İsteği! 👋',
        'body', coalesce(sender_name, 'Bir kullanıcı') || ' sana arkadaşlık isteği gönderdi!',
        'data', jsonb_build_object('friendship_id', new.id, 'type', 'friend_request')
      )
    );
  end if;
  return new;
end;
$$;

revoke all on function public.notify_match_invite()   from public, anon, authenticated;
revoke all on function public.notify_friend_request() from public, anon, authenticated;

commit;
