# TASK-0013 — Fix `ExtensionsController::securityPassword()` PHP 8 compatibility

## Status

**Implemented and validated.** `make smoke`: 16 PASS / 0 FAIL / 0
EXPECTED_LIMITATION. `make call-smoke`: 18/18 PASS. No new PHP Fatal
Errors. Full extension lifecycle (zero extensions → create → list →
edit → list → delete → list) validated against the real running UI, with
the list confirmed to render actual content, not just HTTP 200. Not
committed — stopping at the checkpoint per the task instructions.

## Goal

Fix the single PHP 8 blocker found incidentally during TASK-0012
(`docs/tasks/0012-web-base-path-cleanup.md` §8): `securityPassword()`
crashed the entire extensions list whenever at least one extension
existed in the database. Fix only this, preserving the intended legacy
password-strength-validation behavior. No broader PHP 8 sweep.

## 1. The method and its intent

`snep/modules/default/controllers/ExtensionsController.php`, lines
111-129 (doc comment + body):
```php
/**
 * Verify security password
 * @param int $password
 * @return int $force
 */
public function securityPassword($password){

    $force = 0;

    if(count(password) >= 8) $force += 10;
    if(count(password) >= 16) $force += 10;
    if(preg_match('/[A-Z]/', $password)) $force += 20;
    if(preg_match('/[a-z]/', $password)) $force += 20;
    if(preg_match('/[0-9]/', $password)) $force += 20;
    if(preg_match('/[@?!%#]/', $password)) $force += 20;

    return $force;
}
```
Intent, confirmed by reading the whole method: a **password-strength
scorer**. It awards points for length (`>= 8` chars, `>= 16` chars) and
for each character class present (uppercase, lowercase, digit, one of
`@?!%#`), for a maximum score of 110. The `@param int $password` doc
comment is itself wrong/stale (the parameter is a password string, not
an int) — one more sign this method was never fully adapted after being
copied in from somewhere.

## 2. Callers and the type of `$password` at every call site

**Exactly one call site in the whole tree** (confirmed via
`grep -rn "securityPassword" snep/modules snep/lib`):

`ExtensionsController::indexAction()`, line 96:
```php
$extensions = Snep_Extensions_Manager::getAll();
foreach($extensions as $key => $exten){
    $secure = self::securityPassword($exten["password"]);
    if($secure <= 40){
        $passwordValidate = false;
        $passwordValidateExten .= $exten['exten']." ";
    }
}
if(!$passwordValidate){
    $this->view->alert_message = ...weak passwords warning... . "(".$passwordValidateExten.")";
}
```
`$extensions` comes from `Snep_Extensions_Manager::getAll()`
(`snep/lib/Snep/Extensions/Manager.php:138`), which selects from the
`peers` table with `'password' => 'secret'` as a column alias. Schema
(`snep/install/database/schema.sql:202,378`):
```sql
`secret` varchar(80) default NULL,
```
So `$exten["password"]` is always **`peers.secret`, a plain string
column (nullable in the schema)** — never an array, never a number. The
`@param int` doc comment does not match reality at all.

## 3. Reproducing the failure

Confirmed live against a running `make dev` environment, before any fix:

1. Extensions list with **zero** extensions: `GET
   /index.php/default/extensions` → `200`, renders fine (the crashing
   `foreach` loop over `$extensions` never executes its body when
   `$extensions` is empty).
2. Created a real PJSIP extension through the actual UI HTTP flow
   (`POST /index.php/default/extensions/add`, `secret=Test12345!`) → `302`,
   persisted correctly.
