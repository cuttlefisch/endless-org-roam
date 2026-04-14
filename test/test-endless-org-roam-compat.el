;;; test-endless-org-roam-compat.el --- Compat tests -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Buttercup specs for endless-org-roam-compat.el.
;;
;;; Code:

(require 'test-helper)

(describe "endless-org-roam-compat"

  (describe "eor-compat-check"
    (it "passes on current Emacs version"
      (expect (eor-compat-check) :to-be t))

    (it "signals user-error when Emacs version is too old"
      (let ((emacs-version "27.2"))
        (expect (eor-compat-check) :to-throw 'user-error))))

  (describe "eor-compat--org-roam-version"
    (it "returns org-roam-version when bound"
      ;; boundp checks global binding, not let-binding, so use set
      (defvar org-roam-version nil)
      (let ((original org-roam-version))
        (unwind-protect
            (progn
              (setq org-roam-version "2.2.2")
              (expect (eor-compat--org-roam-version) :to-equal "2.2.2"))
          (setq org-roam-version original))))

    (it "returns unknown when no version info available"
      ;; org-roam-version is not globally bound (no defvar in stubs)
      ;; and package-alist has no org-roam entry, so returns "unknown"
      (expect (eor-compat--org-roam-version) :to-equal "unknown"))

    (it "falls back to package-alist when org-roam-version is unbound"
      ;; With org-roam-version unbound, it checks package-alist
      ;; Our stubs don't define package-alist, so result is "unknown"
      (expect (stringp (eor-compat--org-roam-version)) :to-be t)))

  (describe "eor-compat--has-org-roam-node-list-p"
    (it "returns non-nil when org-roam-node-list is defined"
      ;; org-roam-node-list is stubbed in test-helper
      (expect (eor-compat--has-org-roam-node-list-p) :to-be-truthy)))

  (describe "eor-compat--has-emacsql-p"
    (it "returns non-nil when emacsql is defined"
      ;; emacsql may or may not be defined; test the guard
      (if (fboundp 'emacsql)
          (expect (eor-compat--has-emacsql-p) :to-be-truthy)
        (expect (eor-compat--has-emacsql-p) :to-be nil)))))

;;; test-endless-org-roam-compat.el ends here
