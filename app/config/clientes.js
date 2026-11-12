/*
 * Config isolada dos clientes do CIC.
 * Tudo que é específico de uma operação fica AQUI (e em cic_config no banco de
 * cada cliente). A lógica do app não conhece nenhum cliente pelo nome.
 *
 * chavePublica = chave publishable do Supabase (pode ficar no front; o acesso
 * aos dados é controlado por RLS). NUNCA colocar a service role aqui.
 *
 * Login espelhado: o app tenta o mesmo e-mail e senha em todos os clientes e só
 * mostra o seletor quando a pessoa tem perfil ativo em mais de um.
 */
window.CIC_CLIENTES = [
  {
    slug: 'martha-guterres',
    nome: 'Martha Guterres',
    supabaseUrl: 'https://zrvrfxhzwzumvetgjure.supabase.co',
    chavePublica: 'sb_publishable_4ALB8vtUZGvMeX2KXpXjOQ_EP-YjrE8'
  },
  {
    slug: 'vanessa-oliveira',
    nome: 'Vanessa Oliveira',
    supabaseUrl: 'https://otwxprouwlihkihtrbeq.supabase.co',
    chavePublica: 'sb_publishable_IjpYWtCULX4o7OWvODoEBg_9XVw4Z1Q'
  }
];
