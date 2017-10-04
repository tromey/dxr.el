;;; dxr.el --- Convenient access to a DXR server -*-lexical-binding:t-*-

;; Author: Tom Tromey <tom@tromey.com>
;; Version: 2.4
;; URL: https://github.com/tromey/dxr.el
;; Keywords: comm, tools, matching, mozilla

;;; Commentary:

;; This is a simple Emacs interface to DXR (http://dxr.mozilla.org/).

;; There are three main ways to use this package:

;; * `dxr-browse-url'.  This opens a DXR page for the current file and
;;   line in a browser window.

;; * `dxr-kill-ring-save'.  Like `dxr-browse-url', but instead of opening
;;   the URL, copies it to the kill ring.

;; * `dxr'.  This runs a DXR query and puts the results into a
;;   `*grep*'-like buffer.

;;; Code:

(require 'compile)
(require 'grep)
(require 'json)
(require 'mm-url)
(eval-when-compile
  (require 'browse-url)
  (require 'thingatpt)
  (require 'url-vars)
  (require 'vc))

(declare-function vc-deduce-backend "vc.el")

;; Copied from Emacs 25.
(unless (fboundp 'vc-root-dir)
  (require 'vc)
  (defun vc-root-dir ()
    "Return the root directory for the current VC tree.
Return nil if the root directory cannot be identified."
    (let ((backend (vc-deduce-backend)))
      (if backend
	  (condition-case err
	      (vc-call-backend backend 'root default-directory)
	    (vc-not-supported
	     (unless (eq (cadr err) 'root)
	       (signal (car err) (cdr err)))
	     nil))))))

(defvar dxr-server "https://dxr.mozilla.org/"
  "The DXR server to use.
This must end in a `/'.")

(defvar dxr-tree "mozilla-central"
  "The DXR source tree to use.")

(defvar dxr-limit 100
  "Maximum number of responses to return.")

;; It would be nice not to have to use the command, but this would
;; mean writing our own thing like compilation-mode and (the easy
;; part) interfacing to next-error.
(defvar dxr-cmd "dxr"
  "The local DXR command to invoke.")

(defun dxr--url-representing-point ()
  (unless (buffer-file-name)
    (error "Buffer is not visiting a file"))
  (let* ((root (or (vc-root-dir)
		  (error "Could not find VC root directory")))
	 (start (if (region-active-p)
		    (region-beginning)
		  (point)))
	 (end (if (region-active-p)
		  (region-end)
		nil)))
    ;; If the region ends at the start of a line, then just leave it
    ;; as-is.  But if the region ends mid-line, move it to the next
    ;; line.  This will make the results a little nicer.
    (when end
      (save-excursion
	(goto-char end)
	(when (not (bolp))
	  (forward-line)
	  (setf end (point)))))
    (let ((start-line (line-number-at-pos start))
	  ;; Use 1- here because we want to handle the bolp case
	  ;; specially.
	  (end-line (if end (1- (line-number-at-pos end)))))
      ;; If start and end are the same, don't make a region.
      (when (and end-line (<= end-line start-line))
	(setf end-line nil))
      (concat dxr-server
	      dxr-tree
	      "/source/"
	      (file-relative-name (buffer-file-name) root)
	      "#"
	      (int-to-string start-line)
	      (if end-line "-" "")
	      (if end-line
		  (int-to-string end-line)
		"")))))

;;;###autoload
(defun dxr-browse-url ()
  "Open a DXR page for the source at point in a web browser.
This uses `dxr-server' and `dxr-tree' to compute the URL, and `browse-url'
to open the page in the browser."
  (interactive)
  (browse-url (dxr--url-representing-point)))

;;;###autoload
(defun dxr-kill-ring-save ()
  "Save a DXR URL for the source at point in the kill ring.
This uses `dxr-server' and `dxr-tree' to compute the URL."
  (interactive)
  (let ((url (dxr--url-representing-point)))
    (kill-new url)
    (message "%s" url)))

(defun dxr--create-query-url (query)
  "Given QUERY, a string, create and return a DXR query URL."
  (concat dxr-server dxr-tree "/search?q="
	  (url-hexify-string query)
	  "&redirect=false"
	  "&format=json"
	  "&case=true"			; FIXME
	  "&limit=" (int-to-string dxr-limit)
	  "&offset=0"))

(defun dxr--query-ok (query status)
  "A helper function that checks the result of `url-retrieve'.
QUERY is the DXR query string.  It is used to update the header line
on failure.  STATUS is the status argument as passed by `url-retrieve'.
If the status is considered ok, returns `t', otherwise `nil'."
  (let ((result t))
    (while status
      (if (eq (car status) :error)
	  (progn
	    (setf header-line-format (format "dxr query: %s [error: %s]" query
					     (cadr status)))
	    (setf status nil)
	    (setf result nil)))
      (setf status (cddr status)))
    result))

(defvar dxr--last-query)
(make-variable-buffer-local 'dxr--last-query)
(defvar dxr--running)
(make-variable-buffer-local 'dxr--running)

(defun dxr--query (this-dir query)
  "Do the work of a DXR query.
THIS-DIR is the default directory to use.
QUERY is the query string to use."
  (let ((buffer (get-buffer-create "*DXR*")))
    (with-current-buffer buffer
      (when dxr--running
	(error "Already running a DXR query in this buffer"))
      (let ((inhibit-read-only t))
	(erase-buffer)
	(dxr-mode)
	(setf default-directory this-dir)
	(setf dxr--last-query query)
	(setf header-line-format (format "dxr query: %s [querying...]" query))
	(pop-to-buffer buffer))
      ;; Undocumented URL feature.
      (let ((url-mime-accept-string "application/json; q=1.0, */*; q=0.1"))
	(setf dxr--running t)
	(url-retrieve
	 (dxr--create-query-url query)
	 (lambda (status)
	   (when (with-current-buffer buffer (dxr--query-ok query status))
	     ;; We should only do this for http and https, but
	     ;; realistically that is the only case for DXR.
	     (goto-char (point-min))
	     (re-search-forward "^\n")
	     ;; Silly json.el.
	     (let* ((json-object-type 'alist)
		    (json-array-type 'list)
		    (json-key-type 'symbol)
		    (json-false nil)
		    (json-null nil)
		    (result (json-read)))
	       (with-current-buffer buffer
		 (let ((inhibit-read-only t))
		   (setf header-line-format (format "dxr query: %s" query))
		   (insert "-*- mode: dxr; default-directory: "
			   (prin1-to-string (abbreviate-file-name this-dir))
			   "-*-\n\n")
		   (dolist (record (cdr (assq 'results result)))
		     (let ((file (cdr (assq 'path record))))
		       (dolist (line-record (cdr (assq 'lines record)))
			 (let ((line (cdr (assq 'line line-record)))
			       (line-num (cdr (assq 'line_number line-record))))
			   (insert
			    file
			    ":"
			    (number-to-string line-num)
			    ":"
			    (replace-regexp-in-string
			     "<b>.*?</b>"
			     (lambda (match)
			       (propertize (substring match 3 -4)
			       		   'font-lock-face grep-match-face))
			     line nil t)
			    "\n")))))
		   ;; DXR output has HTML entities in the strings, so
		   ;; decode them all now.
		   (mm-url-decode-entities)
		   (goto-char (point-min))))))
	   ;; Kill the http results.  Comment this out if you need to
	   ;; debug the transfer.
	   (kill-buffer (current-buffer))
	   (with-current-buffer buffer
	     (setf dxr--running nil)))
	 nil t)))))

(defun dxr--revert-buffer (_ignore-auto _noconfirm)
  "A `revert-buffer-function' for `dxr'."
  (dxr--query default-directory dxr--last-query))

(defvar dxr-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map grep-mode-map)
    (define-key map [menu-bar grep] 'undefined)
    (define-key map [menu-bar compilation] 'undefined)
    ;; FIXME - make something like kill-compilation
    (define-key map "\C-c\C-k" 'undefined)
    (define-key map "g" #'revert-buffer)
    map)
  "Keymap for dxr buffers.")

(define-derived-mode dxr-mode grep-mode "DXR Results"
  "Major mode for browsing DXR results.
This is like `grep-mode', but specific to `dxr'.
\\{dxr-mode-map}"
  ;; We don't want the grep-mode setting for this.
  (kill-local-variable 'tool-bar-map)
  (set (make-local-variable 'revert-buffer-function)
       #'dxr--revert-buffer))

;; History of dxr commands.
(defvar dxr-history nil "History list for dxr.")

;;;###autoload
(defun dxr (args)
  "Run a DXR query and put the results into a buffer.
The results can be stepped through using `next-error'."
  (interactive (list
		(read-string (concat "DXR query: ")
			     (thing-at-point 'symbol)
			     'dxr-history)))
  ;; Try to start at the VC root.
  (dxr--query (or (vc-root-dir) default-directory) args))

(provide 'dxr)

;;; dxr.el ends here
