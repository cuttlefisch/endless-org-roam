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
                  :to-throw 'eor-instance-unreachable))))))

;;; test-endless-org-roam-transport.el ends here
