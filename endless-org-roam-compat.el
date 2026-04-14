;;; endless-org-roam-compat.el --- Compatibility layer -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Hayden Stanko
;;
;; Author: Hayden Stanko <system.cuttle@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;; Commentary:
;;
;; Centralizes all Emacs and org-roam version compatibility handling
;; for Endless Org Roam.  This module provides:
;;
;;   - Version detection utilities
;;   - Feature guards for optional functionality
;;   - Backported functions for older Emacs versions
;;   - Obsolete alias management
;;
;; All version-specific conditionals should live here rather than
;; scattered across other modules.
;;
;;; Code:

(require 'org-roam)

;;; Version Detection

(defconst eor-minimum-emacs-version "29.1"
  "Minimum supported Emacs version for EOR.")

(defconst eor-minimum-org-roam-version "2.2.0"
  "Minimum supported org-roam version for EOR.")

(declare-function package-desc-version "package" (pkg-desc))
(declare-function package-version-join "package" (vlist))

(defun eor-compat--org-roam-version ()
  "Return the installed org-roam version as a string."
  (if (and (boundp 'org-roam-version) org-roam-version)
      org-roam-version
    ;; Fallback: read from package descriptor
    (if (boundp 'package-alist)
        (let ((pkg (assq 'org-roam package-alist)))
          (if pkg
              (package-version-join
               (package-desc-version (cadr pkg)))
            "unknown"))
      "unknown")))

;;;###autoload
(defun eor-compat-check ()
  "Verify that the current environment meets EOR requirements.
Signals `user-error' if requirements are not met."
  (when (version< emacs-version eor-minimum-emacs-version)
    (user-error "EOR requires Emacs %s or later (you have %s)"
                eor-minimum-emacs-version emacs-version))
  t)

;;; Feature Guards

(defun eor-compat--has-org-roam-node-list-p ()
  "Return non-nil if `org-roam-node-list' is available."
  (fboundp 'org-roam-node-list))

(defun eor-compat--has-emacsql-p ()
  "Return non-nil if emacsql is available for direct queries."
  (fboundp 'emacsql))

(provide 'endless-org-roam-compat)
;;; endless-org-roam-compat.el ends here
