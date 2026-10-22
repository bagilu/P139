-- Run in Supabase SQL Editor as the project owner if bagilu@gmail.com can manage a group
-- but the group-creation panel is unavailable. This is idempotent and does not change group data.
DO $$
DECLARE v_user_id uuid;
BEGIN
  SELECT id INTO v_user_id FROM auth.users WHERE lower(email)=lower('bagilu@gmail.com') LIMIT 1;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'bagilu@gmail.com is not registered in this Supabase Auth project';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public."TblP139Membership"
    WHERE user_id=v_user_id AND role='admin' AND is_active
  ) AND NOT EXISTS (
    SELECT 1 FROM public."TblP139SystemAdmin" WHERE user_id=v_user_id
  ) THEN
    RAISE EXCEPTION 'bagilu@gmail.com is not an active P139 group administrator';
  END IF;
  INSERT INTO public."TblP139SystemAdmin"(user_id)
  VALUES(v_user_id) ON CONFLICT(user_id) DO NOTHING;
END;
$$;
