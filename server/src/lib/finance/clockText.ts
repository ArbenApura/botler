// A CLOCK TIME AS TEXT FOR A PERSON: 12 OR 24 HOUR, IN THEIR ZONE
// The server has no phone to ask, so auto reads as 12 hour here (the app itself resolves auto from the phone).

// -- TYPES -- //

type TimeFormat = 'auto' | '12' | '24';

export type ClockPrefs = { zone: string; timeFormat: TimeFormat };

// -- FUNCTIONS -- //

/** 3:42 PM or 15:42 in the person's zone. */
export function clockText(instant: Date, prefs: ClockPrefs): string {
	return new Intl.DateTimeFormat('en-US', {
		hour: prefs.timeFormat === '24' ? '2-digit' : 'numeric',
		minute: '2-digit',
		hourCycle: prefs.timeFormat === '24' ? 'h23' : 'h12',
		timeZone: prefs.zone
	}).format(instant);
}
