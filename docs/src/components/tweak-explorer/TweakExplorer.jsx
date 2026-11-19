// Mostra o que cada ajuste da versão mais recente altera e o que o Desfazer restaura, sem ler o JSON bruto.
import { useEffect, useMemo, useState } from 'react';
import Icon from '../docs/Icon.jsx';
import { RATE_LIMITED, loadReleaseConfig } from '../../lib/winutil-release.js';
import { configLink } from '../../lib/config-link.js';
import './TweakExplorer.css';

const PRESETS = ['Standard', 'Minimal', 'Advanced'];
const CHANGES = [
	{ id: 'registry', label: 'Registro' },
	{ id: 'services', label: 'Serviços' },
	{ id: 'script', label: 'Scripts' },
];

// Os scripts são armazenados com indentação para corresponder ao JSON ao redor.
function dedent(blocks) {
	return blocks
		.map((block) => {
			const lines = block.replace(/^\s*\n|\s+$/g, '').split('\n');
			const indent = Math.min(...lines.filter((line) => line.trim()).map((line) => line.match(/^ */)[0].length));
			return lines.map((line) => line.slice(indent)).join('\n');
		})
		.join('\n\n');
}

function toTweak(key, entry, presets) {
	const registry = entry.registry ?? [];
	const states = entry.Type === 'Combobox' ? Object.keys(registry[0]?.Values ?? {}) : [];
	const services = entry.service ?? [];
	const script = dedent(entry.InvokeScript ?? []);
	const undoScript = dedent(entry.UndoScript ?? []);
	const appx = entry.appx ?? [];
	return {
		key,
		name: entry.Content,
		description: entry.Description,
		category: entry.category,
		toggle: entry.Type === 'Toggle',
		link: entry.link?.replace(/^https?:\/\/[^/]+/, ''),
		registry,
		states,
		services,
		script,
		undoScript,
		appx,
		presets: PRESETS.filter((name) => presets[name]?.includes(key)),
		hasUndo: !states.length && (
			registry.some((item) => !item.Values && Object.hasOwn(item, 'OriginalValue')) ||
			services.some((item) => Object.hasOwn(item, 'OriginalType')) || Boolean(undoScript)
		),
		// As listas suspensas usam seleção manual de estado em vez da ação Desfazer da caixa de seleção.
		oneWay: states.length
			? 'Sem ação de desfazer'
			: appx.length ? 'A remoção de AppX não tem desfazer' : script && !undoScript ? 'O script não tem desfazer' : null,
		haystack: [
			entry.Content,
			entry.Description,
			key,
			...registry.map((item) => `${item.Path}\\${item.Name}`),
			...services.map((item) => item.Name),
			script,
			undoScript,
			...appx,
		]
			.join('\n')
			.toLowerCase(),
	};
}

function registryValue(value) {
	return value === '<RemoveEntry>' ? <em>removido</em> : value;
}

