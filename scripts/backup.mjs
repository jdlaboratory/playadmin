// Supabase 데이터 백업 스크립트 (GitHub Actions에서 매일 실행)
// customers, activity_logs 테이블 전체를 CSV + JSON으로 backup/ 폴더에 저장한다.
// 필요한 환경변수: SUPABASE_URL, SUPABASE_SECRET_KEY (RLS 우회 가능한 secret/service_role 키)
import { createClient } from "@supabase/supabase-js";
import { writeFileSync, mkdirSync } from "fs";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SECRET_KEY;
if (!url || !key) {
  console.error("SUPABASE_URL / SUPABASE_SECRET_KEY 환경변수가 필요합니다.");
  process.exit(1);
}
const sb = createClient(url, key, { auth: { persistSession: false } });

async function fetchAll(table) {
  const all = [];
  const PAGE = 1000;
  let from = 0;
  while (true) {
    const { data, error } = await sb.from(table).select("*").order("id").range(from, from + PAGE - 1);
    if (error) throw new Error(`${table}: ${error.message}`);
    all.push(...data);
    if (data.length < PAGE) break;
    from += PAGE;
  }
  return all;
}

function toCsv(rows) {
  if (!rows.length) return "";
  const cols = Object.keys(rows[0]);
  const esc = (v) => (v == null ? "" : /[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v));
  return "﻿" + cols.join(",") + "\n" + rows.map((r) => cols.map((c) => esc(r[c])).join(",")).join("\n") + "\n";
}

const date = new Date().toLocaleDateString("sv-SE", { timeZone: "Asia/Seoul" }); // YYYY-MM-DD (KST)
mkdirSync("backup", { recursive: true });

for (const table of ["customers", "activity_logs"]) {
  const rows = await fetchAll(table);
  writeFileSync(`backup/${table}_${date}.csv`, toCsv(rows));
  writeFileSync(`backup/${table}_${date}.json`, JSON.stringify(rows));
  console.log(`${table}: ${rows.length}건 백업`);
}
console.log(`백업 완료 (${date} KST)`);
