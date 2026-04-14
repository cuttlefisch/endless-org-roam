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
    (it "signals error for unregistered instance"
      (with-eor-test-registry
        (expect (eor-link--resolve-targeted "unknown" "node-id")
                :to-throw 'user-error))))

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
              :to-equal "inst/node"))))

;;; test-endless-org-roam-link.el ends here
