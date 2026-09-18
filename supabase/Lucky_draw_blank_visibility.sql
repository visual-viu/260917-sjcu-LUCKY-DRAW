-- =========================================================
-- AI창작학과 Lucky Draw
-- "꽝" 공개 여부 토글 패치
-- 운영자 페이지에서 꽝(id='blank')을 Hall/Draw 페이지에 노출할지
-- 선택할 수 있도록 prizes 테이블에 is_visible 컬럼을 추가한다.
-- 이 값은 순수 표시 여부일 뿐 추첨 로직(draw_lucky_prize)에는
-- 영향을 주지 않는다 — 꽝은 is_visible 값과 무관하게 항상 정해진
-- 수량만큼 소모된다.
-- Supabase SQL Editor에서 이 파일 전체를 1회 실행하면 됨.
-- =========================================================

alter table public.prizes
  add column if not exists is_visible boolean not null default false;
