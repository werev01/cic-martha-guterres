/*
 * CIC · casca do app (acesso + menu por perfil)
 * Nada específico de cliente aqui: clientes vêm de config/clientes.js,
 * perfil e menus vêm do banco de cada cliente (RLS).
 */
(function () {
  'use strict';

  var BUILD = '2026-11-04b';
  var MUDANCAS = 'símbolo WeRev (ampulheta) no login, no menu e como ícone da aba';

  // Telas do MVP: chave (igual a perfil_menus.menu) -> rótulo, descrição e ícone
  var TELAS = {
    home:          { rotulo: 'Home',                  desc: 'Visão geral da operação.' },
    metadomes:     { rotulo: 'Meta do mês',           desc: 'Faturamento líquido contra as faixas bronze, prata e ouro.' },
    mensageria:    { rotulo: 'Mensageria',            desc: 'Disparos, conversas e automações do WhatsApp.' },
    discadora:     { rotulo: 'Discadora',             desc: 'Ligações e produtividade na Callix.' },
    desempenho:    { rotulo: 'Desempenho individual', desc: 'Resultado por vendedor.' },
    minhapagina:   { rotulo: 'Minha página',          desc: 'Seus números no mês.' },
    relatorios:    { rotulo: 'Relatórios',            desc: 'Relatórios da operação.' },
    taxapassagem:  { rotulo: 'Taxa de passagem',      desc: 'Conversão entre as etapas do CRM.' },
    motivosperda:  { rotulo: 'Motivos de perda',      desc: 'Por que os leads saem do funil.' },
    ciclovenda:    { rotulo: 'Ciclo de vendas',       desc: 'Tempo do primeiro contato até a venda.' },
    reembolsos:    { rotulo: 'Reembolsos',            desc: 'Reembolsos e cancelamentos.' }
  };
  // Símbolo WeRev (dois V espelhados, ampulheta). Fonte: assets/marca/simbolo.svg
  var SIMBOLO = 'M590 0 L0 0 L168 460 L4 920 L595 920 L425 460 Z M550 16 L392 460 L555 904 L106 904 L263 460 L100 16 Z';
  var PAPEIS = { admin: 'Administrador', vendedor: 'Vendedor' };

  var $ = function (id) { return document.getElementById(id); };
  var clientes = window.CIC_CLIENTES || [];
  var cliente = null;
  var sb = null;
  var perfil = null;
  var menus = [];

  console.info('[CIC] build ' + BUILD + ' · ' + MUDANCAS);
  $('build-acesso').textContent = 'build ' + BUILD;
  $('build-cic').textContent = 'build ' + BUILD;

  // ---------- utilidades ----------
  function icone(el, nome) {
    var svg = (window.CIC_ICONES || {})[nome];
    if (!svg) return;
    el.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + svg + '</svg>';
  }
  function guardar(chave, valor) { try { localStorage.setItem(chave, valor); } catch (e) {} }
  function ler(chave) { try { return localStorage.getItem(chave); } catch (e) { return null; } }
  function apagar(chave) { try { localStorage.removeItem(chave); } catch (e) {} }

  function mostrarAcesso(view) {
    $('cic').hidden = true;
    $('acesso').hidden = false;
    ['v-seletor', 'v-login', 'v-esqueci', 'v-senha', 'v-sem-acesso'].forEach(function (v) {
      $(v).hidden = v !== view;
    });
    var foco = $(view).querySelector('input');
    if (foco) setTimeout(function () { foco.focus(); }, 30);
  }
  function msg(id, texto, ok) {
    var el = $(id);
    el.textContent = texto || '';
    el.classList.toggle('ok', !!ok);
  }
  function ocupado(btnId, sim, textoOcupado) {
    var b = $(btnId);
    if (sim) { b.dataset.txt = b.textContent; b.textContent = textoOcupado; b.disabled = true; }
    else { b.textContent = b.dataset.txt || b.textContent; b.disabled = false; }
  }
  function traduzErro(e) {
    var m = (e && e.message) || '';
    if (/invalid login credentials/i.test(m)) return 'E-mail ou senha incorretos.';
    if (/email not confirmed/i.test(m)) return 'E-mail ainda não confirmado.';
    if (/rate limit|too many/i.test(m)) return 'Muitas tentativas. Aguarde alguns minutos.';
    if (/should be different/i.test(m)) return 'A nova senha precisa ser diferente da atual.';
    if (/password should be at least/i.test(m)) return 'A senha precisa ter pelo menos 8 caracteres.';
    if (/failed to fetch|network/i.test(m)) return 'Sem conexão com o servidor. Tente de novo.';
    return 'Não deu certo: ' + m;
  }

  // ---------- cliente (operação) ----------
  function escolherCliente(c) {
    cliente = c;
    guardar('cic-cliente', c.slug);
    $('acesso-cliente').textContent = c.nome;
    $('lateral-cliente').textContent = c.nome;
    document.title = 'CIC · ' + c.nome;
    sb = window.supabase.createClient(c.supabaseUrl, c.chavePublica, {
      auth: {
        storageKey: 'cic-auth-' + c.slug,
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        flowType: 'implicit'
      }
    });
  }

  function mostrarSeletor() {
    var lista = $('lista-clientes');
    lista.innerHTML = '';
    clientes.forEach(function (c) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = c.nome;
      b.addEventListener('click', function () { escolherCliente(c); iniciarSessao({}); });
      lista.appendChild(b);
    });
    $('acesso-cliente').textContent = '';
    mostrarAcesso('v-seletor');
  }

  // ---------- leitura do link que chegou por e-mail ----------
  function lerHash() {
    var h = window.location.hash.replace(/^#/, '');
    if (!/(access_token|error_code|type)=/.test(h)) return {};
    var p = {};
    h.split('&').forEach(function (par) {
      var kv = par.split('=');
      p[decodeURIComponent(kv[0])] = decodeURIComponent((kv[1] || '').replace(/\+/g, ' '));
    });
    return p;
  }
  function limparHash() {
    history.replaceState(null, '', window.location.pathname + window.location.search);
  }

  // ---------- sessão ----------
  function iniciarSessao(link) {
    $('trocar-cliente').hidden = clientes.length < 2;

    if (link.error_code || link.error) {
      limparHash();
      mostrarAcesso('v-login');
      msg('login-msg', link.error_code === 'otp_expired'
        ? 'Esse link expirou ou já foi usado. Peça um novo em "Esqueci minha senha".'
        : 'Link inválido. Peça um novo em "Esqueci minha senha".');
      return;
    }

    var veioDeLink = link.type === 'invite' || link.type === 'recovery' || link.type === 'signup';

    sb.auth.getSession().then(function (r) {
      var sessao = r.data && r.data.session;
      if (veioDeLink && sessao) {
        limparHash();
        $('senha-titulo').textContent = link.type === 'recovery' ? 'Crie uma nova senha' : 'Bem-vindo ao CIC';
        $('senha-texto').textContent = link.type === 'recovery'
          ? 'Mínimo de 8 caracteres.'
          : 'Defina sua senha de acesso. Mínimo de 8 caracteres.';
        mostrarAcesso('v-senha');
        return;
      }
      if (veioDeLink) limparHash();
      if (sessao) carregarCic(sessao);
      else mostrarAcesso('v-login');
    });
  }

  function carregarCic(sessao) {
    var uid = sessao.user.id;
    sb.from('perfis').select('nome,papel,ativo').eq('user_id', uid).maybeSingle()
      .then(function (r) {
        if (r.error) throw r.error;
        if (!r.data || !r.data.ativo) { mostrarAcesso('v-sem-acesso'); return null; }
        perfil = r.data;
        return sb.from('perfil_menus').select('menu,ordem').eq('papel', perfil.papel).order('ordem');
      })
      .then(function (r) {
        if (!r) return;
        if (r.error) throw r.error;
        menus = r.data.map(function (m) { return m.menu; }).filter(function (m) { return TELAS[m]; });
        if (!menus.length) { mostrarAcesso('v-sem-acesso'); return; }
        montarCic();
      })
      .catch(function (e) {
        mostrarAcesso('v-login');
        msg('login-msg', traduzErro(e));
      });
  }

  // ---------- CIC ----------
  function montarCic() {
    $('usuario-nome').textContent = perfil.nome;
    $('usuario-papel').textContent = PAPEIS[perfil.papel] || perfil.papel;
    var nav = $('menu');
    nav.innerHTML = '';
    menus.forEach(function (m) {
      var a = document.createElement('a');
      a.href = '#/' + m;
      a.dataset.menu = m;
      var ic = document.createElement('span');
      ic.className = 'ic';
      icone(ic, m);
      var tx = document.createElement('span');
      tx.textContent = TELAS[m].rotulo;
      a.appendChild(ic);
      a.appendChild(tx);
      nav.appendChild(a);
    });
    $('acesso').hidden = true;
    $('cic').hidden = false;
    rota();
  }

  function rota() {
    if (!perfil) return;
    var m = (window.location.hash.match(/^#\/([a-z]+)/) || [])[1];
    if (menus.indexOf(m) < 0) {
      m = menus[0];
      history.replaceState(null, '', '#/' + m);
    }
    var t = TELAS[m];
    $('tela-titulo').textContent = t.rotulo;
    $('tela-desc').textContent = t.desc;
    icone($('tela-icone'), m);
    Array.prototype.forEach.call(document.querySelectorAll('.menu a'), function (a) {
      a.classList.toggle('ativo', a.dataset.menu === m);
    });
    fecharGaveta();
  }

  function sair() {
    perfil = null;
    menus = [];
    sb.auth.signOut().finally(function () {
      history.replaceState(null, '', window.location.pathname);
      mostrarAcesso('v-login');
      msg('login-msg', '');
    });
  }

  function fecharGaveta() {
    $('lateral').classList.remove('aberta');
    $('btn-menu').setAttribute('aria-expanded', 'false');
  }

  // ---------- eventos ----------
  $('v-login').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var email = $('login-email').value.trim().toLowerCase();
    var senha = $('login-senha').value;
    if (!email || !senha) { msg('login-msg', 'Preencha e-mail e senha.'); return; }
    msg('login-msg', '');
    ocupado('login-btn', true, 'Entrando...');
    sb.auth.signInWithPassword({ email: email, password: senha }).then(function (r) {
      ocupado('login-btn', false);
      if (r.error) { msg('login-msg', traduzErro(r.error)); return; }
      $('login-senha').value = '';
      carregarCic(r.data.session);
    });
  });

  $('ir-esqueci').addEventListener('click', function () {
    $('esqueci-email').value = $('login-email').value;
    msg('esqueci-msg', '');
    mostrarAcesso('v-esqueci');
  });
  $('voltar-login').addEventListener('click', function () { mostrarAcesso('v-login'); });
  $('trocar-cliente').addEventListener('click', function () { apagar('cic-cliente'); mostrarSeletor(); });

  $('v-esqueci').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var email = $('esqueci-email').value.trim().toLowerCase();
    if (!email) { msg('esqueci-msg', 'Informe o e-mail.'); return; }
    ocupado('esqueci-btn', true, 'Enviando...');
    var volta = window.location.origin + window.location.pathname + '?c=' + encodeURIComponent(cliente.slug);
    sb.auth.resetPasswordForEmail(email, { redirectTo: volta }).then(function (r) {
      ocupado('esqueci-btn', false);
      if (r.error && /rate limit|too many/i.test(r.error.message)) { msg('esqueci-msg', traduzErro(r.error)); return; }
      // Mesma resposta com ou sem conta, pra não revelar quem tem acesso
      msg('esqueci-msg', 'Se o e-mail tiver acesso, o link chega em alguns minutos. Confira o spam.', true);
    });
  });

  $('v-senha').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var s1 = $('senha-1').value, s2 = $('senha-2').value;
    if (s1.length < 8) { msg('senha-msg', 'A senha precisa ter pelo menos 8 caracteres.'); return; }
    if (s1 !== s2) { msg('senha-msg', 'As senhas não conferem.'); return; }
    ocupado('senha-btn', true, 'Salvando...');
    sb.auth.updateUser({ password: s1 }).then(function (r) {
      ocupado('senha-btn', false);
      if (r.error) { msg('senha-msg', traduzErro(r.error)); return; }
      $('senha-1').value = '';
      $('senha-2').value = '';
      sb.auth.getSession().then(function (s) { carregarCic(s.data.session); });
    });
  });

  $('btn-sair').addEventListener('click', sair);
  $('sair-sem-acesso').addEventListener('click', sair);
  $('btn-menu').addEventListener('click', function () {
    var aberta = $('lateral').classList.toggle('aberta');
    $('btn-menu').setAttribute('aria-expanded', aberta ? 'true' : 'false');
  });
  window.addEventListener('hashchange', rota);
  icone(document.querySelector('[data-ic="sair"]'), 'sair');
  Array.prototype.forEach.call(document.querySelectorAll('[data-simbolo]'), function (el) {
    el.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 595 920" aria-hidden="true">' +
      '<path fill="currentColor" fill-rule="evenodd" d="' + SIMBOLO + '"/></svg>';
  });

  // ---------- início ----------
  var link = lerHash();
  if (!clientes.length) {
    document.body.textContent = 'Nenhuma operação configurada.';
    return;
  }
  // ?c=<slug> na URL (links de recuperação) tem prioridade sobre a última escolha
  var salvo = (window.location.search.match(/[?&]c=([a-z0-9-]+)/) || [])[1] || ler('cic-cliente');
  var inicial = clientes.length === 1
    ? clientes[0]
    : clientes.filter(function (c) { return c.slug === salvo; })[0];
  if (!inicial) { mostrarSeletor(); return; }
  escolherCliente(inicial);
  iniciarSessao(link);
})();
