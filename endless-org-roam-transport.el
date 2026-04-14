;;; endless-org-roam-transport.el --- EOR transport abstraction -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Hayden Stanko
;;
;; Author: Hayden Stanko <system.cuttle@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;; Commentary:
;;
;; Provides the transport abstraction for EOR federation.  The transport
;; layer dispatches operations to the appropriate backend based on the
;; instance configuration:
;;
;;   - Local backend: temporarily rebinds `org-roam-directory' and
;;     `org-roam-db-location', then uses standard org-roam DB queries.
;;
;;   - HTTP backend: (Phase 3) uses `url-retrieve' to call a JSON API
;;     on a remote instance.
;;
;; All transport operations respect `eor-transport-timeout' and track
;; instance availability via a circuit breaker state machine.
;;
;;; Code:

(require 'endless-org-roam)
(require 'org-roam-db)
(require 'org-roam-node)

;;; Circuit Breaker

(defvar eor-transport--circuit-state (make-hash-table :test #'equal)
  "Hash table mapping instance IDs to circuit breaker state.
Values are one of: closed (normal), open (failing), half-open (testing).")

(defvar eor-transport--circuit-failures (make-hash-table :test #'equal)
  "Hash table mapping instance IDs to consecutive failure counts.")

(defcustom eor-transport-circuit-threshold 3
  "Number of consecutive failures before opening the circuit breaker."
  :type 'integer
  :group 'endless-org-roam)

(defun eor-transport--circuit-state-for (instance-id)
  "Return the circuit breaker state for INSTANCE-ID.
Returns `closed', `open', or `half-open'."
  (or (gethash instance-id eor-transport--circuit-state) 'closed))

(defun eor-transport--record-success (instance-id)
  "Record a successful transport operation for INSTANCE-ID."
  (puthash instance-id 'closed eor-transport--circuit-state)
  (puthash instance-id 0 eor-transport--circuit-failures))

(defun eor-transport--record-failure (instance-id)
  "Record a failed transport operation for INSTANCE-ID.
Opens the circuit if failures exceed the threshold."
  (let ((failures (1+ (or (gethash instance-id
                                   eor-transport--circuit-failures)
                          0))))
    (puthash instance-id failures eor-transport--circuit-failures)
    (when (>= failures eor-transport-circuit-threshold)
      (puthash instance-id 'open eor-transport--circuit-state)
      (eor-message "Circuit breaker opened for instance %s"
                   instance-id))))

(defun eor-transport-reset-circuit (instance-id)
  "Reset the circuit breaker for INSTANCE-ID to closed state."
  (interactive
   (list (completing-read
          "Instance ID: "
          (hash-table-keys eor-transport--circuit-state))))
  (puthash instance-id 'closed eor-transport--circuit-state)
  (puthash instance-id 0 eor-transport--circuit-failures)
  (eor-message "Circuit breaker reset for instance %s" instance-id))

;;; Local Backend

(defun eor-transport--local-node-exists-p (instance node-id)
  "Check if NODE-ID exists in local INSTANCE.
INSTANCE is a registry alist entry.  Returns t or nil."
  (let* ((dir (alist-get :roam-directory instance))
         (db-loc (alist-get :db-location instance))
         (org-roam-directory dir)
         (org-roam-db-location db-loc))
    (when (and dir (file-directory-p dir))
      (condition-case nil
          (let ((result (org-roam-db-query
                         [:select id :from nodes
                          :where (= id $s1)]
                         node-id)))
            (and result (not (seq-empty-p result))))
        (error nil)))))

(defun eor-transport--local-open-node (instance node-id)
  "Open NODE-ID from local INSTANCE.
INSTANCE is a registry alist entry.  Returns the `org-roam-node'
or signals `eor-instance-unreachable'."
  (let* ((dir (alist-get :roam-directory instance))
         (db-loc (alist-get :db-location instance))
         (org-roam-directory dir)
         (org-roam-db-location db-loc))
    (unless (and dir (file-directory-p dir))
      (signal 'eor-instance-unreachable
              (list (format "Directory not accessible: %s" dir))))
    (condition-case err
        (let ((node (org-roam-node-from-id node-id)))
          (if node
              (progn
                (org-roam-node-visit node)
                node)
            (user-error "Node %s not found in instance %s"
                        node-id (alist-get :name instance))))
      (error
       (signal 'eor-instance-unreachable
               (list (error-message-string err)))))))

(defun eor-transport--local-node-list (instance &optional filter-fn)
  "Return all nodes from local INSTANCE, optionally filtered by FILTER-FN.
INSTANCE is a registry alist entry.  Returns a list of `org-roam-node'
structs."
  (let* ((dir (alist-get :roam-directory instance))
         (db-loc (alist-get :db-location instance))
         (org-roam-directory dir)
         (org-roam-db-location db-loc))
    (when (and dir (file-directory-p dir))
      (condition-case nil
          (let ((nodes (org-roam-node-list)))
            (if filter-fn
                (seq-filter filter-fn nodes)
              nodes))
        (error nil)))))

;;; Transport Dispatch

;;;###autoload
(defun eor-transport-node-exists-p (instance node-id)
  "Check if NODE-ID exists in INSTANCE.
Returns t or nil.  Respects circuit breaker and timeout."
  (let ((instance-id (alist-get :id instance))
        (endpoint (alist-get :endpoint instance)))
    (if (eq (eor-transport--circuit-state-for instance-id) 'open)
        (progn
          (eor-message "Skipping instance %s (circuit open)"
                       (alist-get :name instance))
          nil)
      (condition-case nil
          (with-timeout (eor-transport-timeout nil)
            (let ((result (if endpoint
                             ;; Phase 3: HTTP backend
                             (eor-message "HTTP transport not yet implemented")
                           (eor-transport--local-node-exists-p
                            instance node-id))))
              (when result
                (eor-transport--record-success instance-id))
              result))
        (error
         (eor-transport--record-failure instance-id)
         nil)))))

;;;###autoload
(defun eor-transport-open-node (instance node-id)
  "Open NODE-ID from INSTANCE.
Returns the `org-roam-node' or signals an error."
  (let ((instance-id (alist-get :id instance))
        (endpoint (alist-get :endpoint instance)))
    (when (eq (eor-transport--circuit-state-for instance-id) 'open)
      (signal 'eor-instance-unreachable
              (list (format "Instance %s circuit breaker is open"
                            (alist-get :name instance)))))
    (condition-case err
        (with-timeout (eor-transport-timeout
                       (signal 'eor-instance-unreachable
                               (list (format "Timeout reaching %s"
                                             (alist-get :name instance)))))
          (let ((result (if endpoint
                           (user-error "HTTP transport not yet implemented")
                         (eor-transport--local-open-node
                          instance node-id))))
            (eor-transport--record-success instance-id)
            result))
      (eor-instance-unreachable
       (eor-transport--record-failure instance-id)
       (signal (car err) (cdr err))))))

;;;###autoload
(defun eor-transport-node-list (instance &optional filter-fn)
  "Return all nodes from INSTANCE, optionally filtered by FILTER-FN."
  (let ((instance-id (alist-get :id instance))
        (endpoint (alist-get :endpoint instance)))
    (if (eq (eor-transport--circuit-state-for instance-id) 'open)
        (progn
          (eor-message "Skipping instance %s (circuit open)"
                       (alist-get :name instance))
          nil)
      (condition-case nil
          (with-timeout (eor-transport-timeout nil)
            (let ((result (if endpoint
                             nil ;; Phase 3: HTTP backend
                           (eor-transport--local-node-list
                            instance filter-fn))))
              (when result
                (eor-transport--record-success instance-id))
              result))
        (error
         (eor-transport--record-failure instance-id)
         nil)))))

(provide 'endless-org-roam-transport)
;;; endless-org-roam-transport.el ends here
