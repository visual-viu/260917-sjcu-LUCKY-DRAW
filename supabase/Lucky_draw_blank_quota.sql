-- =========================================================
-- AI창작학과 Lucky Draw
-- "꽝(비당첨)" 수량 고정 패치
-- 기존 draw_lucky_prize()는 매 추첨마다 50% 확률로 꽝을 뽑았음.
-- 이제 꽝도 상품처럼 총 수량/남은 수량을 갖는 prizes 테이블의
-- 특수 행(id='blank')으로 관리하고, 추첨은 "남아있는 상품 수량 + 남아있는
-- 꽝 수량"에 비례한 가중치로 뽑는다. 꽝 수량이 소진되면 더 이상 꽝이
-- 나오지 않는다 (남은 추첨은 전부 상품 당첨).
-- Supabase SQL Editor에서 이 파일 전체를 1회 실행하면 됨.
-- =========================================================

-- ---------------------------------------------------------
-- 1. prizes 테이블에 꽝 여부 컬럼 추가
-- ---------------------------------------------------------
alter table public.prizes
  add column if not exists is_blank boolean not null default false;

-- ---------------------------------------------------------
-- 2. 꽝 전용 행 생성 (id='blank' 고정)
-- 총/남은 수량은 기본 0 → 운영자가 어드민 페이지에서 직접 설정하기 전까지는
-- 꽝이 나오지 않음 (전부 당첨).
-- ---------------------------------------------------------
insert into public.prizes (
  id, name, total_qty, remaining_qty, display_order, is_active, is_blank
)
values (
  'blank', '꽝', 0, 0, 9999, true, true
)
on conflict (id) do update
set is_blank = true;

-- ---------------------------------------------------------
-- 3. 추첨 함수 교체
-- - 활성 상태이며 remaining_qty > 0 인 모든 행(상품 + 꽝)을 잠그고
--   remaining_qty 합계를 모수로 가중치 추첨한다.
-- - 꽝 행이 뽑히면 즉시 remaining_qty를 1 차감한다 (꽝은 등록 절차가
--   없으므로 뽑히는 즉시 소모해야 총 개수가 정확히 지켜짐).
-- - 상품 행이 뽑혀도 재고는 차감하지 않는다 (기존과 동일하게
--   register_winner()에서 당첨자 이름을 등록할 때 차감됨).
-- - 상품+꽝 재고가 모두 0이면 sold_out.
-- ---------------------------------------------------------
create or replace function public.draw_lucky_prize()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pool integer;
  v_pick integer;
  v_running integer := 0;
  v_row record;
  v_chosen_id text;
  v_chosen_name text;
  v_chosen_is_blank boolean;
begin
  -- 동시 추첨 시 가중치 합계가 일관되도록 후보 행을 모두 잠근다
  perform 1
  from public.prizes
  where is_active = true and remaining_qty > 0
  for update;

  select coalesce(sum(remaining_qty), 0)
  into v_pool
  from public.prizes
  where is_active = true and remaining_qty > 0;

  if v_pool <= 0 then
    insert into public.draw_logs (result, prize_id, prize_name)
    values ('lose', null, null);

    return jsonb_build_object('result', 'sold_out');
  end if;

  v_pick := floor(random() * v_pool)::int + 1;

  for v_row in
    select id, name, is_blank, remaining_qty
    from public.prizes
    where is_active = true and remaining_qty > 0
    order by display_order asc, id asc
  loop
    v_running := v_running + v_row.remaining_qty;
    if v_pick <= v_running then
      v_chosen_id := v_row.id;
      v_chosen_name := v_row.name;
      v_chosen_is_blank := v_row.is_blank;
      exit;
    end if;
  end loop;

  if v_chosen_is_blank then
    update public.prizes
    set remaining_qty = remaining_qty - 1
    where id = v_chosen_id;

    insert into public.draw_logs (result, prize_id, prize_name)
    values ('lose', null, null);

    return jsonb_build_object('result', 'lose');
  end if;

  insert into public.draw_logs (result, prize_id, prize_name)
  values ('prize', v_chosen_id, v_chosen_name);

  return jsonb_build_object(
    'result', 'prize',
    'prize_id', v_chosen_id,
    'prize_name', v_chosen_name
  );
end;
$$;

-- register_winner / adjust_prize_stock / delete_winner / reset_lucky_draw 는
-- prizes.id 를 그대로 사용하는 범용 로직이라 수정 없이 'blank' 행에도
-- 그대로 재사용된다 (adjust_prize_stock으로 꽝 수량 +/-, reset_lucky_draw로
-- 꽝 remaining_qty도 total_qty로 함께 초기화됨).
