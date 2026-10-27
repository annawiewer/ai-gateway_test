import { readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const images = join(dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'images');
const iconFiles = {
  gateway: '037838045-icon-service-AI-Gateway.svg',
  agent: '038470523-icon-service-Foundry-Agent-Service.svg',
  project: '036509415-icon-service-Foundry-Project.svg',
  models: '038470614-icon-service-Foundry-Models.svg',
  registry: '10105-icon-service-Container-Registries.svg',
  storage: '10086-icon-service-Storage-Accounts.svg',
  insights: '00012-icon-service-Application-Insights.svg',
  endpoint: '02579-icon-service-Private-Endpoints.svg',
  vm: '10021-icon-service-Virtual-Machine.svg',
  dns: '10064-icon-service-DNS-Zones.svg',
  network: '10061-icon-service-Virtual-Networks.svg',
};
const icons = Object.fromEntries(await Promise.all(
  Object.entries(iconFiles).map(async ([key, file]) => [
    key, await readFile(join(images, 'azure-icons', file), 'utf8'),
  ]),
));
const escape = value => String(value).replace(/[&<>"']/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;',
})[char]);
const colors = { request: '#0078d4', telemetry: '#7461a8', configuration: '#64748b' };

// Namespace gradient IDs without modifying official product artwork.
function icon(key, id, x, y, size = 32) {
  const source = icons[key];
  if (!source) throw new Error(`Missing Azure icon: ${key}`);
  const viewBox = source.match(/viewBox="([^"]+)"/)?.[1];
  if (!viewBox) throw new Error(`Icon has no viewBox: ${key}`);
  let content = source.replace(/^[\s\S]*?<svg\b[^>]*>/, '').replace(/<\/svg>\s*$/, '');
  for (const old of [...content.matchAll(/\bid="([^"]+)"/g)].map(match => match[1])) {
    content = content.replaceAll(`id="${old}"`, `id="${id}-${old}"`)
      .replaceAll(`url(#${old})`, `url(#${id}-${old})`)
      .replaceAll(`href="#${old}"`, `href="#${id}-${old}"`);
  }
  return `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="${viewBox}" aria-hidden="true">${content}</svg>`;
}

function text(x, y, value, size = 15, fill = '#475569', weight = 400) {
  return `<text x="${x}" y="${y}" font-size="${size}" fill="${fill}" font-weight="${weight}">${escape(value)}</text>`;
}

function node({ id, x, y, w = 240, h = 104, title, type, notes = [], optional = false }) {
  if (66 + Math.max(0, notes.length - 1) * 20 > h - 10) {
    throw new Error(`Too many lines in ${id}`);
  }
  return `<g data-card="${id}">
<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="5" fill="#fff" stroke="#b8c8d8" stroke-width="1.2"${optional ? ' stroke-dasharray="5 4"' : ''}/>
${type ? icon(type, id, x + 18, y + 15) : ''}
${text(x + (type ? 64 : 18), y + 36, title, w < 230 ? 15 : 17, '#172b4d', 600)}
${notes.map((line, index) => text(x + 18, y + 66 + index * 20, line, 14)).join('')}
</g>`;
}

function frame(x, y, w, h, title, network = false) {
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="6" fill="${network ? '#f3f9ff' : '#f8fafc'}" stroke="${network ? '#8fb8dc' : '#dce4ec'}"/>
${text(x + 20, y + 28, title, 14, network ? '#17649b' : '#53657a', 600)}`;
}

function edge(path, kind = 'request', label, x, y) {
  const color = colors[kind];
  if (!color) throw new Error(`Unknown edge type: ${kind}`);
  let svg = `<path d="${path}" fill="none" stroke="${color}" stroke-width="2"${kind === 'request' ? '' : ' stroke-dasharray="5 5"'} marker-end="url(#arrow-${kind})"/>`;
  if (label) {
    const width = label.length * 7.6 + 16;
    svg += `<rect x="${x - width / 2}" y="${y - 15}" width="${width}" height="22" rx="3" fill="#fff"/>
<text x="${x}" y="${y}" text-anchor="middle" font-size="14" fill="${color}">${escape(label)}</text>`;
  }
  return svg;
}

function start(title, subtitle, width, height) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title description">
<title id="title">${escape(title)}</title><desc id="description">${escape(subtitle)}</desc>
<defs>${Object.entries(colors).map(([key, color]) => `<marker id="arrow-${key}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 1L9 5L0 9Z" fill="${color}"/></marker>`).join('')}</defs>
<rect width="${width}" height="${height}" fill="#fff"/><g font-family="Segoe UI,Arial,sans-serif">
${text(48, 50, title, 28, '#172b4d', 600)}
${text(48, 82, subtitle, 16)}
<path d="M48 104H${width - 48}" stroke="#e2e8f0"/>`;
}

