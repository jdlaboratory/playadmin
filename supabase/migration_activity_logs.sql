-- 활동 내역(스탬프 적립 / 쿠폰 사용) 로그 추가 마이그레이션
-- Supabase SQL Editor 에 붙여넣고 Run 하세요. (한 번만)

-- ── 1. 내역 테이블 ────────────────────────────────────────
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

-- ── 2. 스탬프 적립 RPC: 내역 기록 추가 ────────────────────
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

  insert into public.activity_logs (phone, kind, amount, stamps_after, coupons_after)
  values (p_phone, 'stamp', p_count, result.stamps, result.coupons);

  return result;
end; $$;

-- ── 3. 쿠폰 사용 RPC: 내역 기록 추가 ──────────────────────
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

  insert into public.activity_logs (phone, kind, amount, stamps_after, coupons_after)
  values (p_phone, 'coupon_use', -1, result.stamps, result.coupons);

  return result;
end; $$;
