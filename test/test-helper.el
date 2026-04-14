;;; test-helper.el --- Test helpers for endless-org-roam -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Provides org-roam stubs, test fixtures, and helper macros for the
;; endless-org-roam test suite.  The stubs replace org-roam's heavy
;; dependencies (emacsql-sqlite, etc.) with no-op functions and dummy
;; variables so that tests run without a real org-roam database.
;;
;;; Code:

(require 'buttercup)
(require 'cl-lib)

;; Stub all heavy dependencies BEFORE any EOR module loads.
;; Order matters: provide features first, then define stubs, then
;; require EOR modules.

;; --- org-link (ol) stubs ---
;; Must come first because org-compat triggers org-link-set-parameters
;; via eval-after-load.
(defvar org-link-parameters nil)
(defun org-link-set-parameters (type &rest plist)
  "Stub: record link parameters for TYPE."
  (let ((entry (assoc type org-link-parameters)))
    (if entry
        (setcdr entry (org-plist-merge (cdr entry) plist))
      (push (cons type plist) org-link-parameters))))
(defun org-link-get-parameter (type key)
  "Stub: get KEY from TYPE link parameters."
  (plist-get (cdr (assoc type org-link-parameters)) key))
(defun org-link-make-string (link &optional description)
  "Stub: format an org link string."
  (if description
      (format "[[%s][%s]]" link description)
    (format "[[%s]]" link)))
(defun org-plist-merge (a b)
  "Merge plists A and B, with B taking precedence."
  (let ((result (copy-sequence a)))
    (while b
      (setq result (plist-put result (car b) (cadr b)))
      (setq b (cddr b)))
    result))
(provide 'ol)

;; --- org-id stubs ---
(defvar org-id-method 'uuid)
(defun org-id-uuid ()
  "Stub: generate a test UUID."
  (format "%08x-%04x-%04x-%04x-%012x"
          (random (expt 16 8))
          (random (expt 16 4))
          (random (expt 16 4))
          (random (expt 16 4))
          (random (expt 16 12))))
(defun org-id-new (&optional _prefix)
  "Stub: generate a new ID."
  (org-id-uuid))
(provide 'org-id)

;; --- org stubs ---
(defun org-mark-ring-push (&rest _) nil)
(provide 'org)
(provide 'org-element)
(provide 'org-compat)

;; --- org-roam stubs ---
(defvar org-roam-directory (make-temp-file "eor-test-roam" t))
(defvar org-roam-db-location
  (expand-file-name "org-roam.db" org-roam-directory))
(defvar org-roam-find-file-hook nil)
(defvar org-roam-post-node-insert-hook nil)
(defvar org-roam-verbose nil)
(defvar org-roam-link-auto-replace nil)

(defun org-roam-buffer-p (&rest _) nil)
(defun org-roam-node-from-id (&rest _) nil)
(defun org-roam-node-file (&rest _) nil)
(defun org-roam-node-from-title-or-alias (&rest _) nil)
(defun org-roam-node-visit (&rest _) nil)
(defun org-roam-node-list (&rest _) nil)
(defun org-roam-db-query (&rest _) nil)
(defun org-roam-db (&rest _) nil)

;; Minimal org-roam-node struct for tests
(cl-defstruct (eor-test-node (:constructor eor-test-node-create))
  "Minimal stand-in for org-roam-node used in tests."
  (id nil) (title nil) (file nil) (properties nil))

;; Make standard accessors work on our test struct
(defun org-roam-node-id (node)
  "Stub: return ID from NODE."
  (eor-test-node-id node))
(defun org-roam-node-title (node)
  "Stub: return title from NODE."
  (eor-test-node-title node))
(defun org-roam-node-properties (node)
  "Stub: return properties from NODE."
  (eor-test-node-properties node))

(provide 'org-roam)
(provide 'org-roam-db)
(provide 'org-roam-node)

;; --- Now load EOR modules ---
(require 'endless-org-roam)
(require 'endless-org-roam-registry)
(require 'endless-org-roam-transport)
(require 'endless-org-roam-link)

;;; Fixtures

(defvar eor-test-sentinel-content
  ":PROPERTIES:
:ID:       test-instance-001
:EOR_INSTANCE_ID: test-instance-001
:EOR_INSTANCE_NAME: test-kb
:END:
#+title: EOR Instance: test-kb
"
  "Sample sentinel node content for testing.")

(defvar eor-test-instance-entry
  `((:id . "test-instance-001")
    (:name . "test-kb")
    (:roam-directory . ,(make-temp-file "eor-test-instance" t))
    (:db-location . "/tmp/eor-test.db")
    (:endpoint . nil)
    (:registered-at . "2026-04-15T00:00:00"))
  "Sample registry entry for testing.")

;;; Macros

(defmacro with-eor-test-registry (&rest body)
  "Execute BODY with a fresh temporary registry.
Restores the registry state afterward."
  (declare (indent 0) (debug t))
  `(let* ((temp-dir (make-temp-file "eor-test-reg" t))
          (eor-registry-file (expand-file-name "registry.el" temp-dir))
          (eor--registry nil)
          (eor--registry-loaded-p nil))
     (unwind-protect
         (progn ,@body)
       (delete-directory temp-dir t))))

(defmacro with-eor-test-instance (name &rest body)
  "Create a temp org-roam directory named NAME, execute BODY.
Binds `eor-test-dir' to the directory path.  Cleans up afterward."
  (declare (indent 1) (debug t))
  `(let ((eor-test-dir (make-temp-file
                        (concat "eor-test-" ,name) t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory eor-test-dir t))))

(provide 'test-helper)
;;; test-helper.el ends here
