-- =====================================================================
-- Wordlet — Hesap silme desteği (App Store 5.1.1(v))
--
-- Hesap silme `delete-account` edge function'ı ile yapılır: auth.users satırı silinir,
-- profiles ve ona bağlı her şey (friendships, matches, device_tokens, bot_duel_log)
-- ON DELETE CASCADE ile gider. Tek engel matches.winner_id'ydi: silme kuralı yoktu,
-- bu yüzden bir maç kazanmış kullanıcının profili silinemiyordu.
-- =====================================================================

begin;

do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
     where conrelid = 'public.matches'::regclass and contype = 'f'
       and pg_get_constraintdef(oid) ilike '%(winner_id)%'
  loop
    execute format('alter table public.matches drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.matches
  add constraint matches_winner_id_fkey
  foreign key (winner_id) references public.profiles(id) on delete set null;

commit;
