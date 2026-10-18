const V="aqui-perto-v16",SHELL=["./","index.html","manifest.webmanifest","icon-180.png","icon-192.png","icon-512.png"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(SHELL)));self.skipWaiting();});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))));self.clients.claim();});
self.addEventListener("fetch",e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=="GET")return;
  const own=u.origin===location.origin,lib=u.hostname==="cdn.jsdelivr.net";
  if(!own&&!lib)return; // pedidos ao Supabase vão sempre à rede
  e.respondWith(fetch(r).then(res=>{
    // só guarda respostas completas e sem query string (evita guardar links de login/recuperação)
    if(res.status===200&&!u.search){const c=res.clone();caches.open(V).then(x=>x.put(r,c));}
    return res;
  }).catch(()=>caches.match(r).then(m=>m||(r.mode==="navigate"?caches.match("index.html"):Response.error()))));
});
// Avisos push (pedidos novos, estado dos pedidos, orçamentos)
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
  e.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(l=>{
    for(const c of l){if("focus" in c){c.postMessage({t:(e.notification.data&&e.notification.data.t)||"crm"});return c.focus();}}
    return clients.openWindow(url);
  }));
});
