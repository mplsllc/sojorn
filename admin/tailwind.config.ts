import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#f5f3ff',
          100: '#ede9fe',
          200: '#ddd6fe',
          300: '#c4b5fd',
          400: '#a78bfa',
          500: '#6B5B95',
          600: '#5a4a82',
          700: '#4a3d6b',
          800: '#3b3054',
          900: '#2d243f',
        },
        warm: {
          50: '#FDFCFA',
          100: '#F8F7F4',
          200: '#F0EFEB',
          300: '#E8E6E1',
          400: '#D8D6D1',
          500: '#C8C6C1',
        },
      },
    },
  },
  plugins: [],
};

export default config;
