// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces

declare global {
	namespace App {
		interface Locals {
			/** The signed in person, or null. Set for every request by the authentication hook (P1.4). */
			user: { id: string; name: string; email: string } | null;
		}
	}
}

export {};
