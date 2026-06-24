-- 쿠폰 유효기간(발급일 + 2년) 관리 마이그레이션
-- 방식: 보유 쿠폰을 1장씩 행으로 추적(발급일 기록). 만료는 표시만(데이터 보존).
-- Supabase SQL Editor 에 붙여넣고 Run 하세요. (한 번만)

-- ── 1. 쿠폰 테이블 (현재 보유중인 '미사용' 쿠폰 1장 = 1행) ──
create table if not exists public.coupons (
  id         uuid primary key default gen_random_uuid(),
  phone      text not null,
  issued_at  timestamptz not null default now(),  -- 발급일
  created_at timestamptz not null default now()
);
create index if not exists coupons_phone_idx on public.coupons(phone);

alter table public.coupons enable row level security;
drop policy if exists "authenticated_all" on public.coupons;
create policy "authenticated_all" on public.coupons
  for all to authenticated using (true) with check (true);

-- ── 2. 기존 보유 쿠폰을 1장씩 행으로 백필 (발급일 없음 → 오늘) ──
--     coupons 테이블이 비어있을 때(최초 1회)만 실행되어 중복 방지
insert into public.coupons (phone, issued_at)
select c.phone, now()
from public.customers c
cross join lateral generate_series(1, c.coupons) g
where c.coupons > 0
  and not exists (select 1 from public.coupons);

-- ── 3. 보유(유효)/만료 집계 뷰 ──
--     coupons_valid: 발급 2년 이내(사용 가능) / coupons_expired: 2년 초과(만료)
--     security_invoker=on → 호출자 권한으로 실행되어 RLS(로그인 필요)가 그대로 적용됨
create or replace view public.customer_view
  with (security_invoker = true)
as
select c.*,
  coalesce(cc.valid, 0)   as coupons_valid,
  coalesce(cc.expired, 0) as coupons_expired
from public.customers c
left join (
  select phone,
    count(*) filter (where issued_at >  now() - interval '2 years') as valid,
    count(*) filter (where issued_at <= now() - interval '2 years') as expired
  from public.coupons
  group by phone
) cc on cc.phone = c.phone;

grant select on public.customer_view to authenticated;

-- ── 4. 스탬프 적립 RPC: 새로 생긴 쿠폰을 1장씩 행으로 추가 ──
create or replace function public.add_stamps(p_phone text, p_count integer)
returns public.customers
language plpgsql security invoker as $$
declare
  total  integer;
  gained integer;
  result public.customers;
begin
  if p_count is null or p_count <= 0 then
    raise exception '적립할 스탬프 수는 1 이상이어야 합니다';
  end if;

  insert into public.customers (phone, stamps)
  values (p_phone, 0)
  on conflict (phone) do nothing;

  select stamps into total from public.customers where phone = p_phone for update;
  total := total + p_count;
  gained := total / 10;

  update public.customers
     set stamps  = total % 10,
         coupons = coupons + gained
   where phone = p_phone
  returning * into result;

  if gained > 0 then
    insert into public.coupons (phone, issued_at)
    select p_phone, now() from generate_series(1, gained);
  end if;

  insert into public.activity_logs (phone, kind, amount, stamps_after, coupons_after)
  values (p_phone, 'stamp', p_count, result.stamps, result.coupons);

  return result;
end; $$;

-- ── 5. 쿠폰 사용 RPC: 가장 오래된 '유효기간 내' 쿠폰 1장 사용 ──
create or replace function public.use_coupon(p_phone text)
returns public.customers
language plpgsql security invoker as $$
declare
  v_id      uuid;
  result    public.customers;
  total_cnt integer;
  valid_cnt integer;
begin
  select count(*) into total_cnt from public.coupons where phone = p_phone;
  select count(*) into valid_cnt from public.coupons
   where phone = p_phone and issued_at > now() - interval '2 years';

  if total_cnt = 0 then raise exception '보유한 쿠폰이 없습니다'; end if;
  if valid_cnt = 0 then raise exception '유효기간이 지난 쿠폰만 있어 사용할 수 없습니다'; end if;

  select id into v_id from public.coupons
   where phone = p_phone and issued_at > now() - interval '2 years'
   order by issued_at asc
   limit 1 for update;

  delete from public.coupons where id = v_id;

  update public.customers
     set coupons      = coupons - 1,
         coupons_used = coupons_used + 1
   where phone = p_phone
  returning * into result;

  insert into public.activity_logs (phone, kind, amount, stamps_after, coupons_after)
  values (p_phone, 'coupon_use', -1, result.stamps, result.coupons);

  return result;
end; $$;
