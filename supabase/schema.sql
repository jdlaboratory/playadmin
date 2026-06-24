-- 플레이영 고객관리 DB 스키마
-- Supabase 대시보드 > SQL Editor 에 붙여넣고 실행하세요.

-- ── 1. 테이블 ─────────────────────────────────────────────
create table if not exists public.customers (
  id           uuid primary key default gen_random_uuid(),
  phone        text not null unique,
  stamps       integer not null default 0 check (stamps >= 0),
  coupons      integer not null default 0 check (coupons >= 0),
  coupons_used integer not null default 0 check (coupons_used >= 0),
  name         text not null default '',
  memo         text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists customers_phone_idx on public.customers (phone);

-- updated_at 자동 갱신
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

drop trigger if exists trg_customers_touch on public.customers;
create trigger trg_customers_touch
  before update on public.customers
  for each row execute function public.touch_updated_at();

-- ── 2. 보안(RLS): 로그인한 사용자만 접근 ──────────────────
alter table public.customers enable row level security;

drop policy if exists "authenticated_all" on public.customers;
create policy "authenticated_all" on public.customers
  for all
  to authenticated
  using (true)
  with check (true);

-- ── 3. 활동 내역(스탬프 적립 / 쿠폰 사용) 로그 ────────────
create table if not exists public.activity_logs (
  id            uuid primary key default gen_random_uuid(),
  phone         text not null,
  kind          text not null,            -- 'stamp'(적립) | 'coupon_use'(쿠폰사용)
  amount        integer not null,         -- 적립: +N, 쿠폰사용: -1
  stamps_after  integer,                  -- 처리 후 스탬프 잔여값
  coupons_after integer,                  -- 처리 후 보유 쿠폰
  created_at    timestamptz not null default now()
);

create index if not exists activity_logs_phone_created_idx
  on public.activity_logs (phone, created_at desc);

alter table public.activity_logs enable row level security;

drop policy if exists "authenticated_all" on public.activity_logs;
create policy "authenticated_all" on public.activity_logs
  for all to authenticated using (true) with check (true);

-- ── 4. 쿠폰 테이블(1장=1행, 발급일 기록) + 보유유효/만료 집계 뷰 ──
create table if not exists public.coupons (
  id         uuid primary key default gen_random_uuid(),
  phone      text not null,
  issued_at  timestamptz not null default now(),  -- 발급일 (유효기간 = +2년)
  created_at timestamptz not null default now()
);
create index if not exists coupons_phone_idx on public.coupons(phone);

alter table public.coupons enable row level security;
drop policy if exists "authenticated_all" on public.coupons;
create policy "authenticated_all" on public.coupons
  for all to authenticated using (true) with check (true);

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

-- ── 5. 스탬프 적립 RPC: 쿠폰 생기면 coupons 테이블에 행 추가 ──
create or replace function public.add_stamps(p_phone text, p_count integer)
returns public.customers
language plpgsql security invoker as $$
declare
  total integer; gained integer; result public.customers;
begin
  if p_count is null or p_count <= 0 then
    raise exception '적립할 스탬프 수는 1 이상이어야 합니다';
  end if;
  insert into public.customers (phone, stamps) values (p_phone, 0)
    on conflict (phone) do nothing;
  select stamps into total from public.customers where phone = p_phone for update;
  total := total + p_count;
  gained := total / 10;
  update public.customers
     set stamps = total % 10, coupons = coupons + gained
   where phone = p_phone returning * into result;
  if gained > 0 then
    insert into public.coupons (phone, issued_at)
    select p_phone, now() from generate_series(1, gained);
  end if;
  insert into public.activity_logs (phone, kind, amount, stamps_after, coupons_after)
  values (p_phone, 'stamp', p_count, result.stamps, result.coupons);
  return result;
end; $$;

-- ── 6. 쿠폰 사용 RPC: 가장 오래된 '유효기간 내' 쿠폰 1장 사용 ──
create or replace function public.use_coupon(p_phone text)
returns public.customers
language plpgsql security invoker as $$
declare
  v_id uuid; result public.customers; total_cnt integer; valid_cnt integer;
begin
  select count(*) into total_cnt from public.coupons where phone = p_phone;
  select count(*) into valid_cnt from public.coupons
   where phone = p_phone and issued_at > now() - interval '2 years';
  if total_cnt = 0 then raise exception '보유한 쿠폰이 없습니다'; end if;
  if valid_cnt = 0 then raise exception '유효기간이 지난 쿠폰만 있어 사용할 수 없습니다'; end if;
  select id into v_id from public.coupons
   where phone = p_phone and issued_at > now() - interval '2 years'
   order by issued_at asc limit 1 for update;
  delete from public.coupons where id = v_id;
  update public.customers
     set coupons = coupons - 1, coupons_used = coupons_used + 1
   where phone = p_phone returning * into result;
  insert into public.activity_logs (phone, kind, amount, stamps_after, coupons_after)
  values (p_phone, 'coupon_use', -1, result.stamps, result.coupons);
  return result;
end; $$;
