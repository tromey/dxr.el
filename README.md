This is a simple Emacs interface to [DXR](http://dxr.mozilla.org/).
While earlier versions relied on a separate `dxr` executable, this
version is standalone.

There are three main ways to use `dxr.el`:

* `dxr-browse-url`.  This opens a DXR page for the current file and
  line in a browser window.

* `dxr-kill-ring-save`.  Like `dxr-browse-url`, but instead of opening
  the URL, copies it to the kill ring.

* `dxr`.  This runs a DXR query and puts the results into a
  `*grep*`-like buffer.

You can install this by checking it out, opening `dxr.el`, and then
running `M-x package-install-from-buffer`.
