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

-- ── 3. 스탬프 적립 RPC (원자적) ───────────────────────────
-- 전화번호가 없으면 새로 만들고, 있으면 스탬프를 더한 뒤
-- 10개마다 쿠폰 1개로 전환하고 나머지를 잔여값으로 둔다.
create or replace function public.add_stamps(p_phone text, p_count integer)
returns public.customers
language plpgsql
security invoker
as $$
declare
  total integer;
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

  update public.customers
     set stamps  = total % 10,
         coupons = coupons + (total / 10)
   where phone = p_phone
  returning * into result;

  return result;
end; $$;

-- ── 4. 쿠폰 사용 RPC (원자적) ─────────────────────────────
create or replace function public.use_coupon(p_phone text)
returns public.customers
language plpgsql
security invoker
as $$
declare
  result public.customers;
  cur integer;
begin
  select coupons into cur from public.customers where phone = p_phone for update;
  if cur is null then
    raise exception '등록되지 않은 전화번호입니다';
  end if;
  if cur <= 0 then
    raise exception '보유한 쿠폰이 없습니다';
  end if;

  update public.customers
     set coupons      = coupons - 1,
         coupons_used = coupons_used + 1
   where phone = p_phone
  returning * into result;

  return result;
end; $$;
