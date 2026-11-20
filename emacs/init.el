;;; init.el --- VS Code-like Emacs for C / C++ / assembly on macOS  -*- lexical-binding: t; -*-
;;
;; Target: GNU Emacs 31.1 from emacs-plus (Homebrew) on macOS.
;;
;; Behaviour (sections 1-12) uses mostly built-in parts of Emacs 31:
;;   tree-sitter, Eglot (LSP), Flymake, project.el, which-key, editorconfig.
;; Looks (section 13) add the VS Code layout: light/dark themes, tabs,
;; explorer, breadcrumbs, status bar, floating command palette, icons.
;;
;; New Mac: run ~/.emacs.d/setup-mac.sh once first. It installs Homebrew,
;; Emacs+, the fonts and the tools this file uses.
;;
;; Key notation:  C- = Control   M- = Option   s- = Cmd   S- = Shift

(require 'subr-x)
(require 'seq)


;;;; 0. Startup housekeeping ---------------------------------------------------

(add-hook 'emacs-startup-hook
          (lambda ()
            ;; Back to a normal GC threshold (32 MB) after startup.
            (setq gc-cons-threshold (* 32 1024 1024))
            (message "Emacs ready in %s" (emacs-init-time))))

;; Keep M-x customize output out of this file.
(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file 'noerror 'nomessage)


;;;; 1. Package manager --------------------------------------------------------

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
;; Prefer the official GNU / NonGNU archives when a package is in several.
(setq package-archive-priorities '(("gnu" . 3) ("nongnu" . 2) ("melpa" . 1)))

;; use-package is built in. `:ensure t' = download the package on first launch.
(require 'use-package)


;;;; 2. macOS integration ------------------------------------------------------

(when (eq system-type 'darwin)
  (setq mac-command-modifier 'super        ; Cmd -> s-  (Cmd+C/V/X/Z/S/A/F work)
        mac-option-modifier 'meta          ; left Option -> M-
        mac-right-option-modifier 'none    ; right Option still types special chars
        dired-use-ls-dired nil))           ; macOS `ls' has no --dired flag

;; GUI apps on macOS don't inherit your shell's PATH, so Emacs can't see
;; Homebrew tools (cmake, rg, ...). Copy PATH from a *login* shell.
;; "-l" without "-i" reads ~/.zprofile but skips ~/.zshrc = faster startup.
;; => Keep your PATH lines in ~/.zprofile.
(use-package exec-path-from-shell
  :ensure t
  :if (memq window-system '(mac ns))
  :demand t
  :custom (exec-path-from-shell-arguments '("-l"))
  :config (exec-path-from-shell-initialize))

;; Apple ships clangd and lldb-dap inside Xcode / Command Line Tools, but
;; not on PATH. Find them (fallback: Homebrew LLVM) and add their folders
;; to `exec-path'. Runs once, lazily, when Eglot or Dape first loads.
(defvar my/dev-tools-ready nil)

(defun my/usable-file-p (path)
  "Non-nil if PATH is a non-empty path to an executable file."
  (and path (not (string-empty-p path))
       (file-executable-p path) (not (file-directory-p path))))

(defun my/setup-dev-tools ()
  "Put clangd and lldb-dap on `exec-path' and set SDKROOT (macOS only)."
  (when (and (eq system-type 'darwin) (not my/dev-tools-ready))
    (setq my/dev-tools-ready t)
    (dolist (tool '("clangd" "lldb-dap"))
      (unless (executable-find tool)
        (let* ((from-xcrun (string-trim
                            (shell-command-to-string
                             (concat "xcrun --find " tool " 2>/dev/null"))))
               (path (seq-find #'my/usable-file-p
                               (list from-xcrun
                                     (concat "/opt/homebrew/opt/llvm/bin/" tool)
                                     (concat "/usr/local/opt/llvm/bin/" tool)))))
          (if (not path)
              (message "my/setup-dev-tools: %s not found" tool)
            (let ((dir (file-name-directory path)))
              (add-to-list 'exec-path dir t)
              (setenv "PATH" (concat (getenv "PATH") path-separator dir)))))))
    ;; Lets clangd find the macOS SDK headers (<stdio.h>, <vector>, ...)
    ;; even in files that have no compile_commands.json yet.
    (unless (getenv "SDKROOT")
      (let ((sdk (string-trim
                  (shell-command-to-string "xcrun --show-sdk-path 2>/dev/null"))))
        (when (and (not (string-empty-p sdk)) (file-directory-p sdk))
          (setenv "SDKROOT" sdk))))))


;;;; 3. Editor basics (VS Code-like defaults) -----------------------------------

(use-package emacs
  :ensure nil
  :custom
  (ring-bell-function #'ignore)
  (use-short-answers t)                 ; y/n instead of yes/no
  (indent-tabs-mode nil)                ; spaces, not tabs
  (tab-width 4)
  (tab-always-indent 'complete)         ; TAB indents; if already indented, completes
  (require-final-newline t)
  (create-lockfiles nil)                ; no ".#file" lock files in your repo
  (backup-directory-alist               ; backups go here, not next to your files
   `(("." . ,(locate-user-emacs-file "backups"))))
  (scroll-conservatively 101)           ; scroll smoothly, no half-screen jumps
  (read-process-output-max (* 1024 1024)) ; bigger reads from clangd = snappier LSP
  (enable-recursive-minibuffers t)
  ;; M-x hides commands that don't apply to the current buffer.
  (read-extended-command-predicate #'command-completion-default-include-p)
  :config
  (delete-selection-mode 1)             ; typing replaces the selection
  (electric-pair-mode 1)                ; auto-close () [] {} ""
  (global-auto-revert-mode 1)           ; reload files changed on disk (git checkout)
  (savehist-mode 1)                     ; remember minibuffer history
  (save-place-mode 1)                   ; reopen files where you left off
  (recentf-mode 1)                      ; recent files (shown in C-x b)
  (column-number-mode 1)
  (which-key-mode 1)                    ; popup listing possible next keys
  (editorconfig-mode 1)                 ; honour .editorconfig files
  (global-so-long-mode 1)               ; stay fast on huge one-line files
  :hook
  (prog-mode . display-line-numbers-mode)
  (prog-mode . hl-line-mode))

;; Editor font. To switch, change the name below and restart Emacs.
;; Installed by setup-mac.sh: "Hack", "DejaVu Sans Mono", "Ubuntu Mono",
;; "JetBrains Mono". On every Mac: "Menlo". Ubuntu Mono is drawn smaller;
;; give it a size of about 15.
(defvar my/font "Hack")
(defvar my/font-size 15)                ; points

;; Used when `my/font' isn't installed: the first one that is.
(defvar my/font-fallbacks '("JetBrains Mono" "SF Mono" "Menlo"))

(when (display-graphic-p)
  (when-let* ((font (seq-find (lambda (f) (find-font (font-spec :family f)))
                              (cons my/font my/font-fallbacks))))
    (set-face-attribute 'default nil :family font :height (* 10 my/font-size))
    ;; Code blocks in hover popups, Markdown, etc. use the same font.
    (set-face-attribute 'fixed-pitch nil :family font)))

;; Esc cancels things, like everywhere else on macOS (Emacs' own key: C-g).
(keymap-global-set "<escape>" #'keyboard-escape-quit)


;;;; 4. VS Code muscle-memory keys ----------------------------------------------
;; More VS Code keys are bound in the sections below, next to their feature.

(keymap-global-set "s-P"     #'execute-extended-command) ; Cmd+Shift+P  command palette
(keymap-global-set "s-p"     #'project-find-file)        ; Cmd+P        quick open file
(keymap-global-set "s-/"     #'comment-line)             ; Cmd+/        toggle comment
(keymap-global-set "<f12>"   #'xref-find-definitions)    ; F12          go to definition
(keymap-global-set "s-b"     #'xref-find-definitions)    ; Cmd+B        go to definition (Android Studio / IntelliJ)
(keymap-global-set "S-<f12>" #'xref-find-references)     ; Shift+F12    find references
(keymap-global-set "s-["     #'xref-go-back)             ; Cmd+[        back to where you jumped from
(keymap-global-set "s-]"     #'xref-go-forward)          ; Cmd+]        forward again
;; Go back also: M-,   (Option+comma). Explorer: Cmd+1 (section 10).

(defun my/goto-definition-at-click (event)
  "Cmd+click: go to the definition of the name under the mouse."
  (interactive "e")
  (mouse-set-point event)
  (when (derived-mode-p 'prog-mode)
    (call-interactively #'xref-find-definitions)))
(keymap-global-set "s-<down-mouse-1>" #'ignore)          ; Cmd+click    go to definition
(keymap-global-set "s-<mouse-1>"      #'my/goto-definition-at-click)
;; Cmd+Shift+B build, Ctrl+Option+N run, F5 debug: section 12.


;;;; 5. Syntax highlighting: tree-sitter (built in) ----------------------------
;; Emacs 31 downloads and compiles each grammar the first time you open a
;; file of that language (needs git + cc from the Command Line Tools).
;; The C, C++ and CMake grammars are pinned by Emacs to tested versions.

(when (treesit-available-p)
  (setopt treesit-font-lock-level 4             ; richest highlighting (default 3)
          treesit-auto-install-grammar 'always  ; no prompt, just install
          treesit-enabled-modes t))             ; c-mode -> c-ts-mode, etc.

(use-package c-ts-mode
  :ensure nil
  :defer t
  :custom
  (c-ts-indent-offset 4)                ; VS Code default width
  (c-ts-mode-indent-style 'k&r))        ; default `gnu' style indents braces oddly
;; Real formatting comes from clangd + your project's .clang-format (C-c f).
;; Width of indents and tabs, from the project's .clang-format.
;;   Without one: 4-column indents with spaces (the settings above).
;;   With one: its IndentWidth, TabWidth and UseTab, so what you type and
;;   how tabs look match what clangd writes on save. The Linux kernel
;;   style = indent 8, tabs 8 wide, real tab characters.
;; The values a .clang-format inherits when it doesn't set them itself.
(defconst my/clang-format-base-indent
  '(("llvm" . 2) ("google" . 2) ("chromium" . 2) ("mozilla" . 2)
    ("gnu" . 2) ("webkit" . 4) ("microsoft" . 4))
  "IndentWidth of each clang-format BasedOnStyle.")

(defun my/clang-format-settings (file)
  "Return (INDENT-WIDTH TAB-WIDTH USE-TABS) from the .clang-format FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let (vals)
      ;; Top-level "Key: value" lines; the first of each key wins.
      (while (re-search-forward
              "^\\(BasedOnStyle\\|IndentWidth\\|TabWidth\\|UseTab\\):[ \t]*\\([^ \t\n#]+\\)" nil t)
        (unless (assoc (match-string 1) vals)
          (push (cons (match-string 1) (downcase (match-string 2))) vals)))
      (let ((get (lambda (k) (cdr (assoc k vals)))))
        (list (if (funcall get "IndentWidth")
                  (string-to-number (funcall get "IndentWidth"))
                (alist-get (or (funcall get "BasedOnStyle") "llvm")
                           my/clang-format-base-indent 2 nil #'equal))
              (if (funcall get "TabWidth") (string-to-number (funcall get "TabWidth")) 8)
              (not (member (funcall get "UseTab") '(nil "never" "false"))))))))

(defun my/indent-from-clang-format ()
  "In C / C++ files, take indent and tab widths from the nearest .clang-format."
  (when-let* (((derived-mode-p 'c-ts-mode 'c++-ts-mode 'c-mode 'c++-mode))
              buffer-file-name
              (dir (locate-dominating-file buffer-file-name ".clang-format")))
    (pcase-let ((`(,indent ,tabs ,use-tabs)
                 (my/clang-format-settings (expand-file-name ".clang-format" dir))))
      (when (> indent 0)
        ;; Emacs 31 name, Emacs 29-30 name, older c-mode.
        (dolist (var '(c-ts-indent-offset c-ts-mode-indent-offset c-basic-offset))
          (when (boundp var) (set (make-local-variable var) indent))))
      (when (> tabs 0) (setq-local tab-width tabs))
      (setq-local indent-tabs-mode use-tabs)
      ;; Indent guides measured the old width; redraw them.
      (when (bound-and-true-p indent-bars-mode) (indent-bars-reset)))))
;; After .dir-locals.el and .editorconfig, so the formatter's own file wins.
(add-hook 'hack-local-variables-hook #'my/indent-from-clang-format)


;;;; 6. Language server: Eglot + clangd (built in) ------------------------------
;; Gives completion, diagnostics, go-to-definition, references, rename,
;; quick fixes, inlay hints and formatting for C / C++.

;; Semantic highlighting (clangd coloring code by meaning, new in Emacs 31):
;; off, so code colors come from one place, the theme setup in section 13.
;; When on, clangd paints over it: every use of a variable gets colored,
;; a static local variable gets the keyword color, calls get colored.
;; Like VS Code's "editor.semanticHighlighting.enabled". t = on.
(defvar my/semantic-highlighting nil)

(use-package eglot
  :ensure nil
  :hook ((c-mode c-ts-mode c++-mode c++-ts-mode) . eglot-ensure)
  :bind (:map eglot-mode-map
              ("<f2>"  . eglot-rename)          ; F2     rename symbol
              ("s-."   . eglot-code-actions)    ; Cmd+.  quick fix
              ("C-c f" . eglot-format-buffer))  ; format (uses .clang-format)
  :custom
  (eglot-autoshutdown t)                ; stop clangd when its last buffer closes
  (eglot-extend-to-xref t)              ; keep LSP working in jumped-to headers
  ;; Don't let clangd reformat as you type. Emacs already indents and
  ;; pairs braces on each key; clangd editing the same Enter at the same
  ;; time put the cursor before "}" instead of on the indented line.
  ;; clangd still formats on save and with C-c f.
  (eglot-ignored-server-capabilities
   `(:documentOnTypeFormattingProvider
     ,@(unless my/semantic-highlighting '(:semanticTokensProvider))))
  ;; No JSON logging = less work per message. To debug Eglot itself,
  ;; delete this line and use M-x eglot-events-buffer.
  (eglot-events-buffer-config '(:size 0 :format full))
  :config
  (my/setup-dev-tools)
  (add-to-list 'eglot-server-programs
               '((c-mode c-ts-mode c++-mode c++-ts-mode)
                 . ("clangd" "--header-insertion-decorators=0"))))

;; Format on save, like VS Code's "editor.formatOnSave". clangd formats
;; with the .clang-format closest to the file. Only projects that have one
;; are formatted, so code without a style file is never reflowed.
(defvar my/format-on-save t "Non-nil: format C / C++ files with clangd on save.")
(put 'my/format-on-save 'safe-local-variable #'booleanp) ; can be set per project

(defun my/format-on-save ()
  "Format the buffer with clangd before saving, if a .clang-format applies."
  (when (and my/format-on-save
             buffer-file-name
             (fboundp 'eglot-managed-p) (eglot-managed-p)
             (locate-dominating-file buffer-file-name ".clang-format"))
    (condition-case err
        (eglot-format-buffer)
      (error (message "Format on save skipped: %s" (error-message-string err))))))
(add-hook 'before-save-hook #'my/format-on-save)

;; Diagnostics (errors / warnings from clangd) are shown by Flymake.
(use-package flymake
  :ensure nil
  :bind (:map flymake-mode-map
              ("M-n"  . flymake-goto-next-error)
              ("M-p"  . flymake-goto-prev-error)
              ("<f8>" . flymake-goto-next-error)               ; F8  next problem
              ("s-M"  . flymake-show-project-diagnostics))     ; Cmd+Shift+M  problems
  ;; :custom
  ;; Uncomment for "Error Lens" style messages at the end of each line:
  ;; (flymake-show-diagnostics-at-end-of-line 'short)
  )

;; Hover info appears in the echo area at the bottom. Keep it one line
;; so the window doesn't jump around.
(use-package eldoc
  :ensure nil
  :custom (eldoc-echo-area-use-multiline-p nil))


;;;; 7. Completion UI ----------------------------------------------------------

;; Minibuffer (M-x, C-x C-f, C-x b, ...): vertical list.
(use-package vertico
  :ensure t
  :init (vertico-mode))

;; Fuzzy matching: "vec push" matches "std::vector::push_back".
(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

;; Short descriptions next to each candidate.
(use-package marginalia
  :ensure t
  :init (marginalia-mode))

;; Better search / switch commands with live preview.
(use-package consult
  :ensure t
  :bind (("C-x b" . consult-buffer)      ; buffers + recent files
         ("M-y"   . consult-yank-pop)    ; clipboard history
         ("M-g g" . consult-goto-line)
         ("M-s l" . consult-line)        ; search lines in this file
         ("s-F"   . consult-ripgrep)     ; Cmd+Shift+F  search in project
         ("s-O"   . consult-imenu))      ; Cmd+Shift+O  go to symbol in file
  :custom
  (xref-show-xrefs-function #'consult-xref)
  (xref-show-definitions-function #'consult-xref))

;; In-buffer: VS Code-style popup while typing (fed by clangd via Eglot).
(use-package corfu
  :ensure t
  :custom
  (corfu-auto t)                        ; pop up automatically
  (corfu-auto-delay 0.15)
  (corfu-auto-prefix 2)                 ; after 2 typed characters
  (corfu-cycle t)
  (corfu-popupinfo-delay '(0.4 . 0.2))  ; docs popup next to the list
  :init
  (global-corfu-mode)
  (corfu-popupinfo-mode)
  (corfu-history-mode)                  ; recently picked items rank first
  :config
  (add-to-list 'savehist-additional-variables 'corfu-history))


;;;; 8. Projects, search, build ------------------------------------------------
;; project.el (built in) treats every git repo as a project:
;;   C-x p f  find file    C-x p g  grep    C-x p p  switch project
;;   C-x p c  compile      C-x p s  shell   C-x p b  project buffers

(use-package project
  :ensure nil
  :defer t
  ;; For a folder that isn't a git repo: create an empty ".project" file in it.
  :custom (project-vc-extra-root-markers '(".project")))

(use-package xref
  :ensure nil
  :defer t
  :custom (xref-search-program (if (executable-find "rg") 'ripgrep 'grep)))

(use-package compile
  :ensure nil
  :defer t
  :custom
  (compilation-scroll-output 'first-error) ; follow output, stop at first error
  (compilation-ask-about-save nil)         ; save edited files before building
  :config
  (require 'ansi-color)                    ; coloured compiler output
  (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter))
;; In the *compilation* buffer: RET on an error jumps to it, `g' rebuilds.


;;;; 9. Git --------------------------------------------------------------------

(use-package magit
  :ensure t
  :bind ("C-x g" . magit-status))

;; Changed / added / deleted lines marked in the gutter.
(use-package diff-hl
  :ensure t
  :hook ((prog-mode . diff-hl-mode)
         (magit-post-refresh . diff-hl-magit-post-refresh)))


;;;; 10. Explorer (sidebar) + terminal ---------------------------------------------

(defvar my/explorer-shown-once nil)

(defun my/explorer-show ()
  "Show the explorer with only the current project; keep focus in the editor."
  (require 'treemacs)
  (save-selected-window
    (treemacs-add-and-display-current-project-exclusively)))

(defun my/explorer-toggle ()
  "Cmd+B like VS Code: hide or show the explorer."
  (interactive)
  (require 'treemacs)
  (if (eq (treemacs-current-visibility) 'visible)
      (delete-window (treemacs-get-local-window))
    (if (project-current)
        (my/explorer-show)
      (message "Not inside a project. Open a folder first: Cmd+O"))))

(defun my/explorer-auto-show ()
  "Open the explorer the first time a project file or folder is opened."
  (when (and (display-graphic-p) (not my/explorer-shown-once) (project-current))
    (setq my/explorer-shown-once t)
    (my/explorer-show)))
(add-hook 'find-file-hook #'my/explorer-auto-show)
(add-hook 'dired-mode-hook #'my/explorer-auto-show)

;;;; Recent folders, and the files you had open in each (like VS Code)
;;   Cmd+O / File > Open Folder...   recent folders first, or "Browse…"
;;   File > Open Recent Folder       the same list as a menu
;;   File > Open Recent (a file)     also reopens that folder's other files
;;   Cmd+K F                         close the folder (its files and tabs)
;; Reopening a folder brings back the files you had open there, with the
;; last one you worked in selected (cursor positions come from
;; `save-place-mode'). At startup Emacs reopens the last folder.
;; Saved in ~/.emacs.d/project-sessions.eld when you quit, and every
;; minute you are idle.

(defvar my/reopen-last-folder t
  "Non-nil: at startup, reopen the folder you had open last, like VS Code.")

(defvar my/sessions-file (locate-user-emacs-file "project-sessions.eld"))
(defvar my/sessions nil
  "Folders with their open files: list of (ROOT FILES CURRENT), most recent first.")
(defvar my/sessions-loaded nil)

(defun my/sessions-load ()
  (unless my/sessions-loaded
    (setq my/sessions-loaded t
          my/sessions (ignore-errors
                        (with-temp-buffer
                          (insert-file-contents my/sessions-file)
                          (read (current-buffer)))))))

(defun my/project-root-of (file)
  "Project root (with a slash at the end) of FILE or folder FILE, or nil."
  (when-let* ((dir (file-name-directory (expand-file-name file)))
              (project (let ((default-directory dir)) (project-current))))
    (file-name-as-directory (expand-file-name (project-root project)))))

(defvar-local my/buffer-project-root 'unknown
  "Cache of this buffer's project root (looked up once per buffer).")

(defun my/buffer-project-root ()
  (when (eq my/buffer-project-root 'unknown)
    (setq my/buffer-project-root
          (and buffer-file-name (my/project-root-of buffer-file-name))))
  my/buffer-project-root)

;; Tabs work like VS Code windows: each opened folder has its own tabs.
;; A file belongs to the folder it was opened in, not to where it lives:
;; a file dragged in from Finder (or opened from another folder with
;; C-x C-f) becomes one more tab of the current folder. Only Cmd+O / Open
;; Folder starts a new set of tabs.
(defvar my/open-folders nil
  "Roots of the folders opened like VS Code windows (each has its own tabs).")
(defvar my/opening-group nil
  "When non-nil, the folder that files opened right now belong to.")
(defvar-local my/buffer-group nil
  "The folder (root) this file buffer belongs to as a tab, or \"Other\".")

(defun my/group-of (buf)
  "Tab group of BUF: the folder it was opened in."
  (or (buffer-local-value 'my/buffer-group buf)
      (with-current-buffer buf (my/buffer-project-root))))

(defun my/current-group ()
  "Tab group of the file you are in, else of the last file you were in."
  (seq-some (lambda (b) (buffer-local-value 'my/buffer-group b))
            (cons (window-buffer (selected-window))
                  (seq-filter #'buffer-file-name (buffer-list)))))

(defun my/assign-group ()
  "Give a newly opened file its tab group (runs from `find-file-hook')."
  (unless my/buffer-group
    (let ((root (my/buffer-project-root)))
      (setq my/buffer-group
            (or my/opening-group                         ; Cmd+O, reopening a folder
                (car (member root my/open-folders))      ; a file of an opened folder
                (my/current-group)                       ; anything else: join current tabs
                root                                     ; first file in a fresh Emacs
                "Other"))
      (unless (equal my/buffer-group "Other")
        (add-to-list 'my/open-folders my/buffer-group)))))
(add-hook 'find-file-hook #'my/assign-group)

(defun my/project-file-buffers (root)
  "Open file buffers in ROOT's tabs, most recently used first."
  (seq-filter (lambda (buf) (and (buffer-file-name buf)
                                 (equal root (my/group-of buf))))
              (buffer-list)))

(defun my/session-touch (root)
  "Move ROOT to the top of the recent folders."
  (my/sessions-load)
  (let ((entry (or (assoc root my/sessions) (list root nil nil))))
    (setq my/sessions (cons entry (remove entry my/sessions)))))

(defun my/session-save (root)
  "Remember ROOT's open files (at most 30), if it has any."
  (when-let* ((bufs (seq-take (my/project-file-buffers root) 30)))
    (my/sessions-load)
    (let ((files (mapcar (lambda (b) (expand-file-name (buffer-file-name b))) bufs))
          (old (assoc root my/sessions)))
      (setq my/sessions (cons (list root (reverse files) (car files))
                              (remove old my/sessions))))))

(defun my/sessions-write ()
  "Save the open files of every open folder to `my/sessions-file'."
  (my/sessions-load)
  (dolist (root (reverse (delete-dups
                          (delete "Other"
                                  (delq nil (mapcar #'my/group-of
                                                    (seq-filter #'buffer-file-name (buffer-list))))))))
    (my/session-save root))
  (setq my/sessions (seq-take my/sessions 30))
  (ignore-errors
    (with-temp-file my/sessions-file
      (let ((print-length nil) (print-level nil))
        (prin1 my/sessions (current-buffer))))))
(add-hook 'kill-emacs-hook #'my/sessions-write)
(run-with-idle-timer 60 t #'my/sessions-write)

(defun my/session-restore (root &optional select-file)
  "Reopen ROOT's saved files; select SELECT-FILE, else the last one used.
Return non-nil if a file was opened."
  (my/sessions-load)
  (let* ((entry (assoc root my/sessions))
         (files (seq-filter #'file-exists-p (nth 1 entry)))
         (current (or select-file
                      (and (nth 2 entry) (file-exists-p (nth 2 entry)) (nth 2 entry))
                      (car (last files)))))
    (dolist (file files)
      (unless (get-file-buffer file)
        (with-demoted-errors "Reopening: %S" (find-file-noselect file))))
    (when current (find-file current))
    current))

(defun my/recent-folders ()
  "Recent folders, most recent first: ours, then other known projects."
  (my/sessions-load)
  (seq-filter #'file-directory-p
              (delete-dups (append (mapcar #'car my/sessions)
                                   (mapcar (lambda (d) (file-name-as-directory (expand-file-name d)))
                                           (project-known-project-roots))))))

(defun my/read-folder ()
  "Ask for a folder: recent ones first, or \"Browse…\" for any other."
  (let* ((browse "Browse…")
         (choices (append (mapcar #'abbreviate-file-name (my/recent-folders)) (list browse)))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      '(metadata (category . file)          ; folder icons
                                 (display-sort-function . identity) ; keep recent-first order
                                 (cycle-sort-function . identity))
                    (complete-with-action action choices string pred))))
         (choice (completing-read "Open folder: " table nil t)))
    (if (equal choice browse)
        (read-directory-name "Open folder: ")
      choice)))

(defun my/open-folder (dir)
  "Cmd+O like VS Code's Open Folder: show DIR in the explorer and reopen the
files you had open there; a new folder shows its README instead."
  (interactive (list (my/read-folder)))
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (root (or (my/project-root-of dir) dir))
         (open (my/project-file-buffers root)))
    (setq my/explorer-shown-once t)
    (add-to-list 'my/open-folders root)
    (let ((my/opening-group root))               ; files opened here get ROOT's tabs
      (cond (open (switch-to-buffer (car open))) ; already open: just switch to it
            ((my/session-restore root))
            (t (let ((readme (seq-find #'file-exists-p
                                       (mapcar (lambda (n) (expand-file-name n dir))
                                               '("README.md" "README" "readme.md")))))
                 (if readme (find-file readme) (dired dir))))))
    (my/session-touch root)
    (when (project-current) (my/explorer-show))))

(defun my/open-recent-file (file)
  "File > Open Recent: open FILE. If its folder isn't open yet, also reopen
the other files you had open there."
  (let ((root (my/project-root-of file)))
    (if (or (null root) (my/project-file-buffers root))
        (find-file file)
      (setq my/explorer-shown-once t)
      (add-to-list 'my/open-folders root)
      (let ((my/opening-group root))
        (my/session-restore root file))
      (my/session-touch root)
      (my/explorer-show))))
(setq recentf-menu-action #'my/open-recent-file)

(defun my/close-folder ()
  "Cmd+K F like VS Code: close the current folder's files and the explorer.
They come back the next time you open the folder."
  (interactive)
  (let ((root (or (and buffer-file-name (my/group-of (current-buffer)))
                  (my/buffer-project-root)
                  (when-let* ((buf (my/task-buffer))) (my/group-of buf))
                  (user-error "No folder is open"))))
    (setq my/open-folders (delete root my/open-folders))
    (my/session-save root)
    (my/session-touch root)
    (my/sessions-write)
    (let ((bufs (my/project-file-buffers root)))
      (save-some-buffers nil (lambda () (memq (current-buffer) bufs)))
      (dolist (buf bufs)
        (unless (buffer-modified-p buf) (kill-buffer buf))))
    (dolist (buf (buffer-list))          ; folder listings of that project too
      (with-current-buffer buf
        (when (and (derived-mode-p 'dired-mode)
                   (string-prefix-p root (expand-file-name default-directory)))
          (kill-buffer buf))))
    (when (and (fboundp 'treemacs-current-visibility)
               (eq (treemacs-current-visibility) 'visible))
      (delete-window (treemacs-get-local-window)))
    (setq my/explorer-shown-once nil)
    (switch-to-buffer "*scratch*")
    (message "Closed %s" (abbreviate-file-name root))))

;; File menu: "Open Directory..." becomes Open Folder (with recent folders),
;; followed by an "Open Recent Folder" submenu.
(defun my/recent-folders-menu (_binding)
  (let ((map (make-sparse-keymap)))
    (dolist (dir (reverse (seq-take (my/recent-folders) 15)))   ; `define-key' adds to the front
      (define-key map (vector (intern dir))
                  `(menu-item ,(abbreviate-file-name dir)
                              ,(lambda () (interactive) (my/open-folder dir)))))
    map))

(let ((key (seq-find (lambda (k) (lookup-key menu-bar-file-menu (vector k)))
                     '(open-directory dired))))   ; Emacs 31 / Emacs 29 name
  (when key
    (define-key menu-bar-file-menu (vector key)
                '(menu-item "Open Folder..." my/open-folder
                            :help "Open a folder (recent folders first) with the files you had open"))
    (define-key-after menu-bar-file-menu [my-recent-folders]
      `(menu-item "Open Recent Folder" ,(make-sparse-keymap) :filter my/recent-folders-menu)
      key)))

;; Window size and position, remembered like VS Code: saved when you quit,
;; restored at startup. Kept per Mac in ~/.emacs.d/frame-geometry.eld (not in
;; dotfiles), so the ultrawide and the 24" each keep their own.
(defvar my/frame-geometry-file (locate-user-emacs-file "frame-geometry.eld"))

(defun my/frame-geometry-save ()
  "Remember the Emacs window's size, position and full-screen state."
  (let ((f (selected-frame)))
    (when (display-graphic-p f)
      (let ((pos (frame-position f)))
        (ignore-errors
          (with-temp-file my/frame-geometry-file
            (prin1 (list :left (car pos) :top (cdr pos)
                         :width (frame-text-width f) :height (frame-text-height f)
                         :fullscreen (frame-parameter f 'fullscreen))
                   (current-buffer))))))))
(add-hook 'kill-emacs-hook #'my/frame-geometry-save)

(defun my/frame-geometry-restore ()
  "Put the Emacs window back where it was when you quit."
  (when-let* (((display-graphic-p))
              (g (ignore-errors
                   (with-temp-buffer
                     (insert-file-contents my/frame-geometry-file)
                     (read (current-buffer))))))
    (let ((f (selected-frame))
          (fs (plist-get g :fullscreen)))
      (if (memq fs '(maximized fullboth fullscreen))
          (set-frame-parameter f 'fullscreen fs)
        (set-frame-size f (plist-get g :width) (plist-get g :height) t)
        ;; Only if it is still on screen (e.g. not after unplugging a monitor).
        (when (and (< -50 (plist-get g :left) (- (display-pixel-width) 100))
                   (< -50 (plist-get g :top) (- (display-pixel-height) 100)))
          (set-frame-position f (plist-get g :left) (plist-get g :top)))))))
(add-hook 'window-setup-hook #'my/frame-geometry-restore)

;; At startup, reopen the last folder, unless Emacs was opened with a file.
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (and my/reopen-last-folder
                       (not (seq-some #'buffer-file-name (buffer-list))))
              (my/sessions-load)
              (when-let* ((last (car my/sessions))
                          ((file-directory-p (car last))))
                (with-demoted-errors "Reopening last folder: %S"
                  (my/open-folder (car last)))))))

;; Right-click a file or folder in the explorer for its menu:
;;   New File / New Directory, Rename, Delete (to the macOS Trash, after
;;   asking), Move, Copy, Copy Path.
;; `context-menu-mode' (section 13) would catch the click first and show the
;; general editing menu instead, so switch it off inside the explorer.
(defun my/explorer-own-right-click ()
  (setq-local minor-mode-overriding-map-alist
              (cons (cons 'context-menu-mode (make-sparse-keymap))
                    minor-mode-overriding-map-alist)))

;; Drag a file or folder onto a folder to move it there, like VS Code.
;; Dropping onto a file moves it into that file's folder.
(defvar my/explorer-moving nil
  "Non-nil while the explorer moves files: open buffers follow the move.")

(defun my/explorer-retarget-buffers (from to &rest _)
  "After the explorer moved FROM to TO, keep buffers open at the new place.
Without this, the explorer closes every buffer visiting a moved file."
  (when my/explorer-moving
    (let ((from (expand-file-name from))
          (from-dir (file-name-as-directory (expand-file-name from)))
          (to (expand-file-name to)))
      (dolist (buf (buffer-list))
        (when-let* ((file (buffer-file-name buf)))
          (cond ((string= file from)
                 (with-current-buffer buf (set-visited-file-name to t t)))
                ((string-prefix-p from-dir file)  ; a file inside a moved folder
                 (with-current-buffer buf
                   (set-visited-file-name
                    (concat (file-name-as-directory to) (substring file (length from-dir)))
                    t t)))))))))
(advice-add 'rename-file :after #'my/explorer-retarget-buffers)

(defun my/explorer-keep-buffers (orig &rest args)
  (let ((my/explorer-moving t))
    (apply orig args)))

(declare-function treemacs--button-in-line "treemacs-rendering")
(declare-function treemacs-button-get "treemacs-core-utils")

(defun my/explorer-drag-move (orig source-pos target-pos)
  "Ask before a drag & drop move in the explorer; keep moved files open."
  (let* ((key (lambda (pos) (ignore-errors (treemacs-button-get (treemacs--button-in-line pos) :key))))
         (src (funcall key source-pos))
         (dst (funcall key target-pos))
         (dst-dir (and (stringp dst)
                       (file-name-as-directory (if (file-directory-p dst) dst (file-name-directory dst))))))
    (when (and (stringp src) dst-dir
               (not (string= (expand-file-name src) (expand-file-name dst)))
               (not (string= (file-name-directory (directory-file-name src)) dst-dir))
               (y-or-n-p (format "Move %s into %s? "
                                 (file-name-nondirectory (directory-file-name src))
                                 (file-name-nondirectory (directory-file-name dst-dir)))))
      (let ((my/explorer-moving t))
        (funcall orig source-pos target-pos)))))

;; New File / New Directory (right-click menu) suggest the folder you
;; clicked: a folder itself, or a file's folder. Clicking empty space below
;; the tree suggests the project root (treemacs would suggest ~ there).
(declare-function treemacs-current-workspace "treemacs-workspaces")
(declare-function treemacs-workspace->projects "treemacs-workspaces")
(declare-function treemacs-project->path "treemacs-workspaces")

(defun my/explorer-default-to-root (orig btn &rest args)
  (or (and (null btn)
           (when-let* ((project (car (treemacs-workspace->projects
                                      (treemacs-current-workspace)))))
             (treemacs-project->path project)))
      (apply orig btn args)))

(use-package treemacs
  :ensure t
  :defer t
  :bind (("s-1" . my/explorer-toggle)   ; Cmd+1  toggle explorer (Android Studio's Project view)
         ("s-o" . my/open-folder))      ; Cmd+O  open folder
  :custom
  (treemacs-width 36)
  (treemacs-is-never-other-window t)    ; C-x o skips the explorer
  :hook (treemacs-mode . my/explorer-own-right-click)
  :config
  ;; Highlight the current file. (Not `treemacs-project-follow-mode': it
  ;; jumps to the folder of any buffer, e.g. *Messages*. Like VS Code, the
  ;; explorer changes only when you open another folder with Cmd+O.)
  (treemacs-follow-mode 1)
  ;; One click opens or closes a folder, and opens a file, like VS Code.
  ;; A double click then counts as one click (no open-then-close).
  (keymap-set treemacs-mode-map "<mouse-1>" #'treemacs-single-click-expand-action)
  (keymap-set treemacs-mode-map "<double-mouse-1>" #'ignore)
  (advice-add 'treemacs--select-file-from-btn :around #'my/explorer-default-to-root)
  ;; Drag & drop and the menu's Move: ask first, keep moved files open.
  (advice-add 'treemacs--drag-move-files :around #'my/explorer-drag-move)
  (advice-add 'treemacs-move-file :around #'my/explorer-keep-buffers))


;; Terminal in the project root, in the bottom panel. Like VS Code's Ctrl+`:
;; opens it (or jumps to it); pressed inside the terminal, hides it.
(declare-function eat-project "eat")

(defun my/terminal-toggle ()
  "Ctrl+`: show the project terminal, or hide it when you are in it."
  (interactive)
  (if (derived-mode-p 'eat-mode)
      (if (window-parameter nil 'window-side)
          (delete-window)               ; hide the bottom panel
        (quit-window))                  ; terminal in a normal window
    (eat-project)))

(keymap-global-set "C-`" #'my/terminal-toggle)        ; Ctrl+`

(use-package eat
  :ensure t
  :defer t
  :config
  ;; Inside the terminal, keys go to the shell; keep this one for Emacs.
  (keymap-set eat-semi-char-mode-map "C-`" #'my/terminal-toggle))



;;;; 11. Debugger: Dape + lldb-dap ----------------------------------------------
;; Build with debug info first (-g, or CMAKE_BUILD_TYPE=Debug).
;; F5 (build + debug the current file) is in section 12.
;; In other buffers F5 asks for a config, e.g.   lldb-dap :program "build/app"

(use-package dape
  :ensure t
  :bind (("<f9>"    . dape-breakpoint-toggle)     ; F9        breakpoint
         ("<f10>"   . dape-next)                  ; F10       step over
         ("<f11>"   . dape-step-in)               ; F11       step into
         ("S-<f11>" . dape-step-out))             ; Shift+F11 step out
  :custom
  (dape-buffer-window-arrangement 'right) ; variables / stack on the right
  :hook
  ;; Program output arrives with Windows-style line ends ("^M"); hide them.
  (dape-repl-mode . (lambda ()
                      (setq buffer-display-table (make-display-table))
                      (aset buffer-display-table ?\^M [])))
  :config
  (my/setup-dev-tools))


;;;; 12. VS Code tasks: build / run / debug the current file --------------------
;; Works per open file, like VS Code's "build and debug active file":
;;   Cmd+Shift+B    build the file in the current buffer
;;   Ctrl+Option+N  build it, then run it (type program input in the panel)
;;   F5             build it, then start it in the debugger (stops at F9 breakpoints)
;;                  The program reads and prints in the *Program* panel; type its
;;                  input there. The debugger's own console is *dape-repl*.
;;   Shift+F5       stop: the debug session, the running program or the build
;;
;; Default for any C / C++ file:
;;   clang -g -O0 -Wall <compile_flags.txt> FILE -o build/FILE-without-.c
;;
;; A project can replace the defaults in its .dir-locals.el:
;;   %f = current file, relative to the project root  (VS Code ${relativeFile})
;;   %e = the same without the extension
;;   %p = the program the file belongs to:
;;        a .c file with its own main() (other than main.c) is a program on
;;        its own: exercises/sum.c -> exercises/sum;
;;        otherwise the nearest folder at or above it that has a main.c
;;        (e.g. programs/hello). In a file outside any program (e.g.
;;        shared code), the last program used.
;;   ((nil . ((my/build-command . "./scripts/build.sh %f")
;;            (my/run-command   . "./scripts/run.sh %f")
;;            (my/debug-program . "build/%e"))))
;; Whole project (a Makefile builds all files into one program):
;;   ((nil . ((my/build-command . "make")
;;            (my/run-command   . "make run")
;;            (my/debug-program . "build/app"))))
;; Many programs, one per folder with a main.c or per file with a main():
;;   ((nil . ((my/build-command . "make PROG=%p")
;;            (my/run-command   . "make run PROG=%p")
;;            (my/debug-program . "build/%p"))))
;; Commands run in the folder that holds .dir-locals.el.

(defvar-local my/build-command nil "Shell command that builds the current file.")
(defvar-local my/run-command nil "Shell command that builds and runs the current file.")
(defvar-local my/debug-program nil "Program to start under the debugger.")
(dolist (var '(my/build-command my/run-command my/debug-program))
  (put var 'safe-local-variable #'stringp))  ; strings never trigger a prompt

(defun my/c-buffer-p ()
  "Non-nil in C and C++ buffers."
  (seq-some #'derived-mode-p '(c-mode c-ts-mode c++-mode c++-ts-mode)))

(defun my/default-build-command ()
  "Build template for a single C / C++ file, or nil in other buffers."
  (when (my/c-buffer-p)
    (concat "mkdir -p \"$(dirname build/%e)\" && "
            (if (seq-some #'derived-mode-p '(c++-mode c++-ts-mode)) "clang++" "clang")
            " -g -O0 -Wall $(cat compile_flags.txt 2>/dev/null) %f"
            " -o \"build/%e\" -lm")))

(defvar my/last-program nil
  "Alist (ROOT . PROGRAM-FOLDER): the program last used in each project.")

(defconst my/main-regexp "^[ \t]*\\(?:int\\|void\\)[ \t]+main[ \t]*("
  "A line that starts the main() function. Same test as the Makefile's.")

(defun my/defines-main-p (file)
  "Non-nil if FILE defines main(). Reads its buffer if open (unsaved text too)."
  (with-temp-buffer
    (if-let* ((buf (find-buffer-visiting file)))
        (insert-buffer-substring buf)
      (insert-file-contents file))
    (goto-char (point-min))
    (re-search-forward my/main-regexp nil t)))

(defun my/program-folder (file root)
  "Program FILE belongs to, relative to ROOT (what %p becomes):
- a .c / .cpp file with its own main(), other than main.c, is a program
  on its own: exercises/sum.c -> \"exercises/sum\";
- else the nearest folder at or above FILE that has a main.c: \"hello\";
- else (shared code) the program used last in this project."
  (let ((program
         (if (and (member (file-name-extension file) '("c" "cc" "cpp"))
                  (not (equal (file-name-nondirectory file) "main.c"))
                  (my/defines-main-p file))
             (file-name-sans-extension (file-relative-name file root))
           (when-let* ((dir (locate-dominating-file file "main.c"))
                       ((file-in-directory-p dir root)))
             (directory-file-name (file-relative-name dir root))))))
    (if program
        (setf (alist-get root my/last-program nil nil #'equal) program)
      (or (alist-get root my/last-program nil nil #'equal)
          (user-error "Not inside a program: open a .c file with a main(), or a file in a folder that has a main.c")))))

(defun my/file-task (template &optional from-dir-locals)
  "Expand TEMPLATE for the current file. Return (ROOT . STRING) or nil.
ROOT is the folder the command runs in:
  FROM-DIR-LOCALS non-nil: the folder holding .dir-locals.el (the commands
  were written relative to it); otherwise the project root, or the
  file's own folder outside a project."
  (when-let* ((template)
              (file buffer-file-name)
              (root (expand-file-name
                     (or (and from-dir-locals
                              (locate-dominating-file file ".dir-locals.el"))
                         (when-let* ((project (project-current)))
                           (project-root project))
                         (file-name-directory file))))
              (rel (file-relative-name file root)))
    (cons root (format-spec
                template
                `((?f . ,(shell-quote-argument rel))
                  (?e . ,(file-name-sans-extension rel))
                  ;; Only looked up when used, so other projects never need a main.c.
                  ,@(when (string-search "%p" template)
                      `((?p . ,(my/program-folder file root)))))))))

(defun my/build-task ()
  (if my/build-command
      (my/file-task my/build-command t)
    (my/file-task (my/default-build-command))))

(defun my/run-task ()
  (if my/run-command
      (my/file-task my/run-command t)
    (when-let* ((build (my/default-build-command)))
      (my/file-task (concat build " && \"./build/%e\"")))))

(defun my/debug-task ()
  (if my/debug-program
      (my/file-task my/debug-program t)
    (my/file-task (and (my/c-buffer-p) "build/%e"))))

(defun my/task-buffer ()
  "Buffer that F5, Cmd+Shift+B and Ctrl+Option+N act on: this one if it
visits a file, else the file you were in last. So they also work while
the explorer, the bottom panel or a debugger window has the focus."
  (if buffer-file-name
      (current-buffer)
    (or (seq-find #'buffer-file-name (buffer-list))
        (user-error "Open a file of the program first"))))

(defun my/build ()
  "Cmd+Shift+B: build the current file, or ask for a build command."
  (interactive)
  (with-current-buffer (my/task-buffer)
    (if-let* ((task (my/build-task)))
        (let ((default-directory (car task)))
          (compile (cdr task)))
      (call-interactively #'project-compile))))

(defun my/run ()
  "Ctrl+Option+N (Code Runner): build and run the current file.
Output appears in the bottom panel; you can type program input there."
  (interactive)
  (with-current-buffer (my/task-buffer)
    (if-let* ((task (my/run-task)))
        (let ((default-directory (car task)))
          (compile (cdr task) t))
      (user-error "Not a C / C++ file, and no `my/run-command' in .dir-locals.el"))))

;; The debugged program's input and output: the *Program* panel, like the
;; TERMINAL tab in VS Code. What you type there goes to the program
;; (scanf, getchar, ...); the debug console (*dape-repl*) talks to the
;; debugger only. How: Emacs opens a pseudo-terminal for the panel, and
;; lldb connects the program's stdin / stdout / stderr to it (lldb settings
;; target.input-path, target.output-path, target.error-path). Emacs' own
;; gdb front end (M-x gdb) does the same.
(define-derived-mode my/program-mode comint-mode "Program"
  "Input and output of the program being debugged."
  ;; Must stay nil: Emacs creates this terminal with echo turned off, so the
  ;; program never repeats your input. With t, Emacs deleted the program's
  ;; next output whenever it matched what you typed (e.g. puts of a name).
  (setq-local comint-process-echoes nil)
  (add-hook 'comint-output-filter-functions #'comint-strip-ctrl-m nil t))

(defvar my/program-pending nil
  "Non-nil: show *Program* when the debug session starts.")

(defun my/program-terminal ()
  "Empty the *Program* panel, give it a new terminal, return the terminal's name."
  (require 'comint)
  (let ((buf (get-buffer-create "*Program*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'my/program-mode) (my/program-mode))
      (let ((inhibit-read-only t)) (erase-buffer))
      (let ((process-connection-type t))      ; a pseudo-terminal, not a pipe
        (comint-exec buf "program" nil nil nil)) ; nil = terminal only, no command
      (let ((proc (get-buffer-process buf)))
        (set-process-query-on-exit-flag proc nil)
        (set-process-sentinel proc #'ignore)  ; no "Process ... finished" lines
        (process-tty-name proc)))))

(defun my/program-show ()
  "On debug start: show *Program* in the bottom panel and put the cursor there."
  (when my/program-pending
    (setq my/program-pending nil)
    (when-let* ((buf (get-buffer "*Program*"))
                (win (display-buffer buf)))
      (select-window win)
      (goto-char (point-max)))))
;; After dape loads: adding earlier would replace dape's own start hooks
;; (debug console, variables) instead of joining them.
(with-eval-after-load 'dape
  (add-hook 'dape-start-hook #'my/program-show 90))

(declare-function dape "dape")
(declare-function dape-continue "dape")
(declare-function dape--live-connection "dape")
(declare-function dape--config-from-string "dape")
(declare-function dape--config-eval "dape")

(defun my/debug-start-or-continue ()
  "F5 like VS Code: continue a paused session, else build + debug this file."
  (interactive)
  (require 'dape)
  (if (dape--live-connection 'parent t)
      (call-interactively #'dape-continue)
    (with-current-buffer (my/task-buffer)
      (my/debug-start))))

(defun my/debug-start ()
  "Build the current file's program, then start it in the debugger."
  (let ((program (my/debug-task))
        (build (my/build-task)))
    (cond
     (program
      (message "F5: building, then debugging %s" (cdr program))
      ;; `compile' = build first (VS Code "preLaunchTask"); dape only
      ;; starts the debugger if the build succeeds.
      (let ((spec (format "lldb-dap :program %S%s"
                          (expand-file-name (cdr program) (car program))
                          (if build (format " compile %S" (cdr build)) "")))
            (tty (my/program-terminal)))
        (pcase-let ((`(,key ,config) (dape--config-from-string spec)))
          (let ((default-directory (car program))
                (config (dape--config-eval key config)))
            ;; Before launch: connect the program to the *Program* terminal.
            (setq config (plist-put config :preRunCommands
                                    (vector (concat "settings set target.input-path " tty)
                                            (concat "settings set target.output-path " tty)
                                            (concat "settings set target.error-path " tty))))
            (setq my/program-pending t)
            (dape config)))))
     (t (call-interactively #'dape)))))

;; Stop, like VS Code's Shift+F5:
;;   F5 debug session       ends it (the program is killed)
;;   Ctrl+Option+N program  gets Ctrl+C, also while it waits for input
;;   Cmd+Shift+B build      is stopped
;; A program that ignores Ctrl+C is killed by a second Shift+F5.
;; Also: right-click > Stop in the output pane, or C-c C-c there.
;; Ctrl+D at the end of the pane ends the input instead (EOF), for
;; programs that read until end of input.
(declare-function dape-quit "dape")

(defun my/run-process (&optional buffer)
  "The live build / run process in BUFFER, or else the most recent one."
  (seq-some (lambda (buf)
              (with-current-buffer buf
                (when-let* (((or (derived-mode-p 'compilation-mode)
                                 (bound-and-true-p compilation-shell-minor-mode)))
                            (proc (get-buffer-process buf))
                            ((process-live-p proc)))
                  proc)))
            (if buffer (list buffer) (buffer-list))))

(defun my/debug-live-p ()
  "Non-nil while a debug session runs."
  (and (featurep 'dape) (dape--live-connection 'parent t)))

(defun my/stop ()
  "Shift+F5: stop debugging, or stop the running program or build."
  (interactive)
  (let ((here (my/run-process (current-buffer)))) ; the output pane you are in
    (cond
     ((and (not here) (my/debug-live-p))
      (dape-quit)
      (message "Stopped debugging"))
     ((when-let* ((proc (or here (my/run-process))))
        (if (process-get proc 'my/stop-sent)
            (progn (kill-process proc)            ; 2nd press: force (SIGKILL)
                   (message "Killed the program"))
          (process-put proc 'my/stop-sent t)
          (interrupt-process proc)                ; 1st press: Ctrl+C (SIGINT)
          (message "Stopping... (press Shift+F5 again if it keeps running)"))
        t))
     (t (message "Nothing is running")))))

(keymap-global-set "s-B"   #'my/build)                    ; Cmd+Shift+B
(keymap-global-set "C-M-n" #'my/run)                      ; Ctrl+Option+N
(keymap-global-set "<f5>"  #'my/debug-start-or-continue)  ; F5
(keymap-global-set "S-<f5>" #'my/stop)                    ; Shift+F5


;;;; 13. VS Code look ----------------------------------------------------------

;; Colours. Both are Modus themes, built into Emacs.
;;   Dark:  Modus Vivendi with One Dark colors (purple keywords, gold types,
;;          blue functions, red declared names, green strings).
;;   Light: Modus Operandi, designed for high contrast and readability.
;; Cmd+K Cmd+T switches between them.
(defvar my/theme-mode 'dark
  "Theme at startup: `light', `dark', or `system' (follow macOS appearance).")
(defvar my/light-theme 'modus-operandi)
(defvar my/dark-theme 'modus-vivendi)

;; Your code colors. Change a value, restart Emacs.
;; Keywords (if, return, static, const): all one color, normal weight.
;; Built-in types (int, void, long): see `my-c-builtin-type-face' below.
(defvar my/keyword-color "#a3144d")       ; light theme: dark pink
(defvar my/keyword-color-dark "#c678dd")  ; dark theme: One Dark purple

(setq modus-operandi-palette-overrides
      `((keyword      ,my/keyword-color)
        (variable-use fg-main)))        ; a name where it's used: plain text

;; Dark theme: the colors of the One Dark screenshot.
(setq modus-vivendi-palette-overrides
      `(;; Background and text
        (bg-main      "#191e22")
        (fg-main      "#abb2bf")
        (bg-dim       "#1f252a")        ; popups, inactive panes
        (fg-dim       "#7f848e")
        (cursor       "#528bff")
        (bg-hl-line   "#22282e")        ; current line
        (bg-region    "#3e4451")        ; selection
        (bg-completion "#2c3440")       ; selected item in completion lists
        (bg-paren-match "#3e4451")
        ;; Code
        (keyword      ,my/keyword-color-dark) ; static, return, const
        (builtin      ,my/keyword-color-dark)
        (preprocessor ,my/keyword-color-dark) ; #include, #define
        (type         "#e5c07b")        ; int, void, long, gboolean, struct names
        (fnname       "#61afef")        ; a function where it's defined
        (fnname-call  fg-main)          ; printf(...): plain text
        (variable     "#e06c75")        ; a name where it's declared
        (variable-use fg-main)          ; a name where it's used: plain text
        (property     "#e06c75")        ; struct fields where declared
        (string       "#98c379")
        (constant     "#56b6c2")        ; NULL, true, enum values
        (rx-backslash "#56b6c2")        ; \n inside strings
        (comment      "#5c6370")
        (docstring    "#7f848e")
        ;; Line numbers: dim, on the editor background
        (fg-line-number-inactive "#4b5263")
        (fg-line-number-active   "#abb2bf")
        (bg-line-number-inactive bg-main)
        (bg-line-number-active   bg-hl-line)
        ;; Status bar and tabs
        (bg-mode-line-active     "#2c323a")
        (fg-mode-line-active     "#c8ccd0")
        (border-mode-line-active "#2c323a")
        (bg-mode-line-inactive   "#1f252a")
        (fg-mode-line-inactive   "#7f848e")
        (border-mode-line-inactive "#1f252a")
        (bg-tab-bar     "#14181b")
        (bg-tab-current bg-main)
        (bg-tab-other   "#14181b")))

;; Both themes.
(face-spec-set 'font-lock-property-use-face ; p->age where used: plain text
               '((t :inherit unspecified :foreground unspecified))
               'face-override-spec)

;; C / C++ built-in types (int, void, char, long, unsigned, ...):
;;   light theme: keyword color, as they are keywords of the language;
;;   dark theme:  type color (gold), like struct names and size_t,
;;                as in the One Dark screenshot.
;; (A hyphen, not a slash, in this name: tree-sitter rules reject "/".)
(defface my-c-builtin-type-face
  '((((background light)) :inherit font-lock-keyword-face)
    (t :inherit font-lock-type-face))
  "Face for C / C++ built-in type names such as int and void.")

(defvar c-ts-mode--type-keywords)
(defconst my/c-type-keywords
  (regexp-opt '("void" "char" "short" "int" "long" "float" "double"
                "signed" "unsigned" "bool" "_Bool" "_Complex" "_Imaginary"
                "wchar_t" "char8_t" "char16_t" "char32_t")
              'symbols)
  "Built-in type names that are keywords. The grammar also calls size_t,
int32_t, ... built-in types, but those are ordinary type names.")

(defun my/c-types-as-keywords ()
  "Color int, void, char, unsigned, ... with `my-c-builtin-type-face',
and C++ const like a keyword."
  (let* ((lang (if (derived-mode-p 'c++-ts-mode) 'cpp 'c))
         (rules (treesit-font-lock-rules
                 :language lang :feature 'keyword :override t
                 `(((primitive_type) @my-c-builtin-type-face
                    (:match ,my/c-type-keywords @my-c-builtin-type-face))
                   [,@c-ts-mode--type-keywords] @my-c-builtin-type-face
                   ,@(when (eq lang 'cpp)
                       '((type_qualifier) @font-lock-keyword-face))))))
    (if (fboundp 'treesit-add-font-lock-rules) ; Emacs 31
        (treesit-add-font-lock-rules rules)
      (setq-local treesit-font-lock-settings
                  (append treesit-font-lock-settings rules))
      (treesit-font-lock-recompute-features))))
(add-hook 'c-ts-mode-hook #'my/c-types-as-keywords)
(add-hook 'c++-ts-mode-hook #'my/c-types-as-keywords)

;; Classic colors = Modus Operandi as in Emacs 29 (Modus 3), the look in
;; Claude's screenshots. Emacs 31 ships Modus 5, which changed some code
;; colors and paints file / folder icons and folder names blue.
;; Set to nil for Emacs 31's own Modus colors.
(defvar my/classic-colors t)

(when my/classic-colors
  ;; Code colors: Modus 3 values for the Modus 5 palette names.
  ;; (Keywords and variable uses: see "Your code colors" above.)
  (setq modus-operandi-palette-overrides
        (append
         modus-operandi-palette-overrides
         '((type         "#005a5f")       ; struct names, size_t
          (variable     "#00538b")       ; names where they are declared
          (property     "#00538b")       ; struct fields
          (string       "#2544bb")
          (constant     "#0000c0")       ; NULL, true, enum values
          (comment      "#505050")
          (docstring    "#2a486a")
          (rx-backslash "#654d0f")       ; \n inside strings
          ;; Calls stay plain text, as in Emacs 29.
          (fnname-call  fg-main)         ; printf(...)
          ;; Current line and line numbers.
          (bg-hl-line   "#e0e0e0")
          (fg-line-number-inactive "#505050")
          (bg-line-number-inactive "#f8f8f8")
          (bg-line-number-active   "#d7d7d7"))))

  ;; Icons and explorer folder names: the icon packages' own colors
  ;; (orange folders, blue C files, ...) instead of Modus 5's blue.
  (defun my/classic-ui-colors ()
    "Undo Modus 5's colors for icons and explorer folder names."
    (dolist (face (face-list))
      (cond
       ((and (string-match-p "\\`\\(treemacs-\\)?nerd-icons-" (symbol-name face))
             (get face 'face-defface-spec))
        ;; The face's own spec, on top of the theme. `:foreground unspecified'
        ;; first drops the theme's color, so an `:inherit' in the spec works.
        (face-spec-set
         face
         (mapcar (lambda (clause)          ; (DISPLAY . ATTRS) or (DISPLAY ATTRS)
                   (let ((attrs (if (keywordp (cadr clause)) (cdr clause) (cadr clause))))
                     (cons (car clause) (append '(:foreground unspecified) attrs))))
                 (get face 'face-defface-spec))
         'face-override-spec))
       ((memq face '(treemacs-directory-face treemacs-directory-collapsed-face))
        (face-spec-set face '((t :foreground unspecified)) 'face-override-spec))))
    ;; Explorer title and git colors of file names (light theme only).
    (pcase-dolist (`(,face . ,attrs)
                   '((treemacs-root-face :foreground "#0000c0" :weight bold
                                         :underline t :height 1.2)
                     (treemacs-git-untracked-face :foreground "#505050") ; new file
                     (treemacs-git-ignored-face   :foreground "#505050")
                     (treemacs-git-added-face     :foreground "#005e00" :weight bold)
                     (treemacs-git-modified-face  :foreground "#813e00" :weight bold)
                     (treemacs-git-conflict-face  :foreground "#a60000" :weight bold)))
      (when (facep face)
        (face-spec-set face `((((background light)) ,@attrs)) 'face-override-spec))))
  ;; These packages load later; fix their faces as each one arrives.
  (dolist (feature '(nerd-icons nerd-icons-completion nerd-icons-dired
                     treemacs treemacs-nerd-icons))
    (with-eval-after-load feature (my/classic-ui-colors))))

(defun my/apply-theme (appearance)
  "Load the light or dark theme. APPEARANCE is `light' or `dark'."
  (let ((theme (if (eq appearance 'light) my/light-theme my/dark-theme)))
    (unless (memq theme custom-enabled-themes)
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme theme t)))
  ;; macOS title bar text: dark on light themes, light on dark themes.
  (setf (alist-get 'ns-appearance default-frame-alist) appearance)
  (dolist (frame (frame-list))
    (set-frame-parameter frame 'ns-appearance appearance)))

(defun my/theme-toggle ()
  "Switch between the light and the dark theme."
  (interactive)
  (my/apply-theme (if (memq my/light-theme custom-enabled-themes) 'dark 'light)))

;; Cmd+K chords, like VS Code. Cmd+K Cmd+T = switch theme.
(defvar-keymap my/cmd-k-map "s-t" #'my/theme-toggle)
(keymap-global-set "s-k" my/cmd-k-map)

(if (and (eq my/theme-mode 'system)
         (boundp 'ns-system-appearance-change-functions)) ; emacs-plus only
    (progn
      (my/apply-theme (or (bound-and-true-p ns-system-appearance) 'light))
      (add-hook 'ns-system-appearance-change-functions #'my/apply-theme))
  (my/apply-theme (if (eq my/theme-mode 'dark) 'dark 'light)))

(setq-default cursor-type 'bar          ; thin text cursor
              line-spacing 0.15)        ; a little air between lines
(context-menu-mode 1)                   ; right-click menu

;; Right-click > "Clear" in output panes: the debug console (*dape-repl*),
;; program output from Ctrl+Option+N, and shells. Keyboard: C-c M-o.
(defun my/context-menu-clear (menu _click)
  "Put \"Clear\" at the top of the right-click MENU."
  ;; `define-key' adds to the front of a menu: separator first, then Clear.
  (define-key menu [my-clear-separator] menu-bar-separator)
  (define-key menu [my-clear] '(menu-item "Clear" comint-clear-buffer))
  menu)

;; Right-click > "Stop" (Shift+F5) in the same panes, while something runs.
(defun my/context-menu-stop (menu _click)
  "Put \"Stop\" at the top of the right-click MENU while something runs here."
  (when (or (my/run-process (current-buffer))
            (and (derived-mode-p 'dape-repl-mode 'my/program-mode) (my/debug-live-p)))
    (define-key menu [my-stop-separator] menu-bar-separator)
    (define-key menu [my-stop] '(menu-item "Stop" my/stop)))
  menu)

(add-hook 'comint-mode-hook
          (lambda ()
            (add-hook 'context-menu-functions #'my/context-menu-clear 90 t)
            (add-hook 'context-menu-functions #'my/context-menu-stop 91 t)))
(add-hook 'compilation-mode-hook        ; Cmd+Shift+B build output
          (lambda ()
            (add-hook 'context-menu-functions #'my/context-menu-stop 91 t)))
(setopt window-divider-default-places t ; 1px lines between panes
        window-divider-default-right-width 1
        window-divider-default-bottom-width 1)
(window-divider-mode 1)

;; Start screen with the keys you need first.
(setq initial-scratch-message "\
;; Cmd+O        open folder         Cmd+P        open file in project
;; Cmd+Shift+P  command palette     Cmd+1        explorer
;; Cmd+K F      close folder        File menu    Open Recent Folder
;; Cmd+B        go to definition    Cmd+[        go back
;; Ctrl+\\=`       terminal            Cmd+J        bottom panel
;; Cmd+K Cmd+T  light / dark theme  Cmd+K Cmd+I  hover info at cursor
;; F5           build + debug       Shift+F5     stop

")

;; Package installs print warnings meant for package authors.
;; Never open a window for them (they stay in their buffers).
(add-to-list 'display-buffer-alist
             '("\\`\\*\\(Compile-Log\\|Async-native-compile-log\\)\\*\\'"
               (display-buffer-no-window) (allow-no-window . t)))
(setq warning-minimum-level :error)     ; only real errors pop up

;; Bottom panel: terminal, build / run output, problems -- one strip.
(defconst my/panel-regexp
  "\\`\\*\\(compilation\\|Program\\|.*eat\\|Flymake diagnostics.*\\|xref\\)\\*\\'")
(setq window-sides-vertical t)          ; explorer full height, panel under the editor
(add-to-list 'display-buffer-alist
             `(,my/panel-regexp
               (display-buffer-in-side-window)
               (side . bottom) (slot . 0) (window-height . 0.3)))

(defun my/panel-toggle ()
  "Cmd+J like VS Code: hide or show the bottom panel."
  (interactive)
  (if-let* ((win (window-with-parameter 'window-side 'bottom)))
      (delete-window win)
    (if-let* ((buf (seq-find (lambda (b)
                               (string-match-p my/panel-regexp (buffer-name b)))
                             (buffer-list))))
        (display-buffer buf)
      (call-interactively #'eat-project))))
(keymap-global-set "s-j" #'my/panel-toggle)

;; Icons. They come from the font "Symbols Nerd Font Mono". An older copy
;; of it lacks newer icons, which then show as boxes with hex codes
;; (e.g. collapsed folders in the explorer: E6AD, F107F). So on start,
;; check the font has them; if not, install the matching font once.
(use-package nerd-icons :ensure t :defer t)

(declare-function nerd-icons-install-fonts "nerd-icons")
(defvar nerd-icons-font-family)

(defconst my/icons-test-chars '(#xe6ad     ; closed folder (explorer)
                                #xf107f)   ; build / .cache folder
  "Newer icons; an up-to-date icon font has all of them.")

(defun my/icons-font ()
  "The installed icon font, or nil."
  (require 'nerd-icons)
  (find-font (font-spec :family nerd-icons-font-family)))

(defun my/icons-font-ok-p ()
  "Non-nil when the icon font is installed and new enough."
  (when-let* ((entity (my/icons-font))
              (font (if (fboundp 'open-font) (open-font entity) entity)))
    (seq-every-p (lambda (c) (font-has-char-p font c)) my/icons-test-chars)))

(defun my/icons-font-file ()
  "Where `nerd-icons-install-fonts' puts the font."
  (if (eq system-type 'darwin)
      (expand-file-name "~/Library/Fonts/NFM.ttf")
    (expand-file-name "fonts/NFM.ttf"
                      (or (getenv "XDG_DATA_HOME") "~/.local/share"))))

(defun my/icons-ensure-font ()
  "Install the icon font when it is missing or too old (once)."
  (when (and (display-graphic-p) (not (my/icons-font-ok-p)))
    (if (file-exists-p (my/icons-font-file))
        ;; Already installed by us, so an older copy wins: tell how to fix.
        (display-warning
         'icons
         (concat "Some icons show as boxes: an older \"Symbols Nerd Font\" "
                 "is installed next to the new one (" (my/icons-font-file) ").\n"
                 "Open Font Book, search \"Symbols Nerd Font\", remove all copies "
                 "except NFM.ttf (or: brew uninstall --cask font-symbols-only-nerd-font), "
                 "then restart Emacs.")
         :error)
      (message "Icons: installing the icon font (one time)...")
      (condition-case err
          (progn
            (nerd-icons-install-fonts t)
            (clear-font-cache)
            (if (my/icons-font-ok-p)
                (message "Icons: font installed")
              (message "Icons: font installed. Restart Emacs to see all icons")))
        (error (message "Icons: could not download the font (%s). Try later: M-x nerd-icons-install-fonts"
                        (error-message-string err)))))))

(add-hook 'emacs-startup-hook
          (lambda () (run-with-idle-timer 1 nil #'my/icons-ensure-font)))

(use-package nerd-icons-completion          ; icons in Cmd+P / M-x lists
  :ensure t
  :after marginalia
  :config (nerd-icons-completion-mode))

(use-package nerd-icons-corfu               ; icons in the completion popup
  :ensure t
  :after corfu
  :config (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-dired               ; icons in folder listings
  :ensure t
  :hook (dired-mode . nerd-icons-dired-mode))
(add-hook 'dired-mode-hook #'dired-hide-details-mode) ; names only, no `ls -l'

(use-package treemacs-nerd-icons            ; icons in the explorer
  :ensure t
  :after treemacs
  :config (treemacs-nerd-icons-config))

;; Editor tabs along the top: one per open file.
(use-package centaur-tabs
  :ensure t
  :demand t
  :custom
  (centaur-tabs-style "bar")
  (centaur-tabs-height 30)
  (centaur-tabs-set-bar 'over)               ; accent line on the active tab
  (centaur-tabs-set-icons t)
  (centaur-tabs-icon-type 'nerd-icons)
  (centaur-tabs-set-close-button t)
  (centaur-tabs-set-modified-marker t)       ; dot on unsaved files
  (centaur-tabs-modified-marker "●")
  (centaur-tabs-show-new-tab-button nil)
  (centaur-tabs-cycle-scope 'tabs)
  :config
  ;; Like VS Code: tabs only for files, and only for the current folder's
  ;; files (other folders' files stay open in the background). A file
  ;; dragged in from elsewhere joins the current folder's tabs.
  (setq centaur-tabs-buffer-groups-function
        (lambda () (list (or (my/group-of (current-buffer)) "Other")))
        centaur-tabs-buffer-list-function
        (lambda () (seq-filter #'buffer-file-name (buffer-list)))
        centaur-tabs-hide-tab-function (lambda (buf) (not (buffer-file-name buf))))
  (centaur-tabs-mode 1)
  :hook ((treemacs-mode dired-mode eat-mode compilation-mode) . centaur-tabs-local-mode)
  :bind (("s-}" . centaur-tabs-forward)      ; Cmd+Shift+]  next tab
         ("s-{" . centaur-tabs-backward)     ; Cmd+Shift+[  previous tab
         ("s-w" . kill-current-buffer)))     ; Cmd+W        close tab

;; Breadcrumbs above the code: project > folder > file > function.
(use-package breadcrumb
  :ensure t
  :demand t
  :config (breadcrumb-mode 1))

;; Status bar: git branch, errors, line:column, encoding, language.
(use-package doom-modeline
  :ensure t
  :demand t
  :custom
  (doom-modeline-height 26)
  (doom-modeline-bar-width 0)
  (doom-modeline-buffer-file-name-style 'relative-from-project)
  :config (doom-modeline-mode 1))

;; Cmd+P / Cmd+Shift+P open as a floating box at the top, like VS Code.
(use-package vertico-posframe
  :ensure t
  :after vertico
  :custom
  (vertico-posframe-poshandler #'posframe-poshandler-frame-top-center)
  (vertico-posframe-border-width 1)
  (vertico-posframe-parameters '((left-fringe . 10) (right-fringe . 10)))
  :config (vertico-posframe-mode 1))

;; Hover popups, like VS Code: rest the mouse on a name for 0.4 s.
;;   While editing:          its type and documentation (from clangd).
;;   While debugging (paused): its current value first, then the type.
;; From the keyboard: Cmd+K Cmd+I shows the same popup for the name at the cursor.
(use-package eldoc-mouse
  :ensure t
  :hook (eglot-managed-mode . eldoc-mouse-mode)
  :custom (eldoc-mouse-idle-time 0.4))
(keymap-set my/cmd-k-map "s-i" #'eldoc-mouse-pop-doc-at-cursor)
(keymap-set my/cmd-k-map "f" #'my/close-folder)          ; Cmd+K F  close folder

;; Thin indent guides, like VS Code.
(use-package indent-bars
  :ensure t
  :custom
  (indent-bars-treesit-support t)
  (indent-bars-pattern ".")                ; solid line
  (indent-bars-width-frac 0.1)             ; thin
  (indent-bars-color '(shadow :blend 0.35))
  (indent-bars-color-by-depth nil)         ; one colour, not a rainbow
  (indent-bars-highlight-current-depth '(:blend 0.7))
  :hook ((c-ts-mode c++-ts-mode) . indent-bars-mode))


;;;; 14. Assembly ---------------------------------------------------------------
;; asm-mode is built in and opens .s / .S / .asm files.
;; Its default comment char `;' matches Apple's ARM64 assembler.
;; For x86 AT&T syntax (comments start with `#'), put this in the
;; project's .dir-locals.el:
;;   ((asm-mode . ((asm-comment-char . ?#))))

;;; init.el ends here
