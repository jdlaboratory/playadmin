-- 기존(마이그레이션된) 고객들의 '최근 수정일' 기본값을 2025-01-01 00:00(KST)로 맞춥니다.
-- 한 번만 실행하세요. (이후 스탬프/쿠폰/수정 시에는 실제 시각으로 자동 갱신됩니다)
-- updated_at 자동 갱신 트리거를 잠시 끄고 값을 넣은 뒤 다시 켭니다.

alter table public.customers disable trigger trg_customers_touch;

update public.customers
   set updated_at = '2025-01-01 00:00:00+09';

alter table public.customers enable trigger trg_customers_touch;