3. `GET /index.php/default/extensions` again →

   **`HTTP 500`**, empty body (production `display_errors` off).
   `/var/log/apache2/mag-error.log`:
   ```
   PHP Fatal error:  Uncaught Error: Undefined constant "password" in
   /var/www/html/snep/modules/default/controllers/ExtensionsController.php:120
   Stack trace:
   #0 /var/www/html/snep/modules/default/controllers/ExtensionsController.php(96): ExtensionsController->securityPassword('Test12345!')
   #1 /var/www/html/snep/lib/Zend/Controller/Action.php(516): ExtensionsController->indexAction()
   #2 /var/www/html/snep/lib/Zend/Controller/Dispatcher/Standard.php(308): Zend_Controller_Dispatcher_Standard->dispatch(...)
   #3 /var/www/html/snep/lib/Zend/Controller/Front.php(954): Zend_Controller_Dispatcher_Standard->dispatch(...)
   #4 /var/www/html/snep/lib/Zend/Application/Bootstrap/Bootstrap.php(97): Zend_Controller_Front->dispatch()
   #5 /var/www/html/snep/lib/Zend/Application.php(366): Zend_Application_Bootstrap_Bootstrap->run()
   #6 /var/www/html/snep/index.php(71): Zend_Application->run()
   #7 {main}
     thrown in /var/www/html/snep/modules/default/controllers/ExtensionsController.php on line 120
   ```
   **File:line:** `ExtensionsController.php:120`.
   **Call path:** normal Zend dispatch → `indexAction()` (line 96) →
   `securityPassword('Test12345!')` → fatal at line 120.
   Confirmed the value actually received at the crash site was the real
   `secret` string (`'Test12345!'`), matching §2's type trace exactly.

## 4. Root cause and why `strlen($password)` is correct, not assumed

`count(password)` (no `$`) has two independent problems, either one
fatal on its own under PHP 8:

1. `password` is a bareword with no `$` — PHP looks it up as a constant.
   No such constant exists, so PHP 8 throws `Error: Undefined constant
   "password"` immediately, before `count()` is ever reached.
2. Even fixing only the typo to `count($password)` would still fatal:
   `$password` is a string (§2), and `count()` on a
   non-Countable/non-array in PHP 8 throws `TypeError: count(): Argument
   #1 ($value) must be of type Countable|array, string given`. There is
   no scalar/array ambiguity to preserve here — `$exten["password"]` is
   never anything but a string at this call site.

Given the method's actual purpose (§1: score password strength by length
+ character class, with two length thresholds at 8 and 16 chars),
`strlen($password)` is the only replacement that preserves the intended
behavior — `count()` was never valid for a string in any PHP version;
this was a pre-existing bug (bareword typo, plus the wrong function
entirely) that simply never surfaced before because nothing in earlier
PHP versions or test coverage exercised a populated extensions list
until TASK-0011's real create-extension flow and TASK-0012's manual UI
validation.

One additional consideration, evidence-based rather than assumed: the
`secret` column is `varchar(80) default NULL`, so a NULL value is
possible in the schema even though `execAdd()` — the only code path this
controller uses to write `secret` — always assigns a string (`$secret =
(isset($formData["password"])) ? $formData["password"] : "";`, never
literal NULL). To stay correct for any pre-existing/legacy row that
might have `secret IS NULL` (imported data, manual DB edits, etc.)
without introducing a new PHP 8.1+ "passing null to non-nullable
parameter" deprecation notice, the fix casts to string first:
`strlen((string)$password)`. This is not new validation logic — a NULL/
empty password already scored 0 under the intended design (fails both
length thresholds, no character classes match) and remains untouched.

## 5. Search for the same bug elsewhere (scoped, not a sweep)

Per the task's explicit instruction not to start another broad PHP 8
sweep, this search was scoped to exactly what was asked: the same exact
`count()`-on-scalar pattern, in the extension-management path.

```
grep -rnE "count\([a-z_]+\)" snep/modules snep/lib | grep -v 'count(\$'
```
Only match anywhere in the entire tree: the two lines fixed here
(`ExtensionsController.php:120,121`). Every other `count(...)` call in
`ExtensionsController.php` (lines 275, 791, 858, 968, 973) and in the
same extension-management path (`Snep_Extensions_Manager`,
`Snep_PjsipConf`, `Snep_InterfaceConf`) operates on a genuine array
(`$nameValue`, `$rules`, `$_rules`, `$rulesQuery`, `$peer_data`) —
verified by reading each call site, not by pattern-matching alone.
**No other instances of this bug exist.** No independent blocker was
found; nothing to stop and report per item 10.