function legend(y) {
  return edge(`M48 ${y}H86`) + text(98, y + 5, 'Request', 13)
    + edge(`M216 ${y}H254`, 'configuration') + text(266, y + 5, 'Dependency / separate deployment', 13)
    + edge(`M530 ${y}H568`, 'telemetry') + text(580, y + 5, 'Asynchronous telemetry', 13);
}

const overviewNodes = [
  { id: 'client', x: 48, y: 202, w: 230, title: 'Application / Playground',
    notes: ['Prompt + model alias', 'Gateway API key'] },
  { id: 'gateway', x: 475, y: 202, w: 260, title: 'AI Gateway', type: 'gateway',
    notes: ['Authentication and policies', 'Public endpoint'] },
  { id: 'models', x: 1090, y: 202, w: 254, title: 'Foundry Models', type: 'models',
    notes: ['Model inference', 'Public endpoint'] },
  { id: 'project', x: 430, y: 465, w: 245, title: 'Foundry project', type: 'project',
    notes: ['Account + project', 'Scoped project identity'] },
  { id: 'agent', x: 745, y: 465, w: 245, title: 'Hosted agent', type: 'agent', optional: true,
    notes: ['Separate app deployment', 'Not deployed by Terraform'] },
  { id: 'registry', x: 430, y: 615, w: 245, title: 'Container Registry', type: 'registry',
    notes: ['Container images', 'Project AcrPull role'] },
  { id: 'storage', x: 745, y: 615, w: 245, title: 'Blob Storage', type: 'storage',
    notes: ['Connected application data', 'Scoped data access'] },
  { id: 'gatewayInsights', x: 1090, y: 465, w: 254, title: 'Gateway monitoring', type: 'insights',
    notes: ['Insights / logs / metrics', 'DCE + DCR ingestion'] },
  { id: 'agentInsights', x: 1090, y: 615, w: 254, title: 'Agent monitoring', type: 'insights',
    notes: ['Insights + Log Analytics', 'Application emits telemetry'] },
];

export const architecture = {
  title: 'Public | AI Gateway and Foundry',
  direction: 'LR',
  services: overviewNodes.map(item => ({
    name: item.title,
    type: ({
      gateway: 'AI Gateway', models: 'Microsoft Foundry', project: 'Microsoft Foundry',
      agent: 'Microsoft Foundry', registry: 'Container Registry',
      storage: 'Storage Account', insights: 'Application Insights',
    })[item.type] ?? 'Client',
    description: item.notes.join('. '),
  })),
  connections: [
    { from: 'Application / Playground', to: 'AI Gateway', label: 'HTTPS / API key' },
    { from: 'AI Gateway', to: 'Foundry Models', label: 'Gateway managed identity' },
    { from: 'Foundry project', to: 'Hosted agent', label: 'Separate app deployment', type: 'optional' },
    { from: 'Hosted agent', to: 'AI Gateway', label: 'Agent requests', type: 'optional' },
    { from: 'Foundry project', to: 'Container Registry', label: 'AcrPull', type: 'optional' },
    { from: 'Foundry project', to: 'Blob Storage', label: 'Data access', type: 'optional' },
    { from: 'Foundry project', to: 'Agent monitoring', label: 'Monitoring connection', type: 'optional' },
    { from: 'AI Gateway', to: 'Gateway monitoring', label: 'OpenTelemetry', type: 'async' },
  ],
};

let overview = start(architecture.title,
  'Public gateway and model endpoints. Supporting agent resources are separate from the model request path.', 1440, 860);
