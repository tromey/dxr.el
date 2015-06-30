;;; dxr.el --- Convenient access to a DXR server -*-lexical-binding:t-*-

;; Author: Tom Tromey <tom@tromey.com>
;; Version: 1.0

(eval-when-compile
  (require 'compile)
  (require 'thingatpt)
  (require 'browse-url))

(defvar dxr-server "http://dxr.mozilla.org/"
  "The DXR server to use.")

(defvar dxr-tree "mozilla-central"
  "The DXR source tree to use.")

;; It would be nice not to have to use the command, but this would
;; mean writing our own thing like compilation-mode and (the easy
;; part) interfacing to next-error.
(defvar dxr-cmd "dxr"
  "The local DXR command to invoke.")

(defun dxr-url-representing-point ()
  (unless (buffer-file-name)
    (error "Buffer is not visiting a file"))
  (let ((root (or (vc-root-dir)
		  (error "Could not find VC root directory"))))
    (concat dxr-server
	    dxr-tree
	    "/source/"
	    (file-relative-name (buffer-file-name) root)
	    "#"
	    (int-to-string (line-number-at-pos)))))

;;;###autoload
(defun dxr-browse-url ()
  "Open a DXR page for the source at point in a web browser.
This uses `dxr-base-url' to find the DXR server, and `browse-url'
to open the page in the browser."
  (interactive)
  (browse-url (dxr-url-representing-point)))

;;;###autoload
(defun dxr-kill-ring-save ()
  "Save a DXR URL for the source at point in the kill ring.
This uses `dxr-base-url' to find the DXR server."
  (interactive)
  (kill-new (dxr-url-representing-point)))

;;;###autoload
(defun dxr (args)
  "Run a DXR query and put the results into a buffer.
The results can be stepped through using `next-error'."
  (interactive (list
		(read-string (concat "Run dxr (with args): ")
			     (thing-at-point 'symbol))))
  (let ((compile-command nil)
	;; It's nicer to start at the VC root.
	(compilation-directory (or (vc-root-dir)
				   default-directory)))
    (compilation-start (concat dxr-cmd
			       " --grep --no-highlight"
			       " --server=" dxr-server
			       " --tree=" dxr-tree
			       " " args))))

(provide 'dxr)

;;; dxr.el ends here
