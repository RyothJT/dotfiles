;; -- Garbage collection ------------------------------------
(setq gc-cons-threshold (* 100 1024 1024)) ; 100 MB
;; Reset it to a reasonable background level after startup completes
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 8 1024 1024)))) ; 8 MB

;; -- Package Setup ------------------------------------------
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(setq use-package-always-ensure t)

(unless package-archive-contents
  (package-refresh-contents))

;; -- Identity -----------------------------------------------
(setq user-full-name "Justin Troth"
      user-mail-address "justin.troth@gd-ms.com")

;; -- UI -----------------------------------------------------
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode t)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)
(add-hook 'prog-mode-hook #'display-fill-column-indicator-mode)
(setopt display-fill-column-indicator-column 80)

;; Window size at launch
(setq initial-frame-alist '((width . 180) (height . 41)))
(setq default-frame-alist initial-frame-alist)

;; Maximize
(add-to-list 'initial-frame-alist '(fullscreen . maximized))

;; Soft wrap + navigate visual lines (not logical lines)
(global-visual-line-mode 1)
(setq-default truncate-lines nil)

;; Auto revert buffers, ask when modified
(setq global-auto-revert-mode t)
(save-place-mode 1)

(undelete-frame-mode 1)

;; -- Font ---------------------------------------------------
(set-face-attribute 'default nil
  :font "JetBrains Mono"
  :height 100)

;; Fallback for unicode characters
(set-fontset-font t 'unicode "Noto Sans" nil 'append)

;; -- Skip special buffers with H/L -------------------------
(defun my/next-buffer ()
  "Go to the next valid user buffer in the current perspective."
  (interactive)
  (let* ((all-buffers (persp-current-buffer-names))
         ;; Filter out any internal system buffers starting with *
         (clean-list (cl-remove-if (lambda (name) (string-match-p "^\\*" name)) all-buffers))
         (current-name (buffer-name (current-buffer)))
         (rotated-list (append (cdr (member current-name clean-list)) clean-list))
         (chosen nil))
    (dolist (name rotated-list)
      (when (and (not chosen)
                 (not (string-equal name current-name)))
        (setq chosen name)))
    (if chosen
        (switch-to-buffer chosen)
      (message "No other user buffers in this perspective."))))

(defun my/prev-buffer ()
  "Go to the previous valid user buffer in the current perspective."
  (interactive)
  (let* ((all-buffers (persp-current-buffer-names))
         ;; Filter out any internal system buffers starting with *
         (clean-list (cl-remove-if (lambda (name) (string-match-p "^\\*" name)) all-buffers))
         (reversed-list (reverse clean-list))
         (current-name (buffer-name (current-buffer)))
         (rotated-list (append (cdr (member current-name reversed-list)) reversed-list))
         (chosen nil))
    (dolist (name rotated-list)
      (when (and (not chosen)
                 (not (string-equal name current-name)))
        (setq chosen name)))
    (if chosen
        (switch-to-buffer chosen)
      (message "No other user buffers in this perspective."))))

;; -- Evil Mode ----------------------------------------------
(use-package evil
  :init
  (setq evil-want-integration t)
  (setq evil-want-keybinding nil)
  (setq evil-search-module 'evil-search)
  :config
  (evil-mode 1)
  (define-key evil-normal-state-map "U" 'undo-redo)
  (global-set-key (kbd "C-=") #'global-text-scale-adjust)
  (global-set-key (kbd "C--") #'global-text-scale-adjust)
  (define-key evil-normal-state-map (kbd "j") 'evil-next-visual-line)
  (define-key evil-normal-state-map (kbd "k") 'evil-previous-visual-line)
  (define-key evil-visual-state-map (kbd "j") 'evil-next-visual-line)
  (define-key evil-visual-state-map (kbd "k") 'evil-previous-visual-line))

;; 1. Make the normal/motion state maps act as high-priority intercepts
(evil-make-intercept-map evil-normal-state-map)
(evil-make-intercept-map evil-motion-state-map)

;; 2. Bind your universal buffer navigation keys
(define-key evil-normal-state-map (kbd "H") #'my/next-buffer)
(define-key evil-normal-state-map (kbd "L") #'my/prev-buffer)
(define-key evil-motion-state-map (kbd "H") #'my/next-buffer)
(define-key evil-motion-state-map (kbd "L") #'my/prev-buffer)

;; -- Evil Collection ----------------------------------------
(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

;; -- Evil Nerd Commenter (gcc, gc, gcp, etc) ---------------
(use-package evil-nerd-commenter
  :after evil
  :config
  (evilnc-default-hotkeys nil t)
  ;; Explicitly bind gc operator in normal and visual
  (define-key evil-normal-state-map (kbd "gc") 'evilnc-comment-operator)
  (define-key evil-visual-state-map (kbd "gc") 'evilnc-comment-operator))

;; -- Evil Surround (ys, cs, ds) ----------------------------
(use-package evil-surround
  :after evil
  :config
  (global-evil-surround-mode 1))

;; -- Session/Workspace Persistence -------------------------
(use-package perspective
  :config
  (setq persp-suppress-no-prefix-key-warning t)
  (persp-mode 1)
  ;; Restores the "+" button on the tab bar
  (setq perspective-show-modestring nil)
  (tab-bar-mode 1)
  (setq tab-bar-format '(tab-bar-format-history 
                         tab-bar-format-tabs 
                         tab-bar-format-add-tab
                         tab-bar-format-align-right 
                         tab-bar-format-global))
  ;; Native Perspective Session Saving (Replaces desktop-mode safely)
  (setq persp-state-default-file (expand-file-name "persp-state" user-emacs-directory))
  ;; Auto-save your workspaces and buffers on exit
  (add-hook 'kill-emacs-hook #'persp-state-save))

(with-eval-after-load 'perspective
  ;; Remove the perspective binding for '/' so Evil search can claim it
  (define-key persp-mode-map (kbd "/") nil))

(defun my/persp-kill-or-remove-current-buffer ()
  "Remove current buffer from the perspective and let perspective.el handle the global kill if unreferenced."
  (interactive)
  (let* ((buf (current-buffer))
         (buf-name (buffer-name buf))
         ;; Gather other valid user buffers in this perspective
         (all-buffers (persp-current-buffer-names))
         (clean-list (cl-remove-if (lambda (name) (string-match-p "^\\*" name)) all-buffers))
         (sibling-user-buffers (cl-remove buf-name clean-list :test #'string-equal))
         (target-fallback (car sibling-user-buffers)))
    ;; 1. Evacuate the window safely within local isolation bounds first
    (if target-fallback
        (switch-to-buffer target-fallback)
      (switch-to-buffer "*scratch*"))
    ;; 2. Hand off the target buffer to perspective's internal reference engine
    (persp-remove-buffer buf)))

;; -- Yank Flymake Error at Point ----------------------------
(defun my/yank-flymake-error ()
  "Copy the flymake diagnostic message at point to clipboard."
  (interactive)
  (if-let ((diag (car (flymake-diagnostics (point)))))
      (let ((msg (flymake-diagnostic-text diag)))
        (kill-new msg)
        (message "Copied: %s" msg))
    (message "No diagnostic at point.")))

;; Yank last minibuffer message to clipboard
(defun my/yank-last-message ()
  "Copy the last message from the minibuffer to clipboard."
  (interactive)
  (let ((msg (current-message)))
    (if msg
        (progn (kill-new msg)
               (message "Copied: %s" msg))
      (message "No message to copy."))))

(defun my/switch-to-buffer ()
  "Switch to a perspective buffer, filtering out special buffers."
  (interactive)
  (let ((completion-regexp-list (cons "^[^*]" completion-regexp-list)))
    (persp-switch-to-buffer* 
     (persp-read-buffer "Switch to buffer: " nil t))))

(defun my/safely-close-workspace ()
  "Prompt the user to explicitly confirm before destroying the active workspace."
  (interactive)
  (if (yes-or-no-p "Really delete current tab? ")
      (tab-bar-close-tab)
    (message "Tab deletion canceled.")))

;; -- General.el (Leader Key) --------------------------------
(use-package general
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

  (doom-leader-keys
    ;; Top Level
    "SPC" '(find-file :which-key "Find file")
    ":"   '(execute-extended-command :which-key "M-x")
    ","   '(my/switch-to-buffer :which-key "Switch buffer")
    "/"   '(grep :which-key "Search project")
    ";"   '(evilnc-comment-operator :which-key "Comment")

    ;; Quit / Session
    "q"   '(:ignore t :which-key "quit/session")
    "qq"  '(save-buffers-kill-terminal :which-key "Quit Emacs")
    "qs"  '(persp-state-save :which-key "Save session")
    "ql"  '(persp-state-load :which-key "Load session")
    "qr"  '(restart-emacs :which-key "Restart Emacs")

    ;; Files
    "f"   '(:ignore t :which-key "files")
    "ff"  '(find-file :which-key "Find file")
    "fF"  '(project-find-file :which-key "Find file")
    "f/"  '(project-find-ripgrep :which-key "Find text in project")
    "fh" '((lambda () (interactive) (find-file "~/")) :which-key "Find file from home")
    "fs"  '(save-buffer :which-key "Save file")
    "fS"  '(write-file :which-key "Save file as")
    "fd"  '(dired :which-key "Open dired")
    "fP" '((lambda ()
	    (interactive)
	    (find-file
	    (seq-find #'file-exists-p
			'("~/.emacs.d/init.el"
			"~/.config/emacs/init.el"
			"~/.emacs"))))
	:which-key "Open config")
    "fD"  '((lambda () (interactive)
          (if (buffer-file-name)
              (when (yes-or-no-p (format "Delete %s? " (buffer-file-name)))
                (delete-file (buffer-file-name))
                (kill-buffer))
            (message "Buffer is not visiting a file!")))
        :which-key "Delete file")
    "fy" '((lambda () (interactive)
          (let ((path (buffer-file-name)))
            (if path
                (progn (kill-new path)
                       (message "Copied: %s" path))
              (message "Buffer has no file!"))))
        :which-key "Yank file path")
    "fY" '((lambda () (interactive)
	    (let ((path (buffer-file-name)))
		(if path
		    (let ((win-path (replace-regexp-in-string
				    "/" "\\\\"
				    (replace-regexp-in-string
				    "^/mnt/\\([a-z]\\)/" "\\1:\\\\"
				    path))))
		    (kill-new win-path)
		    (message "Copied: %s" win-path))
		(message "Buffer has no file!"))))
	    :which-key "Yank Windows path")

    ;; Buffers
    "b"   '(:ignore t :which-key "buffers")
    "bb"  '(my/switch-to-buffer :which-key "Switch buffer")
    "bi"  '(ibuffer :which-key "List all buffers")
    "bd"  '(my/persp-kill-or-remove-current-buffer :which-key "Remove buffer from frame")
    "bc"  '(my/persp-kill-or-remove-current-buffer :which-key "Remove buffer from frame")
    "bn"  '(next-buffer :which-key "Next buffer")
    "bm"  '((lambda () (interactive) (switch-to-buffer "*Messages*")) :which-key "Messages buffer")
    "bp"  '(previous-buffer :which-key "Prev buffer")
    "br"  '(revert-buffer :which-key "Revert buffer")

    ;; Windows
    "w"   '(:ignore t :which-key "windows")
    "wv"  '(split-window-right :which-key "Split vertical")
    "ws"  '(split-window-below :which-key "Split horizontal")
    "ww"  '(other-window :which-key "Other window")
    "wo"  '(delete-other-windows :which-key "Delete other windows")
    "wh"  '(windmove-left :which-key "Window left")
    "wl"  '(windmove-right :which-key "Window right")
    "wk"  '(windmove-up :which-key "Window up")
    "wj"  '(windmove-down :which-key "Window down")
    "wm"  '(toggle-frame-maximized :which-key "Maximize frame")
    "wf"  '(toggle-frame-fullscreen :which-key "Fullscreen")
    "wc"  '(delete-window :which-key "Delete current window")

    ;; Search
    "s"   '(:ignore t :which-key "search")
    "ss"  '(occur :which-key "Search buffer")
    "sg"  '(grep :which-key "Grep")
    "si"  '(imenu :which-key "Jump to symbol")
    "sr"  '(query-replace :which-key "Find & replace buffer")
    "sR"  '(project-query-replace-regexp :which-key "Find & replace project")

    ;; Help
    "h"   '(:ignore t :which-key "help")
    "hk"  '(describe-key :which-key "Describe key")
    "hf"  '(describe-function :which-key "Describe function")
    "hv"  '(describe-variable :which-key "Describe variable")
    "hm"  '(describe-mode :which-key "Describe mode")
    "ha"  '(apropos-command :which-key "Find commands")
    "hw"  '(woman :which-key "Man page (woman)")
    "hr"  '((lambda () (interactive) (load-file user-init-file)) :which-key "Reload config")
    "hy" '(my/yank-last-message :which-key "Yank last message")

    ;; Code
    "c"   '(:ignore t :which-key "code")
    "cc"  '(compile :which-key "Compile")
    "cC"  '(recompile :which-key "Recompile")
    "ck"  '(kill-compilation :which-key "Kill compilation")
    "cw"  '(delete-trailing-whitespace :which-key "Delete whitespace")

    ;; Navigation
    "cd"  '(xref-find-definitions :which-key "Go to definition")
    "cD"  '(xref-find-definitions-other-window :which-key "Definition other window")
    "cr"  '(xref-find-references :which-key "Find references")
    "cb"  '(xref-go-back :which-key "Jump back")
    "cF"  '(xref-go-forward :which-key "Jump forward")

    ;; Errors (flymake)
    "ce"  '(:ignore t :which-key "errors")
    "cen" '(flymake-goto-next-error :which-key "Next error")
    "cep" '(flymake-goto-prev-error :which-key "Prev error")
    "cel" '(flymake-show-buffer-diagnostics :which-key "List errors")

    ;; LSP (eglot)
    "l"   '(:ignore t :which-key "lsp")
    "ll"  '(eglot :which-key "Start LSP")
    "lr"  '(eglot-rename :which-key "Rename symbol")
    "lf"  '(eglot-format :which-key "Format buffer")
    "la"  '(eglot-code-actions :which-key "Code actions")
    "lq"  '(eglot-shutdown :which-key "Stop LSP")
    "ld"  '(flymake-show-buffer-diagnostics :which-key "Show diagnostics")
    "ly"  '(my/yank-flymake-error :which-key "Yank error message")

    ;; Global Search/Jump (SPC g)
    "g"   '(:ignore t :which-key "search/jump")
    "gw"  '(my/helix-gw :which-key "Jump to 3-char sequence")
    "gd"  '(xref-find-definitions :which-key "Go to definition")
    "gD"  '(xref-find-definitions-other-window :which-key "Definition other window")

    ;; Git (magit)
    "gi"   '(:ignore t :which-key "git")
    "gig"  '(magit-status :which-key "Status")
    "giB"  '(magit-blame :which-key "Blame")
    "gil"  '(magit-log-current :which-key "Log")
    "giL"  '(magit-log-all :which-key "Log all branches")
    "gid"  '(magit-diff-working-tree :which-key "Diff working tree")
    "giD"  '(magit-diff :which-key "Diff")
    "gic"  '(magit-commit :which-key "Commit")
    "giC"  '(magit-checkout :which-key "Checkout")
    "gip"  '(magit-push-current :which-key "Push")
    "giP"  '(magit-pull :which-key "Pull")
    "gif"  '(magit-fetch :which-key "Fetch")
    "gir"  '(magit-rebase :which-key "Rebase")
    "git"  '(magit-tag :which-key "Tag")
    "gib"  '(magit-branch :which-key "Branch")

    ;; Terminals / Open
    "o"   '(:ignore t :which-key "open")
    "ot"  '(term :which-key "Open term")

    ;; Notes
    "n"  '(org-capture :which-key "New note")

    ;; Spellchecking
    "S"   '(:ignore t :which-key "spellcheck")
    "St"  '(flyspell-mode :which-key "Toggle spellcheck")
    "Sb"  '(flyspell-buffer :which-key "Spellcheck buffer")
    "Sn"  '(flyspell-goto-next-error :which-key "Next spelling error")
    "Sc"  '(flyspell-correct-wrapper :which-key "Correct word at point")

    ;; Workspaces (TAB)
    "TAB"     '(:ignore t :which-key "workspaces")
    "TAB TAB"  '(tab-bar-switch-to-tab :which-key "Switch workspace")
    "TAB l"    '(tab-bar-switch-to-next-tab :which-key "Next workspace")
    "TAB h"    '(tab-bar-switch-to-prev-tab :which-key "Prev workspace")
    "TAB o"    '(tab-bar-new-tab :which-key "New workspace")
    "TAB d"    '(my/safely-close-workspace :which-key "Delete workspace") ; Added explicit confirmation check
    "TAB r"    '(tab-bar-rename-tab :which-key "Rename workspace")
    )

  (doom-local-leader-keys
    ;; Timestamps
    "d"   '(:ignore t :which-key "dates")
    "dd"  '(org-deadline :which-key "Set deadline")
    "ds"  '(org-schedule :which-key "Schedule")
    "dt"  '(org-time-stamp :which-key "Insert active timestamp")
    "dT"  '(org-time-stamp-inactive :which-key "Insert inactive timestamp")

    ;; Todo
    "t"   '(org-todo :which-key "Cycle TODO state")

    ;; Links
    "l"   '(:ignore t :which-key "links")
    "ll"  '(org-insert-link :which-key "Insert link")
    "ls"  '(org-store-link :which-key "Store link")
    "lo"  '(org-open-at-point :which-key "Open link")

    ;; Clocking
    "c"   '(:ignore t :which-key "clock")
    "ci"  '(org-clock-in :which-key "Clock in")
    "co"  '(org-clock-out :which-key "Clock out")
    "cx"  '(org-clock-cancel :which-key "Cancel clock")
    "cq"  '(org-clock-report :which-key "Clock report")

    ;; Subtree
    "s"   '(:ignore t :which-key "subtree")
    "sr"  '(org-refile :which-key "Refile")
    "sa"  '(org-archive-subtree :which-key "Archive")
    "sn"  '(org-narrow-to-subtree :which-key "Narrow to subtree")
    "sw"  '(widen :which-key "Widen")

    ;; Insert
    "i"   '(:ignore t :which-key "insert")
    "ih"  '(org-insert-heading :which-key "Insert heading")
    "is"  '(org-insert-subheading :which-key "Insert subheading")
    "if"  '(org-footnote-new :which-key "Insert footnote")

    ;; Tags/Properties
    "p"   '(org-set-property :which-key "Set property")
    "T"   '(org-set-tags-command :which-key "Set tags")

    ;; Export
    "e"   '(org-export-dispatch :which-key "Export")
    "E"   '((lambda () (interactive) (org-export-dispatch '(4))) :which-key "Export Subtree")

    ;; Babel
    "b"   '(:ignore t :which-key "tables/babel")
    "bb"  '(org-babel-execute-src-block :which-key "Execute block")
    "be"  '(org-edit-src-code :which-key "Edit src block")
    "bt"  '(org-babel-tangle :which-key "Tangle")

    ;; Priority
    "P"   '(org-priority :which-key "Set priority")

    ;; -- Tables (b) -----------------------------------------------
    "b-"   '(org-table-insert-hline :which-key "Insert hline")
    "bir"  '(org-table-insert-row :which-key "Insert row")
    "bic"  '(org-table-insert-column :which-key "Insert column")
    "bdr"  '(org-table-kill-row :which-key "Delete row")
    "bdc"  '(org-table-delete-column :which-key "Delete column")
    "ba"   '(org-table-align :which-key "Align table")
    "bs"   '(org-table-sort-lines :which-key "Sort rows")
    "bf"   '(org-table-edit-formulas :which-key "Edit formulas")
    "be"   '(org-table-eval-formulas :which-key "Eval formulas")

    ;; Checkbox
    "bx"   '(org-toggle-checkbox :which-key "Toggle Checkbox")

    ;; Misc
    "'"   '(org-edit-src-code :which-key "Edit src block")
    "RET" '(org-open-at-point :which-key "Follow link")))

;; -- Which-key (Built-in 30.2) ------------------------------
(use-package which-key
  :ensure nil                       ; Tells Emacs not to download it from MELPA since it's built-in
  :init
  (setq which-key-idle-delay 0.2)   ; Set your preferred delay here (e.g., 0.0 for instant popup)
  :config
  (setq which-key-side-window-location 'bottom
        which-key-popup-type 'side-window
        which-key-side-window-max-height 0.25
        which-key-separator " ? "
        which-key-prefix-prefix "")
  (which-key-mode 1))

;; -- Catppuccin Theme ---------------------------------------
(use-package catppuccin-theme
  :config
  (setq catppuccin-flavor 'macchiato)
  (load-theme 'catppuccin t))


;; --- Two-Tier Workspace/Buffer Tabs ---
(use-package tab-bar
  :ensure nil
  :init
  (tab-bar-mode 1)
  :custom
  (tab-bar-new-tab-to 'rightmost)
  :config
  ;; --- Enhance Active Tab Visibility ---
  (with-eval-after-load 'catppuccin-theme
    (let ((bg-active    "#c6a0f6")  ; Catppuccin Mauve
          (fg-active    "#1e2030")  ; Dark Macchiato Base (high contrast)
          (bg-inactive  "#24273a")  ; Macchiato Surface
          (fg-inactive  "#cad3f5")) ; Macchiato Text
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
                          :background "#181926" ; Darker crust color
                          :foreground fg-inactive))))

;; -- tldr ---------------------------------------------------
(use-package tldr)

;; -- Org Mode -----------------------------------------------
(setq org-directory "~/org")

;; With use-package + straight or elpaca:
(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-star '("◉" "○" "◆" "◇" "▶"))   ; custom heading bullets
  (org-modern-list '((?- . "•") (?+ . "◦") (?* . "▸")))  ; list markers
  (org-modern-checkbox '((?  . "☐") (?X . "☑") (?- . "◫")))
  (org-modern-table t)
  (org-modern-block-name t))

(setq org-hide-leading-stars t)
(setq org-startup-indented t)

(defun my/auto-insert-org-template ()
  "Insert default Org header if new .org file is empty."
  (when (and (buffer-file-name)
             (string-match-p "\\.org\\'" (buffer-file-name))
             (= (buffer-size) 0))
    (insert "#+title: " (file-name-base (buffer-file-name)) "\n"
            "#+author: " user-full-name "\n"
            "#+date: " (format-time-string "<%Y-%m-%d %a %H:%M>") "\n\n")))

(add-hook 'find-file-hook #'my/auto-insert-org-template)
(add-hook 'org-mode-hook 'org-indent-mode)

(setq org-log-done 'time)
(setq org-return-follows-link t)
(setq org-hide-emphasis-markers t)

(defun my/org-smart-backspace ()
  "Delete empty bullets cleanly, otherwise delete characters normally."
  (interactive)
  (let ((line (buffer-substring-no-properties (line-beginning-position) (point))))
    ;; Fixed regex syntax for bullet matching
    (if (string-match-p "^\\s-*\\(- \\|\\* \\|\\+ \\|[0-9]+\\.\\s-\\)\\s-*$" line)
        (kill-line 0)
      (call-interactively #'backward-delete-char-untabify))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "DEL") #'my/org-smart-backspace))

(use-package ox-gfm
  :after org
  :config
  (setq org-export-with-drawers t)
  (setq org-export-with-clocks t)
  (defun my/ox-gfm-fix-links (output backend info)
    "Strip Org anchor tags, fix TOC links, and inject LOGBOOK clock date in GFM export."
    (when (eq backend 'gfm)
      ;; Remove <a id="orgXXX"></a> anchors
      (setq output (replace-regexp-in-string
                    "<a id=\"org[^\"]*\"></a>\n?" "" output))
      ;; Convert [Title](#orgXXX) → plain text
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

;; -- Org Mode Header Sizes ----------------------------------
(with-eval-after-load 'org
  (set-face-attribute 'org-level-1 nil :height 1.4 :weight 'bold)
  (set-face-attribute 'org-level-2 nil :height 1.3 :weight 'bold)
  (set-face-attribute 'org-level-3 nil :height 1.2 :weight 'bold)
  (set-face-attribute 'org-level-4 nil :height 1.1)
  (set-face-attribute 'org-level-5 nil :height 1.0)
  (set-face-attribute 'org-document-title nil :height 1.6 :weight 'bold))

;; -- Projectile ---------------------------------------------
(use-package projectile
  :config
  (projectile-mode 1)
  (setq projectile-project-search-path '("/mnt/c/work/projects/"))
  (setq projectile-enable-caching 'persistent)
  (setq projectile-auto-update-cache t))

;; -- Arrow replacement via post-insert hook -----------------
(defvar my/arrow-replacements
  '(("-->"  . #x2192)
    ("<--"  . #x2190)
    ("==>"  . #x21D2)
    ("<=="  . #x21D0)
    ("<=>"  . #x27FA)
    ("->>"  . #x21A0)
    ("<<-"  . #x219E)
    ("..."  . #x2026)))

(defun my/replace-arrows ()
  "Replace arrow sequences with Unicode characters."
  (dolist (pair my/arrow-replacements)
    (let ((arrow (car pair))
          (char (cdr pair)))
      (when (looking-back (regexp-quote arrow) (- (point) (length arrow)))
        (delete-char (- (length arrow)))
        (insert (string char))))))

(add-hook 'post-self-insert-hook #'my/replace-arrows)

(setq-default prettify-symbols-alist
  '(("!="   . #x2260)
    ("::"   . #x2237)))

;; -- Org Capture Templates ----------------------------------
(setq org-capture-templates
    '(

    ("m" "Meeting" entry 
    (file+olp+datetree "~/org/meetings.org")
    "* %^{Meeting title} %? :meeting:\n:ATTENDEES: %^{Attendees (comma separated)}\n\n** Notes\n- \n\n** Action Items\n*** TODO [#A] "
    :tree-type week
    :clock-in t
    :clock-resume t
    :empty-line 0)

    ("t" "Todo" entry
    (file+headline "~/org/todo.org" "Tasks")
    "* TODO %^{Task}\nSCHEDULED: %^t DEADLINE: %^t\n-  %?"
    :empty-lines 0)

    ("j" "Work Log Entry" item
    (file+datetree "~/org/work-log.org")
    "- %?"
    :empty-lines 0)

    ("n" "Quick Note" entry
     (file+datetree "~/org/notes.org")
     "* %^{Title}\n%T\n\n%?\n"
     :empty-lines 0)))

;; TODO states
(setq org-todo-keywords
      '((sequence "TODO(t)" "PLANNING(p)" "IN-PROGRESS(i@/!)" "VERIFYING(v!)" "BLOCKED(b@)"  "|" "DONE(d!)" "OBE(o@!)" "WONT-DO(w@/!)" )
        ))

(setq org-modern-todo-faces
      '(
        ("TODO"        . (:background "GoldenRod"  :foreground "black" :weight bold))
        ("PLANNING"    . (:background "DeepPink"   :foreground "white" :weight bold))
        ("IN-PROGRESS" . (:background "Cyan"       :foreground "black" :weight bold))
        ("VERIFYING"   . (:background "DarkOrange" :foreground "black" :weight bold))
        ("BLOCKED"     . (:background "Red"        :foreground "white" :weight bold))
        ("DONE"        . (:background "LimeGreen"  :foreground "black" :weight bold))
        ("OBE"         . (:background "LimeGreen"  :foreground "black" :weight bold))
        ("WONT-DO"     . (:background "LimeGreen"  :foreground "black" :weight bold))
        ))

;; Fancy css
(setq org-html-head 
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

;; Tell org-agenda which files to scan
(setq org-agenda-files '("~/org/todo.org"
                          "~/org/meetings"
                          "~/org/notes.org"))

;; -- Evil Org (proper Doom-like org keybinds) ---------------
(use-package evil-org
  :after (evil org)
  :hook (org-mode . evil-org-mode)
  :config
  (evil-org-set-key-theme '(navigation insert textobjects additional todo calendar return)))

;; -- Spellcheck ---------------------------------------------
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
  (setq ispell-dictionary "en_US")
  (setq ispell-local-dictionary "en_US")
  (setq flyspell-default-dictionary "en_US")
  (setq ispell-local-dictionary-alist
        '(("en_US" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil ("-d" "en_US") nil utf-8))))

;; -- Native Comp Warnings (suppress) -----------------------
(setq native-comp-async-report-warnings-errors nil)

;; -- Centered Cursor ----------------------------------------
(use-package centered-cursor-mode
  :config
  (global-centered-cursor-mode 1)
  (add-hook 'after-change-major-mode-hook
            (lambda ()
              (when (derived-mode-p 'term-mode 'eshell-mode)
                (centered-cursor-mode -1)))))

;; -- Vertico (vertical completion UI) ----------------------
(use-package vertico
  :init
  (vertico-mode 1)
  (setq vertico-count 15))        ; show 15 candidates at once

;; -- Orderless (fuzzy/flex matching) -----------------------
(use-package orderless
  :config
  (setq completion-styles '(orderless basic)
        completion-category-overrides
        '((file (styles basic partial-completion)))))

;; -- Magit -------------------------------------------------
(use-package magit)

;; -- Marginalia (annotations on candidates) ----------------
(use-package marginalia
  :init
  (marginalia-mode 1))

;; -- Avy Jumper (Helix gw Emulator) ------------------------
(use-package avy
  :config
  (setq avy-keys '(?a ?s ?d ?f ?j ?k ?l ?e ?r ?u ?i ?o ?w ?v ?c ?m))
  (defun my/helix-gw ()
    "Jump to any visible word instantly, mimicking Helix's 'gw' command."
    (interactive)
    ;; Force avy to label all words matching a word-boundary regex instantly
    (let ((avy-all-windows t))
      (avy-with my/helix-gw
        (avy-process (avy--regex-candidates "\\b[a-zA-Z0-9_]"))))))

;; -- TCL Support --------------------------------------------
(use-package tcl
  :ensure nil
  :mode ("\\.tcl\\'" . tcl-mode)
  :config
  (setq tcl-indent-level 4))

;; -- Verilog / SystemVerilog Support -------------------------
(use-package verilog-mode
  :ensure nil
  :mode (("\\.v\\'" . verilog-mode)
         ("\\.sv\\'" . verilog-mode))

  :config
  ;; -- Verilog Mode -------------------------------------------
  (setq verilog-linter "/usr/local/bin/verible-verilog-lint")

  ;; Customizations to mimic Doom's clean formatting
  (setq verilog-indent-level             4
        verilog-indent-level-module      4
        verilog-indent-level-declaration 4
        verilog-indent-level-behavioral  4
        verilog-auto-endcomments         nil)) ; Disables noisy "endmodule // name" comments

(advice-add 'verilog-auto :after
            (lambda (&rest _) (untabify (point-min) (point-max))))

;; Define custom faces
(defface verilog-parameter-face
  '((t :foreground "#cee49f" :weight bold))
  "Face for Verilog ALL_CAPS parameters/constants.")

(defface verilog-number-face
  '((t :foreground "#f5a97f"))
  "Face for Verilog numeric literals.")

;; Apply via hook with prepend to override verilog-mode defaults
(defun my/verilog-font-lock-setup ()
  (font-lock-add-keywords nil
    '(("\\b\\([A-Z][A-Z0-9_]+\\)\\b"
       0 'verilog-parameter-face prepend)
      ("\\b\\([0-9]+\\('[bdh][0-9a-fA-FxXzZ_]+\\)?\\)\\b"
       0 'verilog-number-face prepend))
    'prepend))

(add-hook 'verilog-mode-hook #'my/verilog-font-lock-setup)

;; -- Powerline ----------------------------------------------
(use-package powerline
  :config
  (powerline-default-theme))

;; -- Eglot + Verible (SystemVerilog LSP) -------------------
(use-package eglot
  :hook (verilog-mode . eglot-ensure)
  :config
  (add-to-list 'eglot-server-programs
               `((verilog-mode) .
                 ,(lambda (interactive)
                    (let* ((proj (project-current))
                           (root (if proj (project-root proj) default-directory)))
                      (list "verible-verilog-ls"
                            "--file_list_path"
                            (let ((f (make-temp-file "verible-files")))
                              (with-temp-file f
                                (insert (mapconcat #'identity
                                                   (directory-files-recursively root "\\.s?v$")
                                                   "\n")))
                              f))))))
  (setq eglot-ignored-server-capabilities '(:semanticTokensProvider)))

(with-eval-after-load 'magit (dolist (map (list magit-mode-map
                     magit-status-mode-map
                     magit-log-mode-map
                     magit-diff-mode-map
                     magit-refs-mode-map
                     magit-revision-mode-map))
    (define-key map (kbd "SPC") nil))
  
  ;; Also unbind from evil-collection's magit bindings
  (evil-define-key '(normal visual motion) magit-mode-map
    (kbd "SPC") nil))

;; These give the most speed with least feature loss
(setq vc-handled-backends nil)          ; safe, magit replaces this anyway
(setq magit-diff-refine-hunk nil)       ; minor visual loss
(setq magit-auto-revert-mode nil)       ; press SPC b r manually after operations

;; Go back to system git
(setq magit-git-executable "git")

;; -- Popup Bottom Windows (Doom-style) ---------------------
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

;; -- Rainbow Delimiters -------------------------------------
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; Force the base label face to not interfere
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-modern-label ((t (:height 0.9 :weight bold :inherit nil)))))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(activities avy beframe catppuccin-theme centered-cursor-mode dash
		evil-collection evil-nerd-commenter evil-org
		evil-surround flyspell-correct general magit
		marginalia orderless org-modern org-superstar ox-gfm
		powerline projectile rainbow-delimiters s tabspaces
		tldr verilog-mode vertico)))


