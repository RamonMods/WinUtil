// Texto do sobretítulo do hero com brilho periódico. O ShinyText não resolve variáveis CSS, então as cores são escolhidas por tema.
// A cor renderizada no servidor vem do CSS, então já corresponde ao tema antes da hidratação.
const FIRST_PAINT = { backgroundImage: 'linear-gradient(var(--wu-eyebrow-text), var(--wu-eyebrow-text))' };
import ShinyText from '../react-bits/ShinyText.jsx';
import useStarlightTheme from '../../hooks/useStarlightTheme.js';
import useAccentColor from '../../hooks/useAccentColor.js';

export default function HeroEyebrow({ text }) {
	const theme = useStarlightTheme();
	const light = theme === 'light';
	const accent = useAccentColor();
	return (
		<ShinyText
			text={text}
			color={light ? '#525252' : '#a3a3a3'}
			shineColor={light ? accent : '#ffffff'}
			speed={3}
			delay={1.5}
			style={FIRST_PAINT}
		/>
	);
}
