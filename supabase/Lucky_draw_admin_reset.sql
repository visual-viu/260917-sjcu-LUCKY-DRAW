CREATE OR REPLACE FUNCTION public.reset_lucky_draw()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.winners where true;
  delete from public.draw_logs where true;

  update public.prizes
  set remaining_qty = total_qty
  where true;

  return jsonb_build_object(
    'success', true
  );
end;
$function$