// PRINTS THE SQL OF THE DATA RESET FUNCTION (yarn tsx scripts/data-reset-sql.ts, or with "latest" for the newest copy). See src/lib/server/db/dataResetSql.ts.

// -- MODULES -- //
import { dataResetLatestSql, dataResetMigrationSql } from '../src/lib/server/db/dataResetSql';

process.stdout.write(process.argv[2] === 'latest' ? dataResetLatestSql() : dataResetMigrationSql());
