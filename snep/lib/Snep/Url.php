<?php

/**
 *  This file is part of SNEP / SENMA PBX.
 *
 *  SNEP is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  TASK-0034I-R7: Canonical URL generation contract.
 *
 *  Distinguishes four concepts that legacy code often conflates:
 *
 *  1. Deployment web base path (setup.conf path.web) — "" at root,
 *     "/subdir" under a subdirectory. Never includes index.php.
 *  2. Front-controller script URL — web base + "/index.php". Used for
 *     controller/action and AJAX endpoints that must hit the MVC entry.
 *  3. Static/public asset URL — web base + resource path. Must NOT
 *     include index.php (see Snep_Manutencao::publicAssetBaseUrl / R6).
 *  4. Absolute URL (scheme + host) — only when explicitly required;
 *     this helper does not invent hosts and does not trust X-Forwarded-*.
 *
 *  Zend_Controller_Front::getBaseUrl() may equal "/index.php" under a
 *  front-controller request. Callers must not treat that value as the
 *  public static asset base.
 */

/**
 * Canonical application URL helpers.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Url {

    /**
     * Deployment web base path from setup.conf path.web.
     *
     * Safe before Zend Front Controller exists (bootstrap / snep-env).
     *
     * @return string "" for root, "/subdir" for subdirectory (no trailing slash)
     */
    public static function webBasePath() {
        $web = '';
        try {
            if (class_exists('Zend_Registry', false) && Zend_Registry::isRegistered('config')) {
                $config = Zend_Registry::get('config');
                if (isset($config->system->path->web)) {
                    $web = (string) $config->system->path->web;
                }
            } elseif (class_exists('Snep_Config', false)) {
                $config = Snep_Config::getConfig();
                if (isset($config->system->path->web)) {
                    $web = (string) $config->system->path->web;
                }
            }
        } catch (Exception $ex) {
            $web = '';
        }
        return rtrim($web, '/');
    }

    /**
     * Front-controller script URL (web base + /index.php).
     *
     * @return string e.g. "/index.php" or "/senma/index.php"
     */
    public static function scriptUrl() {
        return self::webBasePath() . '/index.php';
    }

    /**
     * Public static asset base (same as web base; never includes index.php).
     *
     * @return string
     */
    public static function publicAssetBaseUrl() {
        return self::webBasePath();
    }

    /**
     * Build a static/public asset URL under the deployment web base.
     *
     * @param string $path Relative path (e.g. "/arquivos/...", "css/snep.css")
     * @return string
     */
    public static function assetUrl($path) {
        $path = self::sanitizeRelativePath($path);
        if ($path === '') {
            return self::publicAssetBaseUrl() === '' ? '/' : self::publicAssetBaseUrl();
        }
        return self::publicAssetBaseUrl() . $path;
    }

    /**
     * Build a controller/action URL through the front controller.
     *
     * Does not insert a host or scheme. Rejects absolute URLs and
     * scheme-relative paths to avoid open redirects / host injection.
     *
     * @param string      $controller Controller name (e.g. "route")
     * @param string|null $action     Action name or null for default
     * @param array       $params     Key/value path params (e.g. array('id' => 1))
     * @param string|null $module     Module name or null to omit
     * @return string e.g. "/index.php/default/route/duplicate/id/1"
     */
    public static function actionUrl($controller, $action = null, array $params = array(), $module = null) {
        $controller = self::sanitizeSegment($controller);
        if ($controller === '') {
            throw new InvalidArgumentException('Snep_Url::actionUrl requires a controller segment');
        }

        $parts = array(self::scriptUrl());
        if ($module !== null && $module !== '') {
            $parts[] = self::sanitizeSegment($module);
        }
        $parts[] = $controller;
        if ($action !== null && $action !== '') {
            $parts[] = self::sanitizeSegment($action);
        }
        foreach ($params as $key => $value) {
            $parts[] = self::sanitizeSegment((string) $key);
            $parts[] = self::sanitizeSegment((string) $value);
        }
        return implode('/', $parts);
    }

    /**
     * Normalize a path that must remain application-relative.
     *
     * Rejects scheme/host injection and path traversal tokens. Leading
     * slash is enforced for non-empty paths.
     *
     * @param string $path
     * @return string
     */
    public static function sanitizeRelativePath($path) {
        $path = (string) $path;
        if ($path === '') {
            return '';
        }
        if (preg_match('#^[a-z][a-z0-9+.-]*:#i', $path) || strpos($path, '//') === 0) {
            throw new InvalidArgumentException('Snep_Url rejects absolute or scheme-relative paths');
        }
        if (strpos($path, '..') !== false) {
            throw new InvalidArgumentException('Snep_Url rejects path traversal segments');
        }
        $path = '/' . ltrim(str_replace('\\', '/', $path), '/');
        // Collapse duplicate slashes without touching a possible empty base.
        $path = preg_replace('#/{2,}#', '/', $path);
        return $path;
    }

    /**
     * Allow only safe single URL path segments (no slashes, hosts, schemes).
     *
     * @param string $segment
     * @return string
     */
    public static function sanitizeSegment($segment) {
        $segment = trim((string) $segment);
        if ($segment === '') {
            return '';
        }
        if (preg_match('#^[a-z][a-z0-9+.-]*:#i', $segment) || strpos($segment, '//') !== false) {
            throw new InvalidArgumentException('Snep_Url rejects absolute URL segments');
        }
        if (strpos($segment, '/') !== false || strpos($segment, '\\') !== false || strpos($segment, '..') !== false) {
            throw new InvalidArgumentException('Snep_Url rejects unsafe path segments');
        }
        if (strpos($segment, '?') !== false || strpos($segment, '#') !== false) {
            throw new InvalidArgumentException('Snep_Url rejects query/fragment in path segments');
        }
        return rawurlencode($segment);
    }
}