## 6. Fix

`snep/modules/default/controllers/ExtensionsController.php`:
```php
public function securityPassword($password){

    $force = 0;

    // TASK-0013: was `count(password)` -- a bareword (undefined
    // constant under PHP 8, fatal) that was never valid even as
    // count($password): $password is peers.secret (varchar(80),
    // nullable in schema.sql), a scalar string, not a Countable/array.
    // This function scores password strength by length + character
    // class, so strlen() is the intended check; cast to string since
    // the column can be NULL even though this controller's own
    // execAdd() never writes NULL (isset(...) : "" fallback) -- see
    // docs/tasks/0013-extension-security-password-php84.md.
    $passwordLength = strlen((string)$password);
    if($passwordLength >= 8) $force += 10;
    if($passwordLength >= 16) $force += 10;
    if(preg_match('/[A-Z]/', $password)) $force += 20;
    if(preg_match('/[a-z]/', $password)) $force += 20;
    if(preg_match('/[0-9]/', $password)) $force += 20;
    if(preg_match('/[@?!%#]/', $password)) $force += 20;

    return $force;
}
```
Two-line change (plus the explanatory comment). Nothing else in the file
touched.

## 7. Validation against the real UI

Full lifecycle, all steps against the actual running app (not unit
tests), each list check confirmed to render meaningful content:

1. **Zero extensions**: `GET /index.php/default/extensions` → `200`,
   size 20170 bytes, `var controller = "extensions"` present.
2. **Create** (`exten=1050`, `secret=Test12345!`, a strong password) via
   `POST .../extensions/add` → `302`.
3. **List with extension present**: `200`, size 20942 bytes, `"1050"`
   appears 6 times in the rendered page (extension row content, not
   merely a 200 status). No weak-password alert (strong password scores
   above the `<= 40` threshold).
4. **Edit** (`GET .../extensions/edit/id/1050` → `200`, form
   `action="/index.php/extensions/edit/id/1050"`; submitted a name
   change) → `302`.
5. **List again**: renamed extension's new name (`Task0013 Edited 1050`)
   present in the rendered page.
6. **Weak-password path**, to confirm the fix preserves the intended
   validation (not just "doesn't crash"): created a second extension
   (`exten=1051`, `secret=abc`) → `302`. List reloaded: the weak-password
   alert div renders with the exact expected text (Portuguese, the
   app's configured locale): `"Você possui ramais com senhas fracas. Por
   medida de segurança é importante atualiza-las.(1051 )"` — correctly
   naming only 1051 (score 20: lowercase-only, 3 chars), not 1050 (score
   well above 40).
7. **Delete** both `1050` and `1051` via `POST .../extensions/remove` →
   `302` each.
8. **List again**: back to zero extensions, `200`, no stale rows in
   `peers`.

## 8. Regression

- `make smoke`: **16 PASS / 0 FAIL / 0 EXPECTED_LIMITATION**.
- `make call-smoke`: **18/18 PASS** (includes a real create/delete
  extension HTTP flow plus an actual PJSIP call end-to-end).
- `grep -c "Fatal error" /var/log/apache2/mag-error.log` after the full
  validation run: **0** (the container was recreated by `make
  call-smoke`, giving a clean log; the only fatal errors ever recorded
  in this task were the pre-fix reproduction in §3, captured before the
  fix was applied).

## 9. Noted, not fixed (no independent blocker — informational only)

While reproducing the create-extension flow, the same request logged
several **pre-existing, non-fatal `PHP Warning`s** (not blockers, list
still rendered/functioned correctly around them, extensions still
create/edit/delete/list fine):
`Undefined array key "pickupgroup"` (`extensions/addedit.phtml:64`),
`Undefined array key "cancallforward"` and `"minute_control"`, and
`Undefined variable $fullcontact` (all in `ExtensionsController.php`'s
`execAdd()`, around lines 640-743). These are not the `count()`/fatal
class of bug this task targets, do not block any of the validated
lifecycle steps, and are left untouched per the task's explicit
instruction not to expand scope or start another sweep.
