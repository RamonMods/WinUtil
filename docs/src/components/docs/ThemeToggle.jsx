// Compartilha a chave de armazenamento `starlight-theme` com ThemeProvider.astro, que aplica o tema antes da primeira pintura.
import Icon from './Icon.jsx';
import useStarlightTheme from '../../hooks/useStarlightTheme.js';

const STORAGE_KEY = 'starlight-theme';

export default function ThemeToggle() {
	const label = `Mudar para o tema ${useStarlightTheme() === 'light' ? 'escuro' : 'claro'}`;
	const toggle = () => {
		const next = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
		document.documentElement.dataset.theme = next;
		try {
			localStorage.setItem(STORAGE_KEY, next);
		} catch {
			// O armazenamento pode estar bloqueado; o tema ainda muda nesta página.
		}
	};
	return (
		<button
			type="button"
			className="docs-theme-toggle"
			onClick={toggle}
			aria-label={label}
			title={label}
		>
			<Icon name="sun" className="docs-theme-sun" />
			<Icon name="moon" className="docs-theme-moon" />
		</button>
	);
}
