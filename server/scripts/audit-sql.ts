// PRINTS THE SQL OF THE AUDIT TRIGGERS MIGRATION (yarn tsx scripts/audit-sql.ts). See src/lib/server/db/auditSql.ts.

// -- MODULES -- //
import { auditMigrationSql } from '../src/lib/server/db/auditSql';

process.stdout.write(auditMigrationSql());
