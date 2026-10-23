// THE WEB TOOLS' OUTSIDE SETTINGS, BUILT FROM THE ENVIRONMENT. THE CHAT ROUTE PASSES THEM IN; TESTS PASS THEIR OWN AND NEVER READ THE ENVIRONMENT.

// -- TYPES -- //
import type { WebDeps } from './tools';
// -- ENVS -- //
import { TAVILY_API_KEY } from '$app/env/private';

// -- FUNCTIONS -- //

/** The search key of this server. Blank means search is off and its tool says so. */
export function webDeps(): WebDeps {
	return { tavilyKey: TAVILY_API_KEY };
}
