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
            (expect id :to-equal "new-uuid-123")))))))

;;; test-endless-org-roam-registry.el ends here
