// O índice do Pagefind só é gerado pelo `astro build`, então a busca mostra um aviso em desenvolvimento.
import { useEffect, useRef, useState } from 'react';
import Icon from './Icon.jsx';

const BUNDLE = '/pagefind/pagefind.js';
const MAX_PAGES = 8;
const MAX_SECTIONS = 3;

let pagefindPromise;
let resetting;
let failedImports = 0;
let latestSearch = 0;

function loadPagefind() {
	if (!pagefindPromise) {
		// Uma redefinição ainda desmontando a instância antiga apagaria uma nova criada ao mesmo tempo, então espere por ela primeiro.
		pagefindPromise = Promise.resolve(resetting)
			// O Chromium mantém um download de módulo falhado pelo restante da página, então a nova tentativa pede o arquivo em uma URL diferente.
			.then(() =>
				import(/* @vite-ignore */ failedImports ? `${BUNDLE}?retry=${failedImports}` : BUNDLE).catch((error) => {
					failedImports++;
					throw error;
				})
			)
			.then(async (pagefind) => {
				await pagefind.options({ baseUrl: '/' });
				pagefind.init();
				return pagefind;
			});
		// Esquece uma carga falhada para que a próxima busca tente novamente.
		pagefindPromise.catch(() => {
			pagefindPromise = undefined;
		});
	}
	return pagefindPromise;
}

// O Pagefind mantém uma carga de índice falhada, então uma busca que falha recomeça o processo para a próxima tentativa.
function resetPagefind() {
	const failed = pagefindPromise;
	pagefindPromise = undefined;
	resetting = failed?.then((pagefind) => pagefind.destroy()).catch(() => {});
}

async function runSearch(pagefind, query) {
	const search = await pagefind.debouncedSearch(query, {}, 150);
	if (!search) return null;
	const pages = await Promise.all(search.results.slice(0, MAX_PAGES).map((result) => result.data()));
	return pages.flatMap((page) => {
		const title = page.meta?.title ?? page.url;
		const sections = (page.sub_results ?? [])
			.filter((sub) => sub.url !== page.url && sub.title !== title)
			.slice(0, MAX_SECTIONS)
			.map((sub) => ({ kind: 'section', url: sub.url, title: sub.title, excerpt: sub.excerpt }));
		return [{ kind: 'page', url: page.url, title, excerpt: page.excerpt }, ...sections];
	});
}

