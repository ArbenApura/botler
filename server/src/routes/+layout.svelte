<script lang="ts">
	// -- ASSETS -- //
	import '../app.css';
	// -- DEP-TYPES -- //
	import type { Snippet } from 'svelte';

	// -- REQUIRED PROPS -- //

	let { children }: { children: Snippet } = $props();
</script>

{@render children()}
