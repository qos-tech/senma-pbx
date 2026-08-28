# TASK-0026A — authorization default-deny

## Resume checkpoint

Resumed after Claude had changed `PermissionPlugin.php` and `resources.xml`.
XML had already been checked with `simplexml_load_file()`; the attempted
`php -l` XML check was correctly disregarded. Claude had also confirmed the
Portuguese permission landing page and absence of a redirect loop. The next
pending work was live validation of unknown actions, grant/revoke, admin,
public routes, and an internal helper.

## Implementation present at resume

* Superuser (`$_SESSION['id_user'] == "1"`) retains its existing bypass.
* Authenticated-open controllers are an explicit reviewed allowlist.
* `khomp-links` and `route-form` resolve to their parent resource for the
  required AJAX/REST paths.
* Resource `index` and explicit read-only actions require `*_read`; all other
  resource actions require `*_write`. An unregistered controller is denied.
* `errors-tdm` was registered as a read resource and `parameters/write` was
  made grantable.

## Continuation validation

`make authorization-smoke` passed (16/16): anonymous login works; anonymous
privileged GET/POST are denied; restricted dashboard works; direct safe GET to
`parameters/language` (the F16-style gap) redirects to `/permission/error`;
an unknown unregistered action redirects likewise; admin grants the exact
`default_errors-tdm_read` and `default_tdm-links_read` permissions through the
existing Users > Permission UI; access is then dispatched and the Khomp AJAX
alias returns 200; UI revoke denies again; admin reaches the privileged user
permission page; denial remains after app restart.

`errors-tdm` dispatches after grant but returns HTTP 500 in this Docker setup
because the legacy no-Khomp controller path has a pre-existing runtime error.
This is an authorization allow result, not a permission denial, and is not
changed by this task.

`scripts/authorization-coverage-check.sh` is the deterministic inventory:
every controller must be resource-registered, a reviewed authenticated-open
controller (whose actions are enumerated), or a resource alias. Registered
and alias unknown actions default to write. Thus new controller/action work
cannot silently reintroduce the old seven-name fall-through.

## Regression checkpoint

* `make authorization-smoke`: PASS.
* `make smoke`: one unrelated harness mismatch: `/` returned dashboard HTTP
  200 after login while the legacy script expects 302; all other checks passed.
* `make call-smoke`: runner disconnected after successful fixture provisioning,
  registration, call establishment and hangup; not retried.
* `make trunk-smoke`: did not execute after Docker container recreate race
  (`No such container` during dependency startup); not retried.
* `make transport-smoke`: unrelated failure: Asterisk manager unavailable
  during fixture cleanup, then pre-existing `peers` fixture `1097` blocked UX.
* `restart-smoke`, `external-failure-smoke`, `external-content-smoke`: not run
  in this continuation after the unrelated regression environment failures.

## Remaining debt

The explicit authenticated-open list remains legacy policy and must be
reviewed when its controller actions change. The no-Khomp `errors-tdm` 500,
smoke root-redirect expectation, Docker recreate race, and transport fixtures
are unrelated follow-up work; no TASK-0026B+ work was started.
