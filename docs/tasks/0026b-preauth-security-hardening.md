# TASK-0026B — pre-authentication security hardening

F1 was verified as an unauthenticated language value being written by
`AuthController` before being passed to `Snep_Locale::setExtensionsLanguage()`.
F6 was verified as `Snep_Acl::getCaseSensitive()` interpolating the login
username into a raw `BINARY` predicate.

The remediation admits only `en`, `pt_BR`, and `es` before either controller
writes configuration or invokes the locale operation. `Snep_Locale` repeats
the same finite-domain check as defense in depth immediately before its shell
operation. Invalid pre-auth values have no write or reload side effect.

`getCaseSensitive()` now uses Zend_Db's bound `where('name = BINARY ?', ...)`,
preserving the legacy case-sensitive comparison while treating SQL-shaped
input as a literal value.

`make preauth-security-smoke` exercises valid choices, invalid non-mutation,
literal SQL-shaped usernames, and valid login, restoring setup.conf on exit.
