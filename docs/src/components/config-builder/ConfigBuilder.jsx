// Cria um arquivo -Config a partir do catálogo da versão mais recente, para que toda chave oferecida seja uma que essa versão importará.
import { useCallback, useEffect, useMemo, useState } from 'react';
import Icon from '../docs/Icon.jsx';
import { RATE_LIMITED, loadReleaseConfig } from '../../lib/winutil-release.js';
import { configLink, readConfigLink } from '../../lib/config-link.js';
import './ConfigBuilder.css';

// Cada download recebe seu próprio nome. O navegador renomeia um conflito para "nome (1).json" e o comando executaria
// o arquivo mais antigo.
function configFileName() {
	const stamp = new Date().toISOString().slice(0, 23).replace(/[-:.]/g, '').replace('T', '-');
	return `winutil-config-${stamp}.json`;
}

// Botões compartilham o prefixo WPFFeature, mas não podem ser importados, então só são oferecidas entradas de caixa de seleção e de interruptor.
function entries(catalog, pattern) {
	return Object.entries(catalog)
		.filter(([key, entry]) => pattern.test(key) && entry.Type !== 'Button')
		.map(([key, entry]) => ({
			key,
			name: entry.Content,
			description: entry.Description,
			category: entry.category ?? entry.Category,
			link: entry.link,
		}));
}

async function loadCatalog() {
	const {
		release,
		files: [applications, tweaks, features, appx, presets],
	} = await loadReleaseConfig(['applications', 'tweaks', 'feature', 'appx', 'preset']);
	// A ordem das abas segue a ordem de exportação do WinUtil: aplicativos, ajustes, interruptores, recursos, AppX.
	return {
		release,
		tabs: [
			{
				id: 'apps',
				label: 'Aplicativos',
				items: Object.entries(applications).map(([name, app]) => ({
					key: `WPFInstall${name}`,
					name: app.content,
					description: app.description,
					category: app.category,
					link: app.link,
				})),
			},
			{
				id: 'tweaks',
				label: 'Ajustes',
				items: [...entries(tweaks, /^WPFTweaks/), ...entries(tweaks, /^WPFToggle/)],
				presetScope: 'WPFTweaks',
				presets: ['Standard', 'Minimal', 'Advanced'].map((name) => ({ label: name, keys: presets[name] ?? [] })),
			},
			{ id: 'features', label: 'Recursos', items: entries(features, /^WPFFeature/) },
			{
				id: 'appx',
				label: 'Remoção de AppX',
				items: entries(appx, /^WPFAppx/),
				presetScope: 'WPFAppx',
				presets: [{ label: 'Remoções padrão', keys: presets.AppxDefault ?? [] }],
			},
		],
	};
}

// O WinUtil exporta com Out-File, que grava UTF-16 com uma marca de ordem de byte no Windows PowerShell 5.1.
async function readText(file) {
	const bytes = new Uint8Array(await file.arrayBuffer());
	let encoding = 'utf-8';
	if (bytes[0] === 0xff && bytes[1] === 0xfe) encoding = 'utf-16le';
	else if (bytes[0] === 0xfe && bytes[1] === 0xff) encoding = 'utf-16be';
	return new TextDecoder(encoding).decode(bytes);
}

// As exportações atuais são uma chave ou uma matriz de chaves; as antigas as agrupavam sob WPFInstall, WPFTweaks e assim por diante.
function readConfig(json) {
	if (typeof json === 'string') return [json];
	if (Array.isArray(json)) return json.filter((key) => typeof key === 'string');
	return Object.entries(json)
		.filter(([name]) => /^WPF(?:Install|Tweaks|Toggle|Feature|Appx)/.test(name))
		.flatMap(([, value]) => [value].flat())
		.filter((key) => typeof key === 'string');
}

