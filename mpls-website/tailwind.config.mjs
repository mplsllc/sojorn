export default {
	content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx}'],
	theme: {
		extend: {
			fontFamily: {
				sans: ['"Inter Variable"', 'system-ui', 'sans-serif'],
				display: ['"Space Grotesk Variable"', 'system-ui', 'sans-serif'],
			},
			colors: {
				brand: {
					50: '#e8f4fa',
					100: '#c5e3f2',
					200: '#9dcfe8',
					300: '#73c6e5',
					400: '#5CA4C5',
					500: '#4586AA',
					600: '#2E688F',
					700: '#225982',
					800: '#174A74',
					900: '#002C5A',
					950: '#001d3d',
				},
			},
			animation: {
				'fade-in': 'fadeIn 0.6s ease-out forwards',
				'slide-up': 'slideUp 0.6s ease-out forwards',
			},
			keyframes: {
				fadeIn: {
					'0%': { opacity: '0' },
					'100%': { opacity: '1' },
				},
				slideUp: {
					'0%': { transform: 'translateY(24px)', opacity: '0' },
					'100%': { transform: 'translateY(0)', opacity: '1' },
				},
			},
		},
	},
	plugins: [],
};
