;;; endless-org-roam-search.el --- Cross-instance search -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Hayden Stanko
;;
;; Author: Hayden Stanko <system.cuttle@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;; Commentary:
;;
;; Provides cross-instance search and completion for EOR federation.
;; Phase 2 implementation -- currently a skeleton with the public API
;; defined for forward compatibility.
;;
;;; Code:

(require 'endless-org-roam)
(require 'endless-org-roam-registry)
(require 'endless-org-roam-transport)

;;; Customization

(defcustom eor-include-remote-in-completion nil
  "When non-nil, include remote instance nodes in org-roam completion.
This augments `org-roam-node-read' with nodes from all registered
local instances."
  :type 'boolean
  :group 'endless-org-roam)

;;; Cross-Instance Search (Phase 2 skeleton)

;;;###autoload
(defun eor-node-find ()
  "Find and visit a node from any registered instance.
Searches across all registered instances and presents results in a
unified `completing-read' with instance-name annotations."
  (interactive)
  (let* ((instances (eor-registry-list))
         (all-nodes '()))
    (dolist (instance instances)
      (let ((nodes (eor-transport-node-list instance))
            (inst-name (alist-get :name instance)))
        (dolist (node nodes)
          (push (cons (format "[%s] %s" inst-name
                              (org-roam-node-title node))
                      (cons instance node))
                all-nodes))))
    (unless all-nodes
      (user-error "No nodes found in any registered instance"))
    (let* ((candidates (mapcar #'car all-nodes))
           (selected (completing-read "EOR find node: "
                                      candidates nil t))
           (entry (cdr (assoc selected all-nodes)))
           (instance (car entry))
           (node (cdr entry)))
      (eor-transport-open-node instance (org-roam-node-id node)))))

(provide 'endless-org-roam-search)
;;; endless-org-roam-search.el ends here