// O WinUtil ordena as categorias por nome; o prefixo z__ só serve para empurrar as avançadas para o fim.
function groupByCategory(items) {
	const groups = new Map();
	for (const item of items) {
		if (!groups.has(item.category)) groups.set(item.category, []);
		groups.get(item.category).push(item);
	}
	return [...groups]
		.sort(([a], [b]) => a.localeCompare(b))
		.map(([category, groupItems]) => ({ name: category.replace(/^z__/, ''), items: groupItems }));
}

export default function ConfigBuilder() {
	const [catalog, setCatalog] = useState(null);
	const [error, setError] = useState(null);
	const [attempt, setAttempt] = useState(0);
	const [tabId, setTabId] = useState('apps');
	const [query, setQuery] = useState('');
	const [selected, setSelected] = useState(() => new Set());
	const [notice, setNotice] = useState(null);
	const [copied, setCopied] = useState(null);
	const [fileName, setFileName] = useState(configFileName);
	const [savedJson, setSavedJson] = useState(null);

	useEffect(() => {
		let cancelled = false;
		setError(null);
		loadCatalog()
			.then((loaded) => !cancelled && setCatalog(loaded))
			.catch((reason) => !cancelled && setError(reason.message));
		return () => {
			cancelled = true;
		};
	}, [attempt]);

	useEffect(() => {
		if (!copied) return;
		const timer = setTimeout(() => setCopied(null), 1500);
		return () => clearTimeout(timer);
	}, [copied]);

	const order = useMemo(() => catalog?.tabs.flatMap((tab) => tab.items.map((item) => item.key)) ?? [], [catalog]);
	const known = useMemo(() => new Set(order), [order]);

	const loadKeys = useCallback(
		(loaded, source) => {
			const skipped = loaded.filter((key) => !known.has(key));
			// Como a importação do WinUtil, um arquivo ou link sem nada aproveitável não altera a seleção atual.
			if (skipped.length === loaded.length) {
				const text = loaded.length
					? `Nenhuma das chaves em ${source} está no WinUtil ${catalog.release.tag}: ${skipped.join(', ')}`
					: `${source} não contém nenhuma seleção do WinUtil.`;
				setNotice({ kind: 'error', text });
				return;
			}
			setSelected(new Set(loaded.filter((key) => known.has(key))));
			if (skipped.length) {
				const message = `Foram omitidas ${skipped.length} chave(s) que o WinUtil ${catalog.release.tag} não possui: ${skipped.join(', ')}`;
				setNotice({ kind: 'warning', text: message });
			} else {
				setNotice({ kind: 'info', text: `Carregadas ${loaded.length} seleção(ões) de ${source}.` });
			}
		},
		[catalog, known]
	);

	// Um link compartilhado aberto em uma aba que já está nesta página só altera o hash; por isso, escute isso também.
	useEffect(() => {
		if (!catalog) return;
		const loadLink = () => {
			const linked = readConfigLink(window.location.hash);
			if (linked) loadKeys(linked, 'o link');
		};
		loadLink();
		window.addEventListener('hashchange', loadLink);
		return () => window.removeEventListener('hashchange', loadLink);
	}, [catalog, loadKeys]);

	if (error) {
		return (
			<div className="wu-builder not-content">
				<p className="wu-builder-status">
					{error === RATE_LIMITED
						? RATE_LIMITED
						: `Não foi possível carregar o catálogo do GitHub (${error}). Você ainda pode exportar uma configuração pelo próprio WinUtil.`}
				</p>
				<button type="button" className="wu-builder-button" onClick={() => setAttempt((count) => count + 1)}>
					Tentar novamente
				</button>
			</div>
		);
	}

	if (!catalog) {
		return (
			<div className="wu-builder not-content">
				<p className="wu-builder-status">Carregando o catálogo da versão mais recente do WinUtil…</p>
			</div>
		);
	}

	const keys = order.filter((key) => selected.has(key));
	const json = JSON.stringify(keys, null, 2);
	// O catálogo pode ficar em cache entre versões, então execute a versão que reconhece suas chaves.
	const script = `https://github.com/RamonMods/WinUtil/releases/download/${catalog.release.tag}/winutil.ps1`;
	const command = `& ([ScriptBlock]::Create((irm "${script}"))) -Config "$env:USERPROFILE\\Downloads\\${fileName}"`;
	const tab = catalog.tabs.find((candidate) => candidate.id === tabId);
	const text = query.trim().toLowerCase();
	const groups = groupByCategory(
		tab.items.filter((item) => !text || `${item.name} ${item.description} ${item.key}`.toLowerCase().includes(text))
	);

	const toggle = (key) =>
		setSelected((current) => {
			const next = new Set(current);
			if (next.has(key)) next.delete(key);
			else next.add(key);
			return next;
		});

	// Como os botões de predefinição no WinUtil, uma predefinição substitui essa parte da seleção em vez de acrescentar a ela.
	const applyPreset = (preset) =>
		setSelected((current) => {
			const next = new Set([...current].filter((key) => !key.startsWith(tab.presetScope)));
			preset.keys.filter((key) => known.has(key)).forEach((key) => next.add(key));
			return next;
		});

	const clearTab = () => {
		const inTab = new Set(tab.items.map((item) => item.key));
		setSelected((current) => new Set([...current].filter((key) => !inTab.has(key))));
	};

	const openConfig = async (event) => {
		const file = event.target.files[0];
		event.target.value = '';
		if (!file) return;
		let loaded;
		try {
			loaded = readConfig(JSON.parse(await readText(file)));
		} catch {
			setNotice({ kind: 'error', text: `${file.name} não é um arquivo de configuração do WinUtil.` });
			return;
		}
		loadKeys(loaded, file.name);
	};

	const copy = async (what, value) => {
		try {
			await navigator.clipboard.writeText(value);
			setCopied(what);
		} catch {
			setCopied(null);
			const text =
				what === 'link'
					? 'Não foi possível copiar o link, mas ele está na barra de endereço.'
					: 'Não foi possível copiar para a área de transferência. Selecione o texto e copie-o manualmente.';
			setNotice({ kind: 'error', text });
		}
	};

	// A barra de endereço também recebe o link, então ele ainda pode ser copiado dali se a área de transferência estiver bloqueada.
	const share = () => {
		window.history.replaceState(null, '', configLink(keys));
		copy('link', window.location.href);
	};

	// O primeiro download usa o nome que o comando já mostra; os seguintes recebem um novo nome e atualizam o comando.
	const download = () => {
		const name = savedJson === null ? fileName : configFileName();
		setFileName(name);
		setSavedJson(json);
		const url = URL.createObjectURL(new Blob([json], { type: 'application/json' }));
		const link = Object.assign(document.createElement('a'), { href: url, download: name });
		link.click();
		// Revogar na mesma tarefa pode cancelar o download antes de o navegador ler o blob.
		setTimeout(() => URL.revokeObjectURL(url));
	};

	return (
		<div className="wu-builder not-content">
			<div className="wu-builder-toolbar">
				<p className="wu-builder-release">
					Catálogo de{' '}
					<a href={catalog.release.url} target="_blank" rel="noreferrer">
						WinUtil {catalog.release.tag}
					</a>
				</p>
				<label className="wu-builder-button">
					Abrir uma configuração
					<input type="file" accept=".json,application/json" onChange={openConfig} />
				</label>
			</div>
			{/* Sempre renderizado, para que leitores de tela anunciem um aviso quando ele aparece. */}
			<p role="status" className={notice ? `wu-builder-notice wu-builder-notice--${notice.kind}` : 'sr-only'}>
				{notice?.text}
			</p>

			<div className="wu-builder-picker">
				<div className="wu-builder-tabs">
					{catalog.tabs.map((candidate) => {
						const count = candidate.items.filter((item) => selected.has(item.key)).length;
						return (
							<button
								key={candidate.id}
								type="button"
								className="wu-builder-tab"
								aria-pressed={candidate.id === tabId}
								onClick={() => setTabId(candidate.id)}
							>
								{candidate.label}
								{count > 0 && <span className="wu-builder-count">{count}</span>}
							</button>
						);
					})}
				</div>
				<div className="wu-builder-controls">
					<div className="wu-builder-search">
						<Icon name="magnifier" />
						<input
							type="search"
							placeholder={`Buscar ${tab.label.toLowerCase()}`}
							aria-label={`Buscar ${tab.label.toLowerCase()}`}
							autoComplete="off"
							spellCheck="false"
							value={query}
							onChange={(event) => setQuery(event.target.value)}
						/>
					</div>
					{tab.presets?.map((preset) => (
						<button key={preset.label} type="button" className="wu-builder-chip" onClick={() => applyPreset(preset)}>
							{preset.label}
						</button>
					))}
					<button type="button" className="wu-builder-chip" onClick={clearTab}>
						Limpar
					</button>
				</div>
				<div className="wu-builder-list">
					{groups.length === 0 && (
						<p className="wu-builder-status">
							Nenhum resultado em {tab.label.toLowerCase()} para "{query.trim()}".
						</p>
					)}
					{groups.map((group) => (
						<section key={group.name}>
							<h3 className="wu-builder-group">{group.name}</h3>
							<ul>
								{group.items.map((item) => (
									<li key={item.key} className="wu-builder-item">
										<label>
											<input type="checkbox" checked={selected.has(item.key)} onChange={() => toggle(item.key)} />
											<span className="wu-builder-item-text">
												<span className="wu-builder-item-name">{item.name}</span>
												<span className="wu-builder-item-description">{item.description}</span>
											</span>
										</label>
										{item.link && (
											<a
												href={item.link}
												target="_blank"
												rel="noreferrer"
												className="wu-builder-item-link"
												aria-label={`Mais sobre ${item.name}`}
											>
												<Icon name="external" />
											</a>
										)}
									</li>
								))}
							</ul>
						</section>
					))}
				</div>
			</div>

			<div className="wu-builder-output">
				{keys.some((key) => key.startsWith('WPFAppx')) && (
					<p className="wu-builder-notice wu-builder-notice--warning">
						Esta configuração remove os pacotes AppX selecionados quando executada. Ela não os instala nem os mantém.
					</p>
				)}
				<div className="wu-builder-output-header">
					<span>{keys.length} selecionado(s)</span>
					<button type="button" className="wu-builder-button" disabled={!keys.length} onClick={() => copy('json', json)}>
						{copied === 'json' ? 'Copiado' : 'Copiar JSON'}
					</button>
					<button type="button" className="wu-builder-button" disabled={!keys.length} onClick={share}>
						{copied === 'link' ? 'Copiado' : 'Compartilhar link'}
					</button>
					<button
						type="button"
						className="wu-builder-button wu-builder-button--primary"
						disabled={!keys.length}
						onClick={download}
					>
						Baixar configuração
					</button>
				</div>
				{keys.length > 0 ? (
					<pre className="wu-builder-json">{json}</pre>
				) : (
					<p className="wu-builder-status">Selecione pelo menos um item para criar uma configuração.</p>
				)}
				{/* O comando executa o último arquivo baixado, então só pode ser copiado quando esse arquivo tiver esta seleção. */}
				<p className="wu-builder-hint">
					{savedJson === json
						? 'Em seguida, execute isto em uma janela do PowerShell elevada:'
						: 'Baixe a configuração e execute isto em uma janela do PowerShell elevada:'}
				</p>
				<div className="wu-builder-command">
					<code>{command}</code>
					<button
						type="button"
						className="wu-builder-button"
						disabled={savedJson !== json}
						onClick={() => copy('command', command)}
					>
						{copied === 'command' ? 'Copiado' : 'Copiar'}
					</button>
				</div>
			</div>
		</div>
	);
}
