import { useEffect, useRef, useState } from 'react';
import Icon from './Icon.jsx';
import { flattenToc } from './TableOfContents.jsx';
import useActiveHeading from '../../hooks/useActiveHeading.js';

export default function MobileToc({ items }) {
	const flat = flattenToc(items);
	const active = useActiveHeading(flat.map((item) => item.slug));
	const [open, setOpen] = useState(false);
	const rootRef = useRef(null);
	const current = flat.find((item) => item.slug === active);

	// Fica oculto a partir de 72rem, então ele se fecha nesse ponto em vez de reabrir quando a janela volta a ficar estreita.
	useEffect(() => {
		const wide = matchMedia('(min-width: 72rem)');
		const close = () => setOpen(false);
		wide.addEventListener('change', close);
		return () => wide.removeEventListener('change', close);
	}, []);

	useEffect(() => {
		if (!open) return;
		const onClick = (event) => {
			if (!rootRef.current?.contains(event.target)) setOpen(false);
		};
		const onKey = (event) => {
			if (event.key !== 'Escape') return;
			// Ao fechar, o link focado na lista fica oculto, então o foco volta para o alternador.
			if (rootRef.current?.contains(document.activeElement)) rootRef.current.querySelector('button').focus();
			setOpen(false);
		};
		window.addEventListener('click', onClick);
		window.addEventListener('keydown', onKey);
		return () => {
			window.removeEventListener('click', onClick);
			window.removeEventListener('keydown', onKey);
		};
	}, [open]);

	// Fecha quando o foco sai dele, para que navegar com Tab não deixe a lista sobre a página.
	const closeOnBlur = (event) => {
		if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
	};

	return (
		<nav className="docs-mobile-toc" aria-label="Nesta página" ref={rootRef} onBlur={closeOnBlur}>
			<button type="button" className="docs-mobile-toc-toggle" aria-expanded={open} onClick={() => setOpen(!open)}>
				<span className="docs-mobile-toc-label">
					Nesta página
					<Icon name="right-caret" className="docs-mobile-toc-caret" />
				</span>
				<span className="docs-mobile-toc-current">{current?.text}</span>
			</button>
			{open && (
				<ul className="docs-mobile-toc-list">
					{flat.map((item) => (
						<li key={item.slug}>
							<a
								href={`#${item.slug}`}
								className={`docs-toc-link docs-toc-depth-${item.depth}`}
								aria-current={item.slug === active ? 'true' : undefined}
								onClick={() => setOpen(false)}
							>
								{item.text}
							</a>
						</li>
					))}
				</ul>
			)}
		</nav>
	);
}
