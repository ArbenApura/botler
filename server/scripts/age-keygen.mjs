// MAKES A NEW age KEY PAIR FOR THE ENCRYPTED DATABASE BACKUPS. RUN WITH: node scripts/age-keygen.mjs <file for the private key>
// The PUBLIC key (age1...) goes into BACKUP_AGE_RECIPIENT on the server. The PRIVATE key (AGE-SECRET-KEY-1...) is written to the file
// you name, outside this repo, and kept in a password manager. It must never be on the server. Only the public key is printed.
import { generateIdentity, identityToRecipient } from 'age-encryption';
import { existsSync, writeFileSync } from 'node:fs';

const out = process.argv[2];
if (!out) {
	console.error('Usage: node scripts/age-keygen.mjs <file for the private key>');
	process.exit(1);
}
if (existsSync(out)) {
	console.error(`${out} already exists: refusing to overwrite a key.`);
	process.exit(1);
}
const identity = await generateIdentity();
const recipient = await identityToRecipient(identity);
writeFileSync(
	out,
	`# Botler backup private key. Keep it in a password manager. Never put it on the server or in the repo.\n# Public key: ${recipient}\n${identity}\n`,
	{ mode: 0o600 }
);
console.log(`Public key (BACKUP_AGE_RECIPIENT): ${recipient}`);
console.log(`Private key written to: ${out}`);
