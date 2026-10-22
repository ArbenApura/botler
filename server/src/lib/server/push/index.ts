// THE APP'S PUSH SENDER, BUILT ONCE FROM THE ENVIRONMENT. NULL WHEN PUSH IS NOT SET UP; HALF SET UP IS AN ERROR AT START, NOT A SILENT NO PUSH.

// -- TYPES -- //
import type { Pusher } from './fcm';
// -- ENVS -- //
import { FCM_PROJECT_ID, FCM_SERVICE_ACCOUNT } from '$app/env/private';
// -- MODULES -- //
import { createFcmPusher, parseServiceAccount } from './fcm';

// -- STATES -- //

let pusher: Pusher | null | undefined;

// -- FUNCTIONS -- //

export function getPusher(): Pusher | null {
	if (pusher !== undefined) return pusher;
	if (!FCM_PROJECT_ID && !FCM_SERVICE_ACCOUNT) return (pusher = null);
	if (!FCM_PROJECT_ID || !FCM_SERVICE_ACCOUNT)
		throw new Error('Push needs both FCM_PROJECT_ID and FCM_SERVICE_ACCOUNT. Set both or neither.');
	const { clientEmail, privateKey } = parseServiceAccount(FCM_SERVICE_ACCOUNT);
	return (pusher = createFcmPusher({ projectId: FCM_PROJECT_ID, clientEmail, privateKey }));
}
