;; init.el --- Emacs configuration -*- lexical-binding: t; -*-
;;; core
;;;; package setup
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(defvar use-package-always-ensure) ; Silence byte-compiler warning
(setq use-package-always-ensure t)
(unless package-archive-contents
  (package-refresh-contents))

;;;; gcmh - more garbage collection
(use-package gcmh
  :defines (gcmh-high-cons-threshold)
  :functions (gcmh-mode)
  :config
  (setq gcmh-high-cons-threshold (* 64 1024 1024))
  (gcmh-mode 1))

;;;; no-littering (redirects backups, autosaves, and caches)
(use-package no-littering
  :config
  (require 'no-littering)
  ;; Disable lockfiles (.#filename)
  (setq create-lockfiles nil)

  ;; Redirect backup files (filename~) to ~/.emacs.d/var/backup/
  (setq make-backup-files t
        version-control t
        delete-old-versions t
        kept-new-versions 6
        kept-old-versions 2
        backup-directory-alist `((".*" . ,(no-littering-expand-var-file-name "backup/"))))

  ;; Redirect auto-save files (#filename#) to ~/.emacs.d/var/auto-save/
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t))))

;;;; identity
(setq user-full-name "Justin Troth"
      user-mail-address "justin.troth@gd-ms.com")

;;;; tab settings
(setq-default indent-tabs-mode nil)
(setq-default tab-width 2)

;;; ui
;;;; catppuccin Theme
(use-package catppuccin-theme
  :custom
  (catppuccin-flavor 'macchiato)
  :config
  (load-theme 'catppuccin t))

;;;; menus and layout
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(require 'display-line-numbers)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)
(add-hook 'prog-mode-hook #'display-fill-column-indicator-mode)
(setq display-fill-column-indicator-column 80)
(setq sentence-end-double-space nil)

;;;; Window size at launch
(setq initial-frame-alist '((width . 180) (height . 41)))
(setq default-frame-alist initial-frame-alist)

;;;; Soft wrap + navigate visual lines (not logical lines)
(global-visual-line-mode 1)
(setq-default truncate-lines nil)

;;;; Auto revert buffers, ask when modified
(use-package autorevert
  :ensure nil
  :custom
  ;; Do not attempt to auto-revert lockfiles or temporary files
  (auto-revert-skip-requirements-file-regexp "\\(?:\\`\\.#\\|~\\|#\\)")
  ;; Silence message output during auto-reverts
  (auto-revert-verbose nil))
(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t)
(setq auto-revert-use-notify t)
(save-place-mode 1)
(undelete-frame-mode 1)

;;;; tabs & tab-line keybindings
(defvar-local my/buffer-last-edit-time nil
  "Timestamp of the most recent edit to this buffer.")

(defun my/record-buffer-edit ()
  "Record timestamp when a buffer is modified or opened."
  (setq my/buffer-last-edit-time (float-time)))

;; Track edits on first modification, save, or file visit (zero per-keystroke overhead)
(add-hook 'first-change-hook #'my/record-buffer-edit)
(add-hook 'after-save-hook   #'my/record-buffer-edit)
(add-hook 'find-file-hook    #'my/record-buffer-edit)

(defun my/buffer-edit-time (buf)
  "Return timestamp of last edit for BUF (or disk modtime, or 0.0)."
  (if (buffer-live-p buf)
      (with-current-buffer buf
        (or my/buffer-last-edit-time
            (when-let ((file (buffer-file-name buf)))
              (when (file-exists-p file)
                (float-time (file-attribute-modification-time (file-attributes file)))))
            0.0))
    0.0))

(defun my/tab-line-persp-buffers ()
  "Return window buffers scoped to active perspective, sorted by most recently edited."
  (let* ((win-bufs (tab-line-tabs-window-buffers))
         (persp-bufs (when (and (bound-and-true-p persp-mode)
                                (fboundp 'persp-current-buffers))
                       (persp-current-buffers)))
         ;; 1. Only show buffers belonging to the current perspective
         (scoped-bufs (if persp-bufs
                          (seq-filter (lambda (b) (member b persp-bufs)) win-bufs)
                        win-bufs))
         ;; 2. Filter out internal buffers and Magit buffers
         (live-bufs (seq-filter (lambda (b)
                                  (and (buffer-live-p b)
                                       (not (string-prefix-p " " (buffer-name b)))
                                       ;; Exclude Magit modes and buffer names
                                       (not (with-current-buffer b
                                              (derived-mode-p 'magit-mode 'magit-section-mode)))
                                       (not (string-match-p "\\`magit" (buffer-name b)))))
                                scoped-bufs))
         ;; 3. Filter out *special* buffers if normal file tabs are open
         (file-bufs (seq-filter (lambda (b)
                                  (not (string-match-p "\\`\\*.*\\*\\'" (buffer-name b))))
                                live-bufs))
         (cand-bufs (cond
                     (file-bufs
                      (if (and (buffer-live-p (current-buffer))
                               (not (member (current-buffer) file-bufs))
                               (not (string-prefix-p " " (buffer-name))))
                          (append file-bufs (list (current-buffer)))
                        file-bufs))
                     (live-bufs live-bufs)
                     (t (list (current-buffer))))))
    ;; 4. Sort tabs by most recently edited (newest on the left)
    (sort (copy-sequence cand-bufs)
          (lambda (a b)
            (> (my/buffer-edit-time a)
               (my/buffer-edit-time b))))))

(use-package tab-line
  :ensure nil
  :functions (tab-line-switch-to-prev-tab
              tab-line-switch-to-next-tab
              tab-line-close-tab)
  :init
  (global-tab-line-mode 1)
  :custom
  (tab-line-tabs-function #'my/tab-line-persp-buffers)
  (tab-line-tab-name-function #'tab-line-tab-name-buffer)
  :config
  (with-eval-after-load 'general
    (general-def :keymaps 'override :states '(normal motion visual)
      "H" #'tab-line-switch-to-prev-tab
      "L" #'tab-line-switch-to-next-tab)))

;;;; font
(set-face-attribute 'default nil
                    :font "JetBrains Mono"
                    :height 100)

;; Fallback for unicode characters
(set-fontset-font t 'unicode "Noto Sans" nil 'append)

;;;; typing
(electric-pair-mode 1)

;;;; visual arrow replacement (non-destructive)
(setq-default prettify-symbols-alist
              '(("-->" . ?→)
                ("<--" . ?←)
                ("==>" . ?⇒)
                ("<==" . ?⇐)
                ("<=>" . ?⇔)
                ("->>" . ?↠)
                ("<<-" . ?↞)
                ("..." . ?…)))

(global-prettify-symbols-mode 1)

;;;; outline
;;;; outline mode
(defface my/outline-header-face
  '((t :background "#363a6f" :weight bold))
  "Highlighted background for outline section headers.")
(use-package outline
  :ensure nil ; Built-in package
  :functions (outline-cycle outline-cycle-buffer evil-define-key)
  :hook (emacs-lisp-mode . (lambda ()
                             (setq-local outline-regexp ";;;+")
                             (outline-minor-mode 1)
                             (font-lock-add-keywords nil
                                                     '(("^;;;+.*$" 0 'my/outline-header-face prepend)))))
  :config
  (with-eval-after-load 'evil
    (evil-define-key 'normal outline-minor-mode-map
      (kbd "TAB") #'outline-cycle
      (kbd "<backtab>") #'outline-cycle-buffer)))

;;;; popup bottom windows (Doom-style)
(add-to-list 'display-buffer-alist
             '("\\*scratch\\*"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 0)
               (window-height . 0.2)))

(add-to-list 'display-buffer-alist
             '("\\*Async Shell Command\\*"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 1)
               (window-height . 0.2)))

(add-to-list 'display-buffer-alist
             '("\\*eshell\\*"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 2)
               (window-height . 0.2)))

(add-to-list 'display-buffer-alist
             '("\\*terminal\\*"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 3)
               (window-height . 0.2)))

;;;; image size
(setq org-image-actual-width '(100))
(setq image-responsive-width t)
(setq auto-window-vscroll nil)
(setq image-scaling-factor 'auto)
(setq image-use-external-converter nil)

;;; session/workspace persistence
(require 'cl-lib)

(use-package perspective
  :custom
  (persp-mode-prefix-key (kbd "C-c M-p"))
  (persp-initial-frame-name "Main")
  :init
  (persp-mode 1)
  :config
  (setq confirm-kill-processes nil) ; Prevent prompt about active processes on exit

  (defvar my/persp-state-file
    (if (fboundp 'no-littering-expand-var-file-name)
        (no-littering-expand-var-file-name "perspective-state.el")
      (expand-file-name "perspective-state.el" user-emacs-directory)))

  ;; Save silently without overwrite prompts
  (defun my/persp-save-session ()
    "Save perspective state silently without confirmation prompts."
    (interactive)
    (when (bound-and-true-p persp-mode)
      (cl-letf (((symbol-function 'y-or-n-p) #'always)
                ((symbol-function 'yes-or-no-p) #'always))
        (persp-state-save my/persp-state-file))
      (message "Perspective session saved.")))

  ;; Load silently without overwrite prompts
  (defun my/persp-load-session ()
    "Load perspective state silently without confirmation prompts."
    (interactive)
    (when (and (bound-and-true-p persp-mode)
               (file-exists-p my/persp-state-file))
      (cl-letf (((symbol-function 'y-or-n-p) #'always)
                ((symbol-function 'yes-or-no-p) #'always))
        (persp-state-load my/persp-state-file))
      (tab-bar-mode 1)
      (message "Perspective session loaded.")))

  (defun my/quit-emacs ()
    "Save files and workspace state, then quit Emacs with zero prompts."
    (interactive)
    (save-some-buffers t)
    (my/persp-save-session)
    (let ((confirm-kill-emacs nil)
          (confirm-kill-processes nil)
          (kill-emacs-query-functions nil))
      (cl-letf (((symbol-function 'yes-or-no-p) #'always)
                ((symbol-function 'y-or-n-p) #'always))
        (kill-emacs))))

  (defun my/restart-emacs ()
    "Save files and workspace state, then restart Emacs with zero prompts."
    (interactive)
    (save-some-buffers t)
    (my/persp-save-session)
    (let ((confirm-kill-emacs nil)
          (confirm-kill-processes nil)
          (kill-emacs-query-functions nil))
      (cl-letf (((symbol-function 'yes-or-no-p) #'always)
                ((symbol-function 'y-or-n-p) #'always))
        (if (fboundp 'restart-emacs)
            (restart-emacs)
          (kill-emacs)))))

  ;; Auto-save on exit without prompting
  (add-hook 'kill-emacs-hook #'my/persp-save-session)

  ;; Auto-load on startup without prompting
  (add-hook 'emacs-startup-hook #'my/persp-load-session)

  (setq persp-show-modestring nil)

  ;; Generate tab-bar tabs for all perspectives
  (defun my/persp-tab-bar-tabs ()
    "Generate tab-bar tabs from active perspectives."
    (let ((current (persp-current-name)))
      (mapcar (lambda (name)
                (if (string= name current)
                    `(current-tab (name . ,name))
                  `(tab (name . ,name))))
              (persp-names))))

  (setq tab-bar-tabs-function #'my/persp-tab-bar-tabs)

  ;; Enable clicking tabs to switch perspectives
  (defun my/persp-tab-bar-select-tab (orig-fn &optional tab-number)
    (if (bound-and-true-p persp-mode)
        (let* ((names (persp-names))
               (target (nth (1- (or tab-number 1)) names)))
          (when target (persp-switch target)))
      (funcall orig-fn tab-number)))
  (advice-add 'tab-bar-select-tab :around #'my/persp-tab-bar-select-tab))

;;; evil mode
;;;; evil package
(use-package evil
  :defines (evil-normal-state-map
            evil-insert-state-map
            evil-visual-state-map
            evil-inner-text-objects-map
            evil-outer-text-objects-map)
  :functions (evil-mode
              evil-inner-symbol
              evil-a-symbol
              evil-next-visual-line
              evil-previous-visual-line)
  :custom
  (evil-shift-width 2)
  (evil-want-integration t)
  (evil-want-keybinding nil)
  (evil-search-module 'evil-search)
  (evil-symbol-word-search t)
  :config
  (evil-mode 1)
  (define-key evil-inner-text-objects-map "w" #'evil-inner-symbol)
  (define-key evil-outer-text-objects-map "w" #'evil-a-symbol)
  (global-set-key (kbd "C-=") #'global-text-scale-adjust)
  (global-set-key (kbd "C--") #'global-text-scale-adjust)
  (define-key evil-insert-state-map (kbd "C-y") 'yank)
  (with-eval-after-load 'dired
    (evil-define-key 'normal dired-mode-map (kbd "N") 'dired-create-empty-file))
  (evil-define-key 'normal 'global
    "U"     #'undo-redo
    "gq"    #'fill-paragraph
    "j"     #'evil-next-visual-line
    "k"     #'evil-previous-visual-line
    "q"     #'delete-window)
  (evil-define-key 'visual 'global
    "gq"    #'fill-region
    "j"     #'evil-next-visual-line
    "k"     #'evil-previous-visual-line))

;;;; evil collection
(use-package evil-collection
  :after evil
  :functions evil-collection-init
  :config
  (evil-collection-init))

;;;; evil nerd commenter (gcc, gc, gcp, etc)
(use-package evil-nerd-commenter
  :after evil
  :functions (evilnc-comment-operator)
  :config
  (evil-define-key '(normal visual) 'global "gc" #'evilnc-comment-operator))

;;;; evil surround (ys, cs, ds)
(use-package evil-surround
  :after evil
  :functions global-evil-surround-mode
  :config
  (global-evil-surround-mode 1))

;;;; evil-mc
(use-package evil-mc
  :after evil
  :functions (global-evil-mc-mode
              evil-mc-make-cursor-move-next-line
              evil-mc-make-cursor-move-prev-line
              evil-mc-undo-all-cursors)
  :config
  (global-evil-mc-mode 1)
  (evil-define-key '(normal visual) 'global
    (kbd "C-S-j") #'evil-mc-make-cursor-move-next-line
    (kbd "C-S-k") #'evil-mc-make-cursor-move-prev-line
    "," #'evil-mc-undo-all-cursors))

(use-package comp
  :ensure nil ; Built-in
  :custom
  (native-comp-async-report-warnings-errors nil))

;;;; evil org (proper Doom-like org keybinds)
(use-package evil-org
  :after (evil org)
  :functions evil-org-set-key-theme
  :hook (org-mode . evil-org-mode)
  :config
  (evil-org-set-key-theme '(navigation insert textobjects additional calendar return)))

;;;; evil-goggles
(use-package evil-goggles
  :after evil
  :functions evil-goggles-mode
  :custom
  (evil-goggles-duration 0.050)
  (evil-goggles-enable-delete t)
  (evil-goggles-enable-change t)
  (evil-goggles-enable-indent t)
  (evil-goggles-enable-yank t)
  (evil-goggles-enable-join t)
  (evil-goggles-enable-nerd-commenter t)
  :config
  (evil-goggles-mode 1))

;;; dired
(setq dired-dwim-target t)

;;; custom commands
;;;; custom flymake commands
(use-package flymake
  :ensure nil ; Built-in package
  :functions (flymake-diagnostics
              flymake-diagnostic-text)
  :config
  (defun my/yank-flymake-error ()
    "Copy the flymake diagnostic message at point to clipboard."
    (interactive)
    (if-let ((diag (car (flymake-diagnostics (point)))))
        (let ((msg (flymake-diagnostic-text diag)))
          (kill-new msg)
          (message "Copied: %s" msg))
      (message "No diagnostic at point."))))

(defun my/yank-last-five-messages ()
  "Copy the last 5 messages from the *Messages* buffer to the clipboard."
  (interactive)
  (let ((msgs (with-current-buffer "*Messages*"
                (buffer-substring-no-properties
                 (save-excursion (goto-char (point-max)) (forward-line -5) (point))
                 (point-max)))))
    (kill-new msgs)
    (message "Copied last 5 messages.")))

(defun my/safely-close-workspace ()
  "Prompt the user to explicitly confirm before destroying the active workspace."
  (interactive)
  (if (yes-or-no-p "Really delete current tab? ")
      (tab-bar-close-tab)
    (message "Tab deletion canceled.")))

(with-eval-after-load 'ibuffer
  (add-hook 'ibuffer-hook
            (lambda ()
              (when (bound-and-true-p persp-mode)
                (persp-ibuffer-set-filter-groups)))))

;;;; eshell fix
(use-package eshell
  :ensure nil
  :custom
  (eshell-term-name "xterm-256color")
  (eshell-hist-ignoredups t)
  :defines (eshell-mode-map)
  :functions (eshell-send-input
              my/eshell-swap-return-keys)
  :config
  (defun my/eshell-swap-return-keys ()
    (with-eval-after-load 'evil-collection-eshell
      ;; Swap bindings in Evil's insert state for eshell
      (evil-define-key 'insert eshell-mode-map
        (kbd "RET") #'eshell-send-input
        (kbd "<return>") #'eshell-send-input
        (kbd "C-RET") #'newline
        (kbd "C-<return>") #'newline)))
  (add-hook 'eshell-mode-hook #'my/eshell-swap-return-keys))

(defun my/project-frame-isolated-eshell (&optional arg)
  "Open the frame-local Eshell at the current project root."
  (interactive "P")
  (let ((project-root (project-root (project-current t))))
    (if arg
        (let ((default-directory project-root))
          (call-interactively #'eshell))
      (my/frame-isolated-eshell)
      (setq-local default-directory project-root)
      (eshell-reset))))

;;;; custom file commands
(defun my/open-config-file ()
  "Find and open the user's Emacs initialization file."
  (interactive)
  (if-let ((config-file (seq-find #'file-exists-p
                                  '("~/.emacs.d/init.el"
                                    "~/.config/emacs/init.el"
                                    "~/.emacs"))))
      (find-file config-file)
    (message "No Emacs configuration file found!")))

(defun my/yank-file-path ()
  "Copy the path of the current buffer's file to the kill ring."
  (interactive)
  (if-let ((path (buffer-file-name)))
      (progn
        (kill-new path)
        (message "Copied: %s" path))
    (message "Buffer has no file!")))

(defun my/copy-current-file-to-clipboard ()
  "Copy the current buffer's file object to the Wayland clipboard for Dolphin/KDE."
  (interactive)
  (if-let ((path (buffer-file-name)))
      (let ((file-uri (concat "file://" (expand-file-name path))))
        (with-temp-buffer
          (insert file-uri "\n")
          (call-process-region (point-min) (point-max)
                               "wl-copy" nil nil nil
                               "--type" "text/uri-list"))
        (message "Copied file to clipboard: %s" path))
    (message "Buffer is not visiting a file!")))

(defun my/replace-buffer-with-clipboard ()
  "Replace the entire contents of the current buffer with the clipboard."
  (interactive)
  (let ((clip-text (gui-get-selection 'CLIPBOARD 'STRING)))
    (unless (and clip-text (not (string-empty-p clip-text)))
      (user-error "Clipboard is empty!"))
    (erase-buffer)
    (insert clip-text)
    (goto-char (point-min))
    (message "Replaced buffer contents with clipboard.")))

(defun my/format-buffer (&optional start end)
  "Universal format command.
Prioritizes dedicated CLI tools (Typst/Tcl) before falling back to Eglot.
Formats active region if START and END are specified/active, otherwise the whole buffer."
  (interactive "r")
  (let* ((use-region (use-region-p))
         (beg (if use-region start (point-min)))
         (fin (if use-region end (point-max))))
    (cond
     ;; 1. Typst: ALWAYS use typstyle directly (Tinymist/Eglot returns empty edits)
     ((derived-mode-p 'typst-ts-mode)
      (if (executable-find "typstyle")
          (let ((p (point))
                (temp-buffer (generate-new-buffer " *typstyle-temp*")))
            (unwind-protect
                (let ((exit-code (call-process-region beg fin "typstyle" nil temp-buffer nil)))
                  (if (zerop exit-code)
                      (let ((formatted-text (with-current-buffer temp-buffer (buffer-string))))
                        ;; Only replace region/buffer if there is actual content
                        (unless (string-empty-p formatted-text)
                          (delete-region beg fin)
                          (goto-char beg)
                          (insert formatted-text)
                          (goto-char (min p (point-max)))
                          (message "Formatted Typst %s with typstyle." (if use-region "region" "buffer"))))
                    (message "typstyle error: syntax error, region/buffer unchanged.")))
              (kill-buffer temp-buffer)))
        (user-error "typstyle binary not found in PATH!")))

     ;; 2. Tcl & XDC (preserves backslashes and constraints)
     ((derived-mode-p 'tcl-mode)
      (if (executable-find "tcl-format")
          (let ((p (point)))
            (shell-command-on-region beg fin "tcl-format -" nil t)
            (goto-char (min p (point-max)))
            (message "Formatted Tcl %s with tcl-format." (if use-region "region" "buffer")))
        (save-excursion (indent-region beg fin))
        (message "Re-indented Tcl/XDC %s." (if use-region "region" "buffer"))))

     ;; 3. Org Mode: Align tables and indent
     ((derived-mode-p 'org-mode)
      (save-excursion
        (if use-region
            (indent-region beg fin)
          (org-table-map-tables #'org-table-align t)
          (indent-region beg fin)))
      (message "Formatted Org %s." (if use-region "region" "buffer")))

     ;; 4. Emacs Lisp: Clean indentation
     ((derived-mode-p 'emacs-lisp-mode)
      (save-excursion
        (indent-region beg fin))
      (message "Indented Emacs Lisp %s." (if use-region "region" "buffer")))

     ;; 5. Active Eglot LSP (C, C++, Verilog/SystemVerilog)
     ((and (bound-and-true-p eglot--managed-mode)
           (fboundp 'eglot-format))
      (if use-region
          (eglot-format beg fin)
        (call-interactively #'eglot-format))
      (message "Formatted via active Eglot server."))

     ;; 6. C/C++ fallback (if Eglot is offline)
     ((derived-mode-p 'c-mode 'c++-mode 'c-ts-mode 'c++-ts-mode 'c-or-c++-mode)
      (if (executable-find "clang-format")
          (let ((p (point)))
            (shell-command-on-region beg fin "clang-format" nil t)
            (goto-char (min p (point-max)))
            (message "Formatted C/C++ %s with clang-format." (if use-region "region" "buffer")))
        (save-excursion (indent-region beg fin))
        (message "Re-indented C/C++ %s." (if use-region "region" "buffer"))))

     ;; 7. General Fallback
     (t
      (save-excursion
        (indent-region beg fin))
      (message "Indented %s." (if use-region "region" "buffer"))))))

;;;; custom org
(defun my/org-insert-src-block ()
  "Insert a #+begin_src ... #+end_src block directly (equivalent to `C-c C-, s`)."
  (interactive)
  (org-insert-structure-template "src"))

;;;; custom local-dirs
(defun my/create-dir-locals-template ()
  "Generate a standard .dir-locals.el template in the current project root and open it."
  (interactive)
  (let* ((project-root (expand-file-name (or (vc-root-dir) default-directory)))
         (target-file (expand-file-name ".dir-locals.el" project-root))
         (content (format "((nil . ((compile-command . \" \")
         (rsync-remote-paths . (\" \"))
         (rsync-local-path . \"%s/\")
         (rsync-excluded-dirs . (\".git\" \"data\" \".ipynb_checkpoints\" \".pytest_cache\" \"venv\" \"logs\" \"sim/gen\" \"*.vcd\"))
         (rsync-sync-on-save . nil)
         (eval . (progn (require 'rsync-mode) (rsync-mode))))))\n"
                          (directory-file-name project-root))))
    (unless (file-exists-p target-file)
      (with-temp-file target-file
        (insert content))
      (message "Created .dir-locals.el in %s" project-root))
    (find-file target-file)))

(defun my/refresh-project-dir-locals ()
  "Refresh directory-local variables for all open buffers in the current project."
  (interactive)
  (let ((root (expand-file-name (or (vc-root-dir) default-directory))))
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (and buffer-file-name
                   (string-prefix-p root (expand-file-name buffer-file-name)))
          (hack-dir-local-variables-non-file-buffer)
          (message "Refreshed dir-locals for %s" (buffer-name)))))))

(defun my/auto-refresh-dir-locals-on-save ()
  "Reload dir-locals in all matching project buffers after saving .dir-locals.el."
  (when (string-equal (file-name-nondirectory (buffer-file-name)) ".dir-locals.el")
    (my/refresh-project-dir-locals)))

(add-hook 'after-save-hook #'my/auto-refresh-dir-locals-on-save)

;;; general.el (leader key)
(use-package general
  :defines (doom-leader-keys
             doom-local-leader-keys
             general-override-mode-map)
  :functions (general-create-definer
               doom-leader-keys
               doom-local-leader-keys
               general-def)
  :config
  ;; Main leader
  (general-create-definer doom-leader-keys
    :keymaps '(normal visual emacs)
    :prefix "SPC"
    :global-prefix "C-SPC")

  ;; Local leader for org-mode
  (general-create-definer doom-local-leader-keys
    :keymaps 'org-mode-map
    :states '(normal visual emacs)
    :prefix "SPC m"
    :global-prefix "C-SPC m")

  ;;;; SPC overrides in special buffers
  (with-eval-after-load 'dired
    (general-def :states 'normal :keymaps 'dired-mode-map
      "SPC" general-override-mode-map))
  (with-eval-after-load 'help-mode
    (general-def :states 'normal :keymaps 'help-mode-map
      "SPC" general-override-mode-map))

  ;;;; keybinds
  (doom-leader-keys
;;;;; Top Level
    "SPC" '(find-file :which-key "Find file")
    ":"   '(execute-extended-command :which-key "M-x")

;;;;; Quit / Session
    "q"   '(:ignore t :which-key "quit/session")
    "qq"  '(my/quit-emacs :which-key "Quit Emacs")
    "qs"  '(my/persp-save-session :which-key "Save session")
    "ql"  '(my/persp-load-session :which-key "Load session")
    "qr"  '(my/restart-emacs :which-key "Restart Emacs")

;;;;; Files
    "f"   '(:ignore t :which-key "files")
    "ff"  '(find-file :which-key "Find file")
    "fF"  '(project-find-file :which-key "Find file")
    "fh" '((lambda () (interactive) (find-file "~/")) :which-key "Find file from home")
    "fs"  '(save-buffer :which-key "Save file")
    "fS"  '(write-file :which-key "Save file as")
    "fd"  '(dired :which-key "Open dired")
    "fP" '(my/open-config-file :which-key "Open config")
    "fy" '(my/yank-file-path :which-key "Yank file path")
    "fY" '(my/copy-current-file-to-clipboard :which-key "Copy file to clipboard")
    "fr" '(my/replace-buffer-with-clipboard :which-key "Replace file contents with clipboard")

;;;;; Buffers
    "b"   '(:ignore t :which-key "buffers")
    "bb"  '(my/consult-workspace-buffer :which-key "Switch workspace buffer")
    "bB"  '(my/consult-global-buffer :which-key "Switch global buffer")
    "bk"  '(persp-kill-buffer* :which-key "Kill buffer (this workspace)")
    "bc"  '(persp-remove-buffer :which-key "Remove buffer from workspace")
    "bi"  '(ibuffer :which-key "List all buffers")
    "bd"  '(bury-buffer :which-key "Bury buffer")
    "br"  '(revert-buffer :which-key "Revert buffer")
    "bm"  '((lambda () (interactive) (switch-to-buffer "*Messages*")) :which-key "Messages buffer")

;;;;; Windows
    "w"   '(:ignore t :which-key "windows")
    "wv"  '(split-window-right :which-key "Split vertical")
    "ws"  '(split-window-below :which-key "Split horizontal")
    "wh"  '(windmove-left :which-key "Window left")
    "wl"  '(windmove-right :which-key "Window right")
    "wk"  '(windmove-up :which-key "Window up")
    "wj"  '(windmove-down :which-key "Window down")
    "wm"  '(toggle-frame-maximized :which-key "Maximize frame")
    "wf"  '(toggle-frame-fullscreen :which-key "Fullscreen")
    "wc"  '(delete-window :which-key "Delete current window")

;;;;; Spellchecking
    "s"   '(:ignore t :which-key "spellcheck / search")
    "st"  '(flyspell-mode :which-key "Toggle spellcheck")
    "sn"  '(flyspell-goto-next-error :which-key "Next spelling error")
    "sc"  '(flyspell-correct-word-before-point :which-key "Correct word at point")

;;;;; Search
    "ss"  '(consult-line :which-key "Search line in buffer")
    "s/"  '(consult-ripgrep :which-key "Find in project")
    "so"  '(occur :which-key "Find in buffer")
    "si"  '(consult-imenu :which-key "Jump to symbol")
    "sr"  '(query-replace :which-key "Find & replace buffer")
    "sR"  '(project-query-replace-regexp :which-key "Find & replace project")

;;;;; Help
    "h"   '(:ignore t :which-key "help")
    "hk"  '(describe-key :which-key "Describe key")
    "hf"  '(describe-function :which-key "Describe function")
    "hv"  '(describe-variable :which-key "Describe variable")
    "hm"  '(describe-mode :which-key "Describe mode")
    "ha"  '(apropos-command :which-key "Find commands")
    "hw"  '(woman :which-key "Man page (woman)")
    "hr"  '((lambda () (interactive) (load-file user-init-file)) :which-key "Reload config")
    "hy"  '(my/yank-last-five-messages :which-key "Yank last message")

;;;;; Code
    "c"   '(:ignore t :which-key "code")
    "cc"  '(project-compile :which-key "Compile")
    "ck"  '(kill-compilation :which-key "Kill compilation")
    "cw"  '(delete-trailing-whitespace :which-key "Delete whitespace")

;;;;; Errors (flymake)
    "ce"  '(:ignore t :which-key "errors")
    "cen" '(flymake-goto-next-error :which-key "Next error")
    "cep" '(flymake-goto-prev-error :which-key "Prev error")
    "cel" '(flymake-show-buffer-diagnostics :which-key "List errors")

;;;;; LSP (eglot)
    "l"   '(:ignore t :which-key "lsp")
    "ll"  '(eglot :which-key "Start LSP")
    "lr"  '(eglot-rename :which-key "Rename symbol")
    "lf"  '(my/format-buffer :which-key "Format buffer")
    "la"  '(eglot-code-actions :which-key "Code actions")
    "lq"  '(eglot-shutdown :which-key "Stop LSP")
    "ld"  '(flymake-show-buffer-diagnostics :which-key "Show diagnostics")
    "ly"  '(my/yank-flymake-error :which-key "Yank error message")

;;;;; Global Search/Jump (SPC g)
    "g"   '(:ignore t :which-key "search/jump")
    "gw"  '(my/helix-gw :which-key "Jump to 3-char sequence")
    "gd"  '(xref-find-definitions :which-key "Go to definition")
    "gl"  '(git-link :which-key "Copy web link to line")

;;;;; Git (magit)
    "gi"   '(magit-status :which-key "magit status")

;;;;; Terminals / Open
    "o"   '(:ignore t :which-key "open")
    "ot"  '(term :which-key "Open term")
    "oe"  '(my/project-frame-isolated-eshell :which-key "Open eshell in project")

;;;;; Notes
    "n"  '(org-capture :which-key "New note")

;;;;; Workspaces (t)
    "t"   '(:ignore t :which-key "workspaces")
    "tt"  '(persp-switch :which-key "Switch or create workspace")
    "to"  '(persp-switch :which-key "New workspace")
    "td"  '(persp-kill :which-key "Delete workspace")
    "tr"  '(persp-rename :which-key "Rename workspace")
    "tl"  '(persp-next :which-key "Next workspace")
    "th"  '(persp-prev :which-key "Prev workspace")
    )

;;;;; org mode keybinds
  (doom-local-leader-keys
;;;;;; Top-Level Essentials (High Frequency)
    "c"   '(my/org-insert-src-block :which-key "Insert src block") ; <-- Instant #+begin_src
    "'"   '(org-edit-special :which-key "Edit code block")
    "v"   '(org-toggle-inline-images :which-key "Toggle images")
    "t"   '(org-todo :which-key "Cycle TODO state")
    "e"   '(org-export-dispatch :which-key "Export")

;;;;;; Insert (i) - Used heavily
    "i"   '(:ignore t :which-key "insert")
    "ii"  '(org-insert-structure-template :which-key "Template/block")
    "ih"  '(org-insert-heading :which-key "Heading")
    "is"  '(org-insert-subheading :which-key "Subheading")
    "it"  '(org-toggle-heading :which-key "Toggle heading")
    "im"  '(yank-media :which-key "Paste media")

;;;;;; Tables (T) - Isolated from Babel
    "T"   '(:ignore t :which-key "tables")
    "T-"  '(org-table-insert-hline :which-key "Insert hline")
    "Ta"  '(org-table-align :which-key "Align table")
    "Tr"  '(org-table-insert-row :which-key "Insert row")
    "Tc"  '(org-table-insert-column :which-key "Insert column")
    "Tdc" '(org-table-delete-column :which-key "Delete column")

;;;;;; Babel / Code Blocks (b)
    "b"   '(:ignore t :which-key "babel")
    "bb"  '(org-babel-execute-src-block :which-key "Execute block")
    "bt"  '(org-babel-tangle :which-key "Tangle")

;;;;;; Dates & Deadlines (d)
    "d"   '(:ignore t :which-key "dates")
    "dd"  '(org-deadline :which-key "Deadline")
    "ds"  '(org-schedule :which-key "Schedule")
    "dt"  '(org-time-stamp :which-key "Timestamp")
    ))

;;; org mode
(use-package org
  :ensure nil ; Built-in package
  :init
  ;; Helper functions defined before hooks/binds use them
  (defun my/auto-insert-org-template ()
    "Insert default Org header if new .org file is empty."
    (when (and (buffer-file-name)
               (string-match-p "\\.org\\'" (buffer-file-name))
               (= (buffer-size) 0))
      (insert "#+title: " (file-name-base (buffer-file-name)) "\n"
              "#+author: " user-full-name "\n"
              "#+date: " (format-time-string "<%Y-%m-%d %a %H:%M>") "\n\n")))

  (defun my/org-find-class-headline ()
    "Prompt for a class code, store it for the header function, and locate or create its headline."
    (let ((class-code (completing-read "Class Code: " '("CSCI5607" "EE5301" "EE5327" "EE8350"))))
      (org-capture-put :class-code class-code)
      (goto-char (point-min))
      (if (re-search-forward (format org-complex-heading-regexp-format (regexp-quote class-code)) nil t)
          (goto-char (line-beginning-position))
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert "* " class-code "\n")
        (forward-line -1))))

  (defun my/org-class-lecture-header ()
    "Retrieve the stored class code, find highest lecture number, and return header with that + 1."
    (let* ((class-code (org-capture-get :class-code))
           (file (expand-file-name "~/org/notes.org"))
           (next-num
            (if (file-exists-p file)
                (with-current-buffer (find-file-noselect file)
                  (save-excursion
                    (goto-char (point-min))
                    (let ((max-num 0)
                          (re (format "^\\*+\\s-+%s\\s-+Lecture\\s-+\\([0-9]+\\)"
                                      (regexp-quote class-code))))
                      (while (re-search-forward re nil t)
                        (setq max-num (max max-num (string-to-number (match-string 1)))))
                      (1+ max-num))))
              1)))
      (format "%s Lecture %d :2026F:%s:" class-code next-num class-code)))

  :hook (find-file . my/auto-insert-org-template)
  :custom
  (org-directory "~/org")
  (org-hide-leading-stars t)
  (org-startup-indented t)
  (org-log-done 'time)
  (org-return-follows-link t)
  (org-hide-emphasis-markers t)
  (org-pretty-entities t)
  (org-use-sub-superscripts '{})
  (org-cycle-level-after-item/entry-creation t)
  (org-blank-before-new-entry '((heading . auto)
                                (plain-list-item . nil)))(org-cycle-emulate-tab nil)

  (org-agenda-files '("~/org/todo.org"
                      "~/org/meetings"
                      "~/org/notes.org"))
  (org-todo-keywords
   '((sequence "TODO(t)" "PLANNING(p)" "IN-PROGRESS(i@/!)" "VERIFYING(v!)" "BLOCKED(b@)" "|" "DONE(d!)" "OBE(o@!)" "WONT-DO(w@/!)")))
  (org-capture-templates
   '(("m" "Meeting" entry
      (file+olp+datetree "~/org/meetings.org")
      "* %^{Meeting title} %? :meeting:\n:ATTENDEES: %^{Attendees (comma separated)}\n\n** Notes\n- \n\n** Action Items\n*** TODO [#A] "
      :tree-type week
      :clock-in t
      :clock-resume t
      :empty-line 0)

     ("t" "Todo" entry
      (file+headline "~/org/todo.org" "Tasks")
      "* TODO %^{Task}\nSCHEDULED: %^t DEADLINE: %^t\n-  %?\n"
      :empty-lines-before 1
      :empty-lines-after 0)

     ("j" "Work Log Entry" item
      (file+datetree "~/org/work-log.org")
      "- %?"
      :empty-lines 0)

     ("c" "Class Lecture Note" entry
      (file+function "~/org/notes.org" my/org-find-class-headline)
      "* %(my/org-class-lecture-header)\nENTERED: %U\n\n- %?\n"
      :empty-lines 1)

     ("n" "Quick Note" entry
      (file+datetree "~/org/notes.org")
      "* %^{Title}\n%T\n\n%?\n"
      :empty-lines 0)))
  (org-html-head
   "<style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
          line-height: 1.6;
          max-width: 40rem;
          margin: 40px auto;
          padding: 0 10px;
          color: #333;
          background-color: #fdfdfd;
        }
        h1, h2, h3 { line-height: 1.2; color: #111; }
        code { background: #f4f4f4; padding: 2px 5px; border-radius: 3px; font-size: 85%; }
        pre { background: #f4f4f4; padding: 1rem; overflow-x: auto; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { padding: 10px; border-bottom: 1px solid #ddd; text-align: left; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .todo { color: #d9534f; font-weight: bold; }
        .done { color: #5cb85c; font-weight: bold; }
       </style>")
  :config
  ;; Code/functions that need execution go in :config
  (set-face-attribute 'org-level-1 nil :height 1.4 :weight 'bold)
  (set-face-attribute 'org-level-2 nil :height 1.3 :weight 'bold)
  (set-face-attribute 'org-level-3 nil :height 1.2 :weight 'bold)
  (set-face-attribute 'org-level-4 nil :height 1.1)
  (set-face-attribute 'org-level-5 nil :height 1.0)
  (set-face-attribute 'org-document-title nil :height 1.6 :weight 'bold)
  ;; Elevated background pill with bright text
  (set-face-attribute 'org-table nil
                      :foreground (catppuccin-get-color 'lavender)
                      :background (catppuccin-get-color 'surface0)
                      :weight 'normal))

(use-package ox
  :ensure nil
  :defines (org-export-output-file-name-function)
  :config
  (setq org-export-output-file-name-function
        (lambda (extension &optional _subtreep _pub-dir)
          (expand-file-name
           (concat (file-name-base (buffer-file-name)) extension)
           (let ((dir (expand-file-name "~/org/export/")))
             (unless (file-exists-p dir)
               (make-directory dir t))
             dir)))))

;;;; org-modern
(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-star '("◉" "○" "◆" "◇" "▶"))   ; custom heading bullets
  (org-modern-list '((?- . "•") (?+ . "◦") (?* . "▸")))  ; list markers
  (org-modern-checkbox '((?  . "☐") (?X . "☑") (?- . "◫")))
  (org-modern-table nil)                      ; <-- Completely disable org-modern's table styling
  (org-modern-block-name t)
  (org-modern-todo-faces
   '(("TODO"        . (:background "GoldenRod"  :foreground "black" :weight bold))
     ("PLANNING"    . (:background "DeepPink"   :foreground "white" :weight bold))
     ("IN-PROGRESS" . (:background "Cyan"       :foreground "black" :weight bold))
     ("VERIFYING"   . (:background "DarkOrange" :foreground "black" :weight bold))
     ("BLOCKED"     . (:background "Red"        :foreground "white" :weight bold))
     ("DONE"        . (:background "LimeGreen"  :foreground "black" :weight bold))
     ("OBE"         . (:background "LimeGreen"  :foreground "black" :weight bold))
     ("WONT-DO"     . (:background "LimeGreen"  :foreground "black" :weight bold))))
  :custom-face
  (org-modern-label ((t (:height 0.9 :weight bold :inherit nil)))))

;;;; org special export without html links
(use-package ox-gfm
  :after org
  :defines (org-export-with-drawers
            org-export-with-clocks
            org-export-filter-final-output-functions)
  :functions (org-element-map
                 org-element-parse-buffer
                 org-element-property
               org-element--property
               org-parse-time-string
               my/ox-gfm-fix-links)
  :init
  (require 'org-element)
  :config
  (require 'ox)

  (setq org-export-with-drawers t)
  (setq org-export-with-clocks t)

  (defun my/ox-gfm-fix-links (output backend info)
    "Strip Org anchor tags, fix TOC links, and inject LOGBOOK clock date."
    (when (eq backend 'gfm)
      ;; Remove <a id="orgXXX"></a> anchors
      (setq output (replace-regexp-in-string
                    "<a id=\"org[^\"]*\"></a>\n?" "" output))
      ;; Convert [Title](#orgXXX) -> plain text
      (setq output (replace-regexp-in-string
                    "\\[\\([^]]+\\)\\](#org[a-z0-9]+)" "\\1" output))
      ;; Parse LOGBOOK from source buffer and inject date under matching headings
      (with-current-buffer (plist-get info :input-buffer)
        (org-element-map (org-element-parse-buffer) 'headline
          (lambda (hl)
            (let* ((title (org-element-property :raw-value hl))
                   (drawer (car (org-element-map hl 'drawer
                                  (lambda (d)
                                    (when (string= (org-element-property :drawer-name d)
                                                   "LOGBOOK")
                                      d))
                                  nil t)))
                   (clock-el (when drawer
                               (car (org-element-map drawer 'clock #'identity nil t))))
                   (ts (when clock-el
                         (org-element-property :value clock-el)))
                   (date-str (when ts
                               (format-time-string
                                "%Y-%m-%d %A"
                                (encode-time
                                 (org-parse-time-string
                                  (org-element-property :raw-value ts)))))))
              (when (and title date-str)
                (setq output
                      (replace-regexp-in-string
                       (concat "\\(^#+ " (regexp-quote title) "$\\)")
                       (concat "\\1\n\n**Date:** " date-str)
                       output)))))))
      output))

  (add-to-list 'org-export-filter-final-output-functions
               #'my/ox-gfm-fix-links))

;;; additional packages
;;;; which-key
(use-package which-key
  :init
  (setq which-key-idle-delay 0.2)   ; Set your preferred delay here (e.g., 0.0 for instant popup)
  :config
  (setq which-key-side-window-location 'bottom
        which-key-popup-type 'side-window
        which-key-side-window-max-height 0.25
        which-key-separator " ? "
        which-key-prefix-prefix "")
  (which-key-mode 1))

;;;; Two-Tier Workspace/Buffer Tabs
(use-package tab-bar
  :ensure nil
  :functions (catppuccin-get-color)
  :init
  (tab-bar-mode 1)
  :custom
  (tab-bar-new-tab-to 'right)
  (tab-bar-drag-to-move-tabs t)      ; <-- Allows dragging workspace tabs with the mouse!
  (tab-bar-new-tab-choice "*scratch*") ; Start new tabs in *scratch* to avoid cloning buffers
  (tab-bar-tabs-function #'my/persp-tab-bar-tabs)
  :config
  ;; Enhance Active Tab Visibility
  (let ((bg-active    (catppuccin-get-color 'mauve))    ; Active tab background
        (fg-active    (catppuccin-get-color 'crust))    ; Active tab text
        (bg-inactive  (catppuccin-get-color 'surface0)) ; Inactive tab background (Tone 1)
        (fg-inactive  (catppuccin-get-color 'text))     ; Inactive tab text
        (bg-bar       (catppuccin-get-color 'crust)))   ; Empty bar background (Tone 2)
    ;; Styling for the currently active tab
    (set-face-attribute 'tab-bar-tab nil
                        :background bg-active
                        :foreground fg-active
                        :weight 'bold
                        :box `(:line-width (6 . 3) :color ,bg-active))
    ;; Styling for all inactive tabs
    (set-face-attribute 'tab-bar-tab-inactive nil
                        :background bg-inactive
                        :foreground fg-inactive
                        :weight 'normal
                        :box `(:line-width (6 . 3) :color ,bg-inactive))
    ;; Styling for the empty remaining space behind the tabs
    (set-face-attribute 'tab-bar nil
                        :background bg-bar
                        :foreground fg-inactive)))

;;;; projectile
(use-package projectile
  :functions (no-littering-expand-var-file-name
              projectile-mode)
  :defines (projectile-mode
            projectile-ignored-projects
            projectile-globally-ignored-directories)
  :init
  ;; Ensure no-littering's target directory exists before projectile tries to write to it
  (make-directory (no-littering-expand-var-file-name "projectile/") t)
  :custom
  (projectile-project-search-path '("~/work/projects/"))
  (projectile-cache-file (no-littering-expand-var-file-name "projectile/cache.eld"))
  (projectile-known-projects-file (no-littering-expand-var-file-name "projectile/bookmarks.eld"))
  (projectile-track-known-projects-automatically t)
  (projectile-enable-caching t)
  (projectile-auto-update-cache t)
  :config
  (projectile-mode 1)
  ;; Ignore ~/.emacs.d as a project root
  (add-to-list 'projectile-ignored-projects (expand-file-name user-emacs-directory))
  (add-to-list 'projectile-globally-ignored-directories user-emacs-directory))

;;;; spellcheck
(use-package flyspell
  :ensure nil ; Built-in package
  :hook ((text-mode . flyspell-mode)
         (prog-mode . flyspell-prog-mode)
         (org-capture-mode . flyspell-mode)) ; Enable in org-capture buffers
  :config
  (setq ispell-program-name "hunspell")
  ;; Optimizations
  (setq flyspell-issue-message-flag nil
        flyspell-issue-welcome-flag nil)
  (setq ispell-local-dictionary-alist
        '(("en_US" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil ("-d" "en_US") nil utf-8))))

;;;; centered cursor
(use-package centered-cursor-mode
  :functions (global-centered-cursor-mode
              centered-cursor-mode)
  :config
  (global-centered-cursor-mode 1)
  (add-hook 'after-change-major-mode-hook
            (lambda ()
              (when (derived-mode-p 'term-mode 'eshell-mode)
                (centered-cursor-mode -1)))))

;;;; vertico (vertical completion UI)
(use-package vertico
  :functions (vertico-mode)
  :defines (vertico-count)
  :init
  (vertico-mode 1)
  (setq vertico-count 15))        ; show 15 candidates at once

;;;; orderless (fuzzy/flex matching)
(use-package orderless
  :config
  (setq completion-styles '(orderless basic)
        completion-category-overrides
        '((file (styles basic partial-completion)))))

;;;; marginalia (annotations on candidates)
(use-package marginalia
  :functions (marginalia-mode)
  :init
  (marginalia-mode 1))

;;;; consult (Search with live previews)
(use-package consult
  :functions (consult-fd consult-find consult-buffer consult--buffer-query)
  :custom
  (consult-narrow-key "<")
  :config
  (require 'consult)

  (defun my/consult-workspace-buffer ()
    "Switch to a normal buffer in the active workspace."
    (interactive)
    (if (and (bound-and-true-p persp-mode)
             (fboundp 'persp-current-buffers))
        (let ((workspace-bufs
               (lambda ()
                 (seq-filter
                  (lambda (buf-name)
                    ;; Exclude special buffers (*...) and hidden buffers ( ...)
                    (and (not (string-prefix-p "*" buf-name))
                         (not (string-prefix-p " " buf-name))))
                  (mapcar #'buffer-name (persp-current-buffers))))))
          (consult-buffer
           (list
            `(:name     "Workspace Buffers"
                        :narrow   ?b
                        :category buffer
                        :face     consult-buffer
                        :history  buffer-name-history
                        :state    ,#'consult--buffer-state
                        :items    ,workspace-bufs)
            (when (boundp 'consult-source-recent-file) consult-source-recent-file)
            (when (boundp 'consult-source-bookmark) consult-source-bookmark))))
      (consult-buffer)))

  (defun my/consult-global-buffer ()
    "Switch to any open buffer across all workspaces."
    (interactive)
    (let ((sources (delq nil
                         (list (when (boundp 'consult-source-buffer)
                                 consult-source-buffer)
                               (when (boundp 'consult-source-recent-file)
                                 consult-source-recent-file)
                               (when (boundp 'consult-source-bookmark)
                                 consult-source-bookmark)))))
      (consult-buffer sources))))

;;;; magit
(use-package magit
  :functions (magit-auto-revert-mode
              my/magit-hide-cursor
              magit-after-save-refresh-status
              magit-mode-bury-buffer
              with-editor-cancel)
  :defines (transient-quit-one
            magit-mode-map
            magit-status-mode-map
            magit-log-mode-map
            magit-diff-mode-map
            magit-refs-mode-map
            magit-revision-mode-map)
  :init
  (setq vc-handled-backends '(Git))
  :config
  (magit-auto-revert-mode 1)
  (add-hook 'magit-mode-hook #'display-line-numbers-mode)

  (defun my/magit-hide-cursor ()
    (setq-local evil-normal-state-cursor '(nil)
                evil-motion-state-cursor '(nil)))
  (add-hook 'magit-mode-hook #'my/magit-hide-cursor)

  ;; Magit's conflict resolver replaces Ediff's normal quit hook.  Restore its
  ;; cleanup so temporary Ediff buffers and the control panel are removed.
  (with-eval-after-load 'magit-ediff
    (add-hook 'magit-ediff-quit-hook #'ediff-cleanup-mess t))

  ;; Explicitly refresh status buffer on save (useful for non-standard file watchers/TRAMP/WSL)
  (add-hook 'after-save-hook #'magit-after-save-refresh-status)
  ;; Unbind SPC in Magit keymaps so Leader key works seamlessly
  (dolist (map (list magit-mode-map
                     magit-status-mode-map
                     magit-log-mode-map
                     magit-diff-mode-map
                     magit-refs-mode-map
                     magit-revision-mode-map))
    (define-key map (kbd "SPC") nil))
  (evil-define-key '(normal visual motion) magit-mode-map (kbd "SPC") nil)
  (evil-define-key '(normal visual) 'global
    (kbd "C-d") (lambda () (interactive) (evil-scroll-down 0) (evil-scroll-line-to-center nil))
    (kbd "C-u") (lambda () (interactive) (evil-scroll-up 0)   (evil-scroll-line-to-center nil)))
  (evil-define-key '(normal visual) 'global "s" #'avy-goto-char-timer)
  (evil-define-key 'normal 'global (kbd "C-s") #'save-buffer)
  (general-def :states 'normal :keymaps 'magit-mode-map
    "q" #'magit-mode-bury-buffer)
  (with-eval-after-load 'git-commit
    (general-def :states 'normal :keymaps 'git-commit-mode-map
      "q" #'with-editor-cancel)))

;;;; diff-hl - Git diff indicators in fringe/gutter
(use-package diff-hl
  :after magit
  :functions (global-diff-hl-mode
              diff-hl-flydiff-mode
              diff-hl-magit-pre-refresh
              diff-hl-magit-post-refresh)
  :init
  (global-diff-hl-mode 1)
  :config
  ;; Update indicators live as you edit (without waiting for buffer save)
  (diff-hl-flydiff-mode 1)
  ;; Integration with Magit: refresh fringe automatically after committing/staging
  (add-hook 'magit-pre-refresh-hook  #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))

;;;; git-link
(use-package git-link)

;;;; avy jumper (helix gw emulator)
(use-package avy
  :defines (avy-all-windows my/helix-gw)
  :functions (avy-with avy-process avy--regex-candidates)
  :custom
  (avy-keys '(?a ?s ?d ?f ?j ?k ?l ?e ?r ?u ?i ?o ?w ?v ?c ?m))
  :config
  (defun my/helix-gw ()
    "Jump to any visible word instantly, mimicking Helix's `gw' command."
    (interactive)
    ;; Force avy to label all words matching a word-boundary regex instantly
    (let ((avy-all-windows t))
      (avy-with my/helix-gw
        (avy-process (avy--regex-candidates "\\b[a-zA-Z0-9_]"))))))

;;;; TCL Support
(use-package tcl
  :ensure nil
  :mode (("\\.tcl\\'" . tcl-mode)
         ("\\.xdc\\'" . tcl-mode)
         ("\\.tm\\'"  . tcl-mode))
  :interpreter ("tclsh" . tcl-mode)
  :config
  (setq tcl-indent-level 2))

;;;; verilog / SystemVerilog Support
(use-package verilog-mode
  :ensure nil
  :functions (my/verilog-font-lock-setup
              my/verilog-indent-bars-setup)
  :mode (("\\.v\\'" . verilog-mode)
         ("\\.sv\\'" . verilog-mode))
  :custom-face
  (verilog-parameter-face ((t :foreground "#cee49f" :weight bold)))
  (verilog-number-face    ((t :foreground "#f5a97f")))
  :config
  (setq verilog-linter "/usr/local/bin/verible-verilog-lint"
        verilog-indent-level 2
        verilog-indent-level-module 2
        verilog-indent-level-declaration 2
        verilog-indent-level-behavioral 2
        verilog-auto-endcomments nil
        verilog-auto-newline nil
        verilog-auto-indent-on-newline nil)

  (defun my/verilog-font-lock-setup ()
    (font-lock-add-keywords nil
                            '(("\\b\\([A-Z][A-Z0-9_]+\\)\\b" 1 'verilog-parameter-face)
                              ("\\b\\([0-9]+\\('[bdh][0-9a-fA-FxXzZ_]+\\)?\\)\\b" 1 'verilog-number-face))
                            'append)) ; Use 'append so syntactic comment/string faces take precedence

  (defun my/verilog-indent-bars-setup ()
    (setq-local indent-bars-spacing-override 2)
    (when (bound-and-true-p indent-bars-mode)
      (indent-bars-mode -1)
      (indent-bars-mode 1)))

  (add-hook 'verilog-mode-hook #'my/verilog-font-lock-setup)
  (add-hook 'verilog-mode-hook #'my/verilog-indent-bars-setup))

;;;; eglot + typst + verilog + c/c++
(use-package eglot
  :hook ((verilog-mode . eglot-ensure)
         (typst-ts-mode . eglot-ensure)
         (c-mode        . eglot-ensure)
         (c++-mode      . eglot-ensure)
         (c-ts-mode     . eglot-ensure)
         (c++-ts-mode   . eglot-ensure))
  :config
  ;; Tinymist language server for Typst
  (add-to-list 'eglot-server-programs
               '((typst-ts-mode) . ("tinymist" :initializationOptions
                                    (:formatterMode "typstyle"))))

  ;; Verible language server for SystemVerilog
  (add-to-list 'eglot-server-programs
               `((verilog-mode) .
                 ,(lambda (_interactive)
                    (let* ((proj (project-current))
                           (root (if proj (project-root proj) default-directory))
                           (project-server
                            (expand-file-name "scripts/verible-ls.sh" root)))
                      (list (if (file-executable-p project-server)
                                project-server
                              "verible-verilog-ls")
                            "--file_list_path"
                            (let ((f (make-temp-file "verible-files")))
                              (with-temp-file f
                                (insert (mapconcat #'identity
                                                   (directory-files-recursively root "\\.s?v$")
                                                   "\n")))
                              f))))))
  (setq eglot-ignored-server-capabilities 
        '(:semanticTokensProvider 
          :workspace/didChangeConfiguration)))

;;;; clangd
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `((c-mode c++-mode c-or-c++-mode)
                 . ("clangd"
                    "--compile-commands-dir=build"
                    "--background-index"
                    "--inlay-hints=true"))))

(add-hook 'c-mode-hook #'eglot-inlay-hints-mode)
(add-hook 'c++-mode-hook #'eglot-inlay-hints-mode)

;;;; corfu
(use-package corfu
  :init
  (global-corfu-mode)
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.5)
  (corfu-auto-prefix 1)
  :config
  (defun my/corfu-enable-in-minibuffer ()
    "Enable Corfu in the minibuffer if completion is supported."
    (unless (bound-and-true-p mct-mode)
      (setq-local corfu-echo-delay nil
                  corfu-popupinfo-delay nil)
      (corfu-mode 1)))
  (add-hook 'minibuffer-setup-hook #'my/corfu-enable-in-minibuffer))

;;;; powerline
(use-package powerline
  :defines (projectile-mode-line-prefix
            projectile-mode-line-function
            powerline-height
            powerline-default-separator)
  :functions (powerline-center-evil-theme
              powerline-reset
              projectile-project-name
              catppuccin-get-color)
  :preface
  (defun my/update-powerline-height ()
    "Set powerline height based on actual rendered font pixel height."
    (let* ((info (font-info (face-font 'default)))
           (pixel-height (+ (aref info 2) (aref info 3)))  ; ascent + descent
           (padding 0))
      (setq powerline-height (+ pixel-height padding))
      (powerline-reset)))
  :custom
  (projectile-mode-line-prefix " ")
  :config
  (setq powerline-default-separator 'bar)
  (my/update-powerline-height)
  (add-hook 'after-make-frame-functions
            (lambda (_) (my/update-powerline-height)))
  (powerline-center-evil-theme)
  (setq projectile-mode-line-function
        (lambda ()
          (format " [%s]" (projectile-project-name))))
  (set-face-attribute 'mode-line nil :height 1.0)
  (set-face-attribute 'mode-line-inactive nil :height 1.0)
  (let ((bar-color (catppuccin-get-color 'pink))
        (dark-fg    (catppuccin-get-color 'crust)))
    (set-face-attribute 'powerline-active0 nil
                        :background bar-color
                        :foreground dark-fg)))

;;;; rainbow delimiters
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;;;; indent-bars - Visual scope lines
(use-package indent-bars
  :functions (indent-bars-mode)
  :hook (prog-mode . indent-bars-mode)
  :custom
  (indent-bars-treesitter-support t)
  (indent-bars-no-descend-string t))

;;;; tldr
(use-package tldr)

;;;; ripgrep
(use-package rg)

;;;; wgrep
(use-package wgrep)

;;;; keyfreq
(use-package keyfreq
  :functions (keyfreq-mode keyfreq-autosave-mode)
  :config
  (keyfreq-mode 1)
  (keyfreq-autosave-mode 1))

;;;; yafolding
(use-package yafolding
  :defines (yafolding-ellipsis-content
            yafolding-mode-map)
  :functions (my/yafolding-pad-ellipsis
              yafolding-toggle-element)
  :hook ((prog-mode . yafolding-mode)
         (emacs-lisp-mode . (lambda () (yafolding-mode -1))))
  :config
  (defun my/yafolding-pad-ellipsis (region)
    "Pad `yafolding-ellipsis-content' to column 80 with line count prefix."
    (when (and region (listp region) (numberp (car region)) (numberp (cadr region)))
      (let* ((beg (car region))
             (end (cadr region))
             (lines-folded (count-lines beg end))
             (line-len (- (line-end-position) (line-beginning-position)))
             (target-col 80)
             (prefix (format " [+%d lines]  " lines-folded))
             (base-suffix "│")
             ;; Only include the suffix if the line length + prefix + suffix fits within 80 characters
             (suffix (if (<= (+ line-len (length prefix) (length base-suffix)) target-col)
                         base-suffix
                       ""))
             (pad-count (max 0 (- target-col line-len (length prefix) (length suffix)))))
        (setq yafolding-ellipsis-content
              (concat prefix (make-string pad-count ?─) suffix))))
    region)

  (advice-add 'yafolding-get-element-region :filter-return #'my/yafolding-pad-ellipsis)

  (set-face-attribute 'yafolding-ellipsis-face nil
                      :background (catppuccin-get-color 'base)
                      :foreground (catppuccin-get-color 'peach)
                      :weight 'bold)

  (with-eval-after-load 'evil
    (evil-define-key 'normal yafolding-mode-map
      (kbd "TAB") #'yafolding-toggle-element)))

;;;; typst
(use-package treesit
  :ensure nil
  :config
  (add-to-list 'treesit-language-source-alist
               '(typst "git@github.com:uben0/tree-sitter-typst.git")))

(use-package typst-ts-mode
  :custom
  (typst-ts-mode-watch-options "--open")
  :hook
  (typst-ts-mode . (lambda ()
                     ;; Match lines starting with one or more '=' followed by whitespace
                     (setq-local outline-regexp "=+\\s-")
                     ;; Define where the heading level ends for proper outline parsing
                     (setq-local outline-heading-end-regexp "\n")
                     (outline-minor-mode 1)
                     ;; Apply custom highlighting face to Typst headers
                     (font-lock-add-keywords nil
                                             '(("^=+\\s-.*$" 0 'my/outline-header-face prepend)))))
  :config
  (add-to-list 'auto-mode-alist '("\\.typ\\'" . typst-ts-mode)))

(use-package websocket)

(use-package typst-preview
  ;; :load-path "path/to/typst-preview.el" ;; if installed manually
  :init
  (setq typst-preview-autostart t) ; start preview automatically when typst-preview-mode is activated
  (setq typst-preview-open-browser-automatically nil) ; open browser automatically when typst-preview-start is run
  (setq typst-preview-host "127.0.0.1:6973")

  :custom
  (typst-preview-browser "default") 	; this is the default option; other options are `eaf-browser' or `xwidget'.
  (typst-preview-invert-colors "true")	; invert colors depending on system theme
  (typst-preview-executable "tinymist") ; path to tinymist binary (relative or absolute)
  (typst-preview-partial-rendering t)   ; enable partial rendering 
  
  :config
  (define-key typst-preview-mode-map (kbd "C-c C-j") 'typst-preview-send-position))

(defun my/org-typst-preview-region (start end)
  "Compile selection to SVG via Typst CLI and display inline."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (tmp-typ (make-temp-file "org-typst-" nil ".typ"))
         (tmp-svg (make-temp-file "org-typst-" nil ".svg")))
    (write-region (concat "$ " text " $") nil tmp-typ)
    (if (zerop (call-process "typst" nil nil nil "compile" tmp-typ tmp-svg))
        (let ((ov (make-overlay start end)))
          (overlay-put ov 'display (create-image tmp-svg 'svg nil :ascent 'center))
          (overlay-put ov 'evaporate t))
      (message "Typst compilation failed."))))

;;;; markdown mode
(use-package markdown-mode
  :mode ("\\.md\\'" . gfm-mode)
  :init
  ;; Use gfm-mode (GitHub Flavored Markdown) for previewing and code block features
  (setq markdown-command "multimarkdown")
  :config
  ;; Enable syntax highlighting inside code blocks in the main buffer
  (setq markdown-fontify-code-blocks-natively t)
  
  ;; Map markdown language identifiers to Emacs major modes
  (setq markdown-code-lang-modes
        '(("elisp" . emacs-lisp-mode)
          ("c++" . c++-mode)
          ("cpp" . c++-mode)
          ("py" . python-mode)
          ("python" . python-mode)
          ("json" . js-mode)
          ("sh" . sh-mode)
          ("bash" . sh-mode))))

;;;; rsync-mode
(use-package rsync-mode
  :commands (rsync-mode rsync-full-sync rsync-incremental-sync)
  :init
  ;; Safe local variable predicates
  (put 'rsync-remote-paths 'safe-local-variable #'listp)
  (put 'rsync-local-path 'safe-local-variable #'stringp)
  (put 'rsync-excluded-dirs 'safe-local-variable #'listp)
  (put 'rsync-sync-on-save 'safe-local-variable #'booleanp)

  ;; Mark specific eval forms as safe
  (put 'eval 'safe-local-variable
       (lambda (val)
         (member val '((progn (require 'rsync-mode) (rsync-mode))))))
  :config
  (setq rsync-mode-arguments '("-azP")))

;;;; custom
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(auth-source-save-behavior nil)
 '(custom-safe-themes
   '("c4df9006b9eb32599d758800a32f3487c2cdf13826084511783b47d419024af2"
     default))
 '(package-selected-packages
   '(catppuccin-theme centered-cursor-mode consult corfu diff-hl evil
                      evil-collection evil-goggles evil-nerd-commenter
                      evil-org evil-surround gcmh general indent-bars
                      keyfreq magit marginalia markdown-mode
                      no-littering orderless org-modern ox-gfm
                      perspective powerline projectile
                      rainbow-delimiters rsync-mode typst-preview
                      typst-ts-mode vertico websocket wgrep which-key
                      yafolding))
 '(safe-local-variable-values
   '((eval add-hook 'after-save-hook #'org-gfm-export-to-markdown nil t))))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-modern-label ((t (:height 0.9 :weight bold :inherit nil)))))
