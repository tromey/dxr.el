This is a simple Emacs interface to [DXR](http://dxr.mozilla.org/).

It currently relies on a version of
[dxr-cmd](https://github.com/Osmose/dxr-cmd) that has the `--grep`
option.  Install this and put it in your `$PATH`, or set `dxr-cmd` in
Emacs.

There are three main ways to use `dxr.el`:

* `dxr-browse-url`.  This opens a DXR page for the current file and
  line in a browser window.

* `dxr-kill-ring-save`.  Like `dxr-browse-url`, but instead of opening
  the URL, copies it to the kill ring.

* `dxr`.  This runs a DXR query and puts the results into a
  `*compilation*` buffer.


You can install this by checking it out, opening `dxr.el`, and then
running `M-x package-install-from-buffer`.  I will try to get it into
Marmalade or melpa-stable at some point.
