-- NOT: Bu dosya ilk kurulum şemasıdır. Sonraki değişiklikler supabase/migrations/ altındadır
-- ve bu dosyadan SONRA sırayla çalıştırılmalıdır (RLS / RPC / push güvenliği oradadır).

-- 1. Create Profiles Table (extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    current_level TEXT DEFAULT 'A1',
    xp INTEGER DEFAULT 0,
    matches_won INTEGER DEFAULT 0,
    matches_played INTEGER DEFAULT 0,
    avatar_emoji TEXT DEFAULT '🚀',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Ensure columns exist if table was already created earlier
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS matches_won INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS matches_played INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_emoji TEXT DEFAULT '🚀';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS current_level TEXT DEFAULT 'A1';

-- 2. Enable Row Level Security (RLS) on Profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 3. Create RLS Policies for Profiles
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
CREATE POLICY "Public profiles are viewable by everyone" 
ON public.profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert/update their own profile" ON public.profiles;
CREATE POLICY "Users can insert/update their own profile" 
ON public.profiles FOR ALL USING (auth.uid() = id);

-- 4. Create Friendships Table
CREATE TABLE IF NOT EXISTS public.friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE (sender_id, receiver_id)
);

-- 5. Enable RLS on Friendships
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- 6. Create RLS Policies for Friendships
DROP POLICY IF EXISTS "Users can view their own friendships" ON public.friendships;
CREATE POLICY "Users can view their own friendships" 
ON public.friendships FOR SELECT 
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

DROP POLICY IF EXISTS "Users can insert friendships where they are the sender" ON public.friendships;
CREATE POLICY "Users can insert friendships where they are the sender" 
ON public.friendships FOR INSERT 
WITH CHECK (auth.uid() = sender_id);

DROP POLICY IF EXISTS "Users can update/delete friendships they belong to" ON public.friendships;
CREATE POLICY "Users can update/delete friendships they belong to" 
ON public.friendships FOR UPDATE 
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

DROP POLICY IF EXISTS "Users can delete friendships they belong to" ON public.friendships;
CREATE POLICY "Users can delete friendships they belong to" 
ON public.friendships FOR DELETE 
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- 7. Create Matches (1v1 Duels / Quiz Matchmaking) Table
CREATE TABLE IF NOT EXISTS public.matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_code TEXT,
    player1_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    player2_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    player1_name TEXT NOT NULL,
    player2_name TEXT,
    player1_avatar TEXT DEFAULT '🚀',
    player2_avatar TEXT DEFAULT '🤖',
    player1_score INTEGER DEFAULT 0,
    player2_score INTEGER DEFAULT 0,
    status TEXT DEFAULT 'waiting' CHECK (status IN ('waiting', 'in_progress', 'completed', 'cancelled')),
    winner_id UUID REFERENCES public.profiles(id),
    mode TEXT DEFAULT 'random' CHECK (mode IN ('random', 'friend', 'room', 'bot')),
    level TEXT DEFAULT 'A1',
    word_ids TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 8. Enable RLS on Matches
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view open or participating matches" ON public.matches;
CREATE POLICY "Users can view open or participating matches" 
ON public.matches FOR SELECT 
USING (status = 'waiting' OR auth.uid() = player1_id OR auth.uid() = player2_id);

DROP POLICY IF EXISTS "Users can create matches" ON public.matches;
CREATE POLICY "Users can create matches" 
ON public.matches FOR INSERT 
WITH CHECK (auth.uid() = player1_id);

DROP POLICY IF EXISTS "Participants can update match" ON public.matches;
CREATE POLICY "Participants can update match" 
ON public.matches FOR UPDATE 
USING (auth.uid() = player1_id OR auth.uid() = player2_id);

-- 9. Automatically create profile row when user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, username, display_name, current_level, xp, matches_won, matches_played, avatar_emoji)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'username', lower(split_part(new.email, '@', 1)) || '_' || floor(random() * 1000)::text),
    COALESCE(new.raw_user_meta_data->>'full_name', COALESCE(new.raw_user_meta_data->>'first_name', 'Yeni') || ' ' || COALESCE(new.raw_user_meta_data->>'last_name', 'Kullanıcı')),
    'A1',
    0,
    0,
    0,
    '🚀'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 10. Enable Supabase Realtime for live multiplayer updates
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'matches'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.matches;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'profiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  END IF;
END $$;

-- 11. Add push_token column to profiles table
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS push_token TEXT;

-- 12. APNs Push Notification Triggers via pg_net (Calls Supabase Edge Function send-push)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.notify_match_invite()
RETURNS TRIGGER AS $$
DECLARE
  sender_name TEXT;
BEGIN
  -- Send notification when an invite is created for player 2
  IF NEW.player2_id IS NOT NULL AND NEW.status = 'waiting' THEN
    SELECT display_name INTO sender_name FROM public.profiles WHERE id = NEW.player1_id;
    
    PERFORM net.http_post(
      url := 'https://bmzlgmvtybdsyfgpxpgl.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'recipient_user_id', NEW.player2_id,
        'title', 'Kelime Düellosu Daveti! ⚔️',
        'body', COALESCE(sender_name, 'Bir arkadaşın') || ' seni kelime düellosuna davet etti!',
        'data', jsonb_build_object('match_id', NEW.id, 'type', 'match_invite')
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_notify_match_invite ON public.matches;
CREATE TRIGGER tr_notify_match_invite
  AFTER INSERT ON public.matches
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_match_invite();

CREATE OR REPLACE FUNCTION public.notify_friend_request()
RETURNS TRIGGER AS $$
DECLARE
  sender_name TEXT;
BEGIN
  IF NEW.status = 'pending' THEN
    SELECT display_name INTO sender_name FROM public.profiles WHERE id = NEW.sender_id;
    
    PERFORM net.http_post(
      url := 'https://bmzlgmvtybdsyfgpxpgl.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'recipient_user_id', NEW.receiver_id,
        'title', 'Yeni Arkadaşlık İsteği! 👋',
        'body', COALESCE(sender_name, 'Bir kullanıcı') || ' sana arkadaşlık isteği gönderdi!',
        'data', jsonb_build_object('friendship_id', NEW.id, 'type', 'friend_request')
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_notify_friend_request ON public.friendships;
CREATE TRIGGER tr_notify_friend_request
  AFTER INSERT ON public.friendships
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_friend_request();


