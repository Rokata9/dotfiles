;;; early-init.el --- Runs before the first frame and before packages  -*- lexical-binding: t; -*-

;; Faster startup: don't garbage-collect while the config loads.
;; init.el lowers the threshold again once startup is finished.
(setq gc-cons-threshold most-positive-fixnum)

;; Remove UI chrome *before* the first frame is drawn
;; (no flicker, no extra frame resize).
(setq default-frame-alist
      (append '((tool-bar-lines . 0)
                (vertical-scroll-bars . nil)
                (width . 150)
                (height . 48)
                ;; macOS: the title bar takes the theme's colours.
                ;; init.el switches `ns-appearance' with the theme.
                (ns-transparent-titlebar . t)
                (ns-appearance . light))
              default-frame-alist))

(setq frame-inhibit-implied-resize t
      inhibit-startup-screen t)

;; emacs-plus compiles packages to native code in the background.
;; Its warnings are only useful to package authors, so keep them quiet.
(setq native-comp-async-report-warnings-errors 'silent)

;;; early-init.el ends here
