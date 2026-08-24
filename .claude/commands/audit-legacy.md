# Audit Legacy Runtime

Perform a read-only runtime audit of the MAG/SNEP codebase.

Identify:
- PHP version assumptions
- PHP extensions
- Apache requirements
- database drivers and configuration
- schema/import scripts
- filesystem paths and writable directories
- cron/background processes
- shell/sudo calls
- Asterisk dependencies
- chan_sip dependencies
- absolute `/var/www/html/snep` references
- Debian-specific assumptions

Do not refactor the application during this command.
Record durable findings in a dedicated audit document.
