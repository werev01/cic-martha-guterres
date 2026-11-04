/*
 * Config isolada dos clientes do CIC.
 * Tudo que é específico de uma operação fica AQUI (e em cic_config no banco de
 * cada cliente). A lógica do app não conhece nenhum cliente pelo nome.
 *
 * chavePublica = chave publishable do Supabase (pode ficar no front; o acesso
 * aos dados é controlado por RLS). NUNCA colocar a service role aqui.
 *
 * Com mais de um cliente na lista, o app mostra o seletor antes do login.
 */
window.CIC_CLIENTES = [
  {
    slug: 'martha-guterres',
    nome: 'Martha Guterres',
    supabaseUrl: 'https://zrvrfxhzwzumvetgjure.supabase.co',
    chavePublica: 'sb_publishable_4ALB8vtUZGvMeX2KXpXjOQ_EP-YjrE8'
  }
];