overview += frame(400, 128, 992, 642, 'Azure services');
overview += frame(416, 420, 589, 318, 'Application dependencies');
overview += edge('M278 254H475', 'request', 'HTTPS / API key', 376, 239);
overview += edge('M735 254H1090', 'request', 'Gateway managed identity', 912, 239);
overview += edge('M710 306V377H1217V465', 'telemetry', 'OpenTelemetry', 1090, 367);
overview += edge('M867 465V407H605V306', 'configuration', 'Agent requests', 760, 397);
overview += edge('M675 517H745', 'configuration');
overview += edge('M552 569V615', 'configuration');
overview += edge('M650 569V594H867V615', 'configuration');
overview += edge('M675 549H705V750H1217V719', 'configuration');
overview += overviewNodes.map(node).join('');
overview += legend(800);
overview += text(48, 837, 'Responses return on the same route. Monitoring can create Azure-managed helper groups outside the application resource group.', 14);
overview += '</g></svg>';
await writeFile(join(images, 'architecture-overview.svg'), overview);

let network = start('Private-only | Gateway and model connectivity',
  'Gateway and model public access disabled. Private endpoints are in the VNet; the managed services are not.', 1440, 840);
network += frame(550, 132, 825, 201, 'Azure PaaS services');
network += frame(40, 395, 1360, 330, 'Customer virtual network', true);
network += edge('M274 545H330');
network += edge('M525 493V350H600V295', 'request', 'Private Link', 594, 342);
network += edge('M750 295V545H820', 'request', 'Outbound', 750, 372);
network += edge('M1050 545H1110');
network += edge('M1290 493V295', 'request', 'Private Link', 1290, 372);
network += `<path d="M278 254H514" fill="none" stroke="#a83d46" stroke-width="2" stroke-dasharray="5 5"/>
<path d="M510 248L522 260M522 248L510 260" stroke="#a83d46" stroke-width="2"/>`;
network += text(302, 236, 'Public access blocked', 14, '#a83d46');
for (const [x, label] of [[76, 'Client subnet'], [342, 'Endpoints subnet'], [832, 'Gateway subnet'], [1122, 'Endpoints subnet']]) {
  network += text(x, 472, label, 13, '#17649b', 600);
}
network += [
  { id: 'publicClient', x: 48, y: 202, w: 230, title: 'Public client',
    notes: ['No gateway ingress', 'A valid key is not enough'] },
  { id: 'networkGateway', x: 550, y: 185, w: 230, h: 110, title: 'AI Gateway', type: 'gateway',
    notes: ['Public access disabled', 'Policies + model routing'] },
  { id: 'networkModels', x: 1110, y: 185, w: 230, h: 110, title: 'Foundry Models', type: 'models',
    notes: ['Public access disabled', 'Gateway identity required'] },
  { id: 'client', x: 64, y: 493, w: 210, title: 'Private client', type: 'vm',
    notes: ['Application or test VM', 'Gateway API key'] },
  { id: 'gatewayPe', x: 330, y: 493, w: 210, title: 'Gateway endpoint', type: 'endpoint',
    notes: ['Private gateway ingress'] },
  { id: 'outbound', x: 820, y: 493, w: 230, title: 'VNet integration', type: 'network',
    notes: ['Gateway outbound route', 'To the model endpoint'] },
  { id: 'modelPe', x: 1110, y: 493, w: 230, title: 'Model endpoint', type: 'endpoint',
    notes: ['Private model access', 'Same endpoints subnet'] },
  { id: 'dns', x: 64, y: 631, w: 1300, h: 78, title: 'Private DNS', type: 'dns',
    notes: ['Linked zones resolve gateway and model names to private IPs. Custom DNS requires appropriate forwarding.'] },
].map(node).join('');
network += legend(764);
network += text(48, 810, 'Final profile: private-only. The private-connectivity file is an intermediate setup stage, not another deployment path.', 14);
network += '</g></svg>';
await writeFile(join(images, 'architecture-network.svg'), network);

let privateAgent = start('Private-only | Hosted agent architecture',
  'Private invocation, creation-time agent network injection, and a private gateway-to-model route.', 1600, 1010);
