// Gera uma página estática por perfil (f/<id>.html) para a pré-visualização do link no WhatsApp, etc.,
// mais o sitemap.xml. Não usa segredos: lê o endereço e a chave PÚBLICA do index.html
// e só pede campos públicos (nunca o telemóvel).
import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync } from "node:fs";

const html = readFileSync("index.html", "utf8");
const ler = (re, nome) => { const m = html.match(re); if (!m) throw new Error("Não encontrei " + nome + " no index.html"); return m[1]; };
const SB = ler(/SUPABASE_URL\s*=\s*"([^"]+)"/, "SUPABASE_URL");
const KEY = ler(/SUPABASE_KEY\s*=\s*"([^"]+)"/, "SUPABASE_KEY");
const BASE = ler(/property="og:url"\s+content="([^"]+)"/, "og:url").replace(/\/?$/, "/");
const IMG0 = ler(/property="og:image"\s+content="([^"]+)"/, "og:image");

const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const corta = (s, n) => { s = String(s ?? "").replace(/\s+/g, " ").trim(); return s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s; };

async function perfis() {
  const out = [];
  for (let de = 0; ; de += 1000) {
    const r = await fetch(SB + "/rest/v1/fornecedores?select=id,nome,tipo,cat,localidade,descr,logo,zonas&order=created_at.asc,id.asc", {
      headers: { apikey: KEY, Authorization: "Bearer " + KEY, "Range-Unit": "items", Range: de + "-" + (de + 999) },
    });
    if (!r.ok) throw new Error("Falha ao ler os perfis: " + r.status + " " + (await r.text()).slice(0, 200));
    const lote = await r.json();
    out.push(...lote);
    if (lote.length < 1000) break;
  }
  return out;
}

const L = await perfis();
mkdirSync("f", { recursive: true });
const ids = new Set();

for (const p of L) {
  const id = String(p.id);
  if (!/^[A-Za-z0-9_-]+$/.test(id)) continue;
  ids.add(id + ".html");
  const pagina = BASE + "f/" + id + ".html", app = BASE + "?f=" + encodeURIComponent(id);
  const loc = p.localidade ? " · " + p.localidade : "";
  const titulo = p.nome + " · " + p.cat + loc + " — Aqui Perto";
  const desc = corta(p.descr, 155) || (p.tipo === "servico" ? "Serviço" : "Produtor local") + " perto de si. Fale diretamente com " + p.nome + " na Aqui Perto.";
  const img = p.logo && !String(p.logo).startsWith("data:") ? SB + "/storage/v1/object/public/produtos/" + encodeURI(p.logo) : IMG0;
  const ld = { "@context": "https://schema.org", "@type": "LocalBusiness", name: p.nome, description: desc, url: pagina, image: img,
    ...(p.localidade ? { address: { "@type": "PostalAddress", addressLocality: p.localidade, addressCountry: "PT" } } : {}),
    ...(Array.isArray(p.zonas) && p.zonas.length ? { areaServed: p.zonas } : {}) };
  writeFileSync("f/" + id + "
