-- 1. Create Profiles Table (extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    current_level TEXT DEFAULT 'A1',
    xp INTEGER DEFAULT 0,
    avatar_emoji TEXT DEFAULT '🚀',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Enable Row Level Security (RLS) on Profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 3. Create RLS Policies for Profiles
CREATE POLICY "Public profiles are viewable by everyone" 
ON public.profiles FOR SELECT USING (true);

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
CREATE POLICY "Users can view their own friendships" 
ON public.friendships FOR SELECT 
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can insert friendships where they are the sender" 
ON public.friendships FOR INSERT 
WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update/delete friendships they belong to" 
ON public.friendships FOR UPDATE 
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can delete friendships they belong to" 
ON public.friendships FOR DELETE 
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- 7. Automatically create profile row when user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, username, display_name, current_level, xp, avatar_emoji)
  VALUES (
    new.id,
    lower(split_part(new.email, '@', 1)) || '_' || floor(random() * 1000)::text,
    COALESCE(new.raw_user_meta_data->>'first_name', 'Yeni') || ' ' || COALESCE(new.raw_user_meta_data->>'last_name', 'Kullanıcı'),
    'A1',
    0,
    '🚀'
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
