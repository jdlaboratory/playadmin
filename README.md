# 플레이영 고객관리 웹앱

키즈카페(플레이영 용인구갈점) 스탬프·쿠폰 고객관리 프로그램.
전부 **무료**로 운영합니다. (Supabase 무료 DB + GitHub Pages 무료 호스팅)

- 📋 최종 기획안: [기획안.md](기획안.md)
- 🖥 웹앱: [`web/`](web/)
- 🗄 DB 스키마: [`supabase/schema.sql`](supabase/schema.sql)
- 🔄 엑셀 변환 스크립트: [`scripts/transform.py`](scripts/transform.py)

---

## 설치 가이드 (한 번만 설정)

### 1. Supabase 프로젝트 만들기
1. https://supabase.com 가입 → **New project** 생성 (지역: Northeast Asia(Seoul) 권장).
2. 프로젝트가 만들어지면 **Project Settings → API** 에서 다음 두 값을 복사해 둡니다.
   - `Project URL`
   - `anon public` 키

### 2. 테이블·보안·함수 만들기
1. 좌측 **SQL Editor → New query**.
2. [`supabase/schema.sql`](supabase/schema.sql) 내용을 전부 붙여넣고 **Run**.

### 3. 로그인 계정 만들기 (비밀번호 = play1122#)
1. **Authentication → Users → Add user → Create new user**
   - Email: `admin@playadmin.local`
   - Password: `play1122#`
   - **Auto Confirm User** 체크 ✅
3. (선택) **Authentication → Providers → Email** 에서 `Confirm email` 을 꺼두면 편합니다.

### 4. 초기 고객 데이터 넣기 (9,583명)
1. **Table Editor → customers 테이블 → Insert → Import data from CSV**.
2. [`data/customers.csv`](data/customers.csv) 파일 업로드.
   (컬럼: phone, stamps, coupons, coupons_used, name, memo — 자동 매칭됩니다)
   > CSV가 없으면 `python scripts/transform.py` 로 다시 생성할 수 있습니다.

### 5. 앱에 Supabase 정보 입력
[`web/config.js`](web/config.js) 를 열어 1·3단계에서 복사한 값으로 교체:
```js
window.APP_CONFIG = {
  SUPABASE_URL: "https://xxxx.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOi....",
  ADMIN_EMAIL: "admin@playadmin.local",
};
```

### 6. 무료 배포 (GitHub Pages)
1. 이 저장소를 GitHub에 올립니다 (`git push`).
2. GitHub 저장소 → **Settings → Pages** →
   Source: `Deploy from a branch`, Branch: `main` / `/web` 폴더 (또는 root) 선택 → Save.
3. 잠시 후 나오는 주소(`https://아이디.github.io/playadmin/`)로 접속.
4. 비밀번호 `play1122#` 입력 → 사용 시작.

> 로컬에서 먼저 테스트하려면 `web/` 폴더에서 `python -m http.server 8000` 실행 후
> http://localhost:8000 접속. (파일을 직접 더블클릭하면 보안정책상 동작하지 않습니다)

---

## 사용 방법
- **스탬프 입력**: 전화번호 + 적립 개수 → 적립하기. 10개마다 쿠폰 자동 전환.
- **쿠폰 사용**: 전화번호 조회 → 사용하기(1장 차감).
- **고객 목록**: 검색 / 추가 / 수정 / 삭제.

## 보안 메모
- 데이터는 RLS로 보호되어 **로그인(비밀번호 play1122#) 없이는 접근 불가**.
- `anon` 키는 공개되어도 안전한 공개용 키입니다 (커밋해도 무방).
- 비밀번호를 바꾸려면 Supabase **Authentication → Users** 에서 해당 계정 비밀번호를 변경하면 됩니다.
