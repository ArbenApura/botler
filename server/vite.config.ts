// -- DEP-MODULES -- //
import adapterNode from '@sveltejs/adapter-node';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			adapter: adapterNode()
		})
	],
	// TWO FIXED PORTS: 5280 IS THE DEV SERVER, 5290 IS THE LOCAL BUILD PREVIEW. strictPort FAILS INSTEAD OF MOVING TO ANOTHER PORT (5180 AND 5190 BELONG TO AGENT FLOW BOARD)
	server: { port: 5280, strictPort: true },
	preview: { port: 5290, strictPort: true },
	test: {
		include: ['src/**/*.test.ts', 'tests/**/*.test.ts'],
		environment: 'node',
		testTimeout: 60_000,
		hookTimeout: 180_000
	}
});
