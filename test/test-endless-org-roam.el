;;; test-endless-org-roam.el --- Core module tests -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Buttercup specs for endless-org-roam.el (core module).
;;
;;; Code:

(require 'test-helper)

(describe "endless-org-roam core"

  (describe "custom errors"
    (it "eor-instance-unreachable is a user-error"
      (expect (condition-case nil
                  (signal 'eor-instance-unreachable '("test"))
                (user-error t)
                (error nil))
              :to-be t))

    (it "eor-registry-corrupt is an error"
      (expect (condition-case nil
                  (signal 'eor-registry-corrupt '("test"))
                (error t))
              :to-be t)))

  (describe "eor-message"
    (it "outputs message when eor-verbose is t"
      (spy-on 'message)
      (let ((eor-verbose t))
        (eor-message "test %s" "hello")
        (expect 'message :to-have-been-called)))

    (it "suppresses message when eor-verbose is nil"
      (spy-on 'message)
      (let ((eor-verbose nil))
        (eor-message "test %s" "hello")
        (expect 'message :not :to-have-been-called)))

    (it "prefixes messages with (eor)"
      (spy-on 'message)
      (let ((eor-verbose t))
        (eor-message "test msg")
        (expect 'message :to-have-been-called-with
                "(eor) test msg"))))

  (describe "eor-mode"
    (it "enables and sets lighter"
      (eor-mode 1)
      (expect eor-mode :to-be-truthy)
      (eor-mode -1))

    (it "disables cleanly"
      (eor-mode 1)
      (eor-mode -1)
      (expect eor-mode :to-be nil))

    (it "requires submodules on enable"
      (spy-on 'require :and-call-through)
      (eor-mode 1)
      (expect 'require :to-have-been-called-with
              'endless-org-roam-registry)
      (expect 'require :to-have-been-called-with
              'endless-org-roam-link)
      (expect 'require :to-have-been-called-with
              'endless-org-roam-transport)
      (eor-mode -1)))

  (describe "customization defaults"
    (it "eor-verbose defaults to t"
      (expect (default-value 'eor-verbose) :to-be t))

    (it "eor-search-all-instances defaults to nil"
      (expect (default-value 'eor-search-all-instances) :to-be nil))

    (it "eor-transport-timeout defaults to 5"
      (expect (default-value 'eor-transport-timeout) :to-equal 5))))

;;; test-endless-org-roam.el ends here