export default function SearchDialog() {
	const dialogRef = useRef(null);
	const inputRef = useRef(null);
	const listRef = useRef(null);
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState('');
	const [items, setItems] = useState([]);
	const [itemsQuery, setItemsQuery] = useState('');
	const [status, setStatus] = useState('idle');
	const [activeIndex, setActiveIndex] = useState(0);
	const [shortcut, setShortcut] = useState('Ctrl K');

	useEffect(() => {
		if (/Mac|iPhone|iPad/.test(navigator.userAgent)) setShortcut('⌘K');
		const onKey = (event) => {
			const typing =
				event.target instanceof HTMLElement && event.target.closest('input, textarea, select, [contenteditable="true"]');
			if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
				event.preventDefault();
				setOpen((value) => !value);
			} else if (event.key === '/' && !typing) {
				event.preventDefault();
				setOpen(true);
			}
		};
		window.addEventListener('keydown', onKey);
		return () => window.removeEventListener('keydown', onKey);
	}, []);

	useEffect(() => {
		const dialog = dialogRef.current;
		if (!dialog) return;
		if (open && !dialog.open) {
			dialog.showModal();
			inputRef.current?.focus();
			inputRef.current?.select();
			loadPagefind().then(
				() => setStatus((current) => (current === 'unavailable' ? 'idle' : current)),
				() => setStatus('unavailable')
			);
		} else if (!open && dialog.open) {
			dialog.close();
		}
		document.documentElement.toggleAttribute('data-search-open', open);
	}, [open]);

	useEffect(() => {
		const text = query.trim();
		if (!text) {
			setItems([]);
			setStatus((current) => (current === 'unavailable' ? current : 'idle'));
			return;
		}
		// Reabrir faz a busca rodar de novo, então uma consulta que falhou enquanto o Pagefind não carregava ganha outra tentativa.
		if (!open) return;
		let cancelled = false;
		const search = ++latestSearch;
		setStatus('loading');
		loadPagefind()
			.then((pagefind) => runSearch(pagefind, text))
			.then((found) => {
				if (cancelled || found === null) return;
				setItems(found);
				setItemsQuery(text);
				setActiveIndex(0);
				setStatus(found.length ? 'ready' : 'empty');
			})
			.catch(() => {
				if (!cancelled) setStatus('unavailable');
				// Só a busca mais recente redefine o Pagefind, pois uma mais nova pode já estar usando a mesma instância.
				// Fechar o diálogo não inicia uma busca, então uma falha que ocorre depois de fechar ainda o redefine.
				if (search === latestSearch) resetPagefind();
			});
		return () => {
			cancelled = true;
		};
	}, [query, open]);

	// Novos resultados podem chegar com o primeiro ainda ativo, então eles também o trazem para a área visível.
	useEffect(() => {
		listRef.current?.querySelector('[data-active="true"]')?.scrollIntoView({ block: 'nearest' });
	}, [activeIndex, items]);

	// Os resultados ficam ocultos enquanto a busca está indisponível, mesmo que tenham sobrado de uma consulta anterior.
	const listed = items.length > 0 && status !== 'unavailable';
	// Os resultados da consulta anterior permanecem enquanto a próxima carrega, mas não podem ser abertos até serem substituídos.
	const stale = itemsQuery !== query.trim();
	const note = {
		unavailable: import.meta.env.DEV
			? 'A busca só está disponível em builds de produção.'
			: "Não foi possível carregar a busca. Verifique sua conexão e tente novamente.",
		idle: 'Busque guias, ajustes, recursos e perguntas frequentes.',
		empty: `Nenhum resultado para "${query.trim()}".`,
	}[status];

	const onInputKey = (event) => {
		// Enter enquanto um método de entrada está compondo confirma o texto em vez de abrir um resultado.
		if (!listed || stale || event.nativeEvent.isComposing) return;
		if (event.key === 'ArrowDown') {
			event.preventDefault();
			setActiveIndex((index) => (index + 1) % items.length);
		} else if (event.key === 'ArrowUp') {
			event.preventDefault();
			setActiveIndex((index) => (index - 1 + items.length) % items.length);
		} else if (event.key === 'Enter') {
			event.preventDefault();
			window.location.href = items[activeIndex].url;
			setOpen(false);
		}
	};

	return (
		<>
			<button type="button" className="docs-search-trigger" onClick={() => setOpen(true)} aria-label="Buscar na documentação">
				<Icon name="magnifier" />
				<span className="docs-search-trigger-label">Buscar</span>
				<kbd className="docs-search-trigger-kbd">{shortcut}</kbd>
			</button>
			<dialog
				ref={dialogRef}
				className="docs-search"
				aria-label="Buscar na documentação"
				onClose={() => setOpen(false)}
				onClick={(event) => event.target === dialogRef.current && setOpen(false)}
			>
				<div className="docs-search-panel">
					<div className="docs-search-field">
						<Icon name="magnifier" />
						<input
							ref={inputRef}
							type="search"
							placeholder="Buscar na documentação"
							aria-label="Buscar na documentação"
							role="combobox"
							aria-autocomplete="list"
							aria-expanded={listed}
							aria-controls={listed ? 'docs-search-results' : undefined}
							aria-activedescendant={
								listed && !stale ? `docs-search-item-${activeIndex}` : undefined
							}
							autoComplete="off"
							spellCheck="false"
							value={query}
							onChange={(event) => setQuery(event.target.value)}
							onKeyDown={onInputKey}
						/>
						<button type="button" className="docs-search-close" onClick={() => setOpen(false)}>
							Esc
						</button>
					</div>
					<div className="docs-search-body">
						{/* Sempre renderizado, para que leitores de tela avisem quando uma busca termina e o que foi encontrado. */}
						<p role="status" className={note ? 'docs-search-note' : 'sr-only'}>
							{note ?? (status === 'ready' ? `${items.length} resultados` : '')}
						</p>
						{listed && (
							<ul
								id="docs-search-results"
								className="docs-search-results"
								role="listbox"
								ref={listRef}
								inert={stale}
								aria-busy={stale}
							>
								{items.map((item, index) => (
									<li
										key={`${item.url}-${index}`}
										role="option"
										id={`docs-search-item-${index}`}
										aria-selected={index === activeIndex}
									>
										{/* Os resultados são escolhidos na caixa de busca com as setas do teclado, então os links ficam fora da ordem de Tab. */}
										<a
											href={item.url}
											tabIndex={-1}
											className={`docs-search-result docs-search-result--${item.kind}`}
											data-active={index === activeIndex}
											onMouseMove={() => setActiveIndex(index)}
											onClick={() => setOpen(false)}
										>
											<Icon
												name={item.kind === 'page' ? 'document' : 'right-caret'}
												className="docs-search-result-icon"
											/>
											<span className="docs-search-result-text">
												<span className="docs-search-result-title">{item.title}</span>
												<span
													className="docs-search-result-excerpt"
													dangerouslySetInnerHTML={{ __html: item.excerpt }}
												/>
											</span>
										</a>
									</li>
								))}
							</ul>
						)}
					</div>
					<div className="docs-search-footer" aria-hidden="true">
						<span>
							<kbd>↑</kbd>
							<kbd>↓</kbd> para navegar
						</span>
						<span>
							<kbd>↵</kbd> para abrir
						</span>
						<span>
							<kbd>Esc</kbd> para fechar
						</span>
					</div>
				</div>
			</dialog>
		</>
	);
}