privateAgent += frame(310, 132, 1250, 200, 'Azure PaaS services | Public access disabled for Foundry, gateway and models');
privateAgent += frame(48, 395, 1512, 350, 'Customer virtual network', true);
privateAgent += edge('M262 515H310');
privateAgent += edge('M492 463V295');
privateAgent += edge('M620 295V362H790V463', 'request', 'Agent outbound', 708, 352);
privateAgent += edge('M805 515H845');
privateAgent += edge('M1020 463V295');
privateAgent += edge('M1125 295V362H1280V463', 'request', 'Gateway outbound', 1210, 352);
privateAgent += edge('M1300 515H1330');
privateAgent += edge('M1505 463V295');
privateAgent += edge('M605 567V600H430V638', 'configuration', 'Image pull', 511, 591);
privateAgent += edge('M430 722V805', 'configuration', 'Private Link', 430, 780);
for (const [x, label] of [[84, 'Client subnet'], [322, 'Endpoints subnet'], [587, 'Agent subnet'], [857, 'Endpoints subnet'], [1112, 'Gateway subnet'], [1342, 'Endpoints subnet']]) {
  privateAgent += text(x, 442, label, 13, '#17649b', 600);
}
privateAgent += [
  { id: 'runtime', x: 390, y: 185, w: 240, h: 110, title: 'Foundry agent', type: 'agent',
    notes: ['Account + project', 'Separately deployed app'] },
  { id: 'gateway', x: 900, y: 185, w: 240, h: 110, title: 'AI Gateway', type: 'gateway',
    notes: ['API-key authentication', 'Gateway MI to model'] },
  { id: 'models', x: 1290, y: 185, w: 250, h: 110, title: 'Foundry Models', type: 'models',
    notes: ['Model inference', 'Gateway identity required'] },
  { id: 'client', x: 72, y: 463, w: 190, title: 'Private client', type: 'vm',
    notes: ['Invoke deployed agent', 'Entra authentication'] },
  { id: 'foundryPe', x: 310, y: 463, w: 200, title: 'Foundry endpoint', type: 'endpoint',
    notes: ['Inbound project access'] },
  { id: 'injection', x: 575, y: 463, w: 230, title: 'Network injection', type: 'network',
    notes: ['Configured at creation', 'Delegated agent subnet'] },
  { id: 'gatewayPe', x: 845, y: 463, w: 200, title: 'Gateway endpoint', type: 'endpoint',
    notes: ['Private gateway ingress'] },
  { id: 'outbound', x: 1100, y: 463, w: 200, title: 'VNet integration', type: 'network',
    notes: ['Gateway backend route'] },
  { id: 'modelPe', x: 1330, y: 463, w: 210, title: 'Model endpoint', type: 'endpoint',
    notes: ['Private model access'] },
  { id: 'registryPe', x: 310, y: 638, w: 240, h: 84, title: 'Registry endpoint', type: 'endpoint',
    notes: ['Endpoints subnet / login + data'] },
  { id: 'dns', x: 680, y: 638, w: 850, h: 84, title: 'Private DNS', type: 'dns',
    notes: ['Linked zones for Foundry, gateway, models and registry. All endpoint nodes share the endpoints subnet.'] },
  { id: 'registry', x: 310, y: 805, w: 240, title: 'Container Registry', type: 'registry',
    notes: ['Immutable agent image', 'Scoped AcrPull permissions'] },
].map(node).join('');
privateAgent += frame(680, 805, 850, 104, 'Separate service dependencies');
privateAgent += text(700, 861, 'Entra ID / Azure Resource Manager / Azure Monitor require their own connectivity.', 15);
privateAgent += text(700, 885, 'Network injection does not make all egress or platform-managed agent data private.', 15);
privateAgent += legend(950);
privateAgent += text(48, 987, 'Private request path verified in one deployment. ACR public access is unchanged. Authentication details and evidence are in the guide.', 14);
privateAgent += '</g></svg>';
await writeFile(join(images, 'architecture-private-agent.svg'), privateAgent);
console.log('Rendered Public, Private-only and private hosted-agent topology SVGs.');
