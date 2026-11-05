-- =====================================================================
-- 0007 · Ajustes após os primeiros eventos reais (04/11/2026)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Diagnóstico: varredura de 04/11 ~22h40 (182 vendas Hubla, 7 eventos CRM)
--
-- 1. hubla_vendas: evento fora de ordem não pode sobrescrever estado mais novo
--    (ex.: "paid" voltando pra "unpaid"). Atualização só passa se
--    invoice_modified_at for igual ou mais novo que o gravado.
-- 2. unnichat_eventos: colunas negocio_id e etapa_desde (vêm em data.Etapa[]
--    e são a base do Ciclo de vendas).
-- 3. Corrige os eventos já gravados a partir do raw_payload:
--    etapa (columnName), status, motivo de perda, pipeline, data real do
--    evento (eventDate em segundos), negocio_id e etapa_desde.
-- 4. Remove o carrinho de teste ("Produto teste-cic").
-- =====================================================================

-- 1. Guarda contra evento fora de ordem
create or replace function public.hubla_vendas_ignora_antigo()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.invoice_modified_at is not null
     and new.invoice_modified_at is not null
     and new.invoice_modified_at < old.invoice_modified_at then
    return null;  -- evento mais velho que o gravado: ignora a atualização
  end if;
  return new;
end $$;

create trigger trg_hubla_vendas_ignora_antigo
  before update on public.hubla_vendas
  for each row execute function public.hubla_vendas_ignora_antigo();

-- 2. Colunas do negócio no CRM
alter table public.unnichat_eventos
  add column negocio_id  text,
  add column etapa_desde timestamptz;

create index on public.unnichat_eventos (negocio_id, etapa_desde);

-- 3. Corrige os eventos já gravados (usa o negócio com entrada mais recente na etapa)
with neg as (
  select e.id,
         s.el,
         to_timestamp(nullif(e.raw_payload #>> '{data,eventDate}', '')::bigint) as ts_real
  from public.unnichat_eventos e
  cross join lateral (
    select el from jsonb_array_elements(
      case when jsonb_typeof(e.raw_payload #> '{data,Etapa}') = 'array'
           then e.raw_payload #> '{data,Etapa}' else '[]'::jsonb end) el
    order by (el ->> 'attributedIn')::timestamptz desc nulls last
    limit 1
  ) s
)
update public.unnichat_eventos e
   set etapa_crm    = nullif(neg.el ->> 'columnName', ''),
       status       = nullif(neg.el ->> 'status', ''),
       motivo_perda = nullif(neg.el ->> 'reasonLossDescription', ''),
       pipeline     = coalesce(nullif(neg.el ->> 'pipelineName', ''), e.pipeline),
       negocio_id   = nullif(neg.el ->> 'id', ''),
       etapa_desde  = (neg.el ->> 'attributedIn')::timestamptz,
       event_ts     = coalesce(neg.ts_real, e.event_ts)
  from neg
 where neg.id = e.id;

-- 4. Carrinho de teste
delete from public.hubla_carrinho_abandonado where product_name = 'Produto teste-cic';
