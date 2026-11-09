/*
 * CIC · casca do app (acesso + menu por perfil)
 * Nada específico de cliente aqui: clientes vêm de config/clientes.js,
 * perfil e menus vêm do banco de cada cliente (RLS).
 */
(function () {
  'use strict';

  var BUILD = '2026-11-09c';
  var MUDANCAS = 'Presets de data no filtro; Taxa de passagem por origem com conversão etapa 2 > venda; Motivos de perda em pizza por motivo, etapa, origem e vendedor';

  // Telas do MVP: chave (igual a perfil_menus.menu) -> rótulo, descrição e ícone
  var TELAS = {
    home:          { rotulo: 'Home',                  desc: 'Visão geral da operação.' },
    metadomes:     { rotulo: 'Meta do mês',           desc: 'Faturamento líquido contra as faixas bronze, prata e ouro.' },
    mensageria:    { rotulo: 'Mensageria',            desc: 'Disparos, conversas e automações do WhatsApp.' },
    discadora:     { rotulo: 'Discadora',             desc: 'Ligações e produtividade na Callix.' },
    desempenho:    { rotulo: 'Desempenho individual', desc: 'Resultado por vendedor.' },
    minhapagina:   { rotulo: 'Minha página',          desc: 'Seus números no mês.' },
    relatorios:    { rotulo: 'Relatórios',            desc: 'Lista de vendas pra conferência.' },
    taxapassagem:  { rotulo: 'Taxa de passagem',      desc: 'Conversão entre as etapas do CRM.' },
    motivosperda:  { rotulo: 'Motivos de perda',      desc: 'Por que os leads saem do funil.' },
    ciclovenda:    { rotulo: 'Ciclo de vendas',       desc: 'Tempo do primeiro contato até a venda.' },
    reembolsos:    { rotulo: 'Reembolsos',            desc: 'Reembolsos efetivados e o que foi abatido.' }
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
      tx.className = 'menu-txt';
      tx.textContent = TELAS[m].rotulo;
      a.title = TELAS[m].rotulo;
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
    $('bloco-links').hidden = true;
    var render = RENDER[m];
    $('painel').hidden = !render;
    $('painel-vazio').hidden = !!render;
    if (render) render($('painel'), ++pedido);
    Array.prototype.forEach.call(document.querySelectorAll('.menu a'), function (a) {
      a.classList.toggle('ativo', a.dataset.menu === m);
    });
    fecharGaveta();
  }

  // ---------- formatação e gráficos ----------
  var FUSO = 'America/Sao_Paulo';
  var MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
  var BRL = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
  var pedido = 0;   // descarta resposta de tela que já foi trocada

  function hojeSP() {
    return new Intl.DateTimeFormat('en-CA', { timeZone: FUSO, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  }
  function mesAtual() { return hojeSP().slice(0, 8) + '01'; }
  function nomeMes(d) { return MESES[Number(d.slice(5, 7)) - 1] + ' de ' + d.slice(0, 4); }
  function rs(v) { return BRL.format(Number(v) || 0); }
  function rsCurto(v) {
    v = Number(v) || 0;
    if (Math.abs(v) >= 1000) return 'R$ ' + (v / 1000).toLocaleString('pt-BR', { maximumFractionDigits: v >= 10000 ? 0 : 1 }) + ' mil';
    return 'R$ ' + Math.round(v).toLocaleString('pt-BR');
  }
  function pct(v, casas) {
    if (v === null || v === undefined) return '–';
    return (Number(v) * 100).toLocaleString('pt-BR', { minimumFractionDigits: casas == null ? 1 : casas, maximumFractionDigits: casas == null ? 1 : casas }) + '%';
  }
  function num(v) { return (Number(v) || 0).toLocaleString('pt-BR'); }
  function ddmm(d) { return d.slice(8, 10) + '/' + d.slice(5, 7); }
  // timestamp -> "06/11 16:00" no fuso de São Paulo
  function dataHora(ts) {
    if (!ts) return '–';
    return new Date(ts).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }).replace(',', '');
  }
  function esc(t) {
    return String(t == null ? '' : t).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function kpi(rotulo, valor, sub, destaque) {
    return '<div class="kpi' + (destaque ? ' kpi-destaque' : '') + '"><div class="kpi-rotulo">' + esc(rotulo) + '</div>' +
      '<div class="kpi-valor">' + valor + '</div>' + (sub ? '<div class="kpi-sub">' + sub + '</div>' : '') + '</div>';
  }
  function bloco(titulo, sub, corpo) {
    return '<section class="bloco"><header class="bloco-topo"><h2>' + esc(titulo) + '</h2>' +
      (sub ? '<p>' + sub + '</p>' : '') + '</header>' + corpo + '</section>';
  }
  function carregando(alvo) { alvo.innerHTML = '<p class="painel-msg">Carregando...</p>'; }
  function falhou(alvo, e) {
    alvo.innerHTML = '<p class="painel-msg painel-erro"></p>';
    alvo.firstChild.textContent = traduzErro(e);
  }
  // Conversão contra o alvo (só tons da paleta)
  function convTag(taxa, alvo) {
    if (taxa === null || taxa === undefined) return '<span class="tag">sem contatos</span>';
    return '<span class="tag ' + (Number(taxa) >= Number(alvo) ? 'tag-ok' : 'tag-abaixo') + '">alvo ' + pct(alvo, 0) + '</span>';
  }

  // Barras diárias (empilhadas). series: [{chave, nome, cor}]
  function grafBarras(dados, series, opc) {
    opc = opc || {};
    var n = dados.length;
    if (!n) return '<p class="painel-msg">Sem dados no período.</p>';
    // largura real do bloco: texto do eixo fica legível no celular
    var L = opc.linha, mD = L ? 56 : 8;
    var W = Math.max(300, Math.min(760, Math.round(opc.largura || 760))), H = W < 500 ? 200 : 220, mE = 74, mB = 26, mT = 10;
    var larg = (W - mE - mD) / n, barra = Math.max(4, Math.min(28, larg * 0.62));
    var totais = dados.map(function (d) { return series.reduce(function (s, x) { return s + (Number(d[x.chave]) || 0); }, 0); });
    var max = Math.max.apply(null, totais.concat([1]));
    // escala "redonda": 4 faixas de 1, 2, 2,5, 3, 4, 5, 6 ou 8 x 10^n
    var bruto = max / 4, ordem = Math.pow(10, Math.floor(Math.log10(bruto)));
    var passo = [1, 2, 2.5, 3, 4, 5, 6, 8, 10].map(function (k) { return k * ordem; }).filter(function (k) { return k >= bruto; })[0];
    var topo = passo * 4;
    var y = function (v) { return mT + (H - mT - mB) * (1 - v / topo); };
    // eixo da direita (linha): mesma escala redonda, em quantidade
    if (L) {
      var maxL = Math.max.apply(null, dados.map(function (d) { return Number(d[L.chave]) || 0; }).concat([1]));
      var brL = maxL / 4, orL = Math.pow(10, Math.floor(Math.log10(brL)));
      var passoL = [1, 2, 2.5, 3, 4, 5, 6, 8, 10].map(function (k) { return k * orL; }).filter(function (k) { return k >= brL; })[0];
      var yL = function (v) { return mT + (H - mT - mB) * (1 - v / (passoL * 4)); };
    }
    var svg = '<svg class="grafico" viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="' + esc(opc.rotulo || 'Gráfico diário') + '">';
    for (var g = 0; g <= 4; g++) {
      var vg = passo * g, yg = y(vg);
      svg += '<line x1="' + mE + '" x2="' + (W - mD + 8) + '" y1="' + yg + '" y2="' + yg + '" class="g-grade"/>' +
        '<text x="' + (mE - 8) + '" y="' + (yg + 4) + '" class="g-eixo" text-anchor="end">' + esc(rsCurto(vg)) + '</text>';
      if (L) svg += '<text x="' + (W - mD + 14) + '" y="' + (yg + 4) + '" class="g-eixo">' + esc(num(passoL * g)) + '</text>';
    }
    var cadaRotulo = Math.max(1, Math.ceil(n / Math.floor((W - mE) / 26)));
    dados.forEach(function (d, i) {
      var x = mE + larg * i + (larg - barra) / 2, base = 0;
      var dica = ddmm(d.dia) + ': ' + series.map(function (s) { return s.nome + ' ' + rs(d[s.chave]); }).join(' · ') +
        (L ? ' · ' + L.nome + ' ' + num(d[L.chave]) : '');
      svg += '<g><title>' + esc(dica) + '</title>';
      series.forEach(function (s) {
        var v = Number(d[s.chave]) || 0;
        if (v > 0) {
          svg += '<rect x="' + x.toFixed(1) + '" y="' + y(base + v).toFixed(1) + '" width="' + barra.toFixed(1) + '" height="' +
            (y(base) - y(base + v)).toFixed(1) + '" fill="' + s.cor + '"/>';
          base += v;
        }
      });
      svg += '<rect x="' + (mE + larg * i).toFixed(1) + '" y="' + mT + '" width="' + larg.toFixed(1) + '" height="' + (H - mT - mB) + '" fill="transparent"/></g>';
      if (i % cadaRotulo === 0) {
        svg += '<text x="' + (mE + larg * i + larg / 2).toFixed(1) + '" y="' + (H - 8) + '" class="g-eixo" text-anchor="middle">' + ddmm(d.dia).slice(0, 2) + '</text>';
      }
    });
    if (L) {
      var pts = dados.map(function (d, i) { return (mE + larg * i + larg / 2).toFixed(1) + ',' + yL(Number(d[L.chave]) || 0).toFixed(1); });
      svg += '<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + L.cor + '" stroke-width="2" pointer-events="none"/>' +
        pts.map(function (p) { var c = p.split(','); return '<circle cx="' + c[0] + '" cy="' + c[1] + '" r="3" fill="' + L.cor + '" pointer-events="none"/>'; }).join('');
    }
    svg += '</svg>';
    var leg = series.length > 1 || L ? '<div class="legenda">' + series.map(function (s) {
      return '<span><i style="background:' + s.cor + '"></i>' + esc(s.nome) + '</span>';
    }).join('') + (L ? '<span><i class="leg-linha" style="background:' + L.cor + '"></i>' + esc(L.nome) + ' (eixo da direita)</span>' : '') + '</div>' : '';
    return leg + svg;
  }

  // Régua horizontal com marcos (níveis de comissão ou metas)
  // marcos: [{valor, rotulo, sub}]; atual: valor preenchido; proj: marcador opcional
  function regua(marcos, atual, opc) {
    opc = opc || {};
    var fim = opc.fim || Math.max.apply(null, marcos.map(function (m) { return m.valor; }).concat([atual, opc.proj || 0, 1]));
    var p = function (v) { return Math.max(0, Math.min(100, v / fim * 100)); };
    var h = '<div class="regua"><div class="regua-trilho"><div class="regua-feito" style="width:' + p(atual).toFixed(2) + '%"></div>';
    if (opc.proj) h += '<div class="regua-proj" style="left:' + p(opc.proj).toFixed(2) + '%" title="Projeção ' + esc(rs(opc.proj)) + '"></div>';
    marcos.forEach(function (m) {
      if (m.valor > 0) h += '<div class="regua-marco' + (atual >= m.valor ? ' batido' : '') + '" style="left:' + p(m.valor).toFixed(2) + '%"></div>';
    });
    h += '</div><div class="regua-rotulos">';
    marcos.forEach(function (m) {
      h += '<div class="regua-rotulo' + (atual >= m.valor && m.valor > 0 ? ' batido' : '') + (m.atual ? ' atual' : '') + '" style="left:' + p(m.valor).toFixed(2) + '%">' +
        '<strong>' + esc(m.rotulo) + '</strong><span>' + esc(m.sub || '') + '</span></div>';
    });
    return h + '</div></div>';
  }

  function tabela(cab, linhas, num) {
    num = num || [];
    return '<div class="tabela-rolagem"><table class="tabela"><thead><tr>' + cab.map(function (c, i) {
      // cabeçalho pode ser texto ou { t, dica } (dica aparece ao passar o mouse)
      var txt = typeof c === 'object' ? c.t : c, dica = typeof c === 'object' ? c.dica : '';
      return '<th' + (num.indexOf(i) >= 0 ? ' class="n"' : '') + (dica ? ' title="' + esc(dica) + '"' : '') + '>' +
        (dica ? '<span class="dica">' + esc(txt) + '</span>' : esc(txt)) + '</th>';
    }).join('') + '</tr></thead><tbody>' + linhas.map(function (l) {
      return '<tr>' + l.map(function (c, i) { return '<td' + (num.indexOf(i) >= 0 ? ' class="n"' : '') + '>' + c + '</td>'; }).join('') + '</tr>';
    }).join('') + '</tbody></table></div>';
  }

  var COR = { comercial: '#1f2b38', perda: '#8e6e59', cs: '#c6c6c6', automacao: '#844420', vendedor: '#8e6e59' };

  // ---------- Home (admin) ----------
  function telaHome(alvo, id) {
    carregando(alvo);
    if (id !== pedido) return;
    var corpo = barraFiltro(alvo, carregar, false, true);
    carregar(id);
    function carregar(idc) {
      corpo.innerHTML = '<p class="painel-msg">Carregando...</p>';
      sb.rpc('cic_home', { p_inicio: filtro.ini, p_fim: filtro.fim }).then(function (r) {
        if (idc !== pedido) return;
        if (r.error) return falhou(corpo, r.error);
        corpo.innerHTML = montaHome(r.data || {}, corpo.clientWidth);
      });
    }
  }

  // Card no formato do G2: rótulo, valor, linhas extras e a faixa HOJE / ONTEM
  function hmCard(rotulo, valor, extras, hoje, ontem, legenda) {
    return '<div class="hm-card"><div class="hm-lab">' + rotulo + '</div><div class="hm-val">' + valor + '</div>' +
      (extras ? '<div class="hm-split">' + extras + '</div>' : '') +
      (hoje !== undefined ? '<div class="hm-ho"><div class="hm-ho-c on"><span>Hoje · parcial</span><b>' + hoje + '</b></div>' +
        '<div class="hm-ho-c"><span>Ontem</span><b>' + ontem + '</b></div>' + (legenda ? '<div class="hm-ho-cap">' + esc(legenda) + '</div>' : '') + '</div>' : '') +
      '</div>';
  }
  function hmSplit(rotulo, valor, dica) {
    return '<div' + (dica ? ' title="' + esc(dica) + '"' : '') + '>' + (dica ? '<span class="dica">' + esc(rotulo) + '</span>' : esc(rotulo)) + '<b>' + valor + '</b></div>';
  }
  function rsOuTraco(v) { return v === null || v === undefined ? '–' : rs(v); }

  function montaHome(d, largura) {
    var p = d.periodo || {}, h = d.dia_hoje || {}, o = d.dia_ontem || {};
    var resultado = '<div class="hm-grid">' +
      hmCard('Faturamento bruto', rs(p.bruto), '', rs(h.bruto), rs(o.bruto)) +
      hmCard('Faturamento líquido', rs(p.liquido), hmSplit('após reembolso', rs(p.liquido_apos_reembolso)), rs(h.liquido), rs(o.liquido)) +
      hmCard('Vendas totais', num(p.vendas), '', num(h.vendas), num(o.vendas)) +
      '<div class="hm-card"><div class="hm-dupla"><div><div class="hm-lab">Ticket médio bruto</div><div class="hm-val">' + rsOuTraco(p.ticket_bruto) + '</div></div>' +
        '<div><div class="hm-lab">Ticket médio líquido</div><div class="hm-val">' + rsOuTraco(p.ticket_liquido) + '</div></div></div>' +
        '<div class="hm-ho"><div class="hm-ho-c on"><span>Hoje · parcial</span><b>' + rsOuTraco(h.ticket_liquido) + '</b></div>' +
        '<div class="hm-ho-c"><span>Ontem</span><b>' + rsOuTraco(o.ticket_liquido) + '</b></div><div class="hm-ho-cap">ticket líquido</div></div></div>' +
      '</div><div class="hm-grid">' +
      hmCard('Conversão · Em Contato → Venda', pct(p.conversao), hmSplit('Em Contato', num(p.em_contato)) + hmSplit('Leads', num(p.leads), 'pessoas únicas (telefone)'), pct(h.conversao), pct(o.conversao)) +
      (d.plataformas || []).map(function (pl) {
        return hmCard('Faturamento ' + esc(pl.plataforma), rs(pl.liquido), hmSplit('bruto', rs(pl.bruto)) + hmSplit('vendas', num(pl.vendas)));
      }).join('') +
      hmCard('Reembolso', rs(p.reembolso), hmSplit('reembolsos no período', num(p.reembolso_qtd)), rs(h.reembolso), rs(o.reembolso)) +
      '</div>';

    // Venda por produto, com a quebra por oferta
    var prodLinhas = [];
    (d.produtos || []).forEach(function (pr) {
      prodLinhas.push('<tr class="hm-prod"><td><strong>' + esc(pr.produto) + '</strong></td><td class="n">' + num(pr.vendas) + ' <span class="fraco">' + pct(pr.pct_vendas, 0) + '</span></td>' +
        '<td class="n"><strong>' + rs(pr.liquido) + '</strong> <span class="fraco">' + pct(pr.pct_liquido, 0) + '</span></td>' +
        '<td class="n">' + rs(pr.ticket_bruto) + '</td><td class="n">' + rs(pr.ticket_liquido) + '</td></tr>');
      (pr.ofertas || []).forEach(function (of) {
        prodLinhas.push('<tr class="hm-oferta"><td>' + esc(of.oferta) + '</td><td class="n">' + num(of.vendas) + ' <span class="fraco">' + pct(of.pct_vendas, 0) + '</span></td>' +
          '<td class="n">' + rs(of.liquido) + ' <span class="fraco">' + pct(of.pct_liquido, 0) + '</span></td>' +
          '<td class="n">' + rs(of.ticket_bruto) + '</td><td class="n">' + rs(of.ticket_liquido) + '</td></tr>');
      });
    });
    var produtos = prodLinhas.length
      ? '<div class="tabela-rolagem"><table class="tabela lista"><thead><tr><th>Produto / oferta</th><th class="n">Vendas</th><th class="n">Faturamento líquido</th>' +
        '<th class="n">Ticket bruto</th><th class="n">Ticket líquido</th></tr></thead><tbody>' + prodLinhas.join('') + '</tbody></table></div>'
      : '<p class="painel-msg vazio">Nenhuma venda no período.</p>';

    // Dia a dia (mês da data final)
    var m = d.matriz || {}, dias = m.dias || [], t = m.total || {};
    var linhas = [
      ['Leads', function (x) { return num(x.leads); }],
      ['Em Contato', function (x) { return num(x.em_contato); }],
      ['Conversão', function (x) { return x.conversao == null ? '–' : pct(x.conversao); }],
      ['Vendas', function (x) { return num(x.vendas); }],
      ['Ticket médio', function (x) { return x.ticket_liquido == null ? '–' : rs(x.ticket_liquido).replace(/^R\$\s?/, ''); }],
      ['Faturamento', function (x) { return rs(x.liquido).replace(/^R\$\s?/, ''); }]
    ];
    var classe = function (x) { return (x.util ? '' : ' fds') + (x.parcial ? ' hoje' : ''); };
    var matriz = '<div class="tabela-rolagem"><table class="tabela matriz"><thead><tr><th></th>' +
      dias.map(function (x) {
        return '<th class="n' + classe(x) + '" title="' + esc(x.feriado || (x.util ? '' : 'fim de semana')) + '">' + x.dia.slice(8, 10) +
          '<span>' + diaSemana(x.dia) + (x.parcial ? ' · parcial' : '') + '</span></th>';
      }).join('') + '<th class="n total">TOTAL</th></tr></thead><tbody>' +
      linhas.map(function (l) {
        return '<tr><th>' + l[0] + '</th>' + dias.map(function (x) { return '<td class="n' + classe(x) + '">' + l[1](x) + '</td>'; }).join('') +
          '<td class="n total">' + l[1](t) + '</td></tr>';
      }).join('') + '</tbody></table></div>';

    return '<div class="hm-sec"><h2>Resultado</h2><small>' + periodoTxt() + ' · só comercial</small></div>' + resultado +
      bloco('Venda por produto', 'Vendas do comercial no período, com a quebra por oferta. % sobre o total do período.', produtos) +
      bloco('Dia a dia · ' + (m.mes ? nomeMes(m.mes) : ''), 'Mês da data final do filtro. Fim de semana e feriado sombreados; hoje é parcial. TOTAL conta cada pessoa uma vez no mês. Valores em R$, líquido.', matriz);
  }

  // ---------- Meta do mês (admin) ----------
  var granMatriz = ler('cic-meta-gran') === 'semanas' ? 'semanas' : 'dias';

  function telaMeta(alvo, id) {
    carregando(alvo);
    var mes = mesAtual();
    Promise.all([sb.rpc('cic_meta_mes', { p_mes: mes }), sb.rpc('cic_meta_funil', { p_mes: mes })]).then(function (rr) {
      if (id !== pedido) return;
      var e = rr[0].error || rr[1].error;
      if (e) return falhou(alvo, e);
      var d = rr[0].data, f = rr[1].data || {};
      var metas = d.metas || [];
      var liq = Number(d.liquido) || 0;
      var prox = metas.filter(function (m) { return liq < Number(m.valor); })[0];
      var topo = metas.length ? Number(metas[metas.length - 1].valor) : 0;
      var marcos = metas.map(function (m) {
        return { valor: Number(m.valor), rotulo: m.nivel.charAt(0).toUpperCase() + m.nivel.slice(1), sub: rsCurto(m.valor) };
      });
      var linhasMeta = metas.map(function (m) {
        return ['<strong>' + esc(m.nivel.charAt(0).toUpperCase() + m.nivel.slice(1)) + '</strong>', rs(m.valor), pct(m.pct),
          Number(m.falta) > 0 ? rs(m.falta) : '<span class="tag tag-ok">batida</span>',
          Number(m.falta) > 0 ? (m.falta_dia_util == null ? '–' : rs(m.falta_dia_util)) : '–'];
      });
      alvo.innerHTML =
        '<p class="periodo">' + esc(nomeMes(mes)) + ' · vendas do comercial, líquido de reembolsos</p>' +
        '<div class="kpis">' +
        kpi('Líquido comercial', rs(liq), num(d.vendas_qtd) + ' vendas' + (Number(d.reembolsos_qtd) ? ' · ' + num(d.reembolsos_qtd) + ' reembolsos (' + rs(d.reembolsos_liquido) + ')' : ''), true) +
        kpi('Projeção do mês', d.projecao == null ? '–' : rs(d.projecao), 'ritmo de ' + num(d.dias_uteis_decorridos) + ' dias úteis desde ' + (d.primeira_venda ? ddmm(d.primeira_venda) : '–')) +
        kpi(prox ? 'Falta pro ' + prox.nivel : 'Metas', prox ? rs(prox.falta) : 'todas batidas', prox && prox.falta_dia_util != null ? rs(prox.falta_dia_util) + ' por dia útil' : '') +
        kpi('Dias úteis restantes', num(d.dias_uteis_restantes), 'de ' + num(d.dias_uteis_mes) + ' no mês') +
        '</div>' +
        bloco('Caminho até o ouro', 'Linha tracejada: projeção do mês no ritmo atual.',
          regua(marcos, liq, { fim: Math.max(topo, d.projecao || 0) * 1.04, proj: d.projecao }) +
          tabela(['Meta', 'Valor', 'Atingido', 'Falta', 'Por dia útil'], linhasMeta, [1, 2, 3, 4])) +
        bloco('Burn-up do mês', 'Metas acumuladas por dia útil (planas em fim de semana e feriado) e o realizado acumulado: líquido de vendas menos reembolsos, até hoje. Sombreado: o que falta pra Prata.',
          grafBurn(f.burn || [], f.hoje, alvo.clientWidth - 50)) +
        '<section class="bloco"><header class="bloco-topo bloco-topo-acao"><div><h2>Realizado por funil</h2>' +
        '<p>Funil = origem do evento no CRM. Lead e Em Contato contam no funil do próprio evento; a venda vai pro funil da origem mais recente da pessoa antes da compra. TOTAL: Leads somados, Em Contato únicos.</p></div>' +
        '<div class="alternar" role="group" aria-label="Granularidade">' +
        '<button type="button" data-gran="dias"' + (granMatriz === 'dias' ? ' class="on"' : '') + '>Dias + semanas</button>' +
        '<button type="button" data-gran="semanas"' + (granMatriz === 'semanas' ? ' class="on"' : '') + '>Só semanas</button></div></header>' +
        '<div id="mt-matriz">' + matrizFunil(f) + '</div></section>';
      Array.prototype.forEach.call(alvo.querySelectorAll('[data-gran]'), function (b) {
        b.addEventListener('click', function () {
          granMatriz = b.getAttribute('data-gran');
          guardar('cic-meta-gran', granMatriz);
          Array.prototype.forEach.call(alvo.querySelectorAll('[data-gran]'), function (x) { x.classList.toggle('on', x === b); });
          $('mt-matriz').innerHTML = matrizFunil(f);
        });
      });
    });
  }

  // Burn-up: metas acumuladas (bronze, prata tracejada, ouro) e realizado até hoje
  function grafBurn(burn, hoje, largura) {
    if (!burn.length) return '<p class="painel-msg">Sem calendário do mês.</p>';
    var W = Math.max(300, Math.min(900, Math.round(largura || 760))), H = W < 500 ? 230 : 280, mE = 74, mB = 28, mT = 12, mD = 12;
    var n = burn.length;
    var max = Math.max.apply(null, burn.map(function (b) { return Math.max(Number(b.ouro) || 0, Number(b.realizado) || 0); }).concat([1]));
    var bruto = max / 4, ordem = Math.pow(10, Math.floor(Math.log10(bruto)));
    var passo = [1, 2, 2.5, 3, 4, 5, 6, 8, 10].map(function (k) { return k * ordem; }).filter(function (k) { return k >= bruto; })[0];
    var topo = passo * 4;
    var x = function (i) { return mE + (W - mE - mD) * (n === 1 ? 0 : i / (n - 1)); };
    var y = function (v) { return mT + (H - mT - mB) * (1 - v / topo); };
    var svg = '<svg class="grafico" viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="Burn-up do mês">';
    // fim de semana e feriado
    burn.forEach(function (b, i) {
      if (!b.util) {
        var w = (W - mE - mD) / Math.max(1, n - 1);
        svg += '<rect x="' + (x(i) - w / 2).toFixed(1) + '" y="' + mT + '" width="' + w.toFixed(1) + '" height="' + (H - mT - mB) + '" class="g-fds"><title>' + esc(b.feriado || 'fim de semana') + '</title></rect>';
      }
    });
    for (var g = 0; g <= 4; g++) {
      var vg = passo * g, yg = y(vg);
      svg += '<line x1="' + mE + '" x2="' + (W - mD) + '" y1="' + yg + '" y2="' + yg + '" class="g-grade"/>' +
        '<text x="' + (mE - 8) + '" y="' + (yg + 4) + '" class="g-eixo" text-anchor="end">' + esc(rsCurto(vg)) + '</text>';
    }
    var linha = function (k) { return burn.map(function (b, i) { return (i ? 'L' : 'M') + x(i).toFixed(1) + ' ' + y(Number(b[k]) || 0).toFixed(1); }).join(' '); };
    var real = burn.map(function (b, i) { return { i: i, v: b.realizado }; }).filter(function (p) { return p.v !== null && p.v !== undefined; });
    // gap até a prata (só até hoje)
    if (real.length) {
      var topoP = real.map(function (p) { return x(p.i).toFixed(1) + ' ' + y(Number(burn[p.i].prata) || 0).toFixed(1); });
      var baseR = real.slice().reverse().map(function (p) { return x(p.i).toFixed(1) + ' ' + y(Math.min(Number(p.v), Number(burn[p.i].prata) || 0)).toFixed(1); });
      svg += '<path d="M' + topoP.join(' L') + ' L' + baseR.join(' L') + ' Z" class="g-gap"/>';
    }
    svg += '<path d="' + linha('bronze') + '" class="g-linha g-bronze"/>' +
      '<path d="' + linha('ouro') + '" class="g-linha g-ouro"/>' +
      '<path d="' + linha('prata') + '" class="g-linha g-prata"/>';
    if (real.length) {
      svg += '<path d="' + real.map(function (p, k) { return (k ? 'L' : 'M') + x(p.i).toFixed(1) + ' ' + y(Number(p.v)).toFixed(1); }).join(' ') + '" class="g-linha g-real"/>';
      var u = real[real.length - 1];
      svg += '<circle cx="' + x(u.i).toFixed(1) + '" cy="' + y(Number(u.v)).toFixed(1) + '" r="4" class="g-ponto"><title>' + esc(ddmm(burn[u.i].dia) + ': ' + rs(u.v)) + '</title></circle>';
    }
    var cada = Math.max(1, Math.ceil(n / Math.floor((W - mE) / 30)));
    burn.forEach(function (b, i) {
      if (i % cada === 0 || i === n - 1) svg += '<text x="' + x(i).toFixed(1) + '" y="' + (H - 9) + '" class="g-eixo" text-anchor="middle">' + b.dia.slice(8, 10) + '</text>';
    });
    svg += '</svg>';
    var ult = real.length ? burn[real[real.length - 1].i] : null;
    var leg = '<div class="legenda">' +
      '<span><i class="lg-real"></i>Realizado' + (ult ? ' · ' + rs(ult.realizado) : '') + '</span>' +
      '<span><i class="lg-bronze"></i>Bronze</span><span><i class="lg-prata"></i>Prata (meta)' + (ult ? ' · ' + rs(ult.prata) + ' até hoje' : '') + '</span>' +
      '<span><i class="lg-ouro"></i>Ouro</span>' +
      (ult ? '<span><i class="lg-gap"></i>Falta pra Prata · ' + rs(Math.max(0, Number(ult.prata) - Number(ult.realizado))) + '</span>' : '') + '</div>';
    return leg + svg;
  }

  // Matriz por funil (só realizado)
  function matrizFunil(f) {
    var cols = (f.colunas || []).filter(function (c) { return granMatriz === 'dias' || c.tipo !== 'dia'; });
    var funis = f.funis || [];
    if (!cols.length) return '<p class="painel-msg">Sem dados do mês.</p>';
    var linhas = [
      ['Leads', function (x) { return x ? num(x.leads) : '–'; }],
      ['Em Contato', function (x) { return x ? num(x.em_contato) : '–'; }],
      ['Conversão', function (x) { return x && x.conversao != null ? pct(x.conversao) : '–'; }],
      ['Vendas', function (x) { return x ? num(x.vendas) : '–'; }],
      ['Ticket médio', function (x) { return x && x.ticket != null ? rs(x.ticket).replace(/^R\$\s?/, '') : '–'; }],
      ['Faturamento', function (x) { return x ? rs(x.liquido).replace(/^R\$\s?/, '') : '–'; }]
    ];
    var classe = function (c) {
      return (c.tipo === 'semana' ? ' sem' : c.tipo === 'mes' ? ' total' : '') + (c.tipo === 'dia' && !c.util ? ' fds' : '') +
        (c.parcial ? ' hoje' : '') + (c.futuro ? ' futuro' : '');
    };
    var cab = '<thead><tr><th></th>' + cols.map(function (c) {
      var sub = c.tipo === 'dia' ? diaSemana(c.inicio) + (c.parcial ? ' · parcial' : '') : c.tipo === 'semana' ? 'semana' : '';
      return '<th class="n' + classe(c) + '">' + esc(c.tipo === 'semana' ? (c.inicio === c.fim ? c.inicio.slice(8, 10) : c.rotulo.replace('–', ' a ')) : c.rotulo) + (sub ? '<span>' + esc(sub) + '</span>' : '') + '</th>';
    }).join('') + '</tr></thead>';
    var bloco1 = function (titulo, pega, total) {
      return '<tr class="mt-funil' + (total ? ' mt-total' : '') + '"><th colspan="' + (cols.length + 1) + '">' + esc(titulo) + '</th></tr>' +
        linhas.map(function (l) {
          return '<tr><th>' + l[0] + '</th>' + cols.map(function (c) {
            return '<td class="n' + classe(c) + '">' + (c.futuro ? '' : l[1](pega(c))) + '</td>';
          }).join('') + '</tr>';
        }).join('');
    };
    var corpo = bloco1('TOTAL', function (c) { return c.total; }, true) +
      funis.map(function (fn) { return bloco1(fn, function (c) { return (c.funis || {})[fn]; }); }).join('');
    return '<div class="tabela-rolagem"><table class="tabela matriz mt-matriz">' + cab + '<tbody>' + corpo + '</tbody></table></div>';
  }

  // ---------- Minha página (vendedor e admin) ----------
  // Burn da comissão: realizado, projeção e níveis (só os que cabem até 1,15 x o maior)
  function grafComissao(m, largura) {
    var burn = m.burn || [];
    if (!burn.length) return '<p class="painel-msg">Sem calendário do mês.</p>';
    var real = burn.map(function (b, i) { return { i: i, v: b.acum }; }).filter(function (p) { return p.v !== null && p.v !== undefined; });
    var ult = real.length ? Number(real[real.length - 1].v) : 0;
    var proj = m.projecao == null ? null : Number(m.projecao);
    var topoV = Math.max(ult, proj || 0) * 1.15 || 1000;
    var W = Math.max(300, Math.min(900, Math.round(largura || 760))), H = W < 500 ? 220 : 260, mE = 74, mB = 28, mT = 12, mD = 12, n = burn.length;
    var bruto = topoV / 4, ordem = Math.pow(10, Math.floor(Math.log10(bruto)));
    var passo = [1, 2, 2.5, 3, 4, 5, 6, 8, 10].map(function (k) { return k * ordem; }).filter(function (k) { return k >= bruto; })[0];
    var topo = passo * 4;
    var x = function (i) { return mE + (W - mE - mD) * (n === 1 ? 0 : i / (n - 1)); };
    var y = function (v) { return mT + (H - mT - mB) * (1 - v / topo); };
    var svg = '<svg class="grafico" viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="Faturamento da comissão acumulado">';
    for (var g = 0; g <= 4; g++) {
      var yg = y(passo * g);
      svg += '<line x1="' + mE + '" x2="' + (W - mD) + '" y1="' + yg + '" y2="' + yg + '" class="g-grade"/>' +
        '<text x="' + (mE - 8) + '" y="' + (yg + 4) + '" class="g-eixo" text-anchor="end">' + esc(rsCurto(passo * g)) + '</text>';
    }
    var niveis = (m.niveis || []).filter(function (l) { return Number(l.acima_de) > 0 && Number(l.acima_de) <= topoV; });
    niveis.forEach(function (l) {
      var yl = y(Number(l.acima_de));
      svg += '<line x1="' + mE + '" x2="' + (W - mD) + '" y1="' + yl + '" y2="' + yl + '" class="g-nivel"/>' +
        '<text x="' + (W - mD - 4) + '" y="' + (yl - 5) + '" class="g-eixo g-nivel-txt" text-anchor="end">' + esc(l.nome + ' (' + pct(l.pct) + ')') + '</text>';
    });
    if (real.length) {
      var u = real[real.length - 1];
      if (proj !== null && u.i < n - 1) {
        svg += '<path d="M' + x(u.i).toFixed(1) + ' ' + y(ult).toFixed(1) + ' L' + x(n - 1).toFixed(1) + ' ' + y(proj).toFixed(1) + '" class="g-linha g-proj"/>' +
          '<circle cx="' + x(n - 1).toFixed(1) + '" cy="' + y(proj).toFixed(1) + '" r="3.5" class="g-proj-ponto"><title>' + esc('Projeção: ' + rs(proj)) + '</title></circle>';
      }
      svg += '<path d="' + real.map(function (p, k) { return (k ? 'L' : 'M') + x(p.i).toFixed(1) + ' ' + y(Number(p.v)).toFixed(1); }).join(' ') + '" class="g-linha g-real"/>';
      svg += '<circle cx="' + x(u.i).toFixed(1) + '" cy="' + y(ult).toFixed(1) + '" r="4" class="g-ponto"><title>' + esc(ddmm(burn[u.i].dia) + ': ' + rs(ult)) + '</title></circle>';
      real.forEach(function (p) {
        svg += '<rect x="' + (x(p.i) - 6).toFixed(1) + '" y="' + mT + '" width="12" height="' + (H - mT - mB) + '" fill="transparent"><title>' + esc(ddmm(burn[p.i].dia) + ': ' + rs(p.v)) + '</title></rect>';
      });
    }
    var cada = Math.max(1, Math.ceil(n / Math.floor((W - mE) / 30)));
    burn.forEach(function (b, i) {
      if (i % cada === 0 || i === n - 1) svg += '<text x="' + x(i).toFixed(1) + '" y="' + (H - 9) + '" class="g-eixo" text-anchor="middle">' + b.dia.slice(8, 10) + '</text>';
    });
    svg += '</svg>';
    var foraEscala = (m.niveis || []).filter(function (l) { return Number(l.acima_de) > topoV; });
    return '<div class="legenda"><span><i class="lg-real"></i>Realizado · ' + rs(ult) + '</span>' +
      (proj !== null ? '<span><i class="lg-proj"></i>Projeção · ' + rs(proj) + '</span>' : '') +
      (niveis.length ? '<span><i class="lg-nivel"></i>Níveis</span>' : '') + '</div>' + svg +
      (foraEscala.length ? '<p class="fraco nota">Fora da escala por enquanto: ' + foraEscala.map(function (l) { return esc(l.nome) + ' em ' + rsCurto(l.acima_de); }).join(', ') + '.</p>' : '');
  }

  // Insights da Minha página: no máximo 3, alvos vindos do banco (cic_config)
  function insightsMP(m) {
    var a = m.alvos || {}, out = [];
    var dec = function (v, c) { return Number(v).toLocaleString('pt-BR', { minimumFractionDigits: c, maximumFractionDigits: c }); };
    var cAlvo = Number(a.conversao_alvo), conv = m.conversao == null ? null : Number(m.conversao);
    if (conv !== null && cAlvo && conv < cAlvo) {
      var mais = Math.round((cAlvo - conv) * Number(m.contatos || 0));
      out.push(['Conversão', 'Sua conversão está em ' + pct(conv) + ' e o alvo é ' + pct(cAlvo, 0) + '. Faltam ' + dec((cAlvo - conv) * 100, 1) + ' pontos' +
        (mais > 0 ? ', o que daria ' + plural(mais, 'venda', 'vendas') + ' a mais com os ' + num(m.contatos) + ' contatos do mês.' : '.')]);
    }
    var tAlvo = Number(a.ticket_alvo), tk = m.ticket == null ? null : Number(m.ticket);
    if (tk !== null && tAlvo && tk < tAlvo) {
      out.push(['Ticket', 'Seu ticket líquido está em ' + rs(tk) + ' e o alvo é ' + rs(tAlvo) + '. São ' + rs(tAlvo - tk) + ' a mais por venda.']);
    }
    if (m.proximo_nivel && m.proximo_limite && Number(m.falta_proximo) <= Number(a.proximo_nivel_pct || 0) * Number(m.proximo_limite)) {
      out.push(['Próximo nível', 'Faltam ' + rs(m.falta_proximo) + ' para o ' + esc(m.proximo_nome) + ' (' + pct(m.proximo_pct) + ' sobre o total).']);
    }
    var t = m.tendencia, q = Number(a.queda_tendencia || 0.1);
    if (t) {
      var caiu = function (atual, antes) { return atual !== null && antes && (antes - atual) / antes >= q; };
      var rot = 'no mesmo dia do mês passado';
      if (caiu(conv, t.conversao)) out.push(['Tendência', 'Sua conversão caiu de ' + pct(t.conversao) + ' para ' + pct(conv) + ' ' + rot + '.']);
      else if (caiu(tk, t.ticket)) out.push(['Tendência', 'Seu ticket caiu de ' + rs(t.ticket) + ' para ' + rs(tk) + ' ' + rot + '.']);
      else if (caiu(m.vendas_dia == null ? null : Number(m.vendas_dia), t.vendas_dia)) out.push(['Tendência', 'Suas vendas por dia útil caíram de ' + dec(t.vendas_dia, 1) + ' para ' + dec(m.vendas_dia, 1) + ' ' + rot + '.']);
    }
    out = out.slice(0, 3);
    if (!out.length) return '';
    return bloco('Insights', 'Onde está o próximo ganho no mês.', '<div class="insights">' + out.map(function (x) {
      return '<div class="insight"><strong>' + x[0] + '</strong><p>' + x[1] + '</p></div>';
    }).join('') + '</div>');
  }

  function telaMinha(alvo, id) {
    carregando(alvo);
    var mes = mesAtual();
    Promise.all([
      sb.rpc('cic_vendedor_mes', { p_mes: mes }),
      sb.from('comissao_faixas').select('vigencia_inicio,nivel,nome,acima_de,pct').lte('vigencia_inicio', mes).order('vigencia_inicio', { ascending: false })
    ]).then(function (rr) {
      if (id !== pedido) return;
      var e = rr[0].error || rr[1].error;
      if (e) return falhou(alvo, e);
      var linhas = rr[0].data || [];
      var fx = rr[1].data || [];
      var vig = fx.length ? fx[0].vigencia_inicio : null;
      fx = fx.filter(function (f) { return f.vigencia_inicio === vig; }).sort(function (a, b) { return a.acima_de - b.acima_de; });
      if (!linhas.length) {
        alvo.innerHTML = '<p class="painel-msg">Seu acesso ainda não está ligado a um vendedor. Fale com a equipe WeRev.</p>';
        return;
      }
      var admin = perfil.papel === 'admin';
      var escolhido = admin ? (ler('cic-vendedor') || linhas[0].vendedor_slug) : linhas[0].vendedor_slug;
      var v = linhas.filter(function (l) { return l.vendedor_slug === escolhido; })[0] || linhas[0];
      var lf = Number(v.liquido_final) || 0;
      var marcos = fx.map(function (f) {
        return { valor: Number(f.acima_de), rotulo: f.nome + ' · ' + pct(f.pct), sub: Number(f.acima_de) > 0 ? 'acima de ' + rsCurto(f.acima_de) : 'desde a 1ª venda', atual: f.nivel === v.nivel };
      });
      var fimRegua = fx.length ? Number(fx[fx.length - 1].acima_de) * 1.25 : lf;
      var frase = v.proximo_nivel
        ? 'Faltam <strong>' + rs(v.falta_proximo) + '</strong> para o ' + esc(v.proximo_nome) + ' (' + pct(v.proximo_pct) + ' sobre o total).'
        : 'Você está no nível máximo da régua.';
      var seletor = admin ? '<label class="seletor"><span>Vendedor</span><select id="sel-vendedor">' + linhas.map(function (l) {
        return '<option value="' + esc(l.vendedor_slug) + '"' + (l.vendedor_slug === v.vendedor_slug ? ' selected' : '') + '>' + esc(l.vendedor_nome) + '</option>';
      }).join('') + '</select></label>' : '';
      alvo.innerHTML =
        '<div class="painel-cabeca"><p class="periodo">' + esc((admin ? v.vendedor_nome + ' · ' : '') + nomeMes(mes)) + '</p>' + seletor + '</div>' +
        '<div class="kpis">' +
        kpi('Líquido do mês', rs(lf), 'bruto ' + rs(v.vendas_bruto) + (Number(v.reembolsos_qtd) ? ' · já descontados os reembolsos' : ''), true) +
        kpi('Comissão', rs(v.comissao), esc(v.nivel_nome || '–') + ' · ' + pct(v.pct)) +
        kpi('Vendas', num(v.vendas_qtd), rs(v.vendas_liquido) + ' em vendas') +
        kpi('Reembolsos do mês', num(v.reembolsos_qtd), Number(v.reembolsos_qtd) ? rs(v.reembolsos_liquido) + ' abatidos' : 'nenhum') +
        kpi('Conversão', pct(v.conversao), num(v.vendas_qtd) + ' vendas · ' + num(v.contatos) + ' contatos ' + convTag(v.conversao, v.conversao_alvo)) +
        '</div>' +
        bloco('Régua de níveis', frase, fx.length ? regua(marcos, lf, { fim: Math.max(fimRegua, lf * 1.05) }) : '<p class="painel-msg">Régua do mês não cadastrada.</p>') +
        '<div id="mp-extra"></div>';
      var sel = $('sel-vendedor');
      if (sel) sel.addEventListener('change', function () { guardar('cic-vendedor', sel.value); telaMinha(alvo, ++pedido); });
      var extra = $('mp-extra');
      sb.rpc('cic_minha_pagina', { p_mes: mes, p_vendedor: admin ? v.vendedor_slug : null }).then(function (r2) {
        if (id !== pedido) return;
        if (r2.error) return falhou(extra, r2.error);
        var m = r2.data || {};
        extra.innerHTML = bloco('Faturamento da comissão acumulado no mês', 'Líquido por dia (vendas − reembolsos), a mesma régua da comissão. Projeção pelo ritmo de dia útil.',
          grafComissao(m, extra.clientWidth - 50)) + insightsMP(m);
      });
      $('bloco-links').hidden = false;
      carregarLinks(admin ? v.vendedor_nome : null);
    });
  }

  // ---------- Filtro de período e vendedor (Relatórios e Reembolsos) ----------
  var SEMANA = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  var filtro = null;           // { ini, fim, vend } compartilhado entre as duas telas
  var vendedoresCache = null;  // só admin

  function diaSemana(d) { return SEMANA[new Date(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, Number(d.slice(8, 10))).getDay()]; }
  function iniciais(nome) {
    var p = String(nome || '').trim().split(/\s+/);
    return ((p[0] || '').charAt(0) + (p.length > 1 ? p[p.length - 1].charAt(0) : '')).toUpperCase();
  }
  function pessoa(nome, inativo) {
    if (!nome) return '<span class="pessoa pessoa-sem"><i>–</i>Sem vendedor</span>';
    return '<span class="pessoa"><i>' + esc(iniciais(nome)) + '</i>' + esc(nome) + (inativo ? ' <span class="tag">inativo</span>' : '') + '</span>';
  }
  // +5531999990000 -> +55 31 99999-0000 (outros países ficam como vieram)
  function fone(t) {
    var m = /^\+55(\d{2})(\d{4,5})(\d{4})$/.exec(t || '');
    return m ? '+55 ' + m[1] + ' ' + m[2] + '-' + m[3] : (t || '–');
  }
  function plural(n, um, varios) { return num(n) + ' ' + (Number(n) === 1 ? um : varios); }

  // Monta a barra de filtro e chama recarregar() quando muda
  function barraFiltro(alvo, recarregar, comSem, semVend) {
    if (!filtro) filtro = { ini: mesAtual(), fim: hojeSP(), vend: '' };
    var admin = perfil.papel === 'admin';
    var opcoes = admin && !semVend ? '<label class="seletor"><span>Vendedor</span><select id="f-vend"><option value="">Todos</option>' +
      (comSem ? '<option value="_sem"' + (filtro.vend === '_sem' ? ' selected' : '') + '>Sem vendedor</option>' : '') +
      (vendedoresCache || []).map(function (v) {
        return '<option value="' + esc(v.utm_slug) + '"' + (filtro.vend === v.utm_slug ? ' selected' : '') + '>' + esc(v.nome) + (v.ativo === false ? ' (inativo)' : '') + '</option>';
      }).join('') + '</select></label>' : '';
    var botoes = PRESETS.map(function (pr) {
      return '<button type="button" class="preset' + (filtro.preset === pr[0] ? ' on' : '') + '" data-preset="' + pr[0] + '">' + pr[1] + '</button>';
    }).join('');
    alvo.innerHTML = '<div class="filtro">' +
      '<label class="seletor"><span>De</span><input type="date" id="f-ini" value="' + filtro.ini + '" max="' + hojeSP() + '"></label>' +
      '<label class="seletor"><span>Até</span><input type="date" id="f-fim" value="' + filtro.fim + '" max="' + hojeSP() + '"></label>' +
      '<div class="presets" role="group" aria-label="Período rápido">' + botoes + '</div>' +
      opcoes + '</div><div id="f-corpo"></div>';
    var muda = function () {
      var i = $('f-ini').value, f = $('f-fim').value;
      if (!i || !f) return;
      if (i > f) { var t = i; i = f; f = t; }
      var h = hojeSP();
      if (f > h) f = h;
      if (i > h) i = h;
      filtro.ini = i; filtro.fim = f;
      if ($('f-vend')) filtro.vend = $('f-vend').value;
      recarregar(++pedido);
    };
    // data editada na mão: nenhum preset fica ativo
    ['f-ini', 'f-fim'].forEach(function (k) { $(k).addEventListener('change', function () { filtro.preset = null; marcaPreset(alvo); muda(); }); });
    if ($('f-vend')) $('f-vend').addEventListener('change', muda);
    Array.prototype.forEach.call(alvo.querySelectorAll('.preset'), function (b) {
      b.addEventListener('click', function () {
        var d = datasPreset(b.dataset.preset);
        filtro.preset = b.dataset.preset;
        $('f-ini').value = d[0]; $('f-fim').value = d[1];
        marcaPreset(alvo);
        muda();
      });
    });
    return $('f-corpo');
  }
  // Presets do filtro de data (semana começa na segunda; datas de São Paulo)
  var PRESETS = [['hoje', 'Hoje'], ['ontem', 'Ontem'], ['semana', 'Essa semana'], ['semana_ant', 'Semana passada'], ['mes', 'Esse mês'], ['mes_ant', 'Mês passado']];
  function somaDias(d, n) {
    var x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10);
  }
  function datasPreset(k) {
    var h = hojeSP(), seg = somaDias(h, -((new Date(h + 'T12:00:00Z').getUTCDay() + 6) % 7)), ini1 = h.slice(0, 8) + '01';
    if (k === 'hoje') return [h, h];
    if (k === 'ontem') return [somaDias(h, -1), somaDias(h, -1)];
    if (k === 'semana') return [seg, h];
    if (k === 'semana_ant') return [somaDias(seg, -7), somaDias(seg, -1)];
    if (k === 'mes') return [ini1, h];
    var fimAnt = somaDias(ini1, -1);
    return [fimAnt.slice(0, 8) + '01', fimAnt];
  }
  function marcaPreset(alvo) {
    Array.prototype.forEach.call(alvo.querySelectorAll('.preset'), function (b) { b.classList.toggle('on', b.dataset.preset === filtro.preset); });
  }

  function aplicaVend(linhas) {
    if (!filtro.vend || filtro.vend === '_sem') return linhas;
    return linhas.filter(function (l) { return l.vendedor_slug === filtro.vend; });
  }
  function comVendedores(feito) {
    if (perfil.papel !== 'admin' || vendedoresCache) return feito();
    // inativos entram no filtro (etiqueta "inativo"): podem ter atividade no período
    sb.from('vendedores').select('utm_slug,nome,ativo').order('ativo', { ascending: false }).order('nome').then(function (r) {
      vendedoresCache = r.data || [];
      feito();
    });
  }
  function periodoTxt() { return ddmm(filtro.ini) + ' a ' + ddmm(filtro.fim); }

  // ---------- Relatórios: lista de vendas ----------
  function telaRelatorios(alvo, id) {
    carregando(alvo);
    comVendedores(function () {
      if (id !== pedido) return;
      var corpo = barraFiltro(alvo, carregar);
      carregar(id);
      function carregar(idc) {
        corpo.innerHTML = '<p class="painel-msg">Carregando...</p>';
        sb.rpc('cic_lista_vendas', { p_inicio: filtro.ini, p_fim: filtro.fim }).then(function (r) {
          if (idc !== pedido) return;
          if (r.error) return falhou(corpo, r.error);
          var linhas = aplicaVend(r.data || []);
          var total = linhas.reduce(function (a, l) { return a + Number(l.liquido); }, 0);
          var nReemb = linhas.filter(function (l) { return l.reembolsada; }).length;
          var cab = '<header class="lista-topo"><div><h2>Lista de vendas</h2><p>' + plural(linhas.length, 'venda', 'vendas') + ' em ' + periodoTxt() +
            (nReemb ? ' · ' + plural(nReemb, 'reembolsada', 'reembolsadas') : '') + '</p></div>' +
            '<div class="lista-total"><span>Total líquido</span><strong>' + rs(total) + '</strong></div></header>';
          if (!linhas.length) { corpo.innerHTML = '<section class="bloco">' + cab + '<p class="painel-msg">Nenhuma venda no período.</p></section>'; return; }
          var rows = linhas.map(function (l) {
            var valor = l.reembolsada
              ? '<span class="valor-riscado">' + rs(l.liquido) + '</span><span class="tag tag-abaixo" title="Reembolsada em ' + (l.reembolso_data ? ddmm(l.reembolso_data) : '') + '">Reembolsada</span>'
              : '<span class="valor-ok">' + rs(l.liquido) + '</span>';
            return '<tr><td><strong>' + ddmm(l.data) + '</strong> <span class="fraco">' + diaSemana(l.data) + '</span></td>' +
              '<td class="fraco">' + esc(String(l.hora || '').slice(0, 5)) + '</td>' +
              '<td class="quebra">' + esc(l.cliente || '–') + '</td>' +
              '<td class="fraco">' + esc(fone(l.telefone)) + '</td>' +
              '<td>' + pessoa(l.vendedor_nome) + '</td>' +
              '<td class="quebra">' + esc(l.produto || '–') + (l.oferta ? '<div class="fraco">' + esc(l.oferta) + '</div>' : '') + '</td>' +
              '<td class="n">' + valor + '</td></tr>';
          }).join('');
          corpo.innerHTML = '<section class="bloco">' + cab + '<div class="tabela-rolagem"><table class="tabela lista">' +
            '<thead><tr><th>Data</th><th>Hora</th><th>Cliente</th><th>Telefone</th><th>Vendedor</th><th>Produto</th><th class="n">Valor</th></tr></thead>' +
            '<tbody>' + rows + '</tbody></table></div></section>';
        });
      }
    });
  }

  // ---------- Reembolsos ----------
  function telaReembolsos(alvo, id) {
    carregando(alvo);
    comVendedores(function () {
      if (id !== pedido) return;
      var corpo = barraFiltro(alvo, carregar);
      carregar(id);
      function carregar(idc) {
        corpo.innerHTML = '<p class="painel-msg">Carregando...</p>';
        var par = { p_inicio: filtro.ini, p_fim: filtro.fim };
        Promise.all([sb.rpc('cic_lista_reembolsos', par), sb.rpc('cic_lista_vendas', par)]).then(function (rr) {
          if (idc !== pedido) return;
          var e = rr[0].error || rr[1].error;
          if (e) return falhou(corpo, e);
          var reemb = aplicaVend(rr[0].data || []), vendas = aplicaVend(rr[1].data || []);
          var abatido = reemb.reduce(function (a, l) { return a + Number(l.liquido); }, 0);
          var vendido = vendas.reduce(function (a, l) { return a + Number(l.liquido); }, 0);
          var h = '<div class="kpis">' +
            kpi('Reembolsos', num(reemb.length), periodoTxt(), true) +
            kpi('Líquido abatido', rs(abatido), 'no período') +
            kpi('Sobre o vendido', vendido > 0 ? pct(abatido / vendido) : '–', rs(vendido) + ' vendidos no período') + '</div>';
          if (!reemb.length) {
            corpo.innerHTML = h + '<section class="bloco"><p class="painel-msg vazio">Nenhum reembolso em ' + periodoTxt() + '.</p></section>';
            return;
          }
          var rows = reemb.map(function (l) {
            return '<tr><td><strong>' + ddmm(l.reembolso_data) + '</strong> <span class="fraco">' + diaSemana(l.reembolso_data) + '</span></td>' +
              '<td class="fraco">' + ddmm(l.venda_data) + '</td>' +
              '<td class="quebra">' + esc(l.cliente || '–') + '</td>' +
              '<td class="fraco">' + esc(fone(l.telefone)) + '</td>' +
              '<td>' + pessoa(l.vendedor_nome) + '</td>' +
              '<td class="quebra">' + esc(l.produto || '–') + '</td>' +
              '<td class="n"><span class="valor-abatido">− ' + rs(l.liquido) + '</span></td></tr>';
          }).join('');
          corpo.innerHTML = h + '<section class="bloco"><header class="lista-topo"><div><h2>Lista de reembolsos</h2><p>' +
            plural(reemb.length, 'reembolso', 'reembolsos') + ' em ' + periodoTxt() + '</p></div></header>' +
            '<div class="tabela-rolagem"><table class="tabela lista"><thead><tr><th>Reembolso</th><th>Venda</th><th>Cliente</th><th>Telefone</th>' +
            '<th>Vendedor</th><th>Produto</th><th class="n">Valor abatido</th></tr></thead><tbody>' + rows + '</tbody></table></div></section>';
        });
      }
    });
  }

  // ---------- Telas de gestão (admin) ----------
  // Barras horizontais: itens [{rotulo, valor, sub}]
  function barrasH(itens, opc) {
    opc = opc || {};
    if (!itens.length) return '<p class="painel-msg vazio">' + esc(opc.vazio || 'Nada no período.') + '</p>';
    var max = Math.max.apply(null, itens.map(function (i) { return Number(i.valor) || 0; }).concat([1]));
    var total = itens.reduce(function (a, i) { return a + (Number(i.valor) || 0); }, 0);
    return '<div class="barras-h">' + itens.map(function (i) {
      var v = Number(i.valor) || 0;
      return '<div class="bh"><div class="bh-rotulo">' + esc(i.rotulo) + (i.sub ? '<span>' + i.sub + '</span>' : '') + '</div>' +
        '<div class="bh-trilho"><div class="bh-barra" style="width:' + (v / max * 100).toFixed(1) + '%;background:' + (i.cor || opc.cor || COR.comercial) + '"></div></div>' +
        '<div class="bh-valor">' + (opc.moeda ? rs(v) : num(v)) + (opc.semPct ? '' : ' <span>' + pct(total ? v / total : 0, 0) + '</span>') + '</div></div>';
    }).join('') + '</div>';
  }
  function soma(lista, k) { return lista.reduce(function (a, x) { return a + (Number(x[k]) || 0); }, 0); }
  function horas(h) {
    if (h === null || h === undefined) return '–';
    h = Number(h);
    if (h < 24) return h.toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + ' h';
    return (h / 24).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + ' dias';
  }
  function telaGestao(alvo, id, comSem, buscar) {
    carregando(alvo);
    comVendedores(function () {
      if (id !== pedido) return;
      var corpo = barraFiltro(alvo, carregar, comSem);
      carregar(id);
      function carregar(idc) {
        corpo.innerHTML = '<p class="painel-msg">Carregando...</p>';
        buscar(corpo, idc);
      }
    });
  }
  function rpcGestao(nome, comVend) {
    var par = { p_inicio: filtro.ini, p_fim: filtro.fim };
    if (comVend) par.p_vendedor = filtro.vend || null;
    return sb.rpc(nome, par);
  }

  // minutos -> "6 min" / "1 h 05"
  function minutos(m) {
    if (m === null || m === undefined) return '–';
    m = Math.round(Number(m));
    if (m < 60) return m + ' min';
    return Math.floor(m / 60) + ' h ' + String(m % 60).padStart(2, '0');
  }
  function iconeHTML(nome) {
    var svg = (window.CIC_ICONES || {})[nome];
    return svg ? '<svg class="ic" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + svg.replace(/^\s*<svg[^>]*>/, '') + '</svg>' : '';
  }
  function telaDesempenho(alvo, id) {
    telaGestao(alvo, id, false, function (corpo, idc) {
      rpcGestao('cic_desempenho', false).then(function (r) {
        if (idc !== pedido) return;
        if (r.error) return falhou(corpo, r.error);
        var linhas = (r.data || []).slice().sort(function (a, b) { return Number(b.liquido) - Number(a.liquido); });
        if (!linhas.length) { corpo.innerHTML = '<p class="painel-msg vazio">Nenhum vendedor ativo.</p>'; return; }
        var total = soma(linhas, 'liquido');
        var du = linhas[0].dias_uteis;
        var tab = '<div class="tabela-rolagem"><table class="tabela tabela-rank"><thead><tr><th>Vendedor</th><th class="n">Faturamento</th><th class="n">Vendas</th><th class="n">Ticket médio</th><th>Participação</th></tr></thead><tbody>' +
          linhas.map(function (l, i) {
            var rei = i === 0 && Number(l.liquido) > 0;
            var part = total > 0 ? Number(l.liquido) / total : 0;
            var pos = i < 3 ? '<span class="medalha m' + (i + 1) + '" title="' + (i + 1) + 'º lugar">' + (i + 1) + '</span>' : '<span class="rank">#' + (i + 1) + '</span>';
            return '<tr' + (rei ? ' class="rei"' : '') + '><td><div class="rank-nome">' + pos + pessoa(l.vendedor_nome, l.vendedor_ativo === false) +
              (rei ? '<span class="selo-rei">' + iconeHTML('coroa') + 'The King</span>' : '') + '</div></td>' +
              '<td class="n"><strong>' + (Number(l.liquido) > 0 ? rs(l.liquido) : '–') + '</strong></td><td class="n">' + num(l.vendas_qtd) + '</td>' +
              '<td class="n">' + (l.ticket == null ? '–' : rs(l.ticket)) + '</td>' +
              '<td><div class="part"><div class="part-barra"><i style="width:' + (part * 100).toFixed(1) + '%"></i></div><span>' + pct(part) + '</span></div></td></tr>';
          }).join('') + '</tbody></table></div>';
        var sel = filtro.vend && filtro.vend !== '_sem' ? linhas.filter(function (l) { return l.vendedor_slug === filtro.vend; }) : linhas;
        var kv = function (rot, val, dica) { return '<div class="vd-kv"><span' + (dica ? ' class="dica" title="' + esc(dica) + '"' : '') + '>' + rot + '</span><b>' + val + '</b></div>'; };
        var cards = '<div class="vd-cards">' + sel.map(function (l) {
          var lrtDica = 'Minutos entre a última entrada em etapa anterior e a primeira entrada em Em Contato do negócio (mediana de ' +
            plural(l.lrt_n, 'negócio', 'negócios') + '). ' + plural(l.lrt_mais24, 'passou', 'passaram') + ' de 24 h.';
          return '<div class="vd-card"><div class="vd-topo"><span class="pessoa"><i>' + esc(iniciais(l.vendedor_nome)) + '</i></span>' +
            '<div class="vd-id"><div class="vd-nome">' + esc(l.vendedor_nome) + (l.vendedor_ativo === false ? ' <span class="tag">inativo</span>' : '') + '</div><div class="vd-fat">' + rs(l.liquido) + '</div></div>' +
            '<div class="vd-conv">' + pct(l.conversao) + '<span>conversão</span></div></div>' +
            '<div class="vd-bl"><div class="vd-bl-tit">Funil</div>' +
              kv('Leads', num(l.entradas_0)) + kv('Em Contato', num(l.contatos)) +
              kv('LRT (mediana)', minutos(l.lrt_mediana), lrtDica) +
              kv('Leads em contato p/ venda', Number(l.vendas_qtd) > 0 ? (Number(l.contatos) / Number(l.vendas_qtd)).toLocaleString('pt-BR', { maximumFractionDigits: 1, minimumFractionDigits: 1 }) : '–') + '</div>' +
            '<div class="vd-bl"><div class="vd-bl-tit">Resultado</div>' +
              kv('Vendas', num(l.vendas_qtd)) + kv('Faturamento', rs(l.liquido)) + kv('Ticket médio', l.ticket == null ? '–' : rs(l.ticket)) +
              kv('Média vendas/dia', l.media_dia == null ? '–' : Number(l.media_dia).toLocaleString('pt-BR', { maximumFractionDigits: 1, minimumFractionDigits: 1 }), 'Vendas ÷ ' + plural(du, 'dia útil decorrido', 'dias úteis decorridos') + ' no período') + '</div></div>';
        }).join('') + '</div>';
        corpo.innerHTML = '<p class="periodo">' + periodoTxt() + '</p>' +
          bloco('Desempenho por vendedor', 'Faturamento líquido das vendas na Hubla no período. Participação = % do faturamento do time.', tab) +
          bloco('Por vendedor', 'Leads: negócios que entraram na base. Em Contato: pessoas únicas. Conversão = vendas ÷ Em Contato.', cards);
      });
    });
  }

  function telaPassagem(alvo, id) {
    telaGestao(alvo, id, true, function (corpo, idc) {
      rpcGestao('cic_taxa_passagem_origem', true).then(function (r) {
        if (idc !== pedido) return;
        if (r.error) return falhou(corpo, r.error);
        var todas = r.data || [];
        var geral = todas.filter(function (e) { return e.origem === null || e.origem === undefined; });
        // origens na ordem do banco (por volume de negócios)
        var origens = [];
        todas.forEach(function (e) { if (e.origem != null && origens.indexOf(e.origem) < 0) origens.push(e.origem); });
        var dicaEnt = 'um negócio por entrada no CRM; a mesma pessoa pode ter mais de um';
        var dicaConv = 'vendas comerciais ÷ pessoas únicas que passaram por Em Contato no período (a mesma conversão da Home)';
        var temEtapa = function (e) { return e.ordem !== null && e.ordem !== undefined; };
        var et = geral.filter(temEtapa);
        var max = Math.max.apply(null, et.map(function (e) { return Number(e.entraram); }).concat([1]));
        var funil = '<div class="funil">' + et.map(function (e) {
          return '<div class="funil-etapa"><div class="funil-nome"><strong>' + e.ordem + '. ' + esc(e.etapa) + '</strong>' +
            '<span title="' + dicaEnt + '">' + num(e.entraram) + ' negócios entraram</span></div>' +
            '<div class="funil-trilho"><div class="funil-barra" style="width:' + (Number(e.entraram) / max * 100).toFixed(1) + '%"></div></div>' +
            '<div class="funil-pct"><strong>' + pct(e.passagem, 0) + '</strong><span>passaram</span></div></div>';
        }).join('') + '</div>';
        var g0 = geral[0] || {};
        var conv = function (x) {
          return kpi('Conversão etapa 2 > venda', x.conversao == null ? '–' : pct(x.conversao),
            '<span title="' + esc(dicaConv) + '" class="dica">' + plural(x.vendas_total || 0, 'venda', 'vendas') + ' ÷ ' + num(x.pessoas_e2) + ' em contato</span>', true);
        };
        var quadros = origens.map(function (o) {
          var ls = todas.filter(function (e) { return e.origem === o; });
          var x = ls[0] || {};
          var mx = Math.max.apply(null, ls.filter(temEtapa).map(function (e) { return Number(e.entraram); }).concat([1]));
          // barra: comprimento = entraram (relativo à maior etapa da origem); parte escura = quantos passaram
          var barra = function (e) {
            var w = Number(e.entraram) / mx * 100, f = Number(e.entraram) ? Number(e.avancaram) / Number(e.entraram) * 100 : 0;
            return '<div class="oc-barra" title="' + esc(num(e.entraram) + ' entraram, ' + num(e.avancaram) + ' avançaram') + '"><span style="width:' + w.toFixed(1) + '%"><i style="width:' + Math.min(100, f).toFixed(1) + '%"></i></span></div>';
          };
          var tab = ls.filter(function (e) { return temEtapa(e) || Number(e.vendas); }).map(function (e) {
            if (!temEtapa(e)) return ['<span class="fraco">Sem negócio no CRM</span>', '–', '–', '–', num(e.vendas)];
            return [e.ordem + '. ' + esc(String(e.etapa).replace(/\s*\(.*\)$/, '')) + barra(e), num(e.entraram), num(e.avancaram), pct(e.passagem), num(e.vendas)];
          });
          return '<section class="bloco origem-card"><header class="oc-topo"><h2>' + esc(o) + '</h2>' +
            '<div class="oc-conv" title="' + esc(dicaConv) + '"><b>' + (x.conversao == null ? '–' : pct(x.conversao)) + '</b><span>conversão etapa 2 > venda</span>' +
            '<em>' + plural(x.vendas_total || 0, 'venda', 'vendas') + ' ÷ ' + num(x.pessoas_e2) + ' em contato</em></div></header>' +
            tabela(['Etapa', { t: 'Entraram', dica: dicaEnt }, 'Avançaram', '%', 'Vendas'], tab, [1, 2, 3, 4]) +
            '<p class="fraco oc-leg"><i class="oc-l1"></i>entraram <i class="oc-l2"></i>avançaram</p></section>';
        }).join('');
        corpo.innerHTML = '<div class="kpis kpis-2">' + conv(g0) + kpi('Vendas comerciais', num(g0.vendas_total), 'crédito pelo link do vendedor') + '</div>' +
          bloco('Funil do CRM', 'Negócios que entraram em cada etapa no período e quantos passaram adiante (etapa seguinte ou venda comercial).', funil) +
          (origens.length ? '<h3 class="sub-h sec-h">Por origem</h3><p class="fraco nota">Origem do negócio (último evento com origem). Venda pela origem do lead antes da compra; venda sem lead conta no funil padrão.</p>' +
            '<div class="origens">' + quadros + '</div>' : '');
      });
    });
  }

  // Donut com top 6 + "Outros motivos"; legenda com rótulo, qtd e %
  var COR_PIZZA = ['#1f2b38', '#844420', '#8e6e59', '#4f6274', '#b8875f', '#a39e9a'];
  function pizza(itens, opc) {
    opc = opc || {};
    itens = itens.filter(function (x) { return Number(x.valor) > 0; }).sort(function (a, b) { return b.valor - a.valor; });
    if (opc.ordem) itens = opc.ordem(itens);
    var total = itens.reduce(function (a, x) { return a + Number(x.valor); }, 0);
    if (!total) return '<p class="painel-msg vazio">' + esc(opc.vazio || 'Sem dados no período.') + '</p>';
    var top = opc.semOutros ? itens : itens.slice(0, 6);
    var resto = opc.semOutros ? 0 : itens.slice(6).reduce(function (a, x) { return a + Number(x.valor); }, 0);
    if (resto) top = top.concat([{ rotulo: opc.outros || 'Outros motivos', valor: resto, outros: true }]);
    var R = 15.915, ac = 0, tam = opc.tam || 132;
    var arcos = top.map(function (x, k) {
      var f = Number(x.valor) / total * 100, cor = x.outros ? '#d9d2cf' : COR_PIZZA[k % COR_PIZZA.length];
      var a = '<circle r="' + R + '" cx="21" cy="21" fill="none" stroke="' + cor + '" stroke-width="6.5" stroke-dasharray="' + f.toFixed(3) + ' ' + (100 - f).toFixed(3) + '" stroke-dashoffset="' + (25 - ac).toFixed(3) + '"><title>' + esc(x.rotulo + ': ' + num(x.valor) + ' (' + pct(x.valor / total) + ')') + '</title></circle>';
      ac += f; x.cor = cor; return a;
    }).join('');
    var svg = '<svg class="pizza-svg" viewBox="0 0 42 42" width="' + tam + '" height="' + tam + '" role="img" aria-label="' + esc(opc.rotulo || 'Distribuição') + '">' +
      '<circle r="' + R + '" cx="21" cy="21" fill="none" stroke="#efeae8" stroke-width="6.5"/>' + arcos +
      '<text x="21" y="21" class="pizza-num" text-anchor="middle" dominant-baseline="central">' + num(total) + '</text></svg>';
    var leg = '<ul class="pizza-leg">' + top.map(function (x) {
      return '<li><i style="background:' + x.cor + '"></i><span class="pizza-rot">' + esc(x.rotulo) + '</span><b>' + num(x.valor) + '</b><em>' + pct(x.valor / total) + '</em></li>';
    }).join('') + '</ul>';
    return '<div class="pizza">' + svg + leg + '</div>';
  }

  function telaMotivos(alvo, id) {
    telaGestao(alvo, id, true, function (corpo, idc) {
      rpcGestao('cic_motivos_perda', true).then(function (r) {
        if (idc !== pedido) return;
        if (r.error) return falhou(corpo, r.error);
        // os motivos do grupo cs (detrator/blocklist, reembolso) são dados pelo comercial: contam como motivo normal (09/11)
        var linhas = r.data || [];
        var agrupa = function (lista, chave) {
          var m = {};
          lista.forEach(function (l) { m[l[chave]] = (m[l[chave]] || 0) + Number(l.qtd); });
          return Object.keys(m).map(function (k) { return { rotulo: k, valor: m[k] }; }).sort(function (a, b) { return b.valor - a.valor; });
        };
        var total = soma(linhas, 'qtd');
        var card = function (titulo, lista, extra) {
          var t = soma(lista, 'qtd');
          return '<div class="pz-card"><div class="pz-topo"><div class="pz-nome">' + titulo + '</div>' +
            '<div class="pz-tot"><b>' + num(t) + '</b><span>' + pct(total ? t / total : 0) + ' das perdas</span></div></div>' +
            pizza(agrupa(lista, 'motivo'), { tam: 116, rotulo: 'Motivos de perda' }) + (extra || '') + '</div>';
        };
        var porOrigem = agrupa(linhas, 'origem').map(function (o) {
          return card(esc(o.rotulo), linhas.filter(function (l) { return l.origem === o.rotulo; }));
        }).join('');
        var vends = agrupa(linhas, 'vendedor_nome');
        var porVend = vends.map(function (v) {
          var ls = linhas.filter(function (l) { return l.vendedor_nome === v.rotulo; });
          var sem = !ls[0] || !ls[0].vendedor_slug;
          return card(sem ? pessoa(null) : pessoa(v.rotulo, ls[0].vendedor_ativo === false), ls);
        }).join('');
        var etapas = {};
        linhas.forEach(function (l) { var k = l.etapa_ordem == null ? 99 : l.etapa_ordem; etapas[k] = etapas[k] || { rotulo: (l.etapa_ordem == null ? '' : l.etapa_ordem + '. ') + l.etapa, valor: 0, k: k }; etapas[k].valor += Number(l.qtd); });
        var etapaItens = Object.keys(etapas).map(function (k) { return etapas[k]; });
        var porEtapa = etapaItens.slice().sort(function (a, b) { return a.k - b.k; }).map(function (e) {
          return card(esc(e.rotulo), linhas.filter(function (l) { return (l.etapa_ordem == null ? 99 : l.etapa_ordem) === e.k; }));
        }).join('');
        corpo.innerHTML = '<div class="kpis kpis-2">' +
          kpi('Perdas no período', num(total), '', true) +
          kpi('Motivos diferentes', num(agrupa(linhas, 'motivo').length), '') + '</div>' +
          '<div class="duas">' +
          bloco('Por motivo', 'Todas as perdas do período. Top 6 + outros motivos.', pizza(agrupa(linhas, 'motivo'), { vazio: 'Nenhuma perda no período.', rotulo: 'Perdas por motivo' })) +
          bloco('Etapa da perda', 'Última etapa do negócio antes de ser perdido.', pizza(etapaItens, { semOutros: true, outros: 'Outras etapas', rotulo: 'Perdas por etapa',
            ordem: function (it) { return it.slice().sort(function (a, b) { return a.k - b.k; }); } })) + '</div>' +
          bloco('Motivos por etapa', 'Motivos de perda em cada etapa do CRM (última etapa antes da perda). % sobre o total de perdas do período.', porEtapa ? '<div class="pz-grade">' + porEtapa + '</div>' : '<p class="painel-msg vazio">Nenhuma perda no período.</p>') +
          bloco('Motivo de perda por origem', 'Origem do negócio. % sobre o total de perdas do período.', porOrigem ? '<div class="pz-grade">' + porOrigem + '</div>' : '<p class="painel-msg vazio">Nenhuma perda no período.</p>') +
          bloco('Motivos por vendedor', 'Dono do negócio no CRM. % sobre o total de perdas do período.', porVend ? '<div class="pz-grade">' + porVend + '</div>' : '<p class="painel-msg vazio">Nenhuma perda no período.</p>');
      });
    });
  }

  function telaCiclo(alvo, id) {
    telaGestao(alvo, id, true, function (corpo, idc) {
      rpcGestao('cic_ciclo_venda', true).then(function (r) {
        if (idc !== pedido) return;
        if (r.error) return falhou(corpo, r.error);
        var linhas = r.data || [];
        var lado = function (tipo, titulo, sub, cor) {
          var t = linhas.filter(function (l) { return l.tipo === tipo && l.vendedor_slug === '_time'; })[0];
          if (!t || !Number(t.casos)) return bloco(titulo, sub, '<p class="painel-msg vazio">Sem casos no período.</p>' +
            (t && Number(t.sem_historico) ? '<p class="fraco">' + plural(t.sem_historico, 'caso', 'casos') + ' sem histórico (sem negócio no CRM antes da compra ou desfecho a menos de 6 min da entrada).</p>' : ''));
          var vend = linhas.filter(function (l) { return l.tipo === tipo && l.vendedor_slug !== '_time'; });
          return bloco(titulo, sub,
            '<div class="kpis kpis-2">' + kpi('Mediana', horas(t.mediana_h), plural(t.casos, 'caso', 'casos'), true) + kpi('Média', horas(t.media_h), '') + '</div>' +
            '<h3 class="sub-h">Faixas</h3>' + barrasH([
              { rotulo: 'Até 1 dia', valor: t.ate_1d }, { rotulo: '1 a 3 dias', valor: t.de_1a3d },
              { rotulo: '3 a 7 dias', valor: t.de_3a7d }, { rotulo: 'Mais de 7 dias', valor: t.mais_7d }], { cor: cor }) +
            '<h3 class="sub-h">Por vendedor</h3>' + tabela(['Vendedor', 'Casos', 'Mediana', 'Média'], vend.map(function (v) {
              return [pessoa(v.vendedor_slug === '_sem' ? null : v.vendedor_nome, v.vendedor_ativo === false), num(v.casos), horas(v.mediana_h), horas(v.media_h)];
            }), [1, 2, 3]) +
            (Number(t.sem_historico) ? '<p class="fraco nota">' + plural(t.sem_historico, 'caso', 'casos') + ' sem histórico ficaram fora (sem negócio no CRM antes da compra ou desfecho a menos de 6 min da entrada).</p>' : ''));
        };
        corpo.innerHTML = '<div class="duas">' +
          lado('venda', 'Até a venda', 'Da entrada do negócio no CRM até a venda comercial na Hubla (crédito pelo link do vendedor).', COR.comercial) +
          lado('perda', 'Até a perda', 'Da entrada até a perda comercial (sem as saídas CS).', COR.perda) + '</div>';
      });
    });
  }

  // ---------- Mensageria (admin) ----------
  function telaMensageria(alvo, id) {
    carregando(alvo);
    if (id !== pedido) return;
    var corpo = barraFiltro(alvo, carregar, false, true);
    carregar(id);
    function carregar(idc) {
      corpo.innerHTML = '<p class="painel-msg">Carregando...</p>';
      sb.rpc('cic_mensageria', { p_inicio: filtro.ini, p_fim: filtro.fim }).then(function (r) {
        if (idc !== pedido) return;
        if (r.error) return falhou(corpo, r.error);
        var d = r.data || {}, re = d.resumo || {};
        var reais = function (v) { return v === null || v === undefined ? '–' : rs(v); };
        var cards = '<div class="kpis">' +
          kpi('Custo estimado', reais(re.custo_total), 'templates + serviço' + (Number(re.franquia_desconto) ? ' − franquia ' + rs(re.franquia_desconto) : '') + ' · rate card', true) +
          kpi('Custo por venda', reais(re.custo_por_venda), plural(re.vendas_comercial || 0, 'venda', 'vendas') + ' do comercial') +
          kpi('Templates entregues', num(re.templates_entregues), num(re.templates_enviados) + ' enviados · ' + num(re.falhas) + ' falhas') +
          kpi('Entrega', pct(re.taxa_entrega), 'entregues ÷ enviados') +
          kpi('Leitura', pct(re.taxa_leitura), num(re.lidos) + ' lidos') +
          kpi('Cliques', pct(re.taxa_cliques), num(re.cliques) + ' cliques únicos · só automações') +
          kpi('Leads etapa 0', num(re.leads_e0), re.taxa_leads_e0 == null ? '–' : pct(re.taxa_leads_e0) + ' dos entregues') +
          kpi('Custo por lead E0', re.custo_por_lead_e0 == null ? '–' : reais(re.custo_por_lead_e0), 'broadcasts + automações ÷ leads') +
          kpi('Bloqueios', num(re.bloqueios), pct(re.taxa_bloqueios) + ' dos entregues · ' + num(re.bloqueios_com_copy) + ' com copy') + '</div>';
        var origem = barrasH([
          { rotulo: 'Broadcasts', valor: re.custo_broadcast || 0, cor: COR.comercial },
          { rotulo: 'Automações', valor: re.custo_automacao || 0, cor: COR.automacao },
          { rotulo: 'Vendedores', valor: re.custo_vendedor || 0, cor: COR.vendedor }], { moeda: true });
        var cat = barrasH((d.por_categoria || []).map(function (c) {
          return { rotulo: c.categoria, valor: c.custo || 0, sub: num(c.entregues) + ' entregues' };
        }), { moeda: true, vazio: 'Nenhum template entregue no período.' });
        var sessao = '<p class="fraco nota">Serviço (mensagem que não é template): ' + num(re.servico_msgs) + ' no período, ' + reais(re.custo_servico_bruto) +
          ' brutos. Franquia de 1.000 por mês: ' + num(re.franquia_msgs) + ' usadas no período, desconto de ' + reais(re.franquia_desconto) +
          ' no total (não rateado). Custo por origem é bruto, antes da franquia.</p>';
        var porDia = grafBarras(d.custo_dia || [], [
          { chave: 'broadcast', nome: 'Broadcasts', cor: COR.comercial },
          { chave: 'vendedor', nome: 'Vendedores', cor: COR.vendedor },
          { chave: 'automacao', nome: 'Automações', cor: COR.automacao }],
          { largura: corpo.clientWidth - 40, rotulo: 'Custo de WhatsApp por dia', linha: { chave: 'templates', nome: 'Templates entregues', cor: '#c49a3a' } });
        var semCli = '<span class="fraco" title="A API do Unnichat não informa cliques de broadcast">–</span>';
        // % só quando a cabe em b (E2 pode vir de lead que entrou antes do período)
        var de = function (a, b) { return Number(b) > 0 && Number(a) <= Number(b) ? '<div class="fraco">' + pct(a / b) + '</div>' : ''; };
        var custoPor = function (c, q) { return Number(q) > 0 ? rs(c / q) : '–'; };
        var linhasCamp = (d.campanhas || []).map(function (c, i) {
          var cab = '<tr class="camp" data-camp="' + i + '" tabindex="0" aria-expanded="false">' +
            '<td><div class="camp-nome"><span class="seta">▸</span><div><div class="nome-longo">' + esc(c.campanha) + '</div><div class="fraco">' + plural(c.broadcasts, 'lote', 'lotes') + '</div></div></div></td>' +
            '<td>' + dataHora(c.ultimo) + '</td><td class="n">' + num(c.contatos) + '</td><td class="n">' + num(c.entregues) + de(c.entregues, c.contatos) + '</td>' +
            '<td class="n">' + num(c.lidos) + de(c.lidos, c.entregues) + '</td><td class="n">' + semCli + '</td><td class="n">' + num(c.falhas) + de(c.falhas, c.contatos) + '</td>' +
            '<td class="n"><strong>' + reais(c.custo) + '</strong></td>' +
            '<td class="n">' + num(c.leads_e0) + de(c.leads_e0, c.entregues) + '</td>' +
            '<td class="n">' + custoPor(c.custo, c.leads_e0) + '</td>' +
            '<td class="n">' + num(c.leads_e2) + de(c.leads_e2, c.leads_e0) + '</td>' +
            '<td class="n">' + num(c.vendas) + (Number(c.vendas) > 0 ? '<div class="fraco">' + custoPor(c.custo, c.vendas) + '/venda</div>' : '') + '</td>' +
            '<td class="n">' + num(c.bloqueios) + de(c.bloqueios, c.entregues) + '</td></tr>';
          return cab + (c.lotes || []).map(function (l) {
            var lt = (String(l.nome).match(/_(\d+_LT\d+)$/i) || [])[1];
            return '<tr class="lote" data-de="' + i + '" hidden><td><div class="nome-longo">' + esc(lt ? lt.replace('_', ' · ') : l.nome) + '</div>' +
              '<div class="fraco">' + esc(l.template || '–') + (l.categoria ? ' · ' + esc(l.categoria) : '') + '</div></td>' +
              '<td>' + dataHora(l.disparo) + '</td><td class="n">' + num(l.contatos) + '</td><td class="n">' + num(l.entregues) + de(l.entregues, l.contatos) + '</td>' +
              '<td class="n">' + num(l.lidos) + de(l.lidos, l.entregues) + '</td><td class="n">' + semCli + '</td><td class="n">' + num(l.falhas) + de(l.falhas, l.contatos) + '</td>' +
              '<td class="n">' + reais(l.custo) + '</td><td colspan="5"></td></tr>';
          }).join('');
        }).join('');
        var cabCamp = ['Campanha', 'Último disparo', 'Contatos', 'Entregues', 'Lidos', 'Cliques', 'Falhas', 'Custo', 'Leads (E0)', 'Custo/lead E0', 'Em contato (E2)', 'Vendas', 'Bloqueios'];
        var tabCamp = '<div class="tabela-rolagem"><table class="tabela tabela-camp"><thead><tr>' + cabCamp.map(function (c, i) {
          return '<th' + (i > 1 ? ' class="n"' : '') + '>' + esc(c) + '</th>'; }).join('') + '</tr></thead><tbody>' + linhasCamp + '</tbody></table></div>';
        var aus = (d.automacoes || []).map(function (a) {
          return [esc(a.automacao) + '<div class="fraco">' + esc(a.pasta || '') + '</div>', num(a.templates_enviados), num(a.templates_entregues),
            num(a.lidos) + de(a.lidos, a.templates_entregues), a.taxa_cliques == null ? '–' : pct(a.taxa_cliques) + '<div class="fraco">' + num(a.cliques) + ' cliques</div>',
            num(a.sessao_entregues), esc(a.categoria || '–'), '<strong>' + reais(a.custo) + '</strong>'];
        });
        var fams = (d.familias || []).map(function (f) {
          return [esc(f.familia), num(f.leads_e0), num(f.leads_e2) + de(f.leads_e2, f.leads_e0), num(f.vendas) + de(f.vendas, f.leads_e2), num(f.bloqueios)];
        });
        var vds = (d.vendedores || []).map(function (v) {
          return [pessoa(v.vendedor, v.ativo === false), num(v.servico), num(v.contatos), num(v.tpl_utl), num(v.tpl_mkt), '<strong>' + reais(v.custo) + '</strong>', num(v.vendas), reais(v.custo_por_venda)];
        });
        var fonte = (d.preco || [])[0];
        var precoTxt = (d.preco || []).map(function (p) {
          return esc(p.categoria.toLowerCase()) + ' R$ ' + Number(p.preco).toLocaleString('pt-BR', { minimumFractionDigits: 4 });
        }).join(' · ');
        corpo.innerHTML = cards +
          '<div class="duas">' + bloco('Custo por origem', 'Templates e serviço, antes da franquia.', origem) + bloco('Custo por categoria', 'Entregues x preço da categoria (SERVICE = serviço, antes da franquia).', cat) + '</div>' +
          sessao +
          bloco('Custo por dia', 'Barras: custo em R$ por origem, antes da franquia. Linha: templates entregues no dia. Vendedores do dia só entram após a coleta das 23:40.', porDia) +
          bloco('Broadcasts por campanha', 'Só os do comercial. Clique na campanha para ver os lotes. Leads, em contato, vendas e bloqueios pela copy da campanha no CRM (venda e bloqueio pela última copy antes do fato).', linhasCamp
            ? tabCamp : '<p class="painel-msg vazio">Nenhum broadcast no período.</p>') +
          bloco('Automações', 'Volume do período pela diferença das fotos horárias. Cliques únicos ÷ entregues dos passos com botão. Custo = templates + serviço.', aus.length
            ? tabela(['Automação', 'Templates enviados', 'Entregues', 'Lidos', 'Cliques', 'Serviço', 'Categoria', 'Custo'], aus, [1, 2, 3, 4, 5, 7])
            : '<p class="painel-msg vazio">Nenhum envio de automação no período.</p>') +
          bloco('Automações por família de copy', 'Copy sem o número da versão. Leads e em contato: pessoas únicas no CRM; venda e bloqueio pela última copy antes do fato.', fams.length
            ? tabela(['Família', 'Leads (E0)', 'Em contato (E2)', 'Vendas', 'Bloqueios'], fams, [1, 2, 3, 4])
            : '<p class="painel-msg vazio">Nenhuma copy de automação no período.</p>') +
          bloco('Vendedores', 'Serviço: mensagens enviadas e agendadas pelo vendedor. Custo = serviço + templates do vendedor, antes da franquia.',
            tabela(['Vendedor', 'Serviço', 'Contatos', 'Templates utl', 'Templates mkt', 'Custo', 'Vendas', 'Custo por venda'], vds, [1, 2, 3, 4, 5, 6, 7])) +
          '<p class="rodape-fonte">Custo estimado pelo rate card da Meta (' + (fonte ? esc(fonte.fonte) : 'tabela whatsapp_preco') + ': ' + precoTxt +
          '; serviço com 1.000 grátis por número por mês). A fatura do Unnichat é a referência final.</p>';
        Array.prototype.forEach.call(corpo.querySelectorAll('tr.camp'), function (tr) {
          var abre = function () {
            var on = tr.getAttribute('aria-expanded') !== 'true';
            tr.setAttribute('aria-expanded', on ? 'true' : 'false');
            Array.prototype.forEach.call(corpo.querySelectorAll('tr.lote[data-de="' + tr.dataset.camp + '"]'), function (l) { l.hidden = !on; });
          };
          tr.addEventListener('click', abre);
          tr.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); abre(); } });
        });
      });
    }
  }

  var RENDER = { home: telaHome, metadomes: telaMeta, minhapagina: telaMinha, relatorios: telaRelatorios, reembolsos: telaReembolsos,
    desempenho: telaDesempenho, taxapassagem: telaPassagem, motivosperda: telaMotivos, ciclovenda: telaCiclo, mensageria: telaMensageria };

  // ---------- Minha página: links de venda ----------
  function carregarLinks(soDe) {
    var lista = $('links-lista');
    lista.innerHTML = '<p class="links-vazio">Carregando...</p>';
    $('links-sub').textContent = perfil.papel === 'admin'
      ? 'Links do vendedor escolhido. A venda entra no nome de quem está no link.'
      : 'Use sempre estes links: é por eles que a venda entra no seu nome.';
    sb.rpc('cic_meus_links').then(function (r) {
      lista.innerHTML = '';
      if (r.error) { lista.innerHTML = '<p class="links-vazio"></p>'; lista.firstChild.textContent = traduzErro(r.error); return; }
      var dados = soDe ? r.data.filter(function (l) { return l.vendedor_nome === soDe; }) : r.data;
      if (!dados.length) { lista.innerHTML = '<p class="links-vazio">Nenhum link cadastrado.</p>'; return; }
      var grupos = {};
      dados.forEach(function (l) { (grupos[l.vendedor_nome] = grupos[l.vendedor_nome] || []).push(l); });
      Object.keys(grupos).forEach(function (nome) {
        var g = document.createElement('div');
        g.className = 'links-grupo';
        if (perfil.papel === 'admin') {
          var h = document.createElement('h3'); h.textContent = nome; g.appendChild(h);
        }
        grupos[nome].forEach(function (l) {
          var row = document.createElement('div'); row.className = 'link-venda';
          var info = document.createElement('div'); info.className = 'link-info';
          var n = document.createElement('div'); n.className = 'link-nome'; n.textContent = l.produto + ' · ' + l.rotulo;
          var u = document.createElement('div'); u.className = 'link-url'; u.textContent = l.url; u.title = l.url;
          info.appendChild(n); info.appendChild(u);
          (Array.isArray(l.cupons) ? l.cupons : []).forEach(function (cp) {
            if (!cp || !cp.cupom) return;
            var c = document.createElement('div'); c.className = 'link-cupom';
            var ct = document.createElement('span');
            ct.textContent = 'Cupom: ' + cp.cupom + (cp.desconto ? ' (' + cp.desconto + ' off)' : '');
            var cb = document.createElement('button'); cb.type = 'button'; cb.className = 'btn-copiar btn-copiar-mini'; cb.textContent = 'Copiar';
            cb.addEventListener('click', function () { copiar(cp.cupom, cb); });
            c.appendChild(ct); c.appendChild(cb); info.appendChild(c);
          });
          var b = document.createElement('button'); b.type = 'button'; b.className = 'btn-copiar'; b.textContent = 'Copiar';
          b.addEventListener('click', function () { copiar(l.url, b); });
          row.appendChild(info); row.appendChild(b); g.appendChild(row);
        });
        lista.appendChild(g);
      });
    });
  }

  function copiar(texto, botao) {
    var ok = function () {
      botao.textContent = 'Copiado'; botao.classList.add('ok');
      setTimeout(function () { botao.textContent = 'Copiar'; botao.classList.remove('ok'); }, 1800);
    };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(texto).then(ok, function () { copiarAntigo(texto); ok(); });
    } else { copiarAntigo(texto); ok(); }
  }
  function copiarAntigo(texto) {
    var t = document.createElement('textarea');
    t.value = texto; t.setAttribute('readonly', ''); t.style.position = 'fixed'; t.style.opacity = '0';
    document.body.appendChild(t); t.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(t);
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
  // Menu lateral recolhível (desktop). Sem storage, abre expandido.
  function aplicaRecolhido(sim) {
    $('lateral').classList.toggle('recolhida', sim);
    $('lat-recolher').textContent = sim ? '›' : '‹';
    $('lat-recolher').title = sim ? 'Expandir menu' : 'Recolher menu';
    $('lat-recolher').setAttribute('aria-label', $('lat-recolher').title);
  }
  aplicaRecolhido(ler('cic-menu-recolhido') === '1');
  $('lat-recolher').addEventListener('click', function () {
    var sim = !$('lateral').classList.contains('recolhida');
    aplicaRecolhido(sim);
    guardar('cic-menu-recolhido', sim ? '1' : '0');
  });

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
