;;; test-endless-org-roam-link.el --- Link type tests -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Buttercup specs for endless-org-roam-link.el.
;;
;;; Code:

(require 'test-helper)

(describe "endless-org-roam-link"

  (describe "eor-link--parse"
    (it "parses targeted link with instance-id/node-id"
      (let ((result (eor-link--parse "inst-abc/node-def")))
        (expect (car result) :to-equal "inst-abc")
        (expect (cdr result) :to-equal "node-def")))

    (it "parses local-first link with node-id only"
      (let ((result (eor-link--parse "node-def-only")))
        (expect (car result) :to-be nil)
        (expect (cdr result) :to-equal "node-def-only")))

    (it "handles UUIDs with hyphens correctly"
      (let ((result (eor-link--parse
                     "a1b2c3d4-e5f6-7890-abcd-ef1234567890/f0e1d2c3-b4a5-6789-0abc-def123456789")))
        (expect (car result)
                :to-equal "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        (expect (cdr result)
                :to-equal "f0e1d2c3-b4a5-6789-0abc-def123456789")))

    (it "parses standalone UUID as local-first"
      (let ((result (eor-link--parse
                     "a1b2c3d4-e5f6-7890-abcd-ef1234567890")))
        (expect (car result) :to-be nil)
        (expect (cdr result)
                :to-equal "a1b2c3d4-e5f6-7890-abcd-ef1234567890"))))

  (describe "eor-link--resolve-local"
    (it "returns nil when node not found locally"
      (spy-on 'org-roam-node-from-id :and-return-value nil)
      (expect (eor-link--resolve-local "nonexistent") :to-be nil))

    (it "returns node when found locally"
      (let ((mock-node (eor-test-node-create :id "found-id"
                                              :title "Found")))
        (spy-on 'org-roam-node-from-id :and-return-value mock-node)
        (expect (eor-link--resolve-local "found-id")
                :to-equal mock-node))))

  (describe "eor-link--resolve-targeted"
    (it "falls back to federated search for unregistered instance"
      (with-eor-test-registry
        (spy-on 'eor-link--resolve-federated :and-return-value nil)
        (spy-on 'lwarn)
        (expect (eor-link--resolve-targeted "unknown" "node-id")
                :to-throw 'user-error)
        ;; Should have warned and tried federated
        (expect 'lwarn :to-have-been-called)
        (expect 'eor-link--resolve-federated
                :to-have-been-called-with "node-id")))

    (it "returns node from federated fallback for unregistered instance"
      (with-eor-test-registry
        (let ((mock-node (eor-test-node-create
                           :id "fallback-node" :title "Fallback")))
          (spy-on 'eor-link--resolve-federated
                  :and-return-value mock-node)
          (spy-on 'lwarn)
          (let ((result (eor-link--resolve-targeted "unknown" "fallback-node")))
            (expect result :to-equal mock-node))))))

  (describe "link registration"
    (it "registers eor: link type"
      (expect (org-link-get-parameter "eor" :follow)
              :to-be #'eor-link-follow))

    (it "registers eor: export handler"
      (expect (org-link-get-parameter "eor" :export)
              :to-be #'eor-link-export)))

  (describe "eor-link-export"
    (it "exports HTML with span wrapper"
      (expect (eor-link-export "inst/node" "My Node" 'html nil)
              :to-equal "<span class=\"eor-link\">My Node</span>"))

    (it "exports LaTeX with italic"
      (expect (eor-link-export "inst/node" "My Node" 'latex nil)
              :to-equal "\\textit{My Node}"))

    (it "falls back to description for unknown backends"
      (expect (eor-link-export "inst/node" "My Node" 'ascii nil)
              :to-equal "My Node"))

    (it "uses path when no description given"
      (expect (eor-link-export "inst/node" nil 'ascii nil)
              :to-equal "inst/node")))

  (describe "eor-link--parse (edge cases)"
    (it "handles empty string"
      (let ((result (eor-link--parse "")))
        (expect (car result) :to-be nil)
        (expect (cdr result) :to-equal "")))

    (it "handles path with multiple slashes (takes first as separator)"
      (let ((result (eor-link--parse "a/b/c")))
        (expect (car result) :to-equal "a")
        (expect (cdr result) :to-equal "b/c")))

    (it "handles whitespace in path"
      (let ((result (eor-link--parse " inst / node ")))
        ;; Whitespace should be trimmed
        (expect (car result) :to-equal "inst")
        (expect (cdr result) :to-equal "node"))))

  (describe "eor-link--resolve-federated"
    (it "skips current org-roam-directory"
      (with-eor-test-registry
        (let* ((org-roam-directory (make-temp-file "eor-fed-skip" t))
               (inst `((:id . "skip-me")
                       (:name . "current")
                       (:roam-directory . ,org-roam-directory)
                       (:db-location . "/tmp/skip.db")
                       (:endpoint . nil))))
          (setq eor--registry (list inst)
                eor--registry-loaded-p t)
          (spy-on 'eor-transport-node-exists-p)
          (eor-link--resolve-federated "any-node")
          ;; Should NOT have been called since it matches current dir
          (expect 'eor-transport-node-exists-p
                  :not :to-have-been-called)
          (delete-directory org-roam-directory t))))

    (it "returns nil when no instances registered"
      (with-eor-test-registry
        (expect (eor-link--resolve-federated "any-node")
                :to-be nil)))

    (it "returns nil when node not found in any instance"
      (with-eor-test-registry
        (let ((inst `((:id . "empty-inst")
                      (:name . "empty")
                      (:roam-directory . "/tmp/other-dir/")
                      (:db-location . "/tmp/other.db")
                      (:endpoint . nil))))
          (setq eor--registry (list inst)
                eor--registry-loaded-p t)
          (spy-on 'eor-transport-node-exists-p :and-return-value nil)
          (expect (eor-link--resolve-federated "missing-node")
                  :to-be nil))))

    (it "returns first matching node across instances"
      (with-eor-test-registry
        (let* ((inst-a `((:id . "inst-a")
                         (:name . "A")
                         (:roam-directory . "/tmp/fed-a/")
                         (:db-location . "/tmp/fed-a.db")
                         (:endpoint . nil)))
               (inst-b `((:id . "inst-b")
                         (:name . "B")
                         (:roam-directory . "/tmp/fed-b/")
                         (:db-location . "/tmp/fed-b.db")
                         (:endpoint . nil)))
               (mock-node (eor-test-node-create
                            :id "found-node" :title "Found")))
          (setq eor--registry (list inst-a inst-b)
                eor--registry-loaded-p t)
          (spy-on 'eor-transport-node-exists-p
                  :and-call-fake
                  (lambda (inst _node-id)
                    (string= (alist-get :id inst) "inst-b")))
          (spy-on 'eor-transport-open-node
                  :and-return-value mock-node)
          (let ((result (eor-link--resolve-federated "found-node")))
            (expect result :to-equal mock-node)))))

    (it "skips instances with open circuit breaker"
      (with-eor-test-registry
        (let ((inst `((:id . "cb-skip")
                      (:name . "broken")
                      (:roam-directory . "/tmp/cb-skip/")
                      (:db-location . "/tmp/cb.db")
                      (:endpoint . nil)))
              (eor-transport-circuit-threshold 1))
          (setq eor--registry (list inst)
                eor--registry-loaded-p t)
          ;; Open the circuit
          (eor-transport--record-failure "cb-skip")
          ;; node-exists-p returns nil for open circuits
          (expect (eor-link--resolve-federated "any") :to-be nil)
          (eor-transport-reset-circuit "cb-skip"))))

    (it "warns when node found in multiple instances"
      (with-eor-test-registry
        (let* ((inst-a `((:id . "dup-a")
                         (:name . "KB-A")
                         (:roam-directory . "/tmp/dup-a/")
                         (:db-location . "/tmp/dup-a.db")
                         (:endpoint . nil)))
               (inst-b `((:id . "dup-b")
                         (:name . "KB-B")
                         (:roam-directory . "/tmp/dup-b/")
                         (:db-location . "/tmp/dup-b.db")
                         (:endpoint . nil)))
               (mock-node (eor-test-node-create
                            :id "dup-node" :title "Duplicate")))
          (setq eor--registry (list inst-a inst-b)
                eor--registry-loaded-p t)
          ;; Both instances have the node
          (spy-on 'eor-transport-node-exists-p :and-return-value t)
          (spy-on 'eor-transport-open-node :and-return-value mock-node)
          (spy-on 'lwarn)
          (eor-link--resolve-federated "dup-node")
          ;; Should warn about collision
          (expect 'lwarn :to-have-been-called)))))

  (describe "eor-link-follow (integration)"
    (it "resolves local-first when node exists locally"
      (let ((mock-node (eor-test-node-create
                         :id "local-id" :title "Local")))
        (spy-on 'org-roam-node-from-id :and-return-value mock-node)
        (spy-on 'org-roam-node-visit)
        (spy-on 'org-mark-ring-push)
        (eor-link-follow "local-id" nil)
        (expect 'org-roam-node-visit
                :to-have-been-called-with mock-node)))

    (it "falls back to federated when local fails and search-all is t"
      (let ((eor-search-all-instances t)
            (mock-node (eor-test-node-create
                         :id "fed-id" :title "Federated")))
        (spy-on 'org-roam-node-from-id :and-return-value nil)
        (spy-on 'eor-link--resolve-federated
                :and-return-value mock-node)
        (eor-link-follow "fed-id" nil)
        (expect 'eor-link--resolve-federated
                :to-have-been-called)))

    (it "signals user-error when node not found anywhere"
      (let ((eor-search-all-instances nil))
        (spy-on 'org-roam-node-from-id :and-return-value nil)
        (expect (eor-link-follow "missing-id" nil)
                :to-throw 'user-error)))

    (it "does not search federated when search-all is nil"
      (let ((eor-search-all-instances nil))
        (spy-on 'org-roam-node-from-id :and-return-value nil)
        (spy-on 'eor-link--resolve-federated)
        (ignore-errors (eor-link-follow "missing-id" nil))
        (expect 'eor-link--resolve-federated
                :not :to-have-been-called)))

    (it "dispatches targeted resolution when instance-id present"
      (let ((mock-node (eor-test-node-create
                         :id "targeted-node" :title "Targeted")))
        (spy-on 'eor-link--resolve-targeted
                :and-return-value mock-node)
        (eor-link-follow "inst-abc/targeted-node" nil)
        (expect 'eor-link--resolve-targeted
                :to-have-been-called-with "inst-abc" "targeted-node")))

    (it "runs eor-before-resolve-hook with parsed cons"
      (let ((hook-arg nil)
            (mock-node (eor-test-node-create
                         :id "hook-id" :title "Hook")))
        (spy-on 'org-roam-node-from-id :and-return-value mock-node)
        (spy-on 'org-roam-node-visit)
        (spy-on 'org-mark-ring-push)
        (add-hook 'eor-before-resolve-hook
                  (lambda (parsed) (setq hook-arg parsed)))
        (unwind-protect
            (progn
              (eor-link-follow "hook-id" nil)
              (expect hook-arg :not :to-be nil)
              (expect (car hook-arg) :to-be nil)
              (expect (cdr hook-arg) :to-equal "hook-id"))
          (remove-hook 'eor-before-resolve-hook
                       (car eor-before-resolve-hook)))))

    (it "runs eor-after-resolve-hook with resolved node"
      (let ((hook-arg nil)
            (mock-node (eor-test-node-create
                         :id "after-id" :title "After")))
        (spy-on 'org-roam-node-from-id :and-return-value mock-node)
        (spy-on 'org-roam-node-visit)
        (spy-on 'org-mark-ring-push)
        (add-hook 'eor-after-resolve-hook
                  (lambda (node) (setq hook-arg node)))
        (unwind-protect
            (progn
              (eor-link-follow "after-id" nil)
              (expect hook-arg :to-equal mock-node))
          (remove-hook 'eor-after-resolve-hook
                       (car eor-after-resolve-hook)))))

    (it "pushes mark ring before local visit"
      (let ((mock-node (eor-test-node-create
                         :id "mark-id" :title "Mark")))
        (spy-on 'org-roam-node-from-id :and-return-value mock-node)
        (spy-on 'org-roam-node-visit)
        (spy-on 'org-mark-ring-push)
        (eor-link-follow "mark-id" nil)
        (expect 'org-mark-ring-push :to-have-been-called))))

  (describe "eor-link--resolve-targeted (expanded)"
    (it "calls transport-open-node for registered instance"
      (with-eor-test-registry
        (let ((mock-node (eor-test-node-create
                           :id "tgt-node" :title "Target")))
          (setq eor--registry (list eor-test-instance-entry)
                eor--registry-loaded-p t)
          (spy-on 'eor-transport-open-node
                  :and-return-value mock-node)
          (let ((result (eor-link--resolve-targeted
                         "test-instance-001" "tgt-node")))
            (expect result :to-equal mock-node)
            (expect 'eor-transport-open-node
                    :to-have-been-called)))))

    (it "propagates eor-instance-unreachable from transport"
      (with-eor-test-registry
        (setq eor--registry (list eor-test-instance-entry)
              eor--registry-loaded-p t)
        (spy-on 'eor-transport-open-node
                :and-call-fake
                (lambda (&rest _)
                  (signal 'eor-instance-unreachable '("unreachable"))))
        (expect (eor-link--resolve-targeted
                 "test-instance-001" "any")
                :to-throw 'eor-instance-unreachable))))

  (describe "eor-node-insert"
    (it "signals user-error when no nodes available"
      (spy-on 'eor-registry-list :and-return-value nil)
      (expect (eor-node-insert) :to-throw 'user-error))

    (it "inserts targeted eor: link format"
      (let* ((inst `((:id . "ins-inst") (:name . "InsKB")
                     (:roam-directory . "/tmp/ins")
                     (:db-location . "/tmp/ins.db")
                     (:endpoint . nil)))
             (node (eor-test-node-create :id "ins-node"
                                          :title "Insert Me")))
        (spy-on 'eor-registry-list :and-return-value (list inst))
        (spy-on 'eor-transport-node-list :and-return-value (list node))
        (spy-on 'completing-read :and-return-value "[InsKB] Insert Me")
        (spy-on 'read-string :and-return-value "")
        (with-temp-buffer
          (eor-node-insert)
          (expect (buffer-string)
                  :to-match "eor:ins-inst/ins-node"))))

    (it "uses description when provided"
      (let* ((inst `((:id . "d-inst") (:name . "DKB")
                     (:roam-directory . "/tmp/d")
                     (:db-location . "/tmp/d.db")
                     (:endpoint . nil)))
             (node (eor-test-node-create :id "d-node"
                                          :title "Desc Node")))
        (spy-on 'eor-registry-list :and-return-value (list inst))
        (spy-on 'eor-transport-node-list :and-return-value (list node))
        (spy-on 'completing-read :and-return-value "[DKB] Desc Node")
        (spy-on 'read-string :and-return-value "My Description")
        (with-temp-buffer
          (eor-node-insert)
          (expect (buffer-string)
                  :to-match "My Description"))))

    (it "omits description when empty string given"
      (let* ((inst `((:id . "e-inst") (:name . "EKB")
                     (:roam-directory . "/tmp/e")
                     (:db-location . "/tmp/e.db")
                     (:endpoint . nil)))
             (node (eor-test-node-create :id "e-node"
                                          :title "Empty Desc")))
        (spy-on 'eor-registry-list :and-return-value (list inst))
        (spy-on 'eor-transport-node-list :and-return-value (list node))
        (spy-on 'completing-read :and-return-value "[EKB] Empty Desc")
        (spy-on 'read-string :and-return-value "")
        (with-temp-buffer
          (eor-node-insert)
          ;; Should be [[eor:...]] without description brackets
          (expect (buffer-string)
                  :to-match "\\[\\[eor:e-inst/e-node\\]\\]"))))))

;;; test-endless-org-roam-link.el ends here
