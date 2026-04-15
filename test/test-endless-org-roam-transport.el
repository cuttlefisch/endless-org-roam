;;; test-endless-org-roam-transport.el --- Transport tests -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Buttercup specs for endless-org-roam-transport.el.
;;
;;; Code:

(require 'test-helper)

(describe "endless-org-roam-transport"

  (describe "circuit breaker"
    (it "starts in closed state"
      (expect (eor-transport--circuit-state-for "new-instance")
              :to-be 'closed))

    (it "remains closed after success"
      (eor-transport--record-success "test-circuit-1")
      (expect (eor-transport--circuit-state-for "test-circuit-1")
              :to-be 'closed))

    (it "opens after threshold failures"
      (let ((eor-transport-circuit-threshold 3))
        (dotimes (_ 3)
          (eor-transport--record-failure "test-circuit-2"))
        (expect (eor-transport--circuit-state-for "test-circuit-2")
                :to-be 'open)))

    (it "stays closed below threshold"
      (let ((eor-transport-circuit-threshold 3))
        (dotimes (_ 2)
          (eor-transport--record-failure "test-circuit-3"))
        (expect (eor-transport--circuit-state-for "test-circuit-3")
                :to-be 'closed)))

    (it "resets to closed via eor-transport-reset-circuit"
      (let ((eor-transport-circuit-threshold 1))
        (eor-transport--record-failure "test-circuit-4")
        (expect (eor-transport--circuit-state-for "test-circuit-4")
                :to-be 'open)
        (eor-transport-reset-circuit "test-circuit-4")
        (expect (eor-transport--circuit-state-for "test-circuit-4")
                :to-be 'closed)))

    (it "resets failure count on success"
      (let ((eor-transport-circuit-threshold 3))
        (dotimes (_ 2)
          (eor-transport--record-failure "test-circuit-5"))
        (eor-transport--record-success "test-circuit-5")
        ;; Should be back to 0 failures, so 2 more shouldn't open
        (dotimes (_ 2)
          (eor-transport--record-failure "test-circuit-5"))
        (expect (eor-transport--circuit-state-for "test-circuit-5")
                :to-be 'closed))))

  (describe "local backend"
    (describe "eor-transport--local-node-exists-p"
      (it "returns nil for nonexistent directory"
        (let ((instance `((:id . "no-dir")
                          (:roam-directory . "/nonexistent/path")
                          (:db-location . "/nonexistent/db"))))
          (expect (eor-transport--local-node-exists-p
                   instance "any-id")
                  :to-be nil)))

      (it "queries the database when directory exists"
        (with-eor-test-instance "local-exists"
          (let ((instance `((:id . "local-test")
                            (:roam-directory . ,eor-test-dir)
                            (:db-location
                             . ,(expand-file-name "test.db"
                                                  eor-test-dir)))))
            (spy-on 'org-roam-db-query
                    :and-return-value '(("found-node-id")))
            (expect (eor-transport--local-node-exists-p
                     instance "found-node-id")
                    :to-be t)))))

    (describe "eor-transport--local-open-node"
      (it "signals eor-instance-unreachable for bad directory"
        (let ((instance `((:id . "bad-dir")
                          (:name . "bad")
                          (:roam-directory . "/nonexistent")
                          (:db-location . "/nonexistent/db"))))
          (expect (eor-transport--local-open-node instance "any")
                  :to-throw 'eor-instance-unreachable)))))

  (describe "circuit breaker (advanced)"
    (it "isolates state between instances"
      (let ((eor-transport-circuit-threshold 1))
        (eor-transport--record-failure "isolated-a")
        (expect (eor-transport--circuit-state-for "isolated-a")
                :to-be 'open)
        (expect (eor-transport--circuit-state-for "isolated-b")
                :to-be 'closed)
        ;; Clean up
        (eor-transport-reset-circuit "isolated-a")))

    (it "clears all state via eor-transport-reset-circuit"
      (let ((eor-transport-circuit-threshold 1))
        (eor-transport--record-failure "reset-test")
        (expect (eor-transport--circuit-state-for "reset-test")
                :to-be 'open)
        (eor-transport-reset-circuit "reset-test")
        (expect (eor-transport--circuit-state-for "reset-test")
                :to-be 'closed)
        ;; Verify failure count also reset
        (eor-transport--record-failure "reset-test")
        (expect (eor-transport--circuit-state-for "reset-test")
                :to-be 'open)
        (eor-transport-reset-circuit "reset-test")))

    (it "transitions open to half-open after recovery timeout"
      (let ((eor-transport-circuit-threshold 1)
            (eor-transport-circuit-recovery-timeout 1))
        (eor-transport--record-failure "recovery-test")
        (expect (eor-transport--circuit-state-for "recovery-test")
                :to-be 'open)
        ;; Simulate time passing by backdating the opened-at timestamp
        (puthash "recovery-test"
                 (- (float-time) 2)  ;; 2 seconds ago
                 eor-transport--circuit-opened-at)
        (expect (eor-transport--circuit-state-for "recovery-test")
                :to-be 'half-open)
        (eor-transport-reset-circuit "recovery-test")))

    (it "stays open before recovery timeout"
      (let ((eor-transport-circuit-threshold 1)
            (eor-transport-circuit-recovery-timeout 300))
        (eor-transport--record-failure "stay-open-test")
        (expect (eor-transport--circuit-state-for "stay-open-test")
                :to-be 'open)
        ;; Should still be open (timeout is 300s)
        (expect (eor-transport--circuit-state-for "stay-open-test")
                :to-be 'open)
        (eor-transport-reset-circuit "stay-open-test")))

    (it "closes on success after half-open"
      (let ((eor-transport-circuit-threshold 1)
            (eor-transport-circuit-recovery-timeout 1))
        (eor-transport--record-failure "reclose-test")
        ;; Backdate to trigger half-open
        (puthash "reclose-test"
                 (- (float-time) 2)
                 eor-transport--circuit-opened-at)
        (expect (eor-transport--circuit-state-for "reclose-test")
                :to-be 'half-open)
        ;; Success should close it
        (eor-transport--record-success "reclose-test")
        (expect (eor-transport--circuit-state-for "reclose-test")
                :to-be 'closed))))

  (describe "eor-transport-node-exists-p (dispatch)"
    (it "returns nil when circuit is open"
      (let ((eor-transport-circuit-threshold 1)
            (instance `((:id . "open-inst")
                        (:name . "open")
                        (:roam-directory . "/tmp/open")
                        (:endpoint . nil))))
        (eor-transport--record-failure "open-inst")
        (expect (eor-transport-node-exists-p instance "any-node")
                :to-be nil)
        (eor-transport-reset-circuit "open-inst")))

    (it "calls local backend for local instance"
      (with-eor-test-instance "dispatch-exists"
        (let ((instance `((:id . "local-dispatch")
                          (:name . "local")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil))))
          (spy-on 'eor-transport--local-node-exists-p
                  :and-return-value t)
          (expect (eor-transport-node-exists-p instance "node-1")
                  :to-be t)
          (expect 'eor-transport--local-node-exists-p
                  :to-have-been-called))))

    (it "records success on positive result"
      (with-eor-test-instance "dispatch-success"
        (let ((instance `((:id . "success-inst")
                          (:name . "success")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil))))
          (spy-on 'eor-transport--local-node-exists-p
                  :and-return-value t)
          (spy-on 'eor-transport--record-success :and-call-through)
          (eor-transport-node-exists-p instance "node-1")
          (expect 'eor-transport--record-success
                  :to-have-been-called-with "success-inst"))))

    (it "records failure on error"
      (with-eor-test-instance "dispatch-fail"
        (let ((instance `((:id . "fail-inst")
                          (:name . "fail")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil))))
          (spy-on 'eor-transport--local-node-exists-p
                  :and-call-fake
                  (lambda (&rest _) (error "DB error")))
          (spy-on 'eor-transport--record-failure :and-call-through)
          (eor-transport-node-exists-p instance "node-1")
          (expect 'eor-transport--record-failure
                  :to-have-been-called-with "fail-inst")
          (eor-transport-reset-circuit "fail-inst"))))

    (it "logs skip message when circuit is open"
      (let ((eor-transport-circuit-threshold 1)
            (instance `((:id . "log-skip")
                        (:name . "skip-me")
                        (:roam-directory . "/tmp/skip")
                        (:endpoint . nil))))
        (eor-transport--record-failure "log-skip")
        (spy-on 'eor-message :and-call-through)
        (eor-transport-node-exists-p instance "any")
        (expect 'eor-message :to-have-been-called)
        (eor-transport-reset-circuit "log-skip"))))

  (describe "eor-transport-open-node (dispatch)"
    (it "signals eor-instance-unreachable when circuit is open"
      (let ((eor-transport-circuit-threshold 1)
            (instance `((:id . "open-node")
                        (:name . "open-node-inst")
                        (:roam-directory . "/tmp/open")
                        (:endpoint . nil))))
        (eor-transport--record-failure "open-node")
        (expect (eor-transport-open-node instance "any")
                :to-throw 'eor-instance-unreachable)
        (eor-transport-reset-circuit "open-node")))

    (it "calls local backend for local instance"
      (with-eor-test-instance "open-local"
        (let ((instance `((:id . "open-local-inst")
                          (:name . "local")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil)))
              (mock-node (eor-test-node-create :id "n1" :title "T")))
          (spy-on 'eor-transport--local-open-node
                  :and-return-value mock-node)
          (expect (eor-transport-open-node instance "n1")
                  :to-equal mock-node)
          (expect 'eor-transport--local-open-node
                  :to-have-been-called))))

    (it "records success after successful open"
      (with-eor-test-instance "open-success"
        (let ((instance `((:id . "open-success-inst")
                          (:name . "success")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil)))
              (mock-node (eor-test-node-create :id "n1" :title "T")))
          (spy-on 'eor-transport--local-open-node
                  :and-return-value mock-node)
          (spy-on 'eor-transport--record-success :and-call-through)
          (eor-transport-open-node instance "n1")
          (expect 'eor-transport--record-success
                  :to-have-been-called-with "open-success-inst"))))

    (it "records failure and re-signals on eor-instance-unreachable"
      (with-eor-test-instance "open-fail"
        (let ((instance `((:id . "open-fail-inst")
                          (:name . "fail")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil))))
          (spy-on 'eor-transport--local-open-node
                  :and-call-fake
                  (lambda (&rest _)
                    (signal 'eor-instance-unreachable '("test fail"))))
          (spy-on 'eor-transport--record-failure :and-call-through)
          (expect (eor-transport-open-node instance "n1")
                  :to-throw 'eor-instance-unreachable)
          (expect 'eor-transport--record-failure
                  :to-have-been-called-with "open-fail-inst")
          (eor-transport-reset-circuit "open-fail-inst")))))

  (describe "eor-transport-node-list (dispatch)"
    (it "returns nil when circuit is open"
      (let ((eor-transport-circuit-threshold 1)
            (instance `((:id . "list-open")
                        (:name . "list-open-inst")
                        (:roam-directory . "/tmp/list")
                        (:endpoint . nil))))
        (eor-transport--record-failure "list-open")
        (expect (eor-transport-node-list instance) :to-be nil)
        (eor-transport-reset-circuit "list-open")))

    (it "calls local backend for local instance"
      (with-eor-test-instance "list-local"
        (let ((instance `((:id . "list-local-inst")
                          (:name . "local")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil)))
              (mock-nodes (list (eor-test-node-create
                                 :id "n1" :title "A"))))
          (spy-on 'eor-transport--local-node-list
                  :and-return-value mock-nodes)
          (expect (eor-transport-node-list instance)
                  :to-equal mock-nodes))))

    (it "passes filter-fn through to local backend"
      (with-eor-test-instance "list-filter"
        (let ((instance `((:id . "list-filter-inst")
                          (:name . "filter")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil)))
              (filter-fn (lambda (n) (string= (eor-test-node-id n) "a"))))
          (spy-on 'eor-transport--local-node-list :and-return-value nil)
          (eor-transport-node-list instance filter-fn)
          (expect 'eor-transport--local-node-list
                  :to-have-been-called))))

    (it "records success on non-nil result"
      (with-eor-test-instance "list-success"
        (let ((instance `((:id . "list-suc-inst")
                          (:name . "success")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil)))
              (mock-nodes (list (eor-test-node-create
                                 :id "n1" :title "A"))))
          (spy-on 'eor-transport--local-node-list
                  :and-return-value mock-nodes)
          (spy-on 'eor-transport--record-success :and-call-through)
          (eor-transport-node-list instance)
          (expect 'eor-transport--record-success
                  :to-have-been-called-with "list-suc-inst"))))

    (it "records failure on error"
      (with-eor-test-instance "list-fail"
        (let ((instance `((:id . "list-fail-inst")
                          (:name . "fail")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil))))
          (spy-on 'eor-transport--local-node-list
                  :and-call-fake
                  (lambda (&rest _) (error "DB error")))
          (spy-on 'eor-transport--record-failure :and-call-through)
          (eor-transport-node-list instance)
          (expect 'eor-transport--record-failure
                  :to-have-been-called-with "list-fail-inst")
          (eor-transport-reset-circuit "list-fail-inst"))))

    (it "returns nil on error (not propagated)"
      (with-eor-test-instance "list-nil-err"
        (let ((instance `((:id . "list-nil-inst")
                          (:name . "nil-err")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil))))
          (spy-on 'eor-transport--local-node-list
                  :and-call-fake
                  (lambda (&rest _) (error "DB error")))
          (expect (eor-transport-node-list instance) :to-be nil)
          (eor-transport-reset-circuit "list-nil-inst")))))

  (describe "local backend (advanced)"
    (it "eor-transport--local-node-exists-p returns nil on empty query"
      (with-eor-test-instance "empty-query"
        (let ((instance `((:id . "empty-q")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir)))))
          (spy-on 'org-roam-db-query :and-return-value nil)
          (expect (eor-transport--local-node-exists-p instance "x")
                  :to-be nil))))

    (it "eor-transport--local-open-node visits node on success"
      (with-eor-test-instance "visit-node"
        (let ((instance `((:id . "visit-inst")
                          (:name . "visit")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))))
              (mock-node (eor-test-node-create :id "v1" :title "Visit")))
          (spy-on 'org-roam-node-from-id :and-return-value mock-node)
          (spy-on 'org-roam-node-visit)
          (eor-transport--local-open-node instance "v1")
          (expect 'org-roam-node-visit
                  :to-have-been-called-with mock-node))))

    (it "eor-transport--local-open-node signals user-error for missing node"
      (with-eor-test-instance "missing-node"
        (let ((instance `((:id . "miss-inst")
                          (:name . "missing")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir)))))
          (spy-on 'org-roam-node-from-id :and-return-value nil)
          ;; user-error from inside, but wrapped in condition-case
          ;; which re-signals as eor-instance-unreachable
          (expect (eor-transport--local-open-node instance "missing-id")
                  :to-throw))))

    (it "eor-transport--local-node-list returns nil for empty DB"
      (with-eor-test-instance "empty-db"
        (let ((instance `((:id . "empty-db")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir)))))
          (spy-on 'org-roam-node-list :and-return-value nil)
          (expect (eor-transport--local-node-list instance) :to-be nil))))

    (it "eor-transport--local-node-list applies filter-fn"
      (with-eor-test-instance "filter-apply"
        (let* ((instance `((:id . "filter-inst")
                           (:roam-directory . ,eor-test-dir)
                           (:db-location
                            . ,(expand-file-name "test.db" eor-test-dir))))
               (n1 (eor-test-node-create :id "keep" :title "Keep"))
               (n2 (eor-test-node-create :id "drop" :title "Drop")))
          (spy-on 'org-roam-node-list :and-return-value (list n1 n2))
          (let ((result (eor-transport--local-node-list
                         instance
                         (lambda (n)
                           (string= (eor-test-node-id n) "keep")))))
            (expect (length result) :to-equal 1)
            (expect (eor-test-node-id (car result)) :to-equal "keep"))))))

  (describe "HTTP backend detection"
    (it "routes to HTTP when endpoint is set"
      (let ((instance `((:id . "http-inst")
                        (:name . "remote")
                        (:roam-directory . "/tmp/remote")
                        (:db-location . "/tmp/remote.db")
                        (:endpoint . "http://example.com/eor"))))
        (spy-on 'eor-message :and-call-through)
        ;; node-exists-p for HTTP logs "not yet implemented"
        (eor-transport-node-exists-p instance "any-node")
        ;; Should not have called local backend
        (expect 'eor-message :to-have-been-called)))

    (it "routes to local when endpoint is nil"
      (with-eor-test-instance "local-route"
        (let ((instance `((:id . "local-route")
                          (:name . "local")
                          (:roam-directory . ,eor-test-dir)
                          (:db-location
                           . ,(expand-file-name "test.db" eor-test-dir))
                          (:endpoint . nil))))
          (spy-on 'eor-transport--local-node-exists-p
                  :and-return-value nil)
          (eor-transport-node-exists-p instance "any")
          (expect 'eor-transport--local-node-exists-p
                  :to-have-been-called))))))

;;; test-endless-org-roam-transport.el ends here
