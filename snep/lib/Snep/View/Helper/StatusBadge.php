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
 * Shared status badge primitive (TASK-0032 / TASK-0035E6).
 *
 * TASK-0029B established the 7-state runtime vocabulary (ACTIVE/DEGRADED/
 * PENDING/INACTIVE/DISABLED/ERROR/UNKNOWN, see Snep_PjsipStatus_Manager)
 * and its badge/tooltip convention, but the markup itself was duplicated
 * verbatim in three places (extensions/index.phtml, trunks/index.phtml,
 * trunks/addedit.phtml's Diagnostics section) with no shared definition --
 * confirmed by direct inspection before this task. This helper is the one
 * place that mapping is defined; every caller (Extensions, Trunks,
 * Transports -- list pages and Diagnostics sections alike) renders through
 * it instead of re-declaring its own copy of the class/label maps.
 *
 * TASK-0035E6: detail text is filtered through
 * Snep_PjsipStatus_Presenter::operatorDetail() so healthy ACTIVE states
 * stay quiet, redundant echoes of the primary label are dropped, and
 * diagnostic/exception leakage never reaches the operator surface.
 *
 * Deliberately renders ONLY the badge (+ optional detail paragraph) --
 * never the surrounding <td>/data-attribute, which stays the calling
 * view's own responsibility (a list cell and a Diagnostics form-group
 * need different wrappers; this helper does not need to know which).
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_View_Helper_StatusBadge extends Zend_View_Helper_Abstract {

    private static $classMap = array(
        'ACTIVE'   => 'label-success',
        'PENDING'  => 'label-warning',
        'DEGRADED' => 'label-warning',
        'INACTIVE' => 'label-default',
        'DISABLED' => 'label-default',
        'ERROR'    => 'label-danger',
        'UNKNOWN'  => 'label-default',
    );

    private static $textMap = array(
        'ACTIVE'   => 'Active',
        'PENDING'  => 'Pending',
        'DEGRADED' => 'Degraded',
        'INACTIVE' => 'Inactive',
        'DISABLED' => 'Disabled',
        'ERROR'    => 'Error',
        'UNKNOWN'  => 'Unknown',
    );

    /**
     * statusBadge - render one normalized status badge.
     *
     * @param string|null $state   one of the Snep_PjsipStatus_Manager
     *                    constants, or null for "this row has no runtime
     *                    status at all" (a legacy/unsupported technology --
     *                    a real, distinct product state, never silently
     *                    coerced into UNKNOWN).
     * @param array $options
     *   'detail'        string|null, plain product-language reason --
     *                    NEVER raw Asterisk CLI text (rendered as the
     *                    badge's title tooltip, and additionally as
     *                    visible text when 'showDetail' is set). Filtered
     *                    by Snep_PjsipStatus_Presenter before render.
     *   'showDetail'    bool, also render the detail as a visible
     *                    <p class="help-block snep-status-detail"> below
     *                    the badge -- for a Diagnostics section, where a
     *                    hover-only tooltip is not enough. Omitted when
     *                    the presenter returns an empty detail (healthy
     *                    ACTIVE, redundant, or suppressed leak).
     *   'unavailableText' string, overrides the default "not applicable"
     *                    label used when $state is null.
     *   'timestamp'     string|null, rendered as small muted text next
     *                    to the badge when given -- optional per Phase 5
     *                    ("optional timestamp, where available"); no
     *                    caller currently has one to pass.
     * @return string HTML, safe to echo directly (all dynamic text is
     *         escaped here -- callers never need their own escape() call).
     */
    public function statusBadge($state, array $options = array()) {
        $view = $this->view;

        if ($state === null) {
            $unavailable = isset($options['unavailableText'])
                ? $options['unavailableText']
                : $view->translate('Not applicable');
            return '<span class="text-muted" title="' . $view->escape($unavailable) . '">&mdash;</span>';
        }

        $cls = isset(self::$classMap[$state]) ? self::$classMap[$state] : 'label-default';
        // An unrecognized state string is treated exactly like UNKNOWN for
        // display purposes (never crashes, never invents a color) -- but
        // the raw state name is still shown, never silently swallowed.
        $txt = isset(self::$textMap[$state]) ? $view->translate(self::$textMap[$state]) : $view->escape($state);
        $rawDetail = isset($options['detail']) ? (string) $options['detail'] : '';
        $detail = Snep_PjsipStatus_Presenter::operatorDetail($state, $rawDetail);

        $html = '<span class="label ' . $cls . '"';
        if ($detail !== '') {
            $html .= ' title="' . $view->escape($detail) . '"';
        }
        $html .= '>' . $txt . '</span>';

        if (!empty($options['timestamp'])) {
            $html .= ' <small class="text-muted">' . $view->escape($options['timestamp']) . '</small>';
        }

        if (!empty($options['showDetail']) && $detail !== '') {
            $html .= '<p class="help-block snep-status-detail">' . $view->escape($detail) . '</p>';
        }

        return $html;
    }

}
