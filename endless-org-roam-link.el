;;; endless-org-roam-link.el --- EOR federated link type -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Hayden Stanko
;;
;; Author: Hayden Stanko <system.cuttle@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;; Commentary:
;;
;; Defines the `eor:' link type for cross-instance org-roam links.
;;
;; Link format:
;;   [[eor:<instance-uuid>/<node-uuid>][description]]  -- targeted
;;   [[eor:<node-uuid>][description]]                   -- local-first
;;
;; Resolution algorithm:
;;   1. Parse path into (instance-id . node-id)
;;   2. Without instance-id: try local, then optionally search remotes
;;   3. With instance-id: dispatch directly to that instance
;;   4. Soft error if unreachable -- never block the editor
;;
;;; Code:

(require 'ol)
(require 'org-roam-node)
(require 'endless-org-roam)
(require 'endless-org-roam-registry)
(require 'endless-org-roam-transport)

;;; Link Parsing

(defun eor-link--parse (path)
  "Parse an eor: link PATH into (INSTANCE-ID . NODE-ID).
If PATH contains a `/`, the part before is the instance UUID and
the part after is the node UUID.  Otherwise INSTANCE-ID is nil."
  (if (string-match "\\`\\([^/]+\\)/\\(.+\\)\\'" path)
      (cons (match-string 1 path) (match-string 2 path))
    (cons nil path)))

;;; Link Resolution

(defun eor-link--resolve-local (node-id)
  "Try to resolve NODE-ID in the current org-roam instance.
Returns the `org-roam-node' or nil."
  (condition-case nil
      (org-roam-node-from-id node-id)
    (error nil)))

(defun eor-link--resolve-federated (node-id)
  "Search all registered instances for NODE-ID.
Returns the first `org-roam-node' found, or nil.  Skips the current
local instance."
  (let ((current-dir (expand-file-name
                      (file-name-as-directory org-roam-directory))))
    (catch 'found
      (dolist (instance (eor-registry-list))
        (let ((dir (alist-get :roam-directory instance)))
          (unless (and dir
                       (string= (expand-file-name
                                 (file-name-as-directory dir))
                                current-dir))
            (when (eor-transport-node-exists-p instance node-id)
              (throw 'found
                     (eor-transport-open-node instance node-id))))))
      nil)))

(defun eor-link--resolve-targeted (instance-id node-id)
  "Resolve NODE-ID against the specific instance INSTANCE-ID.
Returns the `org-roam-node' or signals an error."
  (let ((instance (eor-registry-get instance-id)))
    (unless instance
      (user-error "EOR instance not registered: %s" instance-id))
    (eor-transport-open-node instance node-id)))

;;; Link Follow Handler

(defun eor-link-follow (path _prefix)
  "Follow an `eor:' link with PATH.
Implements local-first resolution with optional federated search."
  (let* ((parsed (eor-link--parse path))
         (instance-id (car parsed))
         (node-id (cdr parsed)))
    (run-hook-with-args 'eor-before-resolve-hook parsed)
    (let ((node
           (if instance-id
               ;; Targeted resolution
               (eor-link--resolve-targeted instance-id node-id)
             ;; Local-first resolution
             (or (let ((local-node (eor-link--resolve-local node-id)))
                   (when local-node
                     (org-mark-ring-push)
                     (org-roam-node-visit local-node)
                     local-node))
                 (when eor-search-all-instances
                   (eor-link--resolve-federated node-id))
                 (user-error "Node %s not found" node-id)))))
      (when node
        (run-hook-with-args 'eor-after-resolve-hook node))
      node)))

;;; Link Export

(defun eor-link-export (path description backend _info)
  "Export an `eor:' link with PATH and DESCRIPTION for BACKEND."
  (let ((desc (or description path)))
    (pcase backend
      ('html (format "<span class=\"eor-link\">%s</span>" desc))
      ('latex (format "\\textit{%s}" desc))
      (_ desc))))

;;; Link Registration

(org-link-set-parameters "eor"
                         :follow #'eor-link-follow
                         :export #'eor-link-export)

;;; Interactive Commands

;;;###autoload
(defun eor-node-insert ()
  "Insert an `eor:' link to a node from any registered instance.
Prompts with completing-read across all registered instances."
  (interactive)
  (let* ((instances (eor-registry-list))
         (all-nodes '()))
    ;; Collect nodes from all local instances
    (dolist (instance instances)
      (let ((nodes (eor-transport-node-list instance))
            (inst-name (alist-get :name instance))
            (inst-id (alist-get :id instance)))
        (dolist (node nodes)
          (push (list (format "[%s] %s"
                              inst-name
                              (org-roam-node-title node))
                      (org-roam-node-id node)
                      inst-id)
                all-nodes))))
    (unless all-nodes
      (user-error "No nodes found in any registered instance"))
    (let* ((candidates (mapcar #'car all-nodes))
           (selected (completing-read "EOR node: " candidates nil t))
           (entry (seq-find (lambda (e) (string= (car e) selected))
                            all-nodes))
           (node-id (nth 1 entry))
           (instance-id (nth 2 entry))
           (description (read-string "Description (empty for default): ")))
      (insert (org-link-make-string
               (format "eor:%s/%s" instance-id node-id)
               (if (string-empty-p description) nil description))))))

(provide 'endless-org-roam-link)
;;; endless-org-roam-link.el ends here
