/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./templates/**/*.html",
    "./src/**/*.rs",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        sans: ['DM Sans', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'ui-monospace', 'monospace'],
      },
      colors: {
        // Custom organic colors for use beyond DaisyUI
        leaf: {
          light: '#2D5A3D',
          dark: '#86EFAC',
        },
        bark: {
          light: '#6B5B4F',
          dark: '#A1887F',
        },
        soil: {
          light: '#3D3529',
          dark: '#E7E5E4',
        },
      },
    },
  },
  // Note: DaisyUI is loaded via CDN link in base.html
  // The standalone Tailwind CLI doesn't support plugins
}
