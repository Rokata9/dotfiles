;;; init.el --- VS Code-like Emacs for C / C++ / assembly on macOS  -*- lexical-binding: t; -*-
;;
;; Target: GNU Emacs 31.1 from emacs-plus (Homebrew) on macOS.
;;
;; Behaviour (sections 1-12) uses mostly built-in parts of Emacs 31:
;;   tree-sitter, Eglot (LSP), Flymake, project.el, which-key, editorconfig.
;; Looks (section 13) add the VS Code layout: light/dark themes, tabs,
;; explorer, breadcrumbs, status bar, floating command palette, icons.
;;
;; One-time font install for the icons:
;;   brew install --cask font-symbols-only-nerd-font
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

;; Font: first one that is installed wins.
(when (display-graphic-p)
  (when-let* ((font (seq-find (lambda (f) (find-font (font-spec :family f)))
                              '("JetBrains Mono" "SF Mono" "Menlo"))))
    (set-face-attribute 'default nil :family font :height 130)))

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


;;;; 6. Language server: Eglot + clangd (built in) ------------------------------
;; Gives completion, diagnostics, go-to-definition, references, rename,
;; quick fixes, inlay hints and formatting for C / C++.

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
  (eglot-ignored-server-capabilities '(:documentOnTypeFormattingProvider))
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

(defun my/project-file-buffers (root)
  "Open buffers visiting files in ROOT, most recently used first."
  (seq-filter (lambda (buf)
                (equal root (with-current-buffer buf (my/buffer-project-root))))
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
                          (delq nil (mapcar (lambda (b) (with-current-buffer b (my/buffer-project-root)))
                                            (buffer-list))))))
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
    (cond (open (switch-to-buffer (car open)))   ; already open: just switch to it
          ((my/session-restore root))
          (t (let ((readme (seq-find #'file-exists-p
                                     (mapcar (lambda (n) (expand-file-name n dir))
                                             '("README.md" "README" "readme.md")))))
               (if readme (find-file readme) (dired dir)))))
    (my/session-touch root)
    (when (project-current) (my/explorer-show))))

(defun my/open-recent-file (file)
  "File > Open Recent: open FILE. If its folder isn't open yet, also reopen
the other files you had open there."
  (let ((root (my/project-root-of file)))
    (if (or (null root) (my/project-file-buffers root))
        (find-file file)
      (setq my/explorer-shown-once t)
      (my/session-restore root file)
      (my/session-touch root)
      (my/explorer-show))))
(setq recentf-menu-action #'my/open-recent-file)

(defun my/close-folder ()
  "Cmd+K F like VS Code: close the current folder's files and the explorer.
They come back the next time you open the folder."
  (interactive)
  (let ((root (or (my/buffer-project-root)
                  (with-current-buffer (my/task-buffer) (my/buffer-project-root))
                  (user-error "No folder is open"))))
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


(use-package eat
  :ensure t
  :bind ("C-`" . eat-project))          ; Ctrl+`  terminal in the project root


;;;; 11. Debugger: Dape + lldb-dap ----------------------------------------------
;; Build with debug info first (-g, or CMAKE_BUILD_TYPE=Debug).
;; F5 (build + debug the current file) is in section 12.
;; In other buffers F5 asks for a config, e.g.   lldb-dap :program "build/app"

(use-package dape
  :ensure t
  :bind (("S-<f5>"  . dape-quit)                  ; Shift+F5  stop
         ("<f9>"    . dape-breakpoint-toggle)     ; F9        breakpoint
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
;;                  Program output shows in *dape-repl* (see `my/debug-in-terminal').
;;
;; Default for any C / C++ file:
;;   clang -g -O0 -Wall <compile_flags.txt> FILE -o build/FILE-without-.c
;;
;; A project can replace the defaults in its .dir-locals.el:
;;   %f = current file, relative to the project root  (VS Code ${relativeFile})
;;   %e = the same without the extension
;;   %p = the program the file belongs to: the nearest folder at or above
;;        it that has a main.c (e.g. programs/hello). In a file outside
;;        any program (e.g. shared code), the last program used.
;;   ((nil . ((my/build-command . "./scripts/build.sh %f")
;;            (my/run-command   . "./scripts/run.sh %f")
;;            (my/debug-program . "build/%e"))))
;; Whole project (a Makefile builds all files into one program):
;;   ((nil . ((my/build-command . "make")
;;            (my/run-command   . "make run")
;;            (my/debug-program . "build/app"))))
;; Many programs, one per folder with a main.c:
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

(defun my/program-folder (file root)
  "Program FILE belongs to, relative to ROOT: the nearest folder at or
above FILE that has a main.c. Outside any program, the last one used."
  (let ((dir (locate-dominating-file file "main.c")))
    (if (and dir (file-in-directory-p dir root))
        (setf (alist-get root my/last-program nil nil #'equal)
              (directory-file-name (file-relative-name dir root)))
      (or (alist-get root my/last-program nil nil #'equal)
          (user-error "Not inside a program: open a file in a folder that has a main.c")))))

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

(defvar my/debug-in-terminal nil
  "Non-nil: run the debugged program in its own terminal buffer (`:runInTerminal'),
so it can read keyboard input. Off by default: with Apple's lldb-dap this
mode often fails with \"Timed out trying to get messages from the
runInTerminal launcher\". Without it, program output shows in *dape-repl*.")
(put 'my/debug-in-terminal 'safe-local-variable #'booleanp) ; can be set per project

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
      (let ((spec (format "lldb-dap :program %S%s%s"
                          (expand-file-name (cdr program) (car program))
                          (if my/debug-in-terminal " :runInTerminal t" "")
                          (if build (format " compile %S" (cdr build)) ""))))
        (pcase-let ((`(,key ,config) (dape--config-from-string spec)))
          (let ((default-directory (car program)))
            (dape (dape--config-eval key config))))))
     (t (call-interactively #'dape)))))

(keymap-global-set "s-B"   #'my/build)                    ; Cmd+Shift+B
(keymap-global-set "C-M-n" #'my/run)                      ; Ctrl+Option+N
(keymap-global-set "<f5>"  #'my/debug-start-or-continue)  ; F5


;;;; 13. VS Code look ----------------------------------------------------------

;; Colours.
;;   Light: Modus Operandi. Built into Emacs, the light theme most Emacs
;;          users run, designed for high contrast and readability.
;;   Dark:  VS Code "Dark+".
;; Cmd+K Cmd+T switches between them.
(defvar my/theme-mode 'light
  "Theme at startup: `light', `dark', or `system' (follow macOS appearance).")
(defvar my/light-theme 'modus-operandi)
(defvar my/dark-theme 'vscode-dark-plus)

(use-package vscode-dark-plus-theme :ensure t :defer t)

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

(add-hook 'comint-mode-hook
          (lambda ()
            (add-hook 'context-menu-functions #'my/context-menu-clear 90 t)))
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

")

;; Package installs print warnings meant for package authors.
;; Never open a window for them (they stay in their buffers).
(add-to-list 'display-buffer-alist
             '("\\`\\*\\(Compile-Log\\|Async-native-compile-log\\)\\*\\'"
               (display-buffer-no-window) (allow-no-window . t)))
(setq warning-minimum-level :error)     ; only real errors pop up

;; Bottom panel: terminal, build / run output, problems -- one strip.
(defconst my/panel-regexp
  "\\`\\*\\(compilation\\|.*eat\\|Flymake diagnostics.*\\|xref\\)\\*\\'")
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

;; Icons (need the Nerd Font from the top of this file).
(use-package nerd-icons :ensure t :defer t)

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
  ;; files (other folders' files stay open in the background).
  (setq centaur-tabs-buffer-groups-function
        (lambda () (list (or (my/buffer-project-root) "Other")))
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
