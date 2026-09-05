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
 * Shared save/apply/delete feedback primitive (TASK-0032).
 *
 * TASK-0020 (transports) and TASK-0031 (extensions/trunks) each built
 * their own one-shot FlashMessenger banner set, independently -- the
 * NAMESPACES and the CONTROLLER-SIDE outcome logic they carry rightly stay
 * separate (transports genuinely support RESTART_REQUIRED, extensions/
 * trunks never do -- see docs/tasks/0031-extensions-trunks-administration-experience.md's
 * own "no evidence any endpoint-level save ever needs a hard restart"
 * finding), but the three list pages then hand-rendered near-identical
 * `foreach (...) { <div class="alert alert-X">...</div> }` blocks with
 * only the outcome->Bootstrap-class mapping duplicated between them. This
 * helper is that one shared mapping -- never a new persistence mechanism,
 * never a new controller-side outcome (Phase 6's own explicit boundary:
 * "only use states supported by the entity").
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_View_Helper_ApplyFeedback extends Zend_View_Helper_Abstract {

    /**
     * Canonical outcome -> Bootstrap alert class, fixed rendering order.
     * A controller passes only the subset its own entity actually
     * supports (see each controller's own reportApplyResult()/
     * reportSaveResult()) -- an outcome key that is absent or empty
     * renders nothing, never a fabricated "0 messages" banner.
     */
    private static $classMap = array(
        'saved_active'     => 'alert-success',
        'deleted'          => 'alert-success',
        'saved_pending'    => 'alert-info',
        'restart_required' => 'alert-warning',
        'apply_failed'     => 'alert-danger',
    );

    /**
     * applyFeedback - render every one-shot flash message currently
     * pending, in the canonical outcome order above, regardless of which
     * subset the caller supplies.
     *
     * @param array $messages outcome-key => array of already-translated
     *              message strings (each controller's own
     *              FlashMessenger::getMessages('<namespace>') result,
     *              passed straight through -- this helper does not read
     *              FlashMessenger itself, so it stays agnostic of the
     *              action-helper broker and easy to unit-reason-about).
     * @return string HTML, safe to echo directly.
     */
    public function applyFeedback(array $messages) {
        $view = $this->view;
        $html = '';
        foreach (self::$classMap as $key => $cssClass) {
            if (empty($messages[$key])) {
                continue;
            }
            foreach ($messages[$key] as $msg) {
                $html .= '<div class="alert ' . $cssClass . '">' . $view->escape($msg) . "</div>\n";
            }
        }
        return $html;
    }

}
