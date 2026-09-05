<?php

/**
 *  This file is part of SNEP.
 *
 *  SNEP is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as
 *  published by the Free Software Foundation, either version 3 of
 *  the License, or (at your option) any later version.
 *
 *  SNEP is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with SNEP.  If not, see <http://www.gnu.org/licenses/lgpl.txt>.
 */

/**
 * Shared delete-blocked dependency-warning primitive (TASK-0032).
 *
 * TASK-0030's audit found this exact "object cannot be deleted because
 * N other objects reference it" panel implemented three times
 * independently -- ExtensionsController::removeAction(),
 * TrunksController::removeAction(), PjsipTransportsController::removeAction()
 * -- each hand-building an $error_message HTML string with its own
 * wording, its own (in two of three cases, MISSING) object identity, and
 * -- confirmed by direct inspection -- the extension/trunk route-item
 * text was concatenated with NO escaping at all
 * (`$regra['id'] . " - " . $regra['desc']`), while the transport variant
 * escaped nothing either. This helper is the one shared place that
 * builds this message from here on; it does not query for dependencies
 * itself (Phase 7's own explicit boundary: "do not create new backend
 * dependency discovery") -- callers keep using their existing
 * getValidation()/getRules()/getUsageDetails() calls and simply hand the
 * already-fetched rows to this helper as plain, already-formatted label
 * strings.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_View_Helper_DependencyWarning extends Zend_View_Helper_Abstract {

    /**
     * dependencyWarning - build the canonical blocked-delete message.
     *
     * @param string $objectType translated noun, e.g. "extension",
     *               "trunk", "transport" -- lowercase, used inline.
     * @param string $objectName the specific row's own identity (name/
     *               number/callerid) -- Phase 8's "object identification"
     *               requirement; every caller now has one to pass (none
     *               did before this task for the extension/trunk cases).
     * @param array  $items already-formatted, human-readable dependency
     *               labels (e.g. "12 - Outbound to SP", "Extension 1001
     *               - Reception") -- escaped HERE, never by the caller,
     *               and never by leaving them unescaped (closes the
     *               pre-existing gap described above).
     * @param string|null $nextStep translated actionable instruction,
     *               e.g. "Remove or reassign these references first."
     *               (Phase 7's "what the user should do next").
     * @return string HTML, safe to assign directly to
     *         $this->view->error_message.
     */
    public function dependencyWarning($objectType, $objectName, array $items, $nextStep = null) {
        $view = $this->view;

        // "Cannot remove" (not "Cannot delete") is the established,
        // already-regression-proven phrase for this exact panel
        // (PjsipTransportsController::removeAction(), pre-existing) --
        // kept verbatim rather than relabeled, per this task's own
        // "do not rename purely cosmetically" precedent (TASK-0031).
        // $objectName is user-entered (a trunk callerid/extension number/
        // transport name) and must never reach the page unescaped --
        // escaped BEFORE interpolation, since vsprintf() (inside
        // translate()) does not escape anything itself.
        $html = '<p>' . $view->translate('Cannot remove %s \'%s\'.', $view->escape($objectType), $view->escape($objectName)) . '</p>';
        $html .= '<p>' . $view->translate('The following %d item(s) depend on it:', count($items)) . '</p>';
        $html .= '<ul>';
        foreach ($items as $item) {
            $html .= '<li>' . $view->escape($item) . '</li>';
        }
        $html .= '</ul>';
        if ($nextStep !== null && $nextStep !== '') {
            $html .= '<p>' . $view->escape($nextStep) . '</p>';
        }
        return $html;
    }

}
