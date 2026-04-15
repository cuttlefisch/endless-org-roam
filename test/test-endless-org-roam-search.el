;;; test-endless-org-roam-search.el --- Search tests -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Buttercup specs for endless-org-roam-search.el.
;;
;;; Code:

(require 'test-helper)

(describe "endless-org-roam-search"

  (describe "eor-node-find"
    (it "signals user-error when no instances registered"
      (spy-on 'eor-registry-list :and-return-value nil)
      (expect (eor-node-find) :to-throw 'user-error))

    (it "signals user-error when all instances have no nodes"
      (spy-on 'eor-registry-list
              :and-return-value (list eor-test-instance-entry))
      (spy-on 'eor-transport-node-list :and-return-value nil)
      (expect (eor-node-find) :to-throw 'user-error))

    (it "collects nodes from multiple instances"
      (let* ((inst-a `((:id . "inst-a") (:name . "KB-A")
                       (:roam-directory . "/tmp/a")
                       (:db-location . "/tmp/a.db")
                       (:endpoint . nil)))
             (inst-b `((:id . "inst-b") (:name . "KB-B")
                       (:roam-directory . "/tmp/b")
                       (:db-location . "/tmp/b.db")
                       (:endpoint . nil)))
             (node-a (eor-test-node-create :id "na" :title "Node A"))
             (node-b (eor-test-node-create :id "nb" :title "Node B")))
        (spy-on 'eor-registry-list
                :and-return-value (list inst-a inst-b))
        (spy-on 'eor-transport-node-list
                :and-call-fake
                (lambda (instance &optional _filter)
                  (pcase (alist-get :id instance)
                    ("inst-a" (list node-a))
                    ("inst-b" (list node-b)))))
        (spy-on 'completing-read :and-return-value "[KB-A] Node A")
        (spy-on 'eor-transport-open-node :and-return-value node-a)
        (eor-node-find)
        (expect 'eor-transport-open-node :to-have-been-called)))

    (it "formats candidates as [instance-name] title"
      (let* ((inst `((:id . "inst-1") (:name . "MyKB")
                     (:roam-directory . "/tmp/kb")
                     (:db-location . "/tmp/kb.db")
                     (:endpoint . nil)))
             (node (eor-test-node-create :id "n1" :title "My Note")))
        (spy-on 'eor-registry-list :and-return-value (list inst))
        (spy-on 'eor-transport-node-list :and-return-value (list node))
        (spy-on 'completing-read
                :and-call-fake
                (lambda (prompt candidates &rest _)
                  (expect (car candidates) :to-equal "[MyKB] My Note")
                  (car candidates)))
        (spy-on 'eor-transport-open-node :and-return-value node)
        (eor-node-find)))

    (it "calls eor-transport-open-node for selected node"
      (let* ((inst `((:id . "inst-1") (:name . "KB")
                     (:roam-directory . "/tmp/kb")
                     (:db-location . "/tmp/kb.db")
                     (:endpoint . nil)))
             (node (eor-test-node-create :id "target-id"
                                          :title "Target")))
        (spy-on 'eor-registry-list :and-return-value (list inst))
        (spy-on 'eor-transport-node-list :and-return-value (list node))
        (spy-on 'completing-read :and-return-value "[KB] Target")
        (spy-on 'eor-transport-open-node :and-return-value node)
        (eor-node-find)
        (expect 'eor-transport-open-node :to-have-been-called-with
                inst "target-id")))

    (it "skips instances with open circuit breaker"
      ;; transport-node-list already returns nil for open circuits
      (let* ((inst `((:id . "broken-inst") (:name . "Broken")
                     (:roam-directory . "/tmp/broken")
                     (:db-location . "/tmp/broken.db")
                     (:endpoint . nil)))
             (eor-transport-circuit-threshold 1))
        (eor-transport--record-failure "broken-inst")
        (spy-on 'eor-registry-list :and-return-value (list inst))
        ;; node-list dispatch returns nil for open circuit
        (expect (eor-node-find) :to-throw 'user-error)
        ;; Clean up circuit state
        (eor-transport-reset-circuit "broken-inst")))

    (it "annotates candidates with instance name"
      ;; Verify the format includes instance name in brackets
      (let* ((inst `((:id . "inst-x") (:name . "WorkNotes")
                     (:roam-directory . "/tmp/work")
                     (:db-location . "/tmp/work.db")
                     (:endpoint . nil)))
             (node (eor-test-node-create :id "nx" :title "Meeting")))
        (spy-on 'eor-registry-list :and-return-value (list inst))
        (spy-on 'eor-transport-node-list :and-return-value (list node))
        (spy-on 'completing-read
                :and-call-fake
                (lambda (_prompt candidates &rest _)
                  (expect (car candidates)
                          :to-match "\\[WorkNotes\\]")
                  (car candidates)))
        (spy-on 'eor-transport-open-node :and-return-value node)
        (eor-node-find)))))

;;; test-endless-org-roam-search.el ends here
