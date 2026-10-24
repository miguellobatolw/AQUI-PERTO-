// IMPORTANTE: mudar V sempre que a app (APP_VERSION no index.html) mudar, para os aparelhos receberem a versão nova.
const V="aqui-perto-v30",SHELL=["./","index.html","manifest.webmanifest","icon-180.png","icon-192.png","icon-512.png","badge-96.png"];
// Bibliotecas externas (CDN). Guardadas em cache para a app arrancar mesmo que a CDN falhe ou sem rede.
const LIBS=["cdn.jsdelivr.net","unpkg.com"];
// Só as bibliotecas com versão fixa no endereço (ex.: pacote@2.45.4) são imutáveis e podem ir "cache primeiro".
const PINNED=/@\d+\.\d+\.\d+/;
// Se a rede demorar mais do que isto, a app abre já a partir da cópia guardada (e atualiza a cópia em segundo plano).
const NAV_MS=4000;

// Instala ficheiro a ficheiro: se um faltar (ex.: manifest ou ícone), o SW instala na mesma
self.addEventListener("install",e=>{
  e.waitUntil(caches.open(V).then(c=>Promise.allSettled(SHELL.map(u=>c.add(u)))));
  self.skipWaiting();
});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))));self.clients.claim();});

// só guarda respostas completas e sem query string (evita guardar links de login/recuperação)
const guardar=(r,res)=>{if(res.status===200&&!new URL(r.url).search){const c=res.clone();caches.open(V).then(x=>x.put(r,c));}return res;};
const copia=r=>caches.match(r).then(m=>m||caches.match("index.html")).then(m=>m||caches.match("./"));

self.addEventListener("fetch",e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=="GET")return;
  const own=u.origin===location.origin,lib=LIBS.includes(u.hostname);
  if(!own&&!lib)return; // pedidos ao Supabase vão sempre à rede

  if(lib){
    // Um <script> normal recebe uma resposta "opaca" (status 0) que não dá para guardar com segurança.
    // Por isso pedimos a biblioteca com CORS (as duas CDN permitem) e guardamo-la por URL.
    const rede=()=>fetch(new Request(r.url,{mode:"cors",credentials:"omit"})).then(res=>{
      if(res.status===200){const c=res.clone();caches.open(V).then(x=>x.put(r.url,c));}
      return res;
    });
    if(PINNED.test(u.pathname)){
      // versão fixa: nunca muda, por isso usa a cópia guardada e só vai à rede na primeira vez
      e.respondWith(caches.match(r.url).then(m=>m||rede()).catch(()=>Response.error()));
    }else{
      e.respondWith(rede().catch(()=>caches.match(r.url).then(m=>m||Response.error())));
    }
    return;
  }

  if(r.mode==="navigate"){
    // Abrir a app: rede primeiro, mas com limite de tempo — em rede fraca abre a cópia guardada em vez de ficar parado.
    const f=fetch(r).then(res=>guardar(r,res));
    e.waitUntil(f.catch(()=>{}));
    const lento=new Promise(ok=>setTimeout(ok,NAV_MS)).then(()=>copia(r).then(m=>m||f));
    e.respondWith(Promise.race([f,lento]).catch(()=>copia(r).then(m=>m||Response.error())));
    return;
  }

  // Ícones, manifest e outros ficheiros próprios: mostra a cópia já e atualiza-a em segundo plano.
  const f=fetch(r).then(res=>guardar(r,res));
  e.waitUntil(f.catch(()=>{}));
  e.respondWith(caches.match(r).then(m=>m||f).catch(()=>Response.error()));
});

// Avisos push (pedidos novos, estado dos pedidos, orçamentos, marcações, mensagens)
self.addEventListener("push",e=>{
  let d={};try{d=e.data?e.data.json():{};}catch(x){}
  e.waitUntil(self.registration.showNotification(d.title||"Aqui Perto",{
    body:d.body||"Tem um pedido novo.",icon:"icon-192.png",badge:"badge-96.png",
    tag:d.tag||"pedido",renotify:true,data:{url:d.url||"./?crm=1",t:d.t||"crm"}
  }));
});
self.addEventListener("notificationclick",e=>{
  e.notification.close();
  const url=(e.notification.data&&e.notification.data.url)||"./?crm=1";
  const t=(e.notification.data&&e.notification.data.t)||"crm";
  // se a notificação for de mensagens ou orçamentos, a app abre diretamente esse separador
  const aba=/[?&]aba=mensagens/.test(url)?"mensagens":/[?&]aba=orcamentos/.test(url)?"orcamentos":"";
  e.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(l=>{
    // só janelas desta app (o GitHub Pages partilha a origem com os outros projetos da mesma conta) e, de preferência, a que está visível
    const minhas=l.filter(c=>"focus" in c&&c.url.startsWith(self.registration.scope));
    const c=minhas.find(x=>x.visibilityState==="visible")||minhas[0];
    if(c){c.postMessage({t,aba});return c.focus();}
    return clients.openWindow(url);
  }));
});
