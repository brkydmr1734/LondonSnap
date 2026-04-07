/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: '#FFFC00',
        secondary: '#6C5CE7',
        background: '#0A0A0A',
        surface: '#1A1A1A',
        'surface-variant': '#2A2A2A',
        error: '#FF6B6B',
        success: '#00D084',
        warning: '#FFAE00',
      },
    },
  },
  plugins: [],
};