function TweakDetails({ tweak, picked, onPick }) {
	const [applied, undone] = tweak.toggle ? ['Quando ativado', 'Quando desativado'] : ['Aplicado', 'Desfazer restaura'];
	return (
		<div className="wu-explorer-details">
			{tweak.registry.length > 0 && (
				<section>
					<h4>Registro</h4>
					<div className="wu-explorer-table">
						<table>
							<thead>
								<tr>
									<th>Valor</th>
									<th>Tipo</th>
									{(tweak.states.length ? tweak.states : [applied, undone]).map((label) => (
										<th key={label}>{label}</th>
									))}
								</tr>
							</thead>
							<tbody>
								{tweak.registry.map((item) => (
									<tr key={`${item.Path}\\${item.Name}`}>
										<td>
											<span className="wu-explorer-path">{item.Path}\</span>
											{item.Name}
										</td>
										<td data-label="Tipo">{item.Type}</td>
										{tweak.states.length ? (
											tweak.states.map((state) => (
												<td key={state} data-label={state}>{registryValue(item.Values[state])}</td>
											))
										) : (
											<>
												<td data-label={applied}>{registryValue(item.Value)}</td>
												<td data-label={undone}>{registryValue(item.OriginalValue)}</td>
											</>
										)}
									</tr>
								))}
							</tbody>
						</table>
					</div>
					{tweak.states.length > 0 && (
						<p className="wu-explorer-note">
							As alterações são aplicadas imediatamente quando você escolhe um estado no WinUtil. Para reverter, escolha outro estado;
							Desfazer ajustes selecionados não gerencia este controle.
						</p>
					)}
				</section>
			)}
			{tweak.services.length > 0 && (
				<section>
					<h4>Serviços</h4>
					<div className="wu-explorer-table">
						<table>
							<thead>
								<tr>
									<th>Serviço</th>
									<th>{applied}</th>
									<th>{undone}</th>
								</tr>
							</thead>
							<tbody>
								{tweak.services.map((item) => (
									<tr key={item.Name}>
										<td>{item.Name}</td>
										<td data-label={applied}>{item.StartupType}</td>
										<td data-label={undone}>{item.OriginalType}</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
					<p className="wu-explorer-note">
						A aplicação ignora um serviço cujo tipo de inicialização não é o original, preservando as alterações feitas por você.
					</p>
				</section>
			)}
			{tweak.appx.length > 0 && (
				<section>
					<h4>Remove pacotes AppX</h4>
					<p className="wu-explorer-note">{tweak.appx.join(', ')}. O desfazer não os reinstala.</p>
				</section>
			)}
			{tweak.script && (
				<details>
					<summary>Script executado</summary>
					<pre>{tweak.script}</pre>
				</details>
			)}
			{tweak.undoScript && (
				<details>
					<summary>Script de desfazer</summary>
					<pre>{tweak.undoScript}</pre>
				</details>
			)}
			<div className="wu-explorer-details-footer">
				<code>{tweak.key}</code>
				<span className="wu-explorer-details-actions">
					{tweak.link && <a href={tweak.link}>Página de referência</a>}
					{/^WPF(?:Tweaks|Toggle)/.test(tweak.key) && (
						<button type="button" className="wu-explorer-chip" aria-pressed={picked} onClick={onPick}>
							{picked ? 'Adicionado à configuração' : 'Adicionar à configuração'}{tweak.toggle ? ' (Quando ativado)' : ''}
						</button>
					)}
				</span>
			</div>
		</div>
	);
}

export default function TweakExplorer() {
	const [data, setData] = useState(null);
	const [error, setError] = useState(null);
	const [attempt, setAttempt] = useState(0);
	const [query, setQuery] = useState('');
	const [category, setCategory] = useState(null);
	const [preset, setPreset] = useState(null);
	const [changes, setChanges] = useState(() => new Set());
	const [hasUndoOnly, setHasUndoOnly] = useState(false);
	const [expanded, setExpanded] = useState(() => new Set());
	const [picked, setPicked] = useState(() => new Set());

	useEffect(() => {
		let cancelled = false;
		setError(null);
		loadReleaseConfig(['tweaks', 'preset'])
			.then(({ release, files: [tweaks, presets] }) => {
				if (cancelled) return;
				const list = Object.entries(tweaks)
					.filter(([key, entry]) =>
						/^WPF(?:Tweaks|Toggle)/.test(key) || (entry.Type === 'Combobox' && entry.registry?.[0]?.Values)
					)
					.map(([key, entry]) => toTweak(key, entry, presets));
				setData({ release, tweaks: list });
			})
			.catch((reason) => !cancelled && setError(reason.message));
		return () => {
			cancelled = true;
		};
	}, [attempt]);

	// O WinUtil ordena as categorias por nome; o prefixo z__ só serve para empurrar as avançadas para o fim.
	const categories = useMemo(
		() => [...new Set(data?.tweaks.map((tweak) => tweak.category))].sort((a, b) => a.localeCompare(b)),
		[data]
	);

	if (error) {
		return (
			<div className="wu-explorer not-content">
				<p className="wu-explorer-status">
					{error === RATE_LIMITED ? RATE_LIMITED : `Não foi possível carregar os ajustes do GitHub (${error}).`}
				</p>
				<button type="button" className="wu-explorer-chip" onClick={() => setAttempt((count) => count + 1)}>
					Tentar novamente
				</button>
			</div>
		);
	}

	if (!data) {
		return (
			<div className="wu-explorer not-content">
				<p className="wu-explorer-status">Carregando os ajustes da versão mais recente do WinUtil…</p>
			</div>
		);
	}

	const text = query.trim().toLowerCase();
	const visible = data.tweaks.filter(
		(tweak) =>
			(!text || tweak.haystack.includes(text)) &&
			(!category || tweak.category === category) &&
			(!preset || tweak.presets.includes(preset)) &&
			(!changes.has('registry') || tweak.registry.length > 0) &&
			(!changes.has('services') || tweak.services.length > 0) &&
			(!changes.has('script') || tweak.script) &&
			(!hasUndoOnly || tweak.hasUndo)
	);

	const toggleIn = (setter, value) =>
		setter((current) => {
			const next = new Set(current);
			if (next.has(value)) next.delete(value);
			else next.add(value);
			return next;
		});

	const chip = (label, pressed, onClick) => (
		<button key={label} type="button" className="wu-explorer-chip" aria-pressed={pressed} onClick={onClick}>
			{label}
		</button>
	);

	return (
		<div className="wu-explorer not-content">
			<div className="wu-explorer-filters">
				<div className="wu-explorer-search">
					<Icon name="magnifier" />
					<input
						type="search"
						placeholder="Buscar nomes, caminhos do registro, serviços e scripts"
						aria-label="Buscar ajustes"
						autoComplete="off"
						spellCheck="false"
						value={query}
						onChange={(event) => setQuery(event.target.value)}
					/>
				</div>
				<div className="wu-explorer-filter-row">
					<span>Categoria</span>
					{chip('Todas', !category, () => setCategory(null))}
					{categories.map((name) =>
						chip(name.replace(/^z__/, ''), category === name, () => setCategory(category === name ? null : name))
					)}
				</div>
				<div className="wu-explorer-filter-row">
					<span>Predefinição</span>
					{chip('Qualquer', !preset, () => setPreset(null))}
					{PRESETS.map((name) => chip(name, preset === name, () => setPreset(preset === name ? null : name)))}
				</div>
				<div className="wu-explorer-filter-row">
					<span>Alterações</span>
					{CHANGES.map(({ id, label }) => chip(label, changes.has(id), () => toggleIn(setChanges, id)))}
					{chip('Com desfazer', hasUndoOnly, () => setHasUndoOnly(!hasUndoOnly))}
				</div>
			</div>

			<p className="wu-explorer-note">
				Uma ação de desfazer pode restaurar os padrões ou reinstalar programas sem recuperar dados excluídos nem suas configurações anteriores.
			</p>
			<p className="wu-explorer-status">
				Exibindo {visible.length} de {data.tweaks.length} ajustes do{' '}
				<a href={data.release.url} target="_blank" rel="noreferrer">
					WinUtil {data.release.tag}
				</a>
				{picked.size > 0 && (
					<>
						{' · '}
						<a href={configLink([...picked])}>
							Abrir {picked.size} {picked.size === 1 ? 'ajuste' : 'ajustes'} no Construtor de Configurações
						</a>
					</>
				)}
			</p>

			<ul className="wu-explorer-list">
				{visible.map((tweak) => {
					const open = expanded.has(tweak.key);
					return (
						<li key={tweak.key} className="wu-explorer-tweak">
							<button
								type="button"
								className="wu-explorer-summary"
								aria-expanded={open}
								onClick={() => toggleIn(setExpanded, tweak.key)}
							>
								<span className="wu-explorer-summary-text">
									<span className="wu-explorer-name">{tweak.name}</span>
									<span className="wu-explorer-description">{tweak.description}</span>
									<span className="wu-explorer-badges">
										<span className="wu-explorer-badge">{tweak.category.replace(/^z__/, '')}</span>
										{tweak.presets.map((name) => (
											<span key={name} className="wu-explorer-badge wu-explorer-badge--preset">
												{name}
											</span>
										))}
										{tweak.registry.length > 0 && (
											<span className="wu-explorer-badge">{tweak.registry.length} registro(s)</span>
										)}
										{tweak.services.length > 0 && (
											<span className="wu-explorer-badge">
												{tweak.services.length} {tweak.services.length === 1 ? 'serviço' : 'serviços'}
											</span>
										)}
										{tweak.script && <span className="wu-explorer-badge">Script</span>}
										{tweak.hasUndo && (
											<span className="wu-explorer-badge wu-explorer-badge--good">Com desfazer</span>
										)}
										{tweak.oneWay && (
											<span className="wu-explorer-badge wu-explorer-badge--warn">{tweak.oneWay}</span>
										)}
									</span>
								</span>
								<Icon name="down-caret" className="wu-explorer-caret" />
							</button>
							{open && (
								<TweakDetails
									tweak={tweak}
									picked={picked.has(tweak.key)}
									onPick={() => toggleIn(setPicked, tweak.key)}
								/>
							)}
						</li>
					);
				})}
			</ul>
			{visible.length === 0 && <p className="wu-explorer-status">Nenhum ajuste corresponde a estes filtros.</p>}
		</div>
	);
}
