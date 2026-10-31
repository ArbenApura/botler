// THE WEB TOOLS' OUTSIDE SETTINGS, BUILT FROM THE ENVIRONMENT. THE CHAT ROUTE PASSES THEM IN; TESTS PASS THEIR OWN AND NEVER READ THE ENVIRONMENT.

// -- TYPES -- //
import type { WebDeps } from './tools';
// -- ENVS -- //
import { DEEPSEEK_API_KEY, DEEPSEEK_BASE_URL } from '$app/env/private';

// -- FUNCTIONS -- //

/** The DeepSeek key and address of this server, the same ones the model uses. A blank key means search and read are off and their tools say so. */
export function webDeps(): WebDeps {
	return { deepseekKey: DEEPSEEK_API_KEY, baseUrl: DEEPSEEK_BASE_URL };
}
