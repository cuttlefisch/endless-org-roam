;;; test-endless-org-roam-registry.el --- Registry tests -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Buttercup specs for endless-org-roam-registry.el.
;;
;;; Code:

(require 'test-helper)

(describe "endless-org-roam-registry"

  (describe "eor-registry--load / eor-registry--save"
    (it "round-trips registry data through file"
      (with-eor-test-registry
        (let ((entry `((:id . "abc-123")
                       (:name . "test")
                       (:roam-directory . "/tmp/test")
                       (:db-location . "/tmp/test.db")
                       (:endpoint . nil)
                       (:registered-at . "2026-04-15T00:00:00"))))
          (setq eor--registry (list entry))
          (eor-registry--save)
          ;; Reset and reload
          (setq eor--registry nil
                eor--registry-loaded-p nil)
          (eor-registry--load)
          (expect (length eor--registry) :to-equal 1)
          (expect (alist-get :id (car eor--registry))
                  :to-equal "abc-123"))))

    (it "returns nil for nonexistent registry file"
      (with-eor-test-registry
        (expect (eor-registry--load) :to-be nil))))

  (describe "eor-registry-get"
    (it "finds instance by ID"
      (with-eor-test-registry
        (setq eor--registry (list eor-test-instance-entry)
              eor--registry-loaded-p t)
        (let ((result (eor-registry-get "test-instance-001")))
          (expect result :not :to-be nil)
          (expect (alist-get :name result)
                  :to-equal "test-kb"))))

    (it "returns nil for unknown ID"
      (with-eor-test-registry
        (setq eor--registry (list eor-test-instance-entry)
              eor--registry-loaded-p t)
        (expect (eor-registry-get "nonexistent") :to-be nil))))

  (describe "eor-registry-get-by-name"
    (it "finds instance by name"
      (with-eor-test-registry
        (setq eor--registry (list eor-test-instance-entry)
              eor--registry-loaded-p t)
        (let ((result (eor-registry-get-by-name "test-kb")))
          (expect result :not :to-be nil)
          (expect (alist-get :id result)
                  :to-equal "test-instance-001")))))

  (describe "eor-registry-get-by-directory"
    (it "finds instance by directory path"
      (with-eor-test-registry
        (setq eor--registry (list eor-test-instance-entry)
              eor--registry-loaded-p t)
        (let* ((dir (alist-get :roam-directory eor-test-instance-entry))
               (result (eor-registry-get-by-directory dir)))
          (expect result :not :to-be nil)
          (expect (alist-get :id result)
                  :to-equal "test-instance-001")))))

  (describe "eor-registry--add"
    (it "adds a new entry"
      (with-eor-test-registry
        (eor-registry--add eor-test-instance-entry)
        (expect (length eor--registry) :to-equal 1)))

    (it "updates an existing entry with the same ID"
      (with-eor-test-registry
        (eor-registry--add eor-test-instance-entry)
        (let ((updated (copy-alist eor-test-instance-entry)))
          (setf (alist-get :name updated) "renamed-kb")
          (eor-registry--add updated)
          (expect (length eor--registry) :to-equal 1)
          (expect (alist-get :name (car eor--registry))
                  :to-equal "renamed-kb")))))

  (describe "eor-registry-remove"
    (it "removes instance by ID"
      (with-eor-test-registry
        (eor-registry--add eor-test-instance-entry)
        (eor-registry-remove "test-instance-001")
        (expect (length eor--registry) :to-equal 0))))

  (describe "sentinel node"
    (describe "eor--read-sentinel-id"
      (it "reads instance ID from sentinel file"
        (with-eor-test-instance "sentinel"
          (let ((sentinel (expand-file-name "eor-instance.org"
                                            eor-test-dir)))
            (with-temp-file sentinel
              (insert eor-test-sentinel-content))
            (expect (eor--read-sentinel-id eor-test-dir)
                    :to-equal "test-instance-001"))))

      (it "returns nil when no sentinel exists"
        (with-eor-test-instance "no-sentinel"
          (expect (eor--read-sentinel-id eor-test-dir)
                  :to-be nil))))

    (describe "eor--write-sentinel"
      (it "creates a valid sentinel file"
        (with-eor-test-instance "write-sentinel"
          (eor--write-sentinel eor-test-dir "new-uuid-123" "my-kb")
          (let ((id (eor--read-sentinel-id eor-test-dir)))
            (expect id :to-equal "new-uuid-123"))))))

  (describe "registry corruption"
    (it "signals eor-registry-corrupt for malformed file"
      (with-eor-test-registry
        (with-temp-file eor-registry-file
          ;; Unbalanced parens cause read to fail
          (insert "(((:id . \"abc\") (:name . \"test\")"))
        (setq eor--registry-loaded-p nil)
        (expect (eor-registry--load) :to-throw 'eor-registry-corrupt)))

    (it "signals eor-registry-corrupt for truncated file"
      (with-eor-test-registry
        (with-temp-file eor-registry-file
          ;; Starts a list but never closes it
          (insert "("))
        (setq eor--registry-loaded-p nil)
        (expect (eor-registry--load) :to-throw 'eor-registry-corrupt)))

    (it "handles empty registry file gracefully"
      (with-eor-test-registry
        (with-temp-file eor-registry-file
          (insert "nil"))
        (setq eor--registry-loaded-p nil)
        (eor-registry--load)
        (expect eor--registry :to-be nil)
        (expect eor--registry-loaded-p :to-be t))))

  (describe "eor-registry--ensure-loaded"
    (it "loads registry on first call"
      (with-eor-test-registry
        (spy-on 'eor-registry--load :and-call-through)
        (eor-registry--ensure-loaded)
        (expect 'eor-registry--load :to-have-been-called)))

    (it "does not reload if already loaded"
      (with-eor-test-registry
        (setq eor--registry-loaded-p t)
        (spy-on 'eor-registry--load)
        (eor-registry--ensure-loaded)
        (expect 'eor-registry--load :not :to-have-been-called)))

    (it "reloads after resetting loaded-p"
      (with-eor-test-registry
        (setq eor--registry-loaded-p t)
        (eor-registry--ensure-loaded)
        ;; Reset and verify it reloads
        (setq eor--registry-loaded-p nil)
        (spy-on 'eor-registry--load :and-call-through)
        (eor-registry--ensure-loaded)
        (expect 'eor-registry--load :to-have-been-called))))

  (describe "path normalization"
    (it "matches directories with and without trailing slash"
      (with-eor-test-registry
        (with-eor-test-instance "path-norm"
          (let ((entry `((:id . "path-test")
                         (:name . "path-kb")
                         (:roam-directory
                          . ,(file-name-as-directory eor-test-dir))
                         (:db-location . "/tmp/test.db")
                         (:endpoint . nil)
                         (:registered-at . "2026-04-15T00:00:00"))))
            (setq eor--registry (list entry)
                  eor--registry-loaded-p t)
            ;; Query without trailing slash
            (expect (eor-registry-get-by-directory
                     (directory-file-name eor-test-dir))
                    :not :to-be nil)))))

    (it "expands ~ in directory paths"
      (with-eor-test-registry
        (let* ((home (expand-file-name "~"))
               (dir (concat home "/test-kb/"))
               (entry `((:id . "tilde-test")
                        (:name . "tilde-kb")
                        (:roam-directory . ,dir)
                        (:db-location . "/tmp/test.db")
                        (:endpoint . nil)
                        (:registered-at . "2026-04-15T00:00:00"))))
          (setq eor--registry (list entry)
                eor--registry-loaded-p t)
          (expect (eor-registry-get-by-directory "~/test-kb/")
                  :not :to-be nil)))))

  (describe "eor-register-instance integration"
    (it "creates sentinel file in new directory"
      (with-eor-test-registry
        (with-eor-test-instance "reg-sentinel"
          (eor-register-instance eor-test-dir "test-reg")
          (expect (file-exists-p
                   (expand-file-name "eor-instance.org" eor-test-dir))
                  :to-be t))))

    (it "reuses existing sentinel UUID on re-registration"
      (with-eor-test-registry
        (with-eor-test-instance "reg-reuse"
          (eor--write-sentinel eor-test-dir "existing-uuid" "old-name")
          (let ((entry (eor-register-instance eor-test-dir "new-name")))
            (expect (alist-get :id entry)
                    :to-equal "existing-uuid")))))

    (it "generates new UUID when no sentinel exists"
      (with-eor-test-registry
        (with-eor-test-instance "reg-new-uuid"
          (let ((entry (eor-register-instance eor-test-dir "fresh")))
            (expect (alist-get :id entry) :not :to-be nil)
            (expect (stringp (alist-get :id entry)) :to-be t)))))

    (it "signals user-error for nonexistent directory"
      (with-eor-test-registry
        (expect (eor-register-instance "/nonexistent/dir/xyz" "bad")
                :to-throw 'user-error)))

    (it "runs eor-after-register-hook with entry"
      (with-eor-test-registry
        (with-eor-test-instance "reg-hook"
          (let ((hook-called nil))
            (add-hook 'eor-after-register-hook
                      (lambda (entry) (setq hook-called entry)))
            (unwind-protect
                (progn
                  (eor-register-instance eor-test-dir "hook-test")
                  (expect hook-called :not :to-be nil)
                  (expect (alist-get :name hook-called)
                          :to-equal "hook-test"))
              (remove-hook 'eor-after-register-hook
                           (car eor-after-register-hook)))))))

    (it "persists entry to registry file"
      (with-eor-test-registry
        (with-eor-test-instance "reg-persist"
          (eor-register-instance eor-test-dir "persist-test")
          ;; Reset cache and reload
          (setq eor--registry nil
                eor--registry-loaded-p nil)
          (eor-registry--load)
          (expect (length eor--registry) :to-equal 1)
          (expect (alist-get :name (car eor--registry))
                  :to-equal "persist-test")))))

  (describe "duplicate handling"
    (it "prevents duplicate entries for same directory"
      (with-eor-test-registry
        (with-eor-test-instance "dup-dir"
          ;; Register same dir twice
          (eor-register-instance eor-test-dir "first")
          (eor-register-instance eor-test-dir "second")
          ;; Should have exactly 1 entry (re-registration reuses sentinel UUID)
          (expect (length eor--registry) :to-equal 1))))

    (it "updates name when re-registering existing instance"
      (with-eor-test-registry
        (with-eor-test-instance "dup-name"
          (eor-register-instance eor-test-dir "original")
          (eor-register-instance eor-test-dir "renamed")
          (let ((entry (car eor--registry)))
            (expect (alist-get :name entry)
                    :to-equal "renamed"))))))

  (describe "eor-registry-list"
    (it "returns empty list for fresh registry"
      (with-eor-test-registry
        (expect (eor-registry-list) :to-be nil)))

    (it "returns all registered instances"
      (with-eor-test-registry
        (setq eor--registry-loaded-p t)
        (eor-registry--add eor-test-instance-entry)
        (expect (length (eor-registry-list)) :to-equal 1)))))

;;; test-endless-org-roam-registry.el ends here
