;;; endless-org-roam-registry.el --- EOR instance registry -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Hayden Stanko
;;
;; Author: Hayden Stanko <system.cuttle@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;; Commentary:
;;
;; Manages the EOR instance registry -- a persistent alist of org-roam
;; instances that participate in federation.  Each instance is identified
;; by a UUID and has an associated org-roam directory, database location,
;; and optional HTTP endpoint.
;;
;; The registry is stored as a plain Lisp file at `eor-registry-file'
;; (default: ~/.emacs.d/eor-registry.el).  It is human-readable, diffable,
;; and version-controllable.
;;
;; On registration, a sentinel node `eor-instance.org' is created in the
;; instance's org-roam directory.  This node stores the instance UUID in
;; its property drawer for idempotent re-registration.
;;
;;; Code:

(require 'org-id)
(require 'endless-org-roam)

;;; Customization

(defcustom eor-registry-file
  (expand-file-name "eor-registry.el" user-emacs-directory)
  "Path to the EOR instance registry file."
  :type 'file
  :group 'endless-org-roam)

(defcustom eor-sentinel-filename "eor-instance.org"
  "Filename for the sentinel node created in registered instances."
  :type 'string
  :group 'endless-org-roam)

;;; Internal State

(defvar eor--registry nil
  "Cached registry data.  An alist of instance entries.")

(defvar eor--registry-loaded-p nil
  "Non-nil when the registry has been loaded from disk.")

;;; Registry Persistence

(defun eor-registry--load ()
  "Load the registry from `eor-registry-file'.
Returns the loaded alist, or nil if the file does not exist."
  (if (file-exists-p eor-registry-file)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents eor-registry-file)
            (let ((data (read (current-buffer))))
              (setq eor--registry data
                    eor--registry-loaded-p t)
              data))
        (error
         (signal 'eor-registry-corrupt
                 (list (format "Failed to read %s: %s"
                               eor-registry-file
                               (error-message-string err))))))
    (setq eor--registry nil
          eor--registry-loaded-p t)
    nil))

(defun eor-registry--save ()
  "Write the registry to `eor-registry-file' atomically."
  (let ((temp-file (make-temp-file "eor-registry-"))
        (dir (file-name-directory eor-registry-file)))
    (when dir (make-directory dir t))
    (with-temp-file temp-file
      (insert ";; -*- mode: emacs-lisp; no-byte-compile: t; -*-\n")
      (insert ";; EOR Instance Registry -- auto-generated\n")
      (insert ";; See `endless-org-roam-registry.el' for format.\n\n")
      (pp eor--registry (current-buffer)))
    (rename-file temp-file eor-registry-file t)
    (eor-message "Registry saved to %s" eor-registry-file)))

(defun eor-registry--ensure-loaded ()
  "Ensure the registry is loaded from disk."
  (unless eor--registry-loaded-p
    (eor-registry--load)))

;;; Registry CRUD

(defun eor-registry-list ()
  "Return the list of all registered instances."
  (eor-registry--ensure-loaded)
  eor--registry)

(defun eor-registry-get (instance-id)
  "Return the registry entry for INSTANCE-ID, or nil."
  (eor-registry--ensure-loaded)
  (seq-find (lambda (entry)
              (string= (alist-get :id entry) instance-id))
            eor--registry))

(defun eor-registry-get-by-name (name)
  "Return the registry entry for instance NAME, or nil."
  (eor-registry--ensure-loaded)
  (seq-find (lambda (entry)
              (string= (alist-get :name entry) name))
            eor--registry))

(defun eor-registry-get-by-directory (directory)
  "Return the registry entry for DIRECTORY, or nil."
  (eor-registry--ensure-loaded)
  (let ((expanded (expand-file-name (file-name-as-directory directory))))
    (seq-find (lambda (entry)
                (let ((dir (alist-get :roam-directory entry)))
                  (and dir
                       (string= (expand-file-name
                                 (file-name-as-directory dir))
                                expanded))))
              eor--registry)))

(defun eor-registry--add (entry)
  "Add ENTRY to the registry and save."
  (eor-registry--ensure-loaded)
  (let ((existing (eor-registry-get (alist-get :id entry))))
    (if existing
        (setq eor--registry
              (mapcar (lambda (e)
                        (if (string= (alist-get :id e)
                                     (alist-get :id entry))
                            entry
                          e))
                      eor--registry))
      (push entry eor--registry)))
  (eor-registry--save))

(defun eor-registry-remove (instance-id)
  "Remove instance with INSTANCE-ID from the registry."
  (eor-registry--ensure-loaded)
  (setq eor--registry
        (seq-remove (lambda (entry)
                      (string= (alist-get :id entry) instance-id))
                    eor--registry))
  (eor-registry--save)
  (eor-message "Removed instance %s from registry" instance-id))

;;; Sentinel Node

(defun eor--sentinel-path (directory)
  "Return the path to the sentinel node in DIRECTORY."
  (expand-file-name eor-sentinel-filename directory))

(defun eor--read-sentinel-id (directory)
  "Read the EOR instance ID from the sentinel node in DIRECTORY.
Returns the UUID string, or nil if no sentinel exists."
  (let ((sentinel (eor--sentinel-path directory)))
    (when (file-exists-p sentinel)
      (with-temp-buffer
        (insert-file-contents sentinel)
        (goto-char (point-min))
        (when (re-search-forward
               ":EOR_INSTANCE_ID:\\s-+\\(.+\\)" nil t)
          (string-trim (match-string 1)))))))

(defun eor--write-sentinel (directory instance-id name)
  "Write a sentinel node to DIRECTORY with INSTANCE-ID and NAME."
  (let ((sentinel (eor--sentinel-path directory)))
    (with-temp-file sentinel
      (insert (format ":PROPERTIES:\n"))
      (insert (format ":ID:       %s\n" instance-id))
      (insert (format ":EOR_INSTANCE_ID: %s\n" instance-id))
      (insert (format ":EOR_INSTANCE_NAME: %s\n" name))
      (insert (format ":END:\n"))
      (insert (format "#+title: EOR Instance: %s\n\n" name))
      (insert (format "This node identifies this org-roam directory as a\n"))
      (insert (format "federated instance in the Endless Org Roam network.\n"))
      (insert (format "\n"))
      (insert (format "- Instance ID: %s\n" instance-id))
      (insert (format "- Instance Name: %s\n" name))
      (insert (format "- Registered: %s\n"
                      (format-time-string "%Y-%m-%dT%H:%M:%S"))))
    (eor-message "Created sentinel node at %s" sentinel)))

;;; Registration

;;;###autoload
(defun eor-register-instance (&optional directory name)
  "Register an org-roam instance for federation.

DIRECTORY is the `org-roam-directory' to register (default: current
`org-roam-directory').  NAME is a human-readable name for the instance
\(default: directory basename).

If the directory already has a sentinel node with an EOR instance ID,
that ID is reused (idempotent registration)."
  (interactive
   (list (read-directory-name "Org-roam directory: " org-roam-directory)
         (read-string "Instance name: "
                      (file-name-nondirectory
                       (directory-file-name org-roam-directory)))))
  (let* ((dir (expand-file-name (file-name-as-directory
                                 (or directory org-roam-directory))))
         (name (or name
                   (file-name-nondirectory (directory-file-name dir))))
         (existing-id (eor--read-sentinel-id dir))
         (instance-id (or existing-id (org-id-uuid)))
         (db-loc (expand-file-name "org-roam.db" dir))
         (entry `((:id . ,instance-id)
                  (:name . ,name)
                  (:roam-directory . ,dir)
                  (:db-location . ,db-loc)
                  (:endpoint . nil)
                  (:registered-at
                   . ,(format-time-string "%Y-%m-%dT%H:%M:%S")))))
    (unless (file-directory-p dir)
      (user-error "Directory does not exist: %s" dir))
    ;; Create sentinel if it doesn't exist
    (unless existing-id
      (eor--write-sentinel dir instance-id name))
    ;; Add to registry
    (eor-registry--add entry)
    (run-hook-with-args 'eor-after-register-hook entry)
    (eor-message "Registered instance %s (%s)" name instance-id)
    entry))

(provide 'endless-org-roam-registry)
;;; endless-org-roam-registry.el ends here
