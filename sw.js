const V="aqui-perto-v20",SHELL=["./","index.html","manifest.webmanifest","icon-180.png","icon-192.png","icon-512.png"];
// Bibliotecas externas (CDN). Guardadas em cache para a app arrancar mesmo que a CDN falhe ou sem rede.
const LIBS=["cdn.jsdelivr.net","unpkg.com"];
// Instala ficheiro a ficheiro: se um faltar (ex.: manifest ou ícone), o SW instala na mesma
self.addEventListener("install",e=>{
  e.waitUntil(caches.open(V).then(c=>Promise.allSettled(SHELL.map(u=>c.add(u)))));
  self.skipWaiting();
});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))));self.clients.claim();});
self.addEventListener("fetch",e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=="GET")return;
  const own=u.origin===location.origin,lib=LIBS.includes(u.hostname);
  if(!own&&!lib)return; // pedidos ao Supabase vão sempre à rede
  if(lib){
    // Um <script> normal recebe uma resposta "opaca" (status 0) que não dá para guardar com segurança.
    // Por isso pedimos a biblioteca com CORS (as duas CDN permitem) e guardamo-la por URL.
    e.respondWith(
      fetch(new Request(r.url,{mode:"cors",credentials:"omit"})).then(res=>{
        if(res.status===200){const c=res.clone();caches.open(V).then(x=>x.put(r.url,c));}
        return res;
      }).catch(()=>caches.match(r.url).then(m=>m||Response.error()))
    );
    return;
  }
  e.respondWith(fetch(r).then(res=>{
    // só guarda respostas completas e sem query string (evita guardar links de login/recuperação)
    if(res.status===200&&!u.search){const c=res.clone();caches.open(V).then(x=>x.put(r,c));}
    return res;
  }).catch(()=>caches.match(r).then(m=>m||(r.mode==="navigate"?caches.match("index.html").then(i=>i||caches.match("./")):Response.error()))));
});
// Avisos push (pedidos novos, estado dos pedidos, orçamentos, marcações, mensagens)
self.addEventListener("push",e=>{
  let d={};try{d=e.data?e.data.json():{};}catch(x){}
  e.waitUntil(self.registration.showNotification(d.title||"Aqui Perto",{
    body:d.body||"Tem um pedido novo.",icon:"icon-192.png",
    tag:d.tag||"pedido",renotify:true,data:{url:d.url||"./?crm=1",t:d.t||"crm"}
  }));
});
self.addEventListener("notificationclick",e=>{
  e.notification.close();
  const url=(e.notification.data&&e.notification.data.url)||"./?crm=1";
  const t=(e.notification.data&&e.notification.data.t)||"crm";
  // se a notificação for de mensagens, a app abre diretamente o separador Mensagens
  const aba=/[?&]aba=mensagens/.test(url)?"mensagens":"";
  e.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(l=>{
    for(const c of l){if("focus" in c){c.postMessage({t,aba});return c.focus();}}
    return clients.openWindow(url);
  }));
});
