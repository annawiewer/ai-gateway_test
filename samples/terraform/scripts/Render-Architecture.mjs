import { readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const images = join(dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'images');
const iconFiles = {
  gateway: '037838045-icon-service-AI-Gateway.svg',
  foundry: '035746832-icon-service-AI-Foundry.svg',
  project: '036509415-icon-service-Foundry-Project.svg',
  agent: '038470523-icon-service-Foundry-Agent-Service.svg',
  models: '038470614-icon-service-Foundry-Models.svg',
  registry: '10105-icon-service-Container-Registries.svg',
  storage: '10086-icon-service-Storage-Accounts.svg',
  insights: '00012-icon-service-Application-Insights.svg',
  logs: '00009-icon-service-Log-Analytics-Workspaces.svg',
  monitor: '00001-icon-service-Monitor.svg',
  dcr: '01857-icon-service-Data-Collection-Rules.svg',
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
const colors = { request: '#1269b0', telemetry: '#7551b5', configuration: '#718297' };

// Each embedded icon needs its own gradient IDs; product artwork is otherwise unchanged.
function icon(key, id, x, y, size = 40) {
  const source = icons[key];
  if (!source) throw new Error(`Missing V24 icon: ${key}`);
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

function text(x, y, value, size = 17, fill = '#344b65', weight = 400) {
  return `<text x="${x}" y="${y}" font-size="${size}" fill="${fill}" font-weight="${weight}">${escape(value)}</text>`;
}

function lines(value, max) {
  const result = [];
  let line = '';
  for (const word of value.split(/\s+/)) {
    if (line && `${line} ${word}`.length > max) {
      result.push(line);
      line = word;
    } else {
      line = line ? `${line} ${word}` : word;
    }
  }
  if (line) result.push(line);
  return result;
}

function card({ id, x, y, w = 440, h = 190, title, type, badge, body, optional = false }) {
  const compact = w < 300;
  const titleX = x + (type && !compact ? 78 : 22);
  let svg = `<g data-card="${id}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="14" fill="#fff" stroke="${optional ? '#a5aeba' : '#cedae6'}" stroke-width="1.5"${optional ? ' stroke-dasharray="7 5"' : ''}/>`;
  if (type) svg += icon(type, id, x + 22, y + (compact ? 37 : 44), compact ? 30 : 40);
  svg += text(x + 22, y + 26, badge.toUpperCase(), 12, '#586f88', 700);
  svg += text(titleX, y + (compact ? 92 : 71), title, compact ? 17 : w < 400 ? 20 : 22, '#163451', 650);
  let baseline = y + (compact ? 125 : 107);
  for (const paragraph of body) {
    for (const line of lines(paragraph, Math.floor((w - 44) / 8.7))) {
      if (baseline > y + h - 14) throw new Error(`Text overflows ${id}: ${line}`);
      svg += text(x + 22, baseline, line);
      baseline += 24;
    }
    baseline += 5;
  }
  return `${svg}</g>`;
}

function edge(path, kind = 'request', label, x, y) {
  const color = colors[kind];
  let svg = `<path d="${path}" fill="none" stroke="${color}" stroke-width="2.5"${kind === 'request' ? '' : ' stroke-dasharray="7 6"'} marker-end="url(#arrow-${kind})"/>`;
  if (label) {
    const width = label.length * 8 + 18;
    svg += `<rect x="${x - width / 2}" y="${y - 18}" width="${width}" height="26" rx="5" fill="#f5f8fc"/>`;
    svg += `<text x="${x}" y="${y}" text-anchor="middle" font-size="14" fill="${color}">${escape(label)}</text>`;
  }
  return svg;
}

function start(title, subtitle, height) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1560" height="${height}" viewBox="0 0 1560 ${height}" role="img" aria-labelledby="title description">
<title id="title">${escape(title)}</title><desc id="description">${escape(subtitle)}</desc>
<defs>${Object.entries(colors).map(([key, color]) => `<marker id="arrow-${key}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10Z" fill="${color}"/></marker>`).join('')}</defs>
<rect width="1560" height="${height}" fill="#f5f8fc"/><g font-family="Segoe UI,Arial,sans-serif">
${text(40, 50, title, 30, '#153552', 700)}
${text(40, 82, subtitle, 17)}
${text(40, 120, 'BLUE: REQUEST PATH', 12, colors.request, 700)}
${text(280, 120, 'PURPLE DASHED: TELEMETRY', 12, colors.telemetry, 700)}
${text(595, 120, 'GRAY DASHED: CONFIGURATION / DEPENDENCY', 12, colors.configuration, 700)}`;
}

const overviewCards = [
  { id: 'client', x: 40, y: 165, title: 'Application or Playground', badge: '1 / Send a model request',
    body: ['Send a prompt and a model alias, such as gpt-mini, to one gateway URL.', 'Authenticate with a gateway API key.'] },
  { id: 'gateway', x: 560, y: 165, title: 'AI Gateway', type: 'gateway', badge: '2 / Authenticate, govern and route',
    body: ['Check the key, apply a per-caller token limit and select the model backend.', 'The gateway does not run the model.'] },
  { id: 'models', x: 1080, y: 165, title: 'Foundry Models', type: 'models', badge: '3 / Generate the answer',
    body: ['The dedicated model account runs GPT-4.1 or GPT-4.1-mini in this example.', 'Trusts the gateway managed identity.'] },
  { id: 'project', x: 40, y: 480, title: 'Foundry account + project', type: 'project', badge: 'Terraform / Ready for an agent app', h: 210,
    body: ['Organize a later hosted-agent deployment and its connections.', 'Project identity has scoped access to the registry and Blob Storage.'] },
  { id: 'agent', x: 560, y: 480, title: 'Hosted agent application', type: 'agent', badge: 'Separate deployment / Not Terraform', optional: true, h: 210,
    body: ['Your container needs its own network route to call the gateway.', 'Private-only ingress needs private DNS and reachability; not configured here.'] },
  { id: 'monitor', x: 1080, y: 480, title: 'Azure Monitor ingestion', type: 'monitor', badge: 'Azure-managed / DCE + DCR', h: 210,
    body: ['An endpoint receives OpenTelemetry; a collection rule routes each signal.', 'Logs and traces go to Log Analytics; metrics go to a Monitor workspace.'] },
  { id: 'registry', x: 40, y: 790, w: 210, h: 245, title: 'Container Registry', type: 'registry', badge: 'Terraform / Premium',
    body: ['Store and serve the agent container image.', 'Not a running container.'] },
  { id: 'storage', x: 270, y: 790, w: 210, h: 245, title: 'Blob Storage', type: 'storage', badge: 'Terraform / Data',
    body: ['Provide connected storage for agent features.', 'Not the model backend.'] },
  { id: 'agentInsights', x: 560, y: 790, h: 225, title: 'Agent monitoring', type: 'insights', badge: 'Terraform / Separate from gateway',
    body: ['Application Insights and Log Analytics are connected to the agent account.', 'A later app must actually emit telemetry; the connection alone is not proof.'] },
  { id: 'gatewayInsights', x: 1080, y: 790, h: 225, title: 'Gateway monitoring', type: 'insights', badge: 'Terraform / Linked destination',
    body: ['Application Insights links the gateway to its monitoring destinations.', 'Log Analytics stores request details. A Monitor workspace stores metrics.'] },
];

export const architecture = {
  title: 'Base sample: AI Gateway and Foundry responsibilities',
  direction: 'LR',
  services: overviewCards.map(node => ({
    name: node.title,
    type: ({
      gateway: 'AI Gateway', models: 'Microsoft Foundry', project: 'Microsoft Foundry',
      agent: 'Microsoft Foundry', monitor: 'Azure Monitor', registry: 'Container Registry',
      storage: 'Storage Account', insights: 'Application Insights',
    })[node.type] ?? 'Client',
    description: `${node.badge}. ${node.body.join(' ')}`,
  })),
  connections: [
    { from: 'Application or Playground', to: 'AI Gateway', label: 'Prompt + alias + API key' },
    { from: 'AI Gateway', to: 'Foundry Models', label: 'Gateway managed identity' },
    { from: 'Foundry account + project', to: 'Hosted agent application', label: 'Separate application deployment', type: 'optional' },
    { from: 'Hosted agent application', to: 'AI Gateway', label: 'Requires supported network route', type: 'optional' },
    { from: 'Foundry account + project', to: 'Container Registry', label: 'Image connection / AcrPull', type: 'optional' },
    { from: 'Foundry account + project', to: 'Blob Storage', label: 'Storage connection / Blob RBAC', type: 'optional' },
    { from: 'Foundry account + project', to: 'Agent monitoring', label: 'Monitoring connection', type: 'optional' },
    { from: 'AI Gateway', to: 'Azure Monitor ingestion', label: 'OpenTelemetry / gateway identity', type: 'async' },
    { from: 'Gateway monitoring', to: 'Azure Monitor ingestion', label: 'Linked collection resources', type: 'optional' },
  ],
};

let overview = start(architecture.title,
  'Start at the top: a prompt goes through the gateway to a model. Lower cards explain the supporting resources.', 1125);
overview += edge('M480 260 H560', 'request');
overview += edge('M1000 260 H1080', 'request');
overview += edge('M780 480 V355', 'configuration', 'Requires network route', 780, 440);
overview += edge('M930 355 V415 H1300 V480', 'telemetry', 'Asynchronous telemetry', 1180, 406);
overview += edge('M480 580 H560', 'configuration');
overview += edge('M150 690 V790', 'configuration', 'Image access', 150, 751);
overview += edge('M375 690 V790', 'configuration', 'Data access', 375, 751);
overview += edge('M470 660 H520 V900 H560', 'configuration');
overview += edge('M1300 790 V690', 'configuration', 'Destination linkage', 1300, 751);
overview += overviewCards.map(card).join('');
overview += text(40, 1065, 'The response returns along the request path. Network options are shown separately; private routing does not remove authentication.', 17);
overview += text(40, 1095, 'Solid card borders: infrastructure or existing clients. Dashed card: later app deployment. No private Blob endpoint is implied.', 15, '#586f88');
overview += '</g></svg>';
await writeFile(join(images, 'architecture-overview.svg'), overview);

let network = start('Base profile: private-only gateway and model connectivity',
  'private-only end state after staging, not runtime proof. PaaS services stay outside the VNet; private endpoints are inside.', 1240);
network += `<rect x="30" y="475" width="1500" height="690" rx="18" fill="#edf4fc" stroke="#8caed0" stroke-width="2"/>`;
network += icon('network', 'vnet', 52, 491, 29);
network += text(96, 516, 'CUSTOMER VIRTUAL NETWORK / 10.247.0.0/16 in the example profile', 17, '#17486f', 650);
for (const [x, w, label] of [[50, 440, 'CLIENT SUBNET / 10.247.2.0/24'], [570, 440, 'ENDPOINTS SUBNET / 10.247.1.0/24'], [1090, 420, 'GATEWAY SUBNET / 10.247.0.0/24']]) {
  network += `<rect x="${x}" y="545" width="${w}" height="490" rx="12" fill="#f8fbff" stroke="#c1d5e9" stroke-dasharray="6 5"/>`;
  network += text(x + 18, 576, label, 12, '#456b90', 700);
}
network += `<path d="M480 260 H535" fill="none" stroke="#b44d3a" stroke-width="2.5" stroke-dasharray="7 6"/>`;
network += text(520, 269, 'X', 24, '#b44d3a', 700);
network += edge('M460 705 H590', 'request', 'API key', 525, 695);
network += edge('M980 665 H1025 V445 H780 V355', 'request', 'Private ingress', 895, 437);
network += edge('M935 355 V400 H1060 V650 H1110', 'request', 'Private outbound', 1060, 392);
network += edge('M1110 725 H1040 V930 H980', 'request', 'To model PE', 1064, 839);
network += edge('M980 955 H1518 V430 H1300 V355', 'request');
network += [
  { id: 'publicClient', x: 40, y: 165, title: 'Public app / hosted agent', badge: 'No public ingress / Private route needed',
    body: ['Public gateway access is disabled.', 'Needs supported private routing and DNS; a valid key or token is not enough.'] },
  { id: 'networkGateway', x: 560, y: 165, title: 'AI Gateway', type: 'gateway', badge: 'PaaS service / Public access disabled',
    body: ['Private endpoint is the ingress path.', 'Outbound VNet integration reaches the private model backend.'] },
  { id: 'networkModels', x: 1080, y: 165, title: 'Foundry model account', type: 'models', badge: 'PaaS service / Public access disabled',
    body: ['Receives inference through its private endpoint, not a public model route.', 'Authorizes the gateway identity.'] },
  { id: 'vm', x: 70, y: 620, w: 390, h: 200, title: 'Private test client', type: 'vm', badge: 'Optional VM / No public IP',
    body: ['Checks private DNS, routing and model inference from inside the VNet.', 'Use an existing client instead if suitable.'] },
  { id: 'gatewayPe', x: 590, y: 620, w: 390, h: 180, title: 'Gateway private endpoint', type: 'endpoint', badge: 'Private IP / Inbound to gateway',
    body: ['Lets private clients reach the gateway.', 'Public access is disabled separately.'] },
  { id: 'modelPe', x: 590, y: 855, w: 390, h: 155, title: 'Model private endpoint', type: 'endpoint', badge: 'Private IP / Model backend',
    body: ['Connects this VNet to the model account.'] },
  { id: 'outbound', x: 1110, y: 620, w: 380, h: 200, title: 'Outbound VNet integration', type: 'network', badge: 'Routing / Not another AI gateway',
    body: ['Gives the gateway a path into this VNet.', 'The connector gateway is supporting infrastructure, not a model service.'] },
].map(card).join('');
network += icon('dns', 'privateDns', 65, 1070, 40);
network += text(125, 1087, 'PRIVATE DNS ZONES / LINKED TO THIS VNET', 14, '#234f75', 700);
network += text(125, 1117, 'Resolve gateway and model hostnames to private endpoint IPs. Custom DNS clients need an appropriate forwarding path.', 17);
network += text(125, 1143, 'Zones: privatelink.azure-api.net | privatelink.cognitiveservices.azure.com | privatelink.openai.azure.com | privatelink.services.ai.azure.com', 13);
network += text(40, 1205, 'Hybrid alternative: private-connectivity keeps gateway public ingress. Neither profile configures private hosted-agent execution.', 16);
network += '</g></svg>';
await writeFile(join(images, 'architecture-network.svg'), network);

const privateAgentCards = [
  { id: 'privateExecutor', x: 40, y: 175, h: 230, title: 'Private deployment client', type: 'vm', badge: '1 / Client subnet / 10.247.2.0/24',
    body: ['Deploy the image and invoke the agent from a VNet-connected client.', 'The test VM uses managed identity and is deallocated after verification.'] },
  { id: 'foundryPe', x: 560, y: 175, h: 230, title: 'Foundry private endpoint', type: 'endpoint', badge: '2 / Endpoint subnet / 10.247.1.0/24',
    body: ['Private DNS directs the client to this private IP, then to the project API.', 'This inbound path is NOT agent outbound network injection.'] },
  { id: 'privateRuntime', x: 1080, y: 175, h: 230, title: 'Foundry + hosted agent', type: 'agent', badge: '3 / Foundry account / Public access disabled',
    body: ['Create a Basic account/project with network injection from the start.', 'Deploy the app separately. A fresh version returned OK in the live proof.'] },
  { id: 'privateGateway', x: 40, y: 505, h: 230, title: 'AI Gateway', type: 'gateway', badge: '6 / PaaS / Public access disabled',
    body: ['Validate the runtime API key, enforce the token limit and route gpt-mini.', 'The runtime retrieves its key from ARM using its own managed identity.'] },
  { id: 'privateGatewayPe', x: 560, y: 505, h: 230, title: 'Gateway private endpoint', type: 'endpoint', badge: '5 / Endpoint subnet / 10.247.1.0/24',
    body: ['Private gateway ingress for the agent model request.', 'A valid credential on the public route still receives network-denial 403.'] },
  { id: 'agentInjection', x: 1080, y: 505, h: 230, title: 'Agent network injection', type: 'network', badge: '4 / Agent subnet / 10.247.3.0/24',
    body: ['Dedicated delegation: Microsoft.App/environments. Gives the runtime an outbound route into this VNet.', 'Not a VM or the Foundry inbound endpoint.'] },
  { id: 'privateOutbound', x: 40, y: 835, h: 230, title: 'Gateway VNet integration', type: 'network', badge: '7 / Gateway subnet / 10.247.0.0/24',
    body: ['Routes gateway backend calls into the VNet through its outbound integration.', 'Separate from the agent subnet and from gateway inbound Private Link.'] },
  { id: 'privateModelPe', x: 560, y: 835, h: 230, title: 'Model private endpoint', type: 'endpoint', badge: '8 / Endpoint subnet / 10.247.1.0/24',
    body: ['Private path to the existing model account.', 'The model account keeps public access disabled. No direct-model fallback.'] },
  { id: 'privateModels', x: 1080, y: 835, h: 230, title: 'Foundry Models', type: 'models', badge: '9 / Model inference / HTTP 200',
    body: ['Runs the model that generates the answer; trusts the gateway managed identity.', 'Gateway and backend HTTP 200 matched the same live agent trace.'] },
  { id: 'privateRegistry', x: 40, y: 1165, h: 230, title: 'Existing container registry', type: 'registry', badge: 'Image dependency / Premium ACR',
    body: ['Reuse an immutable image digest without rebuilding it.', 'Project and runtime registry roles are checked separately. ACR public setting is unchanged.'] },
  { id: 'privateRegistryPe', x: 560, y: 1165, h: 230, title: 'Registry private endpoint', type: 'endpoint', badge: 'Endpoint subnet / Login + data',
    body: ['Private DNS resolves both registry login and regional data endpoints.', 'This private image path is a dependency, not an extra model-call hop.'] },
  { id: 'privateDnsRoles', x: 1080, y: 1165, h: 230, title: 'DNS and identity boundaries', type: 'dns', badge: 'Linked zones / Scoped permissions',
    body: ['The four subnets share one VNet. DNS links make private endpoint names usable.', 'Entra, ARM and monitoring still need separate egress. NSG is not deny-all.'] },
];
let privateAgent = start('Private agent reference: verified end-to-end request path',
  'New agent deployment with creation-time network injection. Read steps 1-9 in a zigzag; the response returns on the same path.', 1550);
privateAgent += edge('M480 290 H560');
privateAgent += edge('M1000 290 H1080');
privateAgent += edge('M1300 405 V505', 'request', 'Injected outbound route', 1300, 460);
privateAgent += edge('M1080 620 H1000');
privateAgent += edge('M560 620 H480');
privateAgent += edge('M260 735 V835', 'request', 'Gateway backend route', 260, 790);
privateAgent += edge('M480 950 H560');
privateAgent += edge('M1000 950 H1080');
privateAgent += edge('M480 1280 H560', 'configuration');
privateAgent += edge('M1000 1280 H1040 V1430 H1540 V290 H1520', 'configuration');
privateAgent += privateAgentCards.map(card).join('');
privateAgent += text(40, 1440, 'Image delivery via private ACR', 16, colors.configuration, 650);
privateAgent += text(40, 1475, 'Verified October 25, 2026: agent OK; gateway + backend HTTP 200; authenticated public gateway 403. One environment, not a universal guarantee.', 16);
privateAgent += text(40, 1505, 'Basic agent data remains platform-managed. This view omits unrelated storage and monitoring resources; it does not claim fully private egress.', 16);
privateAgent += '</g></svg>';
await writeFile(join(images, 'architecture-private-agent.svg'), privateAgent);
console.log('Rendered base overview, base network and private-agent reference SVGs with unmodified V24 artwork.');
