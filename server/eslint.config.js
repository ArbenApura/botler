import js from '@eslint/js';
import svelte from 'eslint-plugin-svelte';
import globals from 'globals';
import ts from 'typescript-eslint';
import noLiteralColours from './eslint-rules/no-literal-colours.js';

export default ts.config(
	{
		ignores: [
			'.svelte-kit/',
			'cli/',
			'build/',
			'node_modules/',
			'.yarn/',
			'static/',
			'coverage/',
			'test-results/'
		]
	},
	js.configs.recommended,
	...ts.configs.recommended,
	...svelte.configs['flat/recommended'],
	{
		languageOptions: { globals: { ...globals.browser, ...globals.node } }
	},
	{
		files: ['**/*.svelte', '**/*.svelte.ts'],
		languageOptions: { parserOptions: { parser: ts.parser } }
	},
	{
		rules: {
			'@typescript-eslint/no-explicit-any': 'error',
			'@typescript-eslint/ban-ts-comment': [
				'error',
				{ 'ts-ignore': true, 'ts-expect-error': 'allow-with-description' }
			],
			'@typescript-eslint/no-unused-vars': [
				'error',
				{ argsIgnorePattern: '^_', varsIgnorePattern: '^_' }
			],
			'svelte/no-navigation-without-resolve': 'off',
			'svelte/no-at-html-tags': 'error',
			'svelte/require-each-key': 'error'
		}
	},
	{
		// LITERAL COLOURS ARE REFUSED IN COMPONENTS AND SERVER PAGES, THE THEME FILES AND TESTS MAY HOLD THEM
		files: ['src/**/*.svelte', 'src/**/*.ts'],
		ignores: ['src/lib/theme/**', '**/*.test.ts'],
		plugins: { botler: { rules: { 'no-literal-colours': noLiteralColours } } },
		rules: { 'botler/no-literal-colours': 'error' }
	}
);
