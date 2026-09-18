-- =========================================================
-- AI창작학과 Lucky Draw
-- Supabase 초기 DB 설정
-- =========================================================

-- UUID 생성용
create extension if not exists pgcrypto;

-- ---------------------------------------------------------
-- 1. 상품 테이블
-- ---------------------------------------------------------
create table if not exists public.prizes (
  id text primary key,
  name text not null,
  total_qty integer not null default 0 check (total_qty >= 0),
  remaining_qty integer not null default 0 check (remaining_qty >= 0),
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- 2. 당첨자 테이블
-- ---------------------------------------------------------
create table if not exists public.winners (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  prize_id text not null references public.prizes(id),
  prize_name text not null,
  won_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- 3. 전체 추첨 로그
-- ---------------------------------------------------------
create table if not exists public.draw_logs (
  id uuid primary key default gen_random_uuid(),
  result text not null check (result in ('prize', 'lose')),
  prize_id text references public.prizes(id),
  prize_name text,
  drawn_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- 4. updated_at 자동 갱신
-- ---------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_prizes_updated_at on public.prizes;

create trigger trg_prizes_updated_at
before update on public.prizes
for each row
execute function public.set_updated_at();

-- ---------------------------------------------------------
-- 5. 초기 상품 데이터
-- ---------------------------------------------------------
insert into public.prizes (
  id,
  name,
  total_qty,
  remaining_qty,
  display_order,
  is_active
)
values
  ('cgv', 'CGV 영화 예매권', 10, 10, 1, true),
  ('boost', '부스트랩 생활용품', 5, 5, 2, true),
  ('magsafe', '캐릭터 굿즈 맥세이프', 10, 10, 3, true)
on conflict (id) do update
set
  name = excluded.name,
  total_qty = excluded.total_qty,
  display_order = excluded.display_order,
  is_active = excluded.is_active;

-- ---------------------------------------------------------
-- 6. RLS 활성화
-- ---------------------------------------------------------
alter table public.prizes enable row level security;
alter table public.winners enable row level security;
alter table public.draw_logs enable row level security;

-- ---------------------------------------------------------
-- 7. 기존 정책 제거
-- ---------------------------------------------------------
drop policy if exists "public read prizes" on public.prizes;
drop policy if exists "public read winners" on public.winners;
drop policy if exists "deny direct prize writes" on public.prizes;
drop policy if exists "deny direct winner writes" on public.winners;
drop policy if exists "deny direct draw log writes" on public.draw_logs;

-- ---------------------------------------------------------
-- 8. 공개 조회만 허용
-- ---------------------------------------------------------
create policy "public read prizes"
on public.prizes
for select
to anon, authenticated
using (true);

create policy "public read winners"
on public.winners
for select
to anon, authenticated
using (true);

-- 직접 insert/update/delete 는 정책을 만들지 않음
-- 즉 브라우저에서 테이블을 직접 수정하지 못하게 함

-- ---------------------------------------------------------
-- 9. 안전한 추첨 함수
-- 동시에 여러 명이 눌러도 재고 중복 방지
-- ---------------------------------------------------------
create or replace function public.draw_lucky_prize()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_roll numeric;
  v_available_count integer;
  v_prize public.prizes%rowtype;
  v_result jsonb;
begin
  -- 활성 + 재고 있는 상품 개수
  select count(*)
  into v_available_count
  from public.prizes
  where is_active = true
    and remaining_qty > 0;

  -- 상품이 모두 소진된 경우
  if v_available_count = 0 then
    insert into public.draw_logs (
      result,
      prize_id,
      prize_name
    )
    values (
      'lose',
      null,
      null
    );

    return jsonb_build_object(
      'result', 'sold_out'
    );
  end if;

  -- 꽝 확률
  -- 현재 약 50%
  -- 숫자가 0.5보다 작으면 꽝
  v_roll := random();

  if v_roll < 0.5 then
    insert into public.draw_logs (
      result,
      prize_id,
      prize_name
    )
    values (
      'lose',
      null,
      null
    );

    return jsonb_build_object(
      'result', 'lose'
    );
  end if;

  -- 상품 1개를 랜덤 선택하면서 행 잠금
  select *
  into v_prize
  from public.prizes
  where is_active = true
    and remaining_qty > 0
  order by random()
  for update skip locked
  limit 1;

  -- 잠금 충돌 등으로 선택 실패한 경우
  if v_prize.id is null then
    insert into public.draw_logs (
      result,
      prize_id,
      prize_name
    )
    values (
      'lose',
      null,
      null
    );

    return jsonb_build_object(
      'result', 'lose'
    );
  end if;

  -- 재고 1 차감
  update public.prizes
  set remaining_qty = remaining_qty - 1
  where id = v_prize.id
    and remaining_qty > 0;

  insert into public.draw_logs (
    result,
    prize_id,
    prize_name
  )
  values (
    'prize',
    v_prize.id,
    v_prize.name
  );

  v_result := jsonb_build_object(
    'result', 'prize',
    'prize_id', v_prize.id,
    'prize_name', v_prize.name,
    'remaining_qty', v_prize.remaining_qty - 1
  );

  return v_result;
end;
$$;

-- ---------------------------------------------------------
-- 10. 당첨자 등록 함수
-- ---------------------------------------------------------
create or replace function public.register_winner(
  p_name text,
  p_prize_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prize_name text;
  v_winner_id uuid;
  v_won_at timestamptz;
begin
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'name_required';
  end if;

  select name
  into v_prize_name
  from public.prizes
  where id = p_prize_id;

  if v_prize_name is null then
    raise exception 'invalid_prize';
  end if;

  insert into public.winners (
    name,
    prize_id,
    prize_name
  )
  values (
    trim(p_name),
    p_prize_id,
    v_prize_name
  )
  returning id, won_at
  into v_winner_id, v_won_at;

  return jsonb_build_object(
    'id', v_winner_id,
    'name', trim(p_name),
    'prize_id', p_prize_id,
    'prize_name', v_prize_name,
    'won_at', v_won_at
  );
end;
$$;

-- ---------------------------------------------------------
-- 11. 관리자용 당첨자 삭제 함수
-- 삭제 시 재고 복구 가능
-- ---------------------------------------------------------
create or replace function public.delete_winner(
  p_winner_id uuid,
  p_restore_stock boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prize_id text;
begin
  select prize_id
  into v_prize_id
  from public.winners
  where id = p_winner_id;

  if v_prize_id is null then
    raise exception 'winner_not_found';
  end if;

  delete from public.winners
  where id = p_winner_id;

  if p_restore_stock = true then
    update public.prizes
    set remaining_qty = least(total_qty, remaining_qty + 1)
    where id = v_prize_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'restored', p_restore_stock
  );
end;
$$;

-- ---------------------------------------------------------
-- 12. 관리자용 재고 직접 조정 함수
-- ---------------------------------------------------------
create or replace function public.adjust_prize_stock(
  p_prize_id text,
  p_delta integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remaining integer;
begin
  update public.prizes
  set remaining_qty = greatest(
    0,
    least(total_qty, remaining_qty + p_delta)
  )
  where id = p_prize_id
  returning remaining_qty
  into v_remaining;

  if v_remaining is null then
    raise exception 'prize_not_found';
  end if;

  return jsonb_build_object(
    'success', true,
    'remaining_qty', v_remaining
  );
end;
$$;

-- ---------------------------------------------------------
-- 13. 전체 초기화 함수
-- ---------------------------------------------------------
create or replace function public.reset_lucky_draw()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.winners;
  delete from public.draw_logs;

  update public.prizes
  set remaining_qty = total_qty;

  return jsonb_build_object(
    'success', true
  );
end;
$$;

-- ---------------------------------------------------------
-- 14. RPC 함수 실행 권한
-- ---------------------------------------------------------
grant execute on function public.draw_lucky_prize() to anon, authenticated;
grant execute on function public.register_winner(text, text) to anon, authenticated;

-- 관리자 함수는 우선 anon 접근 차단
revoke execute on function public.delete_winner(uuid, boolean) from anon;
revoke execute on function public.adjust_prize_stock(text, integer) from anon;
revoke execute on function public.reset_lucky_draw() from anon;

-- ---------------------------------------------------------
-- 15. Realtime publication에 필요한 테이블 추가
-- 이미 등록된 경우 오류 방지를 위해 조건 처리
-- ---------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'prizes'
  ) then
    alter publication supabase_realtime add table public.prizes;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'winners'
  ) then
    alter publication supabase_realtime add table public.winners;
  end if;
end $$;