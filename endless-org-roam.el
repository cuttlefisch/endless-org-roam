;;; endless-org-roam.el --- Federated org-roam instances -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Hayden Stanko
;;
;; Author: Hayden Stanko <system.cuttle@gmail.com>
;; Maintainer: Hayden Stanko <system.cuttle@gmail.com>
;; Created: April 15, 2026
;; Version: 0.2.0
;; Keywords: convenience org-roam federation
;; Homepage: https://github.com/cuttlefisch/endless-org-roam
;; Package-Requires: ((emacs "29.1") (org-roam "2.2.0"))
;;
;; This file is not part of GNU Emacs.
;;
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;; Commentary:
;;
;; Endless Org Roam (EOR) enables federation across multiple org-roam
;; instances.  Each instance registers with a local registry, receives
;; a UUID, and can link to and search across nodes in other registered
;; instances.
;;
;; EOR introduces a new `eor:' link type that resolves local-first,
;; then searches registered remote instances.  The package requires no
;; modifications to org-roam itself -- it extends org-roam purely via
;; `org-link-set-parameters', `advice-add', and temporary let-bindings
;; of `org-roam-directory'.
;;
;; Entry points:
;;   `eor-register-instance'  -- register an org-roam directory
;;   `eor-node-insert'        -- insert a cross-instance link
;;
;;; Code:

(require 'org-roam)

;;; Customization

(defgroup endless-org-roam nil
  "Federated org-roam instances."
  :group 'org-roam
  :prefix "eor-"
  :link '(url-link :tag "Homepage"
                   "https://github.com/cuttlefisch/endless-org-roam"))

(defcustom eor-verbose t
  "When non-nil, log informational messages to *Messages*."
  :type 'boolean
  :group 'endless-org-roam)

(defcustom eor-search-all-instances nil
  "When non-nil, search all registered instances during link resolution.
When nil, only resolve links with an explicit instance UUID against
remote instances.  Links without an instance UUID resolve locally only
unless this is non-nil."
  :type 'boolean
  :group 'endless-org-roam)

(defcustom eor-transport-timeout 5
  "Timeout in seconds for transport operations.
Applies to both local cross-instance queries and remote HTTP requests."
  :type 'integer
  :group 'endless-org-roam)

;;; Hooks

(defvar eor-after-register-hook nil
  "Hook run after an instance is registered.
Each function receives the instance alist as its sole argument.")

(defvar eor-before-resolve-hook nil
  "Hook run before resolving an `eor:' link.
Each function receives the parsed (INSTANCE-ID . NODE-ID) cons cell.")

(defvar eor-after-resolve-hook nil
  "Hook run after successfully resolving an `eor:' link.
Each function receives the resolved `org-roam-node'.")

;;; Logging

(defun eor-message (format-string &rest args)
  "Pass FORMAT-STRING and ARGS to `message' when `eor-verbose' is t."
  (when eor-verbose
    (apply #'message (concat "(eor) " format-string) args)))

;;; Custom Errors

(define-error 'eor-instance-unreachable
  "EOR instance is unreachable" 'user-error)

(define-error 'eor-registry-corrupt
  "EOR registry file is corrupt" 'error)

;;; Minor Mode

;;;###autoload
(define-minor-mode eor-mode
  "Toggle Endless Org Roam federation mode.
When enabled, the `eor:' link type is active and cross-instance
operations are available."
  :global t
  :lighter " EOR"
  :group 'endless-org-roam
  (if eor-mode
      (eor--enable)
    (eor--disable)))

(defun eor--enable ()
  "Set up EOR federation."
  (require 'endless-org-roam-registry)
  (require 'endless-org-roam-link)
  (require 'endless-org-roam-transport)
  (eor-message "Federation mode enabled"))

(defun eor--disable ()
  "Tear down EOR federation."
  (eor-message "Federation mode disabled"))

(provide 'endless-org-roam)
;;; endless-org-roam.el ends here
